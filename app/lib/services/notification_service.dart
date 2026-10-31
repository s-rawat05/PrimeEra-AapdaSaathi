import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Shows the emergency notification and reports taps (payload = route hint, e.g. `alert:<id>`).
abstract class EmergencyNotifier {
  Future<void> init({required void Function(String payload) onTap});
  Future<void> show({required int id, required String title, required String body, required String payload});
  Future<bool> requestPermission();

  /// Payload of the notification that launched the app, if any.
  Future<String?> launchPayload();
}

class NoopNotifier implements EmergencyNotifier {
  final List<String> shown = [];

  @override
  Future<void> init({required void Function(String payload) onTap}) async {}

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async {
    shown.add(payload);
  }

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> launchPayload() async => null;
}

class LocalEmergencyNotifier implements EmergencyNotifier {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const channelId = 'aapda_emergency';

  static final _channel = AndroidNotificationChannel(
    channelId,
    'Emergency alerts',
    description: 'Official disaster alerts that need your reply (SAFE / HELP).',
    importance: Importance.max,
    // Android only honours this if the user granted Do Not Disturb access; otherwise it is ignored.
    bypassDnd: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  @override
  Future<void> init({required void Function(String payload) onTap}) async {
    if (kIsWeb) return; // Browser notifications are not used; the in-app alert screen still opens.
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) onTap(p);
        },
      );
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission() ?? false;
      // Android 14+: full-screen intents need a separate user grant for non-calling/alarm apps.
      await android?.requestFullScreenIntentPermission();
      return granted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> show({required int id, required String title, required String body, required String payload}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            ticker: title,
            visibility: NotificationVisibility.public,
            audioAttributesUsage: AudioAttributesUsage.alarm,
            vibrationPattern: Int64List.fromList([0, 800, 400, 800, 400, 800]),
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Could not show notification: $e');
    }
  }

  @override
  Future<String?> launchPayload() async {
    if (!_ready) return null;
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d?.didNotificationLaunchApp ?? false) return d?.notificationResponse?.payload;
    } catch (_) {}
    return null;
  }
}
