import 'package:shared_preferences/shared_preferences.dart';

/// Persists the access token between page reloads.
abstract class SessionStore {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> clear();
}

class SharedPrefsSessionStore implements SessionStore {
  static const _key = 'aapda_command.access_token';

  @override
  Future<String?> readToken() async => (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> writeToken(String token) async => (await SharedPreferences.getInstance()).setString(_key, token);

  @override
  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._token]);

  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
