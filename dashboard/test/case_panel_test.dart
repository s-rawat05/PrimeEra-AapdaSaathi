import 'package:aapda_command/features/dispatch/case_panel.dart';
import 'package:aapda_command/features/overview/command_centre_controller.dart';
import 'package:aapda_command/models/models.dart';
import 'package:aapda_command/services/app_scope.dart';
import 'package:aapda_command/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_api.dart';

void main() {
  testWidgets('case panel opens and its override button opens the reason dialog', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = FakeApi();
    final services = fakeServices(api);
    final cc = CommandCentreController(api: api, realtime: services.realtime);
    addTearDown(cc.dispose);
    await cc.refreshAll();
    final first = asJsonList(fixture('priority')).first['delivery_id'] as String;
    await tester.pumpWidget(AppScope(
      services: services,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(onPressed: () => openCasePanel(context, cc, first), child: const Text('case')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('case'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(CasePanel), findsOneWidget);
    expect(api.called('candidates'), isTrue);
    expect(api.called('deliveryTimeline'), isTrue);
    await tester.tap(find.byKey(const Key('case-override')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(OverrideDialog), findsOneWidget);
  });
}
