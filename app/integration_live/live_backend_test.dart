// ignore_for_file: avoid_print
// Live check of the app's HTTP client + models against a running backend (NOT part of `flutter test`).
//
//   flutter test integration_live/live_backend_test.dart --dart-define=LIVE_API=http://localhost:8101
//
// It resets the DEMO data, simulates the demo flash-flood alert, and exercises every app endpoint with
// the same AapdaApi/HttpAapdaApi code the app uses. Demo mode only — it never touches real residents.
import 'dart:convert';

import 'package:aapda_saathi/core/api_client.dart';
import 'package:aapda_saathi/core/api_exception.dart';
import 'package:aapda_saathi/core/config.dart';
import 'package:aapda_saathi/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const base = String.fromEnvironment('LIVE_API', defaultValue: 'http://localhost:8101');

void main() {
  final config = AppConfig(apiBaseUrl: base);
  late List<DemoPersona> personas;

  HttpAapdaApi client() => HttpAapdaApi(config);

  Future<HttpAapdaApi> loginAs(String namePrefix) async {
    final api = client();
    final p = personas.firstWhere((p) => p.fullName.startsWith(namePrefix));
    final t = await api.demoLogin(p.userId);
    api.token = t.accessToken;
    return api;
  }

  Future<dynamic> raw(String method, String path, String token, [Object? body]) async {
    final req = http.Request(method, Uri.parse('${config.apiRoot}$path'))
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json';
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await http.Client().send(req));
    expect(res.statusCode, inInclusiveRange(200, 299), reason: '$method $path → ${res.statusCode} ${res.body}');
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  test('live backend end-to-end with app models', () async {
    final anon = client();
    personas = await anon.demoPersonas();
    expect(personas, isNotEmpty);
    print('personas: ${personas.length}');

    // Operator: reset demo + simulate the flash flood alert.
    final op = await loginAs('Arjun');
    expect((await op.me()).user.role, UserRole.operator);
    await raw('POST', '/demo/reset', op.token!);
    final inc = await raw('POST', '/demo/simulate', op.token!, {'fixture': 'demo_flash_flood_alert', 'onset_in_minutes': 20});
    print('simulated incident ${inc['id']} mode=${inc['escalation_mode']} approval=${inc['requires_dispatch_approval']}');

    // Resident Ramesh.
    final ramesh = await loginAs('Ramesh Joshi');
    final me = await ramesh.me();
    expect(me.user.role, UserRole.resident);
    expect(me.resident, isNotNull);
    print('me: ${me.user.fullName} ward=${me.resident!.wardName} needs=${me.resident!.needs}');

    final active = await ramesh.activeAlerts();
    expect(active, isNotEmpty);
    final a = active.first;
    print('alert ${a.deliveryId} status=${a.status} modes=${a.accessibilityModes} '
        'title="${a.presentation.title}" shelters=${a.shelters.length} onsetNote=${a.official.onsetNote != null}');
    expect(a.awaitingReply, isTrue);
    expect(a.official.headline, isNotNull);

    final hist = await ramesh.alertHistory();
    print('history total=${hist.total}');
    final loc = await ramesh.myLocation();
    print('my location: ${loc?.lat},${loc?.lng}');
    final wards = await ramesh.publicWards();
    print('wards: ${wards.map((w) => w.code).join(',')}');
    final single = await ramesh.alert(a.deliveryId);
    expect(single.deliveryId, a.deliveryId);

    // Realtime: ticket → WebSocket → first frame is hello.
    final ticket = await ramesh.realtimeTicket();
    final ws = WebSocketChannel.connect(config.realtimeUri(ticket));
    await ws.ready;
    final first = jsonDecode(await ws.stream.first.timeout(const Duration(seconds: 10)) as String);
    print('realtime first frame: $first');
    expect(first['type'], 'hello');
    await ws.sink.close();

    // Respond SAFE with an idempotency key, then replay the same key.
    final key = const Uuid().v4();
    final r1 = await ramesh.respond(a.deliveryId, 'SAFE', idempotencyKey: key);
    final r2 = await ramesh.respond(a.deliveryId, 'SAFE', idempotencyKey: key);
    print('respond SAFE → ${r1.status} changed=${r1.changed}; replay → ${r2.status} changed=${r2.changed}');
    expect(r1.status, 'SAFE');
    expect(r2.changed, r1.changed);
    expect((await ramesh.activeAlerts()).first.status, 'SAFE');

    // Language round trip and needs patch.
    expect((await ramesh.patchMe(language: 'hi')).language, 'hi');
    expect((await ramesh.patchMe(language: 'en')).language, 'en');
    final patched = await ramesh.patchResident({'needs': me.resident!.needs});
    expect(patched.needs, me.resident!.needs);
    final renewed = await ramesh.renewConsent();
    print('consent renewed: reverify_due_at=${renewed.reverifyDueAt}');

    // Easy-read resident (Hindi).
    final bhuwan = await loginAs('Bhuwan');
    final ba = (await bhuwan.activeAlerts()).first;
    print('bhuwan: style=${ba.presentation.style} steps=${ba.presentation.easyReadSteps.length}');

    // Caregiver.
    final neha = await loginAs('Neha');
    final cg = await neha.caregiverResidents();
    print('caregiver residents: ${cg.map((c) => '${c.resident.fullName}:${c.activeAlerts.map((x) => x.status)}').join('; ')}');
    final kamlaAlert = cg.expand((c) => c.activeAlerts).first;
    final cr = await neha.caregiverRespond(kamlaAlert.deliveryId, 'SAFE', note: 'Live test: spoke on phone');
    print('caregiver SAFE → ${cr.status}');

    // Neighbour.
    final vikram = await loginAs('Vikram');
    final checks = await vikram.neighbourChecks(includeClosed: true);
    print('vikram checks: ${checks.map((t) => '${t.residentFirstName}:${t.status}').join(', ')}');
    final openCheck = checks.where((t) => t.isOpen).toList();
    if (openCheck.isNotEmpty) {
      final out = await vikram.neighbourRespond(openCheck.first.id, 'CANNOT_REACH', note: 'Live test');
      print('neighbour CANNOT_REACH → ${out.status} outcome=${out.outcome}');
    }

    // Volunteers: wait for escalation to create tasks; approve pending ones as the operator.
    final vols = {for (final n in ['Aman', 'Sneha']) n: await loginAs(n)};
    List<TaskOut> open = [];
    String? who;
    for (var i = 0; i < 30 && open.isEmpty; i++) {
      final opTasks = await raw('GET', '/incidents/${inc['id']}/tasks', op.token!) as List;
      for (final t in opTasks.where((t) => t['status'] == 'PENDING_APPROVAL')) {
        await raw('POST', '/tasks/${t['id']}/approve', op.token!);
        print('operator approved task ${t['id']}');
      }
      for (final e in vols.entries) {
        final ts = (await e.value.volunteerTasks()).where((t) => t.isAssigned).toList();
        if (ts.isNotEmpty) {
          open = ts;
          who = e.key;
          break;
        }
      }
      if (open.isEmpty) await Future<void>.delayed(const Duration(seconds: 5));
    }
    if (open.isEmpty) {
      print('NO volunteer task appeared within the wait window');
    } else {
      final vol = vols[who]!;
      final vme = await vol.volunteerMe();
      print('$who available=${vme.isAvailable} active_task=${vme.activeTaskId}');
      final toggled = await vol.setAvailability(vme.isAvailable);
      expect(toggled.isAvailable, vme.isAvailable);
      final t = open.first;
      final d = await vol.taskDetail(t.id);
      print('task ${t.id} ${d.kind} ${d.status} resident=${d.residentFullName} phone=${d.residentPhone != null} '
          'exact=${d.exactLocation != null} walk_note="${d.walkEstimateNote.substring(0, 30)}…"');
      final acc = await vol.acceptTask(t.id);
      print('accept → ${acc.status}');
      try {
        await vol.reached(t.id, 'needs_rescue');
        fail('note should be required');
      } on ApiException catch (e) {
        print('reached without note → ${e.statusCode} ${e.code}');
      }
      final rc = await vol.reached(t.id, 'resident_safe', note: 'Live test');
      print('reached → ${rc.status} outcome=${rc.outcome}');
      final closed = await vol.taskDetail(t.id);
      print('closed detail exact_location=${closed.exactLocation} phone=${closed.residentPhone}');
      if (open.length > 1) {
        final cg2 = await vol.cantGo(open[1].id, 'route_blocked', note: 'Live test');
        print('cant-go → ${cg2.status} reason=${cg2.cantGoReason}');
      }
    }

    // Error envelope is parsed.
    try {
      await ramesh.alert('does-not-exist');
      fail('expected 404');
    } on ApiException catch (e) {
      print('404 → code=${e.code} message="${e.message}"');
      expect(e.statusCode, 404);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
