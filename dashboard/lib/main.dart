import 'package:flutter/material.dart';

import 'app.dart';
import 'core/config.dart';
import 'core/http_api.dart';
import 'core/realtime.dart';
import 'core/session_store.dart';
import 'services/app_scope.dart';
import 'services/auth_controller.dart';

void main() {
  final config = AppConfig.fromEnvironment();
  final api = HttpAapdaApi(config);
  final services = AppServices(
    config: config,
    api: api,
    auth: AuthController(api: api, store: SharedPrefsSessionStore()),
    realtime: WebSocketRealtimeHub(api),
  );
  runApp(AapdaCommandApp(services: services));
}
