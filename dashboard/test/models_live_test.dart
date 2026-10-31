// Parses every response captured from the real backend (port 8102, see test/fixtures/live/)
// through the app's model parsers. Parse mismatches with the API fail here.
import 'dart:convert';

import 'package:aapda_command/core/api_error.dart';
import 'package:aapda_command/core/realtime.dart';
import 'package:aapda_command/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  List<T> list<T>(String name, T Function(Json) f) => asJsonList(fixture(name)).map(f).toList();

  test('auth: token, me, personas', () {
    final t = TokenOut.fromJson(fixtureObj('token'));
    expect(t.accessToken, isNotEmpty);
    expect(t.user.role, 'operator');
    final me = MeOut.fromJson(fixtureObj('me'));
    expect(me.user.isOps, isTrue);
    expect(me.notifyRealResidents, isFalse);
    final p = list('demo_personas', DemoPersona.fromJson);
    expect(p.where((x) => x.isOps).length, 2);
  });

  test('incidents: single, list, manual, patched, closed', () {
    for (final n in ['incident', 'incident_manual', 'incident_patched', 'incident_closed']) {
      final i = Incident.fromJson(fixtureObj(n));
      expect(i.wards, isNotEmpty, reason: n);
      expect(i.modeLabel, isNotEmpty, reason: n);
    }
    final page = PageOf.fromJson(fixtureObj('incidents'), Incident.fromJson);
    expect(page.items, isNotEmpty);
    final inc = Incident.fromJson(fixtureObj('incident'));
    expect(inc.sourceTag, 'SIMULATED');
    expect(inc.isDemo, isTrue);
    expect(inc.counts.total, greaterThan(0));
    expect(Incident.fromJson(fixtureObj('incident_closed')).isActive, isFalse);
    expect(Incident.fromJson(fixtureObj('incident_patched')).severity, 'Severe');
  });

  test('priority list, override, resend', () {
    final p = list('priority', PriorityItem.fromJson);
    expect(p, isNotEmpty);
    for (final x in p) {
      expect(x.priorityComponents, isNotEmpty);
      expect(x.priorityComponents.fold<int>(0, (a, c) => a + c.points), x.priorityTotal, reason: x.residentName);
    }
    expect(PriorityItem.fromJson(fixtureObj('override')).status, 'SAFE');
    PriorityItem.fromJson(fixtureObj('resend'));
  });

  test('map', () {
    final m = IncidentMap.fromJson(fixtureObj('map'));
    expect(m.wards.first.boundaryGeojson, isNotNull);
    expect(m.markers, isNotEmpty);
    expect(m.markers.first.precision, contains('m'));
    expect(m.volunteers, isNotEmpty);
    expect(m.shelters, isNotEmpty);
  });

  test('tasks, approve/reject results, timeline, candidates, location', () {
    final tasks = list('tasks', TaskOut.fromJson);
    expect(tasks.where((t) => t.isPendingApproval).length, greaterThanOrEqualTo(2));
    list('tasks_after', TaskOut.fromJson);
    expect(TaskOut.fromJson(fixtureObj('approve_result')).status, 'ASSIGNED');
    expect(TaskOut.fromJson(fixtureObj('reject_result')).status, 'REJECTED');
    expect(list('timeline', TimelineEvent.fromJson), isNotEmpty);
    expect(list('delivery_timeline', TimelineEvent.fromJson), isNotEmpty);
    expect(list('candidates', CandidateOut.fromJson), isNotEmpty);
    expect(ExactLocationOut.fromJson(fixtureObj('location')).source, isNotEmpty);
  });

  test('feed status, messages, poll', () {
    final s = FeedStatus.fromJson(fixtureObj('feed_status'));
    expect(s.feeds, isNotEmpty);
    final m = PageOf.fromJson(fixtureObj('feed_messages'), CapMessage.fromJson);
    expect(m.items, isNotEmpty);
    final poll = asJsonList(fixture('feed_poll')).map(FeedPollResult.new).toList();
    expect(poll.first.summary, startsWith('HTTP'));
  });

  test('demo: status, reset, sms result, outbox', () {
    final d = DemoStatus.fromJson(fixtureObj('demo_status'));
    expect(d.fixtures, contains('demo_flash_flood_alert'));
    expect(d.escalationIntervalSeconds, greaterThan(0));
    expect(DemoResetOut.fromJson(fixtureObj('demo_reset')).realDataUntouched, isTrue);
    expect(SmsResult.fromJson(fixtureObj('sms_result')).result, isNotEmpty);
    SmsResult.fromJson(fixtureObj('sms_result_neighbour'));
    expect(list('outbox', OutboxItem.fromJson), isNotEmpty);
    expect(list('outbox_all', OutboxItem.fromJson).where((o) => o.recipientPhone != null), isNotEmpty);
  });

  test('reports (active and closed)', () {
    for (final n in ['report_active', 'report']) {
      final r = IncidentReport.fromJson(fixtureObj(n));
      expect(r.counts.total, greaterThan(0), reason: n);
      expect(r.notes, isNotEmpty, reason: n);
      expect(r.tasks.total, greaterThan(0), reason: n);
    }
  });

  test('admin lists', () {
    expect(list('wards', WardOut.fromJson), isNotEmpty);
    WardOut.fromJson(fixtureObj('ward_access'));
    expect(list('shelters', ShelterOut.fromJson), isNotEmpty);
    final res = PageOf.fromJson(fixtureObj('residents'), ResidentOut.fromJson);
    expect(res.items.first.consents, isNotEmpty);
    expect(list('volunteers', VolunteerOut.fromJson), isNotEmpty);
    VolunteerOut.fromJson(fixtureObj('volunteer_avail'));
    expect(list('neighbour_links', NeighbourLinkOut.fromJson), isNotEmpty);
    expect(list('pre_assigned', PreAssignedOut.fromJson), isNotEmpty);
    expect(list('templates', TemplateOut.fromJson).every((t) => t.body.contains('{headline}')), isTrue);
    expect(PageOf.fromJson(fixtureObj('users'), UserAdminOut.fromJson).items, isNotEmpty);
    expect(PageOf.fromJson(fixtureObj('audit'), AuditOut.fromJson).items, isNotEmpty);
  });

  test('error bodies', () {
    for (final (name, code) in [('error_422', 422), ('error_409', 409), ('error_403', 403)]) {
      final e = ApiException.fromResponse(code, jsonEncode(fixtureObj(name)));
      expect(e.statusCode, code);
      expect(e.message, isNotEmpty);
      expect(e.code, isNot('error'));
    }
  });

  test('realtime events from the live socket', () {
    final events = asJsonList(fixture('ws_events')).map((j) => RealtimeEvent(j['type'] as String, j)).toList();
    expect(events.first.type, 'hello');
    expect(events.where((e) => e.isRefreshHint), isNotEmpty);
  });
}
