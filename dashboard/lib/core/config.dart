/// Build-time configuration. Override with
/// `flutter run -d chrome --dart-define=API_BASE_URL=https://api.example.org`.
class AppConfig {
  const AppConfig({required this.apiBaseUrl, this.mapTilesEnabled = true});

  factory AppConfig.fromEnvironment() =>
      AppConfig(apiBaseUrl: _trim(const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000')));

  /// Origin of the backend, without `/api/v1` (e.g. `http://localhost:8000`).
  final String apiBaseUrl;

  /// OSM tiles are disabled in widget tests (no network).
  final bool mapTilesEnabled;

  String get apiRoot => '$apiBaseUrl/api/v1';

  Uri apiUri(String path, [Map<String, String?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null && v.isNotEmpty) q[k] = v;
    });
    final base = Uri.parse('$apiRoot$path');
    return q.isEmpty ? base : base.replace(queryParameters: {...base.queryParameters, ...q});
  }

  Uri realtimeUri(String ticket) {
    final base = Uri.parse(apiRoot);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '${base.path}/realtime',
      queryParameters: {'ticket': ticket},
    );
  }

  static String _trim(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;
}
