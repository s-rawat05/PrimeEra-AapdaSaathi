import 'dart:convert';
import 'dart:io';

import 'package:aapda_saathi/accessibility/alert_effects.dart';
import 'package:aapda_saathi/app.dart';
import 'package:aapda_saathi/core/api_client.dart';
import 'package:aapda_saathi/core/api_exception.dart';
import 'package:aapda_saathi/core/config.dart';
import 'package:aapda_saathi/core/json.dart';
import 'package:aapda_saathi/models/models.dart';
import 'package:aapda_saathi/repositories/alert_repository.dart';
import 'package:aapda_saathi/services/connectivity_service.dart';
import 'package:aapda_saathi/services/device_services.dart';
import 'package:aapda_saathi/services/local_store.dart';
import 'package:aapda_saathi/services/notification_service.dart';
import 'package:aapda_saathi/services/offline_queue.dart';
import 'package:aapda_saathi/services/session_store.dart';
import 'package:aapda_saathi/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Real JSON captured from the backend (port 8101, demo seed) — see test/fixtures.
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());

Json fixtureObj(String name) => Map<String, dynamic>.from(fixture(name) as Map);

List<Json> fixtureList(String name) =>
    (fixture(name) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

Json meFor(String role) {
  switch (role) {
    case 'resident':
      return fixtureObj('me_ramesh');
    case 'caregiver':
      return fixtureObj('me_neha');
    case 'neighbour':
      return fixtureObj('me_vikram');
    case 'volunteer':
      return fixtureObj('me_Aman');
    default:
      final m = fixtureObj('me_neha');
      final u = Map<String, dynamic>.from(m['user'] as Map)
        ..['role'] = role
        ..['full_name'] = 'Arjun Mehta (Control Room)';
      return {...m, 'user': u};
  }
}

Json alertJson({String status = 'NO_REPLY', List<String>? modes, bool shelters = true}) {
  final a = fixtureList('active_ramesh').first;
  a['status'] = status;
  if (modes != null) a['accessibility_modes'] = modes;
  if (!shelters) a['shelters'] = <dynamic>[];
  return a;
}

Json taskJson({String id = 'task-1', String status = 'ASSIGNED', String kind = 'volunteer_assist'}) {
  final t = fixtureList('checks_vikram').first;
  return {...t, 'id': id, 'status': status, 'kind': kind};
}

/// In-memory fake of the backend used by widget tests.
class FakeApi implements AapdaApi {
  @override
  String? token;

  bool offline = false;
  ApiException? alertsError;
  Json meJson = meFor('resident');
  List<Json> alerts = [];
  List<DemoPersona> personas = [];
  List<Json> tasks = [];
  List<Json> checks = [];
  bool volunteerAvailable = true;
  final List<String> calls = [];
  final List<(String, String, String)> responds = []; // (deliveryId, status, key)

  Never _offline() => throw const ApiException.network();

  void _guard(String name) {
    calls.add(name);
    if (offline) _offline();
  }

  @override
  Future<OtpRequestOut> requestOtp(String phone) async {
    _guard('requestOtp');
    return OtpRequestOut(sent: true, expiresIn: 300, channel: 'simulator', note: 'Code delivered to the SMS simulator inbox (demo).');
  }

  @override
  Future<TokenOut> verifyOtp(String phone, String code, {String? fullName}) async {
    _guard('verifyOtp');
    return TokenOut.fromJson({'access_token': 'tok', 'expires_in': 3600, 'user': meJson['user'], 'is_new_user': false});
  }

  @override
  Future<List<DemoPersona>> demoPersonas() async {
    _guard('demoPersonas');
    return personas;
  }

  @override
  Future<TokenOut> demoLogin(String userId) async {
    _guard('demoLogin:$userId');
    return TokenOut.fromJson({'access_token': 'tok-$userId', 'expires_in': 3600, 'user': meJson['user']});
  }

  @override
  Future<MeOut> me() async {
    _guard('me');
    return MeOut.fromJson(meJson);
  }

  @override
  Future<UserOut> patchMe({String? language, String? fullName}) async {
    _guard('patchMe:$language');
    return UserOut.fromJson({...(meJson['user'] as Map<String, dynamic>), 'language': ?language});
  }

  @override
  Future<void> registerDevice(String fcmToken, String platform) async => _guard('registerDevice');

  @override
  Future<String> realtimeTicket() async {
    _guard('ticket');
    return 't';
  }

  @override
  Future<List<WardOut>> publicWards() async {
    _guard('wards');
    return fixtureList('wards').map(WardOut.fromJson).toList();
  }

  @override
  Future<ResidentOut> register(RegistrationIn body) async {
    _guard('register');
    return ResidentOut.fromJson(meJson['resident'] as Json);
  }

  @override
  Future<ResidentOut> patchResident(Json patch) async {
    _guard('patchResident');
    return ResidentOut.fromJson({...(meJson['resident'] as Json), ...patch});
  }

  @override
  Future<ExactLocationOut?> myLocation() async {
    _guard('myLocation');
    return ExactLocationOut(lat: 29.352, lng: 79.557, addressText: 'House 18', landmark: null, source: 'registration');
  }

  @override
  Future<ResidentOut> withdrawConsent() async {
    _guard('withdraw');
    return ResidentOut.fromJson(meJson['resident'] as Json);
  }

  @override
  Future<ResidentOut> renewConsent() async {
    _guard('renew');
    return ResidentOut.fromJson(meJson['resident'] as Json);
  }

  @override
  Future<List<AlertOut>> activeAlerts() async {
    _guard('activeAlerts');
    if (alertsError != null) throw alertsError!;
    return alerts.map(AlertOut.fromJson).toList();
  }

  @override
  Future<PageOut<AlertOut>> alertHistory({int limit = 50, int offset = 0}) async {
    _guard('history');
    return PageOut(items: alerts.map(AlertOut.fromJson).toList(), total: alerts.length, limit: limit, offset: offset);
  }

  @override
  Future<AlertOut> alert(String deliveryId) async {
    _guard('alert');
    return AlertOut.fromJson(alerts.firstWhere((a) => a['delivery_id'] == deliveryId));
  }

  @override
  Future<RespondOut> respond(String deliveryId, String status, {required String idempotencyKey}) async {
    _guard('respond:$status');
    responds.add((deliveryId, status, idempotencyKey));
    for (final a in alerts) {
      if (a['delivery_id'] == deliveryId) a['status'] = status;
    }
    return RespondOut(deliveryId: deliveryId, status: status, changed: true, serverTime: DateTime.now());
  }

  @override
  Future<List<CaregiverResidentOut>> caregiverResidents() async {
    _guard('caregiverResidents');
    return fixtureList('caregiver').map(CaregiverResidentOut.fromJson).toList();
  }

  @override
  Future<RespondOut> caregiverRespond(String deliveryId, String status, {String? note}) async {
    _guard('caregiverRespond:$status:$note');
    return RespondOut(deliveryId: deliveryId, status: status, changed: true, serverTime: DateTime.now());
  }

  @override
  Future<List<TaskOut>> neighbourChecks({bool includeClosed = false}) async {
    _guard('checks');
    return checks.map(TaskOut.fromJson).toList();
  }

  @override
  Future<TaskOut> neighbourRespond(String taskId, String outcome, {String? note}) async {
    _guard('neighbourRespond:$outcome');
    return TaskOut.fromJson({...checks.first, 'status': 'COMPLETED', 'outcome': outcome});
  }

  @override
  Future<VolunteerOut> volunteerMe() async {
    _guard('volunteerMe');
    return VolunteerOut.fromJson({...(meJson['volunteer'] as Json), 'is_available': volunteerAvailable});
  }

  @override
  Future<VolunteerOut> setAvailability(bool available) async {
    _guard('availability:$available');
    volunteerAvailable = available;
    return VolunteerOut.fromJson({...(meJson['volunteer'] as Json), 'is_available': available});
  }

  @override
  Future<List<TaskOut>> volunteerTasks({bool includeClosed = false}) async {
    _guard('volunteerTasks');
    return tasks.map(TaskOut.fromJson).toList();
  }

  Json _task(String id) => tasks.firstWhere((t) => t['id'] == id);

  @override
  Future<TaskDetailOut> taskDetail(String taskId) async {
    _guard('taskDetail');
    return TaskDetailOut.fromJson({
      ..._task(taskId),
      'resident_full_name': 'Kamla Devi Bisht',
      'resident_phone': '+919000000001',
      'exact_location': {'lat': 29.35, 'lng': 79.55, 'address_text': 'House 3', 'landmark': null, 'source': 'registration'},
      'location_note': 'Exact location shown because this task is active.',
      'official_instruction': 'Move to Demo Relief Post A.',
      'shelters': <dynamic>[],
      'walk_estimate_note': 'Walking time is an ESTIMATE.',
    });
  }

  @override
  Future<TaskOut> acceptTask(String taskId) async {
    _guard('accept:$taskId');
    _task(taskId)['status'] = 'ACCEPTED';
    return TaskOut.fromJson(_task(taskId));
  }

  @override
  Future<TaskOut> cantGo(String taskId, String reason, {String? note}) async {
    _guard('cantGo:$taskId:$reason');
    _task(taskId)['status'] = 'CANT_GO';
    _task(taskId)['cant_go_reason'] = reason;
    return TaskOut.fromJson(_task(taskId));
  }

  @override
  Future<TaskOut> reached(String taskId, String outcome, {String? note}) async {
    _guard('reached:$taskId:$outcome');
    _task(taskId)['status'] = 'REACHED';
    _task(taskId)['outcome'] = outcome;
    return TaskOut.fromJson(_task(taskId));
  }
}

class Harness {
  Harness(this.api, this.controller, this.effects, this.launcher, this.notifier);
  final FakeApi api;
  final AppController controller;
  final RecordingAlertEffects effects;
  final RecordingLauncher launcher;
  final NoopNotifier notifier;
}

/// Builds the app with fakes. [signedIn] stores a token so bootstrap loads `/me`.
Future<Harness> pumpApp(
  WidgetTester tester, {
  FakeApi? api,
  bool signedIn = true,
  String lang = 'en',
  Set<String> announced = const {},
  bool introSeen = true,
  bool settleAfter = true,
}) async {
  SharedPreferences.setMockInitialValues({
    'ui.language': lang,
    'ui.language_chosen': true,
    'ui.intro_seen': introSeen,
    if (signedIn) 'auth.token': 'tok',
    'alerts.announced': announced.toList(),
  });
  final prefs = await SharedPreferences.getInstance();
  final fake = api ?? FakeApi();
  final queue = OfflineQueue(MemoryBox());
  final effects = RecordingAlertEffects();
  final launcher = RecordingLauncher();
  final notifier = NoopNotifier();
  final controller = AppController(
    config: AppConfig(apiBaseUrl: 'http://test.invalid'),
    api: fake,
    session: SessionStore(prefs),
    queue: queue,
    alerts: AlertRepository(fake, MemoryBox(), queue),
    connectivity: ConnectivityService(listenToPlatform: false),
    notifier: notifier,
    effects: effects,
    location: const NoLocation(),
    permissions: FakePermissionGateway(),
    launcher: launcher,
    enableLiveUpdates: false,
    enableMapTiles: false,
  );
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AapdaSaathiApp(controller: controller));
  await tester.runAsync(controller.bootstrap);
  if (settleAfter) {
    await settle(tester);
  } else {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  return Harness(fake, controller, effects, launcher, notifier);
}

/// Lets fire-and-forget futures (refresh, flush) finish, then settles the UI.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    // Also advances fake time past the controller's 300 ms refresh debounce.
    await tester.pump(const Duration(milliseconds: 350));
  }
  await tester.pumpAndSettle();
}

/// Scrolls [finder] into view and taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}
