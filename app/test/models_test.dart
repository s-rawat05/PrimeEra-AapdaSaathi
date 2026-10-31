import 'package:aapda_saathi/accessibility/modes.dart';
import 'package:aapda_saathi/core/config.dart';
import 'package:aapda_saathi/models/models.dart';
import 'package:aapda_saathi/services/local_store.dart';
import 'package:aapda_saathi/services/offline_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('models parse real backend JSON (test/fixtures captured from port 8101)', () {
    test('AlertOut', () {
      final a = AlertOut.fromJson(fixtureList('active_ramesh').first);
      expect(a.status, 'NO_REPLY');
      expect(a.awaitingReply, isTrue);
      expect(a.presentation.label, 'AapdaSaathi presentation of an official alert');
      expect(a.official.headline, startsWith('DEMO EXERCISE'));
      expect(a.official.onset, isNotNull);
      expect(a.official.onsetNote, contains('DRILL TIMING'));
      expect(a.shelters.single.distanceM, 294.0);
      expect(a.accessibilityModes, containsAll(['vibrate', 'flash_screen', 'torch_blink']));
    });

    test('easy-read alert (Hindi)', () {
      final a = AlertOut.fromJson(fixtureList('active_bhuwan').first);
      expect(a.presentation.easyReadSteps, hasLength(5));
      expect(AlertModes(a.accessibilityModes).stepByStep, isTrue);
    });

    test('MeOut for each role', () {
      expect(MeOut.fromJson(fixtureObj('me_ramesh')).resident!.needs, ['hearing']);
      expect(MeOut.fromJson(fixtureObj('me_neha')).user.role, UserRole.caregiver);
      expect(MeOut.fromJson(fixtureObj('me_vikram')).user.role, UserRole.neighbour);
      final v = MeOut.fromJson(fixtureObj('me_Aman'));
      expect(v.user.role, UserRole.volunteer);
      expect(v.volunteer!.isAvailable, isTrue);
    });

    test('caregiver, checks, history, wards', () {
      final cg = fixtureList('caregiver').map(CaregiverResidentOut.fromJson).toList();
      expect(cg.first.activeAlerts.first.status, 'NO_REPLY');
      final checks = fixtureList('checks_vikram').map(TaskOut.fromJson).toList();
      expect(checks.every((t) => t.kind == 'neighbour_check' && t.isOpen), isTrue);
      final page = PageOut.fromJson(fixtureObj('history_ramesh'), AlertOut.fromJson);
      expect(page.items, isNotEmpty);
      expect(fixtureList('wards').map(WardOut.fromJson), hasLength(2));
    });
  });

  test('accessibility modes are a union', () {
    final m = AlertModes.fromNeeds(['hearing', 'elderly_alone']);
    expect(m.raw, containsAll(['vibrate', 'flash_screen', 'large_text', 'repeat_reminders', 'large_controls']));
    expect(m.textScale, greaterThan(1));
  });

  test('realtime URI derives ws/wss from API_BASE_URL', () {
    expect(AppConfig(apiBaseUrl: 'http://10.0.2.2:8000').realtimeUri('abc').toString(),
        'ws://10.0.2.2:8000/api/v1/realtime?ticket=abc');
    expect(AppConfig(apiBaseUrl: 'https://api.example.org/').realtimeUri('x').toString(),
        'wss://api.example.org/api/v1/realtime?ticket=x');
  });

  test('offline queue keeps the same idempotency key across retries and flushes on reconnect', () async {
    final api = FakeApi()..alerts = [alertJson()];
    final q = OfflineQueue(MemoryBox());
    api.offline = true;
    final r = await q.send(api, 'd1', 'SAFE', 'key-1');
    expect(r.isDelivered, isFalse);
    expect(q.length, 1);
    await q.flush(api); // still offline
    expect(q.items.single.attempts, 2);
    api.offline = false;
    expect(await q.flush(api), 1);
    expect(q.isEmpty, isTrue);
    expect(api.responds.single, ('d1', 'SAFE', 'key-1'));
  });
}
