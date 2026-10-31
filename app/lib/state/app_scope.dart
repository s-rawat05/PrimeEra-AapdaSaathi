import 'package:flutter/widgets.dart';

import '../l10n/strings.dart';
import 'app_controller.dart';

/// Exposes the [AppController] to the widget tree and rebuilds dependants when it changes.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({super.key, required AppController controller, required super.child})
      : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.notifier!;
  }

  /// Read without subscribing to changes (for callbacks).
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.notifier!;
  }
}

extension AppContextX on BuildContext {
  AppController get app => AppScope.of(this);
  AppController get appRead => AppScope.read(this);
  Strings get s => AppScope.of(this).s;
}
