import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'features/alerts/emergency_response_screen.dart';
import 'features/caregiver/caregiver_screen.dart';
import 'features/neighbour/neighbour_checks_screen.dart';
import 'features/volunteer/task_detail_screen.dart';
import 'routing/root_gate.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/app_theme.dart';
import 'widgets/flash_overlay.dart';

class AapdaSaathiApp extends StatefulWidget {
  const AapdaSaathiApp({super.key, required this.controller});
  final AppController controller;

  @override
  State<AapdaSaathiApp> createState() => _AapdaSaathiAppState();
}

class _AapdaSaathiAppState extends State<AapdaSaathiApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  String? _lastTarget;

  @override
  void initState() {
    super.initState();
    widget.controller.onEmergency = _openEmergency;
    _lifecycle = AppLifecycleListener(onResume: () => widget.controller.refresh());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// Opens the screen for a new alert/task (from the poll loop or a notification tap).
  void _openEmergency(EmergencyTarget target) {
    final nav = _navigator.currentState;
    if (nav == null) return;
    final (String id, WidgetBuilder builder) = switch (target) {
      AlertTarget(:final deliveryId) => ('a:$deliveryId', (_) => EmergencyResponseScreen(deliveryId: deliveryId)),
      TaskTarget(:final taskId) => ('t:$taskId', (_) => TaskDetailScreen(taskId: taskId)),
      CheckTarget(:final taskId) => ('c:$taskId', (_) => NeighbourChecksScreen(focusTaskId: taskId)),
      CaregiverTarget() => ('g', (_) => const CaregiverScreen()),
    };
    if (_lastTarget == id && nav.canPop()) return; // already showing it
    _lastTarget = id;
    nav.push(MaterialPageRoute(builder: builder, settings: RouteSettings(name: id)));
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.controller;
    return AppScope(
      controller: app,
      child: ListenableBuilder(
        listenable: app,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigator,
          title: 'AapdaSaathi',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          locale: Locale(app.lang),
          supportedLocales: const [Locale('en'), Locale('hi')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) {
            final scale = app.profileModes.textScale;
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * scale)),
              child: FlashOverlay(effects: app.effects, strings: app.s, child: child ?? const SizedBox.shrink()),
            );
          },
          home: const RootGate(),
        ),
      ),
    );
  }
}
