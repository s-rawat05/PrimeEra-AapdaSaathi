/// Build-time configuration, supplied with `--dart-define=KEY=value`.
///
/// Nothing here is a secret: API keys for Firebase/Supabase are public client identifiers.
class AppConfig {
  AppConfig({
    String? apiBaseUrl,
    this.smsGatewayNumber = const String.fromEnvironment('SMS_GATEWAY_NUMBER'),
    this.firebaseApiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
    this.firebaseAppId = const String.fromEnvironment('FIREBASE_APP_ID'),
    this.firebaseSenderId = const String.fromEnvironment('FIREBASE_SENDER_ID'),
    this.firebaseProjectId = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
    this.supabaseUrl = const String.fromEnvironment('SUPABASE_URL'),
    this.supabaseAnonKey = const String.fromEnvironment('SUPABASE_ANON_KEY'),
    this.pollInterval = const Duration(seconds: 10),
  }) : apiBaseUrl = _trimSlash(apiBaseUrl ?? _defaultBaseUrl());

  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Backend origin, e.g. `http://10.0.2.2:8000`. The API lives under `/api/v1`.
  final String apiBaseUrl;
  final String smsGatewayNumber;
  final String firebaseApiKey;
  final String firebaseAppId;
  final String firebaseSenderId;
  final String firebaseProjectId;
  final String supabaseUrl;
  final String supabaseAnonKey;
  final Duration pollInterval;

  static String _defaultBaseUrl() {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    // On physical Android devices with `adb reverse tcp:8000 tcp:8000`, 127.0.0.1 reaches the host IPv4 reverse tunnel.
    return 'http://127.0.0.1:8000';
  }

  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  String get apiRoot => '$apiBaseUrl/api/v1';

  /// WebSocket URL for the realtime channel (ws for http, wss for https).
  Uri realtimeUri(String ticket) {
    final base = Uri.parse(apiBaseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/api/v1/realtime',
      queryParameters: {'ticket': ticket},
    );
  }

  bool get hasSmsGateway => smsGatewayNumber.isNotEmpty;

  bool get hasFirebase =>
      firebaseApiKey.isNotEmpty &&
      firebaseAppId.isNotEmpty &&
      firebaseSenderId.isNotEmpty &&
      firebaseProjectId.isNotEmpty;

  bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
