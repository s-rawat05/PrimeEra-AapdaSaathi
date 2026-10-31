import 'package:flutter/widgets.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/realtime.dart';
import 'auth_controller.dart';

/// Dependency container exposed to the widget tree.
class AppServices {
  AppServices({required this.config, required this.api, required this.auth, required this.realtime});

  final AppConfig config;
  final AapdaApi api;
  final AuthController auth;
  final RealtimeHub realtime;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing from widget tree');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => oldWidget.services != services;
}

extension AppScopeX on BuildContext {
  AppServices get services => AppScope.of(this);
  AapdaApi get api => AppScope.of(this).api;
}
