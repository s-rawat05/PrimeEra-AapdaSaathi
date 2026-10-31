import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/config.dart';

/// Optional Firebase Cloud Messaging. Only active when all FIREBASE_* dart-defines are set;
/// otherwise the app relies on realtime + polling + SMS. Never throws.
///
/// NOT verified end-to-end: no Firebase project or physical device was available while building.
class PushService {
  PushService(this.config);

  final AppConfig config;
  bool _initialised = false;
  bool get enabled => _initialised;

  /// Called when a push arrives in the foreground (treated as a "refetch" hint, like realtime).
  VoidCallback? onMessage;

  Future<void> init() async {
    if (!config.hasFirebase) return;
    try {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          apiKey: config.firebaseApiKey,
          appId: config.firebaseAppId,
          messagingSenderId: config.firebaseSenderId,
          projectId: config.firebaseProjectId,
        ),
      );
      FirebaseMessaging.onMessage.listen((_) => onMessage?.call());
      FirebaseMessaging.onMessageOpenedApp.listen((_) => onMessage?.call());
      _initialised = true;
    } catch (e) {
      debugPrint('Firebase disabled: $e');
    }
  }

  /// Registers this device's FCM token with the backend (`POST /me/devices`).
  Future<void> registerWith(AapdaApi api) async {
    if (!_initialised) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      // The backend sends through FCM registration tokens; the newer register()/onRegistered API
      // yields a Firebase Installation ID instead, so the classic token call is kept deliberately.
      // ignore: deprecated_member_use
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.length < 10) return;
      final platform = kIsWeb
          ? 'web'
          : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
      await api.registerDevice(token, platform);
    } catch (e) {
      debugPrint('FCM registration failed: $e');
    }
  }
}
