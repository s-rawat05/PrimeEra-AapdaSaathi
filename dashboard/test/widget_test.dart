import 'package:aapda_command/app.dart';
import 'package:aapda_command/core/api_error.dart';
import 'package:aapda_command/features/dispatch/case_panel.dart';
import 'package:aapda_command/features/dispatch/tasks_panel.dart';
import 'package:aapda_command/features/reports/report_page.dart';
import 'package:aapda_command/models/models.dart';
import 'package:aapda_command/services/app_scope.dart';
import 'package:aapda_command/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

Future<void> _desktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1700, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget _host(FakeApi api, Widget child) => AppScope(
      services: fakeServices(api),
      child: MaterialApp(theme: buildAppTheme(), home: Scaffold(body: child)),
    );

void main() {
  group('authentication', () {
    testWidgets('login screen shows only admin/operator demo personas', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      await tester.pumpWidget(AapdaCommandApp(services: fakeServices(api)));
      await _settle(tester);

      expect(find.text('Operations sign-in'), findsOneWidget);
      expect(find.byKey(const Key('demo-picker')), findsOneWidget);
      expect(find.byKey(const Key('persona-admin')), findsOneWidget);
      expect(find.byKey(const Key('persona-operator')), findsOneWidget);
      // Residents / neighbours / caregivers from the same endpoint are not offered.
      expect(find.byKey(const Key('persona-resident')), findsNothing);
      expect(find.text('Neha Bisht'), findsNothing);
    });

    testWidgets('password login validates and calls POST /auth/login', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      await tester.pumpWidget(AapdaCommandApp(services: fakeServices(api)));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('login-submit')));
      await tester.pump();
      expect(find.text('Enter your email or phone'), findsOneWidget);
      expect(api.called('login'), isFalse);

      await tester.enterText(find.byKey(const Key('login-identifier')), 'operator@demo.aapdasaathi.invalid');
      await tester.enterText(find.byKey(const Key('login-password')), 'secret-password');
      await tester.tap(find.byKey(const Key('login-submit')));
      await _settle(tester);
      expect(api.called('login:operator@demo.aapdasaathi.invalid'), isTrue);
      expect(api.called('me'), isTrue);
      expect(find.text('Command centre'), findsWidgets);
    });

    testWidgets('demo persona login opens the command centre', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      await tester.pumpWidget(AapdaCommandApp(services: fakeServices(api)));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('persona-operator')));
      await _settle(tester, 20);
      expect(api.called('demoLogin:'), isTrue);
      expect(find.byKey(const Key('drill-badge')), findsOneWidget);
    });

    testWidgets('non-ops role is blocked', (tester) async {
      await _desktop(tester);
      final api = FakeApi(role: 'volunteer');
      final services = fakeServices(api, token: 'persisted-token');
      await tester.pumpWidget(AapdaCommandApp(services: services));
      await _settle(tester);

      expect(find.text('This console is for operations staff'), findsOneWidget);
      expect(find.text('Command centre'), findsNothing);
      expect(api.called('listIncidents'), isFalse);
    });
  });

  group('command centre', () {
    testWidgets('renders counters, priority list and score breakdown from the API', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      await tester.pumpWidget(AapdaCommandApp(services: fakeServices(api, token: 'persisted-token')));
      await _settle(tester, 30);

      final inc = Incident.fromJson(fixtureObj('incident'));
      final pri = asJsonList(fixture('priority')).map(PriorityItem.fromJson).toList();

      // Counters come from incident.counts.
      expect(tester.widget<Text>(find.byKey(const Key('counter-noreply'))).data, '${inc.counts.noReply}');
      expect(tester.widget<Text>(find.byKey(const Key('counter-total'))).data, '${inc.counts.total}');
      expect(tester.widget<Text>(find.byKey(const Key('counter-safe'))).data, '${inc.counts.safe}');

      // Badges.
      expect(find.byKey(const Key('drill-badge')), findsOneWidget);
      expect(find.text('SIMULATED'), findsOneWidget);
      expect(find.text('Real-resident notifications: OFF'), findsOneWidget);

      // Top-ranked resident with every priority component and the total.
      final top = pri.first;
      expect(find.byKey(ValueKey('priority-${top.deliveryId}')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(ValueKey('score-${top.deliveryId}'))).data, '${top.priorityTotal}');
      for (final c in top.priorityComponents) {
        expect(find.text('+${c.points} ${c.factor}'), findsWidgets);
      }
      expect(find.text('= ${top.priorityTotal}'), findsWidgets);

      // Every view was fetched from the API.
      for (final c in ['listIncidents', 'getIncident', 'priority', 'map', 'tasks', 'timeline', 'feedStatus', 'demoStatus']) {
        expect(api.called(c), isTrue, reason: c);
      }
    });
  });

  group('case actions', () {
    testWidgets('override dialog requires a reason before calling the API', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      final deliveryId = asJsonList(fixture('priority')).first['delivery_id'] as String;
      await tester.pumpWidget(_host(api, Builder(builder: (context) {
        return Center(
          child: ElevatedButton(
            onPressed: () => showDialog<PriorityItem>(
              context: context,
              builder: (_) => OverrideDialog(api: api, deliveryId: deliveryId, currentStatus: 'NO_REPLY'),
            ),
            child: const Text('open'),
          ),
        );
      })));
      await tester.tap(find.text('open'));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('override-submit')));
      await tester.pump();
      expect(find.text('A reason of at least 5 characters is required'), findsOneWidget);
      expect(api.called('override'), isFalse);

      await tester.enterText(find.byKey(const Key('override-reason')), 'abc');
      await tester.tap(find.byKey(const Key('override-submit')));
      await tester.pump();
      expect(api.called('override'), isFalse);

      await tester.enterText(find.byKey(const Key('override-reason')), 'Confirmed safe by phone call');
      await tester.tap(find.byKey(const Key('override-submit')));
      await _settle(tester);
      expect(api.calls, contains('override:$deliveryId:SAFE:Confirmed safe by phone call'));
      expect(find.byType(OverrideDialog), findsNothing);
    });

    testWidgets('approve and reject buttons call the API', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      final tasks = asJsonList(fixture('tasks')).map(TaskOut.fromJson).toList();
      final pending = tasks.where((t) => t.isPendingApproval).toList();
      expect(pending.length, greaterThanOrEqualTo(2), reason: 'fixture should contain two pending approvals');
      var refreshed = 0;
      await tester.pumpWidget(_host(
        api,
        SingleChildScrollView(
          child: TasksPanel(
            api: api,
            tasks: tasks,
            onChanged: () async => refreshed++,
            onOpenCase: (_) {},
          ),
        ),
      ));
      await _settle(tester);

      await tester.tap(find.byKey(Key('approve-${pending[0].id}')));
      await _settle(tester);
      expect(api.calls, contains('approve:${pending[0].id}'));
      expect(refreshed, 1);

      await tester.ensureVisible(find.byKey(Key('reject-${pending[1].id}')));
      await tester.tap(find.byKey(Key('reject-${pending[1].id}')));
      await _settle(tester);
      // Reason is mandatory.
      await tester.tap(find.byKey(const Key('reason-submit')));
      await tester.pump();
      expect(api.called('reject'), isFalse);
      await tester.enterText(find.byKey(const Key('reason-field')), 'Route along the stream is flooded');
      await tester.tap(find.byKey(const Key('reason-submit')));
      await _settle(tester);
      expect(api.calls, contains('reject:${pending[1].id}:Route along the stream is flooded'));
      expect(refreshed, 2);
    });

    testWidgets('409 from approve is shown to the operator', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      final tasks = asJsonList(fixture('tasks')).map(TaskOut.fromJson).toList();
      final pending = tasks.firstWhere((t) => t.isPendingApproval);
      // Same body shape the backend returns for this conflict (dispatch/service.py `no_longer_safe`).
      api.failNext = const ApiException(
        statusCode: 409,
        code: 'no_longer_safe',
        message: 'Dispatch is no longer safe: Already on an active task. Reassign or reject.',
      );
      await tester.pumpWidget(_host(
        api,
        SingleChildScrollView(child: TasksPanel(api: api, tasks: tasks, onChanged: () async {}, onOpenCase: (_) {})),
      ));
      await tester.tap(find.byKey(Key('approve-${pending.id}')));
      await _settle(tester);
      expect(find.textContaining('Dispatch is no longer safe'), findsOneWidget);
    });
  });

  group('report', () {
    testWidgets('closing report renders from GET /incidents/{id}/report', (tester) async {
      await _desktop(tester);
      final api = FakeApi();
      final report = IncidentReport.fromJson(fixtureObj('report'));
      await tester.pumpWidget(AppScope(
        services: fakeServices(api),
        child: MaterialApp(theme: buildAppTheme(), home: ReportPage(api: api, incidentId: report.incident.id)),
      ));
      await _settle(tester);

      expect(api.called('report:${report.incident.id}'), isTrue);
      expect(find.text('Closing report'), findsOneWidget);
      expect(find.text(report.incident.title), findsOneWidget);
      expect(find.text('Alert-to-safe time'), findsOneWidget);
      expect(find.text('Unresolved (${report.unresolved.length})'), findsOneWidget);
      expect(find.byKey(const Key('report-download')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-download')));
      await _settle(tester);
      expect(api.called('reportCsv:${report.incident.id}'), isTrue);
    });
  });
}
