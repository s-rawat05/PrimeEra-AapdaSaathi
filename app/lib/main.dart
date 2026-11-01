import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accessibility/alert_effects.dart';
import 'accessibility/voice_input.dart';
import 'app.dart';
import 'core/api_client.dart';
import 'core/config.dart';
import 'repositories/alert_repository.dart';
import 'services/connectivity_service.dart';
import 'services/device_services.dart';
import 'services/local_store.dart';
import 'services/notification_service.dart';
import 'services/offline_queue.dart';
import 'services/push_service.dart';
import 'services/session_store.dart';
import 'services/supabase_auth.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig();
  final prefs = await SharedPreferences.getInstance();
  final session = SessionStore(prefs);

  // Hive: offline reply queue + non-sensitive alert cache. Falls back to memory if storage fails.
  LocalBox queueBox;
  LocalBox cacheBox;
  try {
    queueBox = await HiveBox.open('reply_queue');
    cacheBox = await HiveBox.open('alert_cache');
  } catch (e) {
    debugPrint('Local storage unavailable, using memory: $e');
    queueBox = MemoryBox();
    cacheBox = MemoryBox();
  }

  final api = HttpAapdaApi(config);
  final connectivity = ConnectivityService();
  api.onReachability = connectivity.reportRequest;
  final queue = OfflineQueue(queueBox);

  final controller = AppController(
    config: config,
    api: api,
    session: session,
    queue: queue,
    alerts: AlertRepository(api, cacheBox, queue),
    connectivity: connectivity,
    notifier: LocalEmergencyNotifier(),
    effects: DeviceAlertEffects(),
    location: GeolocatorLocation(),
    permissions: HandlerPermissionGateway(),
    launcher: UrlExternalLauncher(),
    push: PushService(config),
    supabase: SupabaseAuth(config),
    voice: DeviceVoiceInput(),
  );

  runApp(AapdaSaathiApp(controller: controller));
  await controller.bootstrap();
}
