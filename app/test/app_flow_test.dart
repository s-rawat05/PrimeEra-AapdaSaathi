import 'package:aapda_saathi/core/api_exception.dart';
import 'package:aapda_saathi/l10n/strings.dart';
import 'package:aapda_saathi/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const en = Strings('en');
const hi = Strings('hi');

void main() {
  group('auth states', () {
    testWidgets('logged out shows login; demo personas listed by role and labelled DEMO', (tester) async {
      final api = FakeApi()
        ..personas = [
          DemoPersona(userId: 'u1', fullName: 'Ramesh Joshi', role: UserRole.resident, description: 'Deaf resident'),
          DemoPersona(userId: 'u2', fullName: 'Aman Verma (NSS)', role: UserRole.volunteer, description: 'Volunteer'),
        ];
      await pumpApp(tester, api: api, signedIn: false);
      expect(find.text(en.sendCode), findsOneWidget);
      expect(find.text(en.demoPersonas), findsOneWidget);
      expect(find.textContaining('DEMO'), findsWidgets);
      expect(find.text('RESIDENT'), findsOneWidget);
      expect(find.text('VOLUNTEER'), findsOneWidget);
      expect(find.text('Deaf resident'), findsOneWidget);

      await tester.tap(find.text('Ramesh Joshi'));
      await settle(tester);
      expect(api.calls, contains('demoLogin:u1'));
      expect(find.byKey(const Key('greeting')), findsOneWidget);
    });

    testWidgets('no persona section when the list is empty; OTP flow shows demo hint', (tester) async {
      final api = FakeApi();
      await pumpApp(tester, api: api, signedIn: false);
      expect(find.text(en.demoPersonas), findsNothing);
      await tester.enterText(find.byKey(const Key('phone-field')), '9000000002');
      await tester.tap(find.byKey(const Key('send-code')));
      await settle(tester);
      expect(api.calls, contains('requestOtp'));
      expect(find.byKey(const Key('demo-otp-hint')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('code-field')), '123456');
      await tester.tap(find.byKey(const Key('verify')));
      await settle(tester);
      expect(api.calls, contains('verifyOtp'));
      expect(find.byKey(const Key('greeting')), findsOneWidget);
    });

    testWidgets('first launch shows the intro', (tester) async {
      await pumpApp(tester, signedIn: false, introSeen: false);
      expect(find.text(en.introTitle1), findsOneWidget);
      await tester.tap(find.text(en.skip));
      await settle(tester);
      expect(find.text(en.sendCode), findsOneWidget);
    });
  });

  group('navigation by role', () {
    Future<void> check(WidgetTester tester, String role, Finder expected) async {
      final api = FakeApi()..meJson = meFor(role);
      await pumpApp(tester, api: api);
      expect(expected, findsOneWidget, reason: role);
    }

    testWidgets('resident', (t) => check(t, 'resident', find.byKey(const Key('tab-evacuate'))));
    testWidgets('caregiver', (t) => check(t, 'caregiver', find.byKey(const Key('tab-people'))));
    testWidgets('neighbour', (t) => check(t, 'neighbour', find.byKey(const Key('tab-checks'))));
    testWidgets('volunteer', (t) => check(t, 'volunteer', find.byKey(const Key('tab-tasks'))));
    testWidgets('operator → web command centre notice', (t) => check(t, 'operator', find.text(en.opsTitle)));
    testWidgets('resident without profile → onboarding', (tester) async {
      final me = meFor('resident')..['resident'] = null;
      final api = FakeApi()..meJson = me;
      await pumpApp(tester, api: api);
      expect(find.text(en.needsTitle), findsOneWidget);
    });
  });

  group('resident home and alert', () {
    testWidgets('no active alerts', (tester) async {
      await pumpApp(tester);
      expect(find.text(en.greeting('Ramesh')), findsOneWidget);
      expect(find.text('Sarovar Nagar (DEMO ward DW-01)'), findsOneWidget);
      expect(find.text(en.noActiveAlerts), findsOneWidget);
      expect(find.byKey(const Key('sos-pill')), findsOneWidget);
    });

    testWidgets('active alert card and alert detail separate framing from official text', (tester) async {
      final a = alertJson(modes: []);
      final api = FakeApi()..alerts = [a];
      await pumpApp(tester, api: api, announced: {'a:${a['delivery_id']}'});
      expect(find.byKey(const Key('active-alert-card')), findsOneWidget);
      expect(find.text('AapdaSaathi: Flood alert'), findsOneWidget);

      await tester.tap(find.text(en.viewAlert));
      await settle(tester);
      expect(find.textContaining('AapdaSaathi presentation of an official alert'), findsOneWidget);
      expect(find.byKey(const Key('official-section')), findsOneWidget);
      expect(find.text(en.officialText), findsOneWidget);
      final official = AlertOut.fromJson(a).official;
      expect(find.text(official.headline!), findsWidgets);
      expect(find.text(official.instruction!), findsOneWidget);
      expect(find.textContaining('DRILL TIMING'), findsOneWidget);
    });

    testWidgets('a new alert opens the emergency screen, starts effects and notifies', (tester) async {
      final api = FakeApi()..alerts = [alertJson(modes: ['vibrate'])];
      (api.meJson['resident'] as Map)['needs'] = <String>[]; // so only the alert's own modes apply
      final h = await pumpApp(tester, api: api);
      expect(find.text(en.areYouSafe), findsWidgets);
      expect(h.notifier.shown.single, startsWith('alert:'));
      expect(h.effects.log.first, 'start:vibrate');
    });

    testWidgets('flash_screen shows a stoppable flashing overlay', (tester) async {
      final api = FakeApi()..alerts = [alertJson(modes: ['flash_screen'])];
      final h = await pumpApp(tester, api: api, settleAfter: false);
      expect(h.effects.flashing.value, isTrue);
      await tester.tap(find.text(en.stopAlarm).last);
      await tester.pump(const Duration(seconds: 1));
      expect(h.effects.flashing.value, isFalse);
      await h.effects.stop();
      await tester.pumpAndSettle();
    });

    testWidgets('error state is shown', (tester) async {
      final api = FakeApi()..alertsError = const ApiException(code: 'boom', message: 'Server exploded', statusCode: 500);
      await pumpApp(tester, api: api);
      expect(find.text('Server exploded'), findsOneWidget);
    });
  });

  group('emergency response', () {
    Future<Harness> openEmergency(WidgetTester tester, {bool offline = false}) async {
      final a = alertJson(modes: []);
      final api = FakeApi()..alerts = [a];
      final h = await pumpApp(tester, api: api, announced: {'a:${a['delivery_id']}'});
      api.offline = offline;
      await tapVisible(tester, find.byKey(const Key('respond-now')));
      await settle(tester);
      return h;
    }

    testWidgets('SAFE/HELP/SOS have semantics labels', (tester) async {
      final handle = tester.ensureSemantics();
      await openEmergency(tester);
      expect(find.bySemanticsLabel(en.safeSemantics), findsOneWidget);
      expect(find.bySemanticsLabel(en.helpSemantics), findsOneWidget);
      Navigator.of(tester.element(find.byKey(const Key('btn-safe')))).pop();
      await settle(tester);
      expect(find.bySemanticsLabel(en.sosSemantics), findsWidgets);
      handle.dispose();
    });

    testWidgets('SAFE needs confirmation, then calls the API with an idempotency key', (tester) async {
      final h = await openEmergency(tester);
      await tapVisible(tester, find.byKey(const Key('btn-safe')));
      await tester.pumpAndSettle();
      expect(find.text(en.confirmSafe), findsOneWidget);
      expect(h.api.responds, isEmpty);
      await tester.tap(find.byKey(const Key('btn-confirm')));
      await settle(tester);
      expect(h.api.responds.single.$2, 'SAFE');
      expect(h.api.responds.single.$3, isNotEmpty);
      expect(find.text(en.safeConfirmedTitle), findsWidgets);
    });

    testWidgets('HELP confirmation calls the API and shows help status', (tester) async {
      final h = await openEmergency(tester);
      await tapVisible(tester, find.byKey(const Key('btn-help')));
      await tester.pumpAndSettle();
      expect(find.text(en.confirmHelp), findsOneWidget);
      await tester.tap(find.byKey(const Key('btn-confirm')));
      await settle(tester);
      expect(h.api.responds.single.$2, 'HELP');
      expect(find.byKey(const Key('assistance-summary')), findsOneWidget);
    });

    testWidgets('cancel on the confirm step sends nothing', (tester) async {
      final h = await openEmergency(tester);
      await tapVisible(tester, find.byKey(const Key('btn-help')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-cancel')));
      await tester.pumpAndSettle();
      expect(h.api.responds, isEmpty);
      expect(find.byKey(const Key('btn-safe')), findsOneWidget);
    });

    testWidgets('offline: reply is queued and never shown as delivered; flushes on reconnect', (tester) async {
      final h = await openEmergency(tester, offline: true);
      await tapVisible(tester, find.byKey(const Key('btn-safe')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn-confirm')));
      await settle(tester);
      expect(find.textContaining(en.queuedNotDelivered), findsWidgets);
      expect(find.text(en.safeConfirmedTitle), findsNothing);
      expect(h.controller.queue.length, 1);
      expect(h.api.responds, isEmpty);

      h.api.offline = false;
      await tester.runAsync(h.controller.refresh);
      await settle(tester);
      expect(h.controller.queue.isEmpty, isTrue);
      expect(h.api.responds.single.$2, 'SAFE');
    });

    testWidgets('Reply by SMS opens the SMS app with 1 / 2', (tester) async {
      final h = await openEmergency(tester);
      await tester.ensureVisible(find.byKey(const Key('sms-help')));
      await tester.tap(find.byKey(const Key('sms-help')));
      await tester.pumpAndSettle();
      expect(h.launcher.opened.single.scheme, 'sms');
      expect(h.launcher.opened.single.query, 'body=2');
    });
  });

  testWidgets('evacuation shows relief post, direction-only line and ESTIMATE', (tester) async {
    final a = alertJson(modes: []);
    final api = FakeApi()..alerts = [a];
    final h = await pumpApp(tester, api: api, announced: {'a:${a['delivery_id']}'});
    await tester.tap(find.byKey(const Key('tab-evacuate')));
    await settle(tester);
    expect(find.textContaining('Demo Relief Post A'), findsWidgets);
    expect(find.byKey(const Key('direction-only')), findsOneWidget);
    expect(find.byKey(const Key('walk-estimate')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('open-in-maps')));
    await tester.pumpAndSettle();
    expect(h.launcher.opened.single.host, 'www.google.com');
  });

  testWidgets('evacuation says so when no relief post is registered', (tester) async {
    final a = alertJson(modes: [], shelters: false);
    final api = FakeApi()..alerts = [a];
    await pumpApp(tester, api: api, announced: {'a:${a['delivery_id']}'});
    await tester.tap(find.byKey(const Key('tab-evacuate')));
    await settle(tester);
    expect(find.byKey(const Key('no-relief-post')), findsOneWidget);
  });

  testWidgets('language switching changes strings instantly and syncs PATCH /me', (tester) async {
    final h = await pumpApp(tester);
    expect(find.text(en.navHome), findsOneWidget);
    await tester.tap(find.byKey(const Key('tab-profile')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('lang-hi')));
    await settle(tester);
    expect(find.text(hi.navHome), findsOneWidget);
    expect(find.text(hi.profileTitle), findsWidgets);
    expect(h.api.calls, contains('patchMe:hi'));
  });

  group('volunteer', () {
    Future<Harness> open(WidgetTester tester) async {
      final api = FakeApi()
        ..meJson = meFor('volunteer')
        ..tasks = [taskJson(id: 'task-1')];
      return pumpApp(tester, api: api, announced: {'t:task-1'});
    }

    testWidgets('accept calls the API', (tester) async {
      final h = await open(tester);
      await tapVisible(tester, find.byKey(const Key('accept-task-1')));
      await settle(tester);
      expect(h.api.calls, contains('accept:task-1'));
      expect(find.text(en.taskStatusName('ACCEPTED')), findsWidgets);
    });

    testWidgets("can't go requires a reason", (tester) async {
      final h = await open(tester);
      await tapVisible(tester, find.byKey(const Key('cantgo-task-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cant-go-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reason-required')), findsOneWidget);
      expect(h.api.calls.where((c) => c.startsWith('cantGo')), isEmpty);

      await tester.tap(find.byKey(const Key('reason-route_blocked')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cant-go-submit')));
      await settle(tester);
      expect(h.api.calls, contains('cantGo:task-1:route_blocked'));
    });

    testWidgets('availability toggle calls PUT', (tester) async {
      final h = await open(tester);
      await tester.tap(find.byKey(const Key('availability')));
      await settle(tester);
      expect(h.api.calls, contains('availability:false'));
    });

    testWidgets('reached with needs_rescue requires a note', (tester) async {
      final api = FakeApi()
        ..meJson = meFor('volunteer')
        ..tasks = [taskJson(id: 'task-2', status: 'ACCEPTED')];
      await pumpApp(tester, api: api, announced: {'t:task-2'});
      await tester.tap(find.text('Sunita'));
      await settle(tester);
      expect(find.byKey(const Key('call-resident')), findsOneWidget);
      expect(find.byKey(const Key('walk-note')), findsOneWidget);
      await tester.tap(find.byKey(const Key('detail-reached')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('outcome-needs_rescue')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reached-submit')));
      await tester.pumpAndSettle();
      expect(find.text(en.noteRequiredForOutcome), findsOneWidget);
      await tester.enterText(find.byKey(const Key('reached-note')), 'Water at the door');
      await tester.tap(find.byKey(const Key('reached-submit')));
      await settle(tester);
      expect(api.calls, contains('reached:task-2:needs_rescue'));
    });
  });

  testWidgets('neighbour answers a check', (tester) async {
    final api = FakeApi()
      ..meJson = meFor('neighbour')
      ..checks = fixtureList('checks_vikram');
    final id = api.checks.first['id'] as String;
    await pumpApp(tester, api: api, announced: {for (final c in api.checks) 'c:${c['id']}'});
    await tapVisible(tester, find.byKey(Key('check-cannot-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('check-confirm')));
    await settle(tester);
    expect(api.calls, contains('neighbourRespond:CANNOT_REACH'));
  });

  testWidgets('caregiver responds on behalf with a note', (tester) async {
    final api = FakeApi()..meJson = meFor('caregiver');
    await pumpApp(tester, api: api, announced: {
      for (final r in fixtureList('caregiver'))
        for (final al in (r['active_alerts'] as List)) 'g:${(al as Map)['delivery_id']}:${al['status']}',
    });
    final first = fixtureList('caregiver').first['active_alerts'] as List;
    final d = (first.first as Map)['delivery_id'];
    await tapVisible(tester, find.byKey(Key('cg-safe-$d')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('caregiver-note')), 'Spoke on phone');
    await tester.tap(find.byKey(const Key('caregiver-confirm')));
    await settle(tester);
    expect(api.calls, contains('caregiverRespond:SAFE:Spoke on phone'));
  });
}
