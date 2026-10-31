import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/json.dart';

/// Small persisted settings: token, language, onboarding flags, cached profile, last sync time.
class SessionStore {
  SessionStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kToken = 'auth.token';
  static const _kLang = 'ui.language';
  static const _kLangChosen = 'ui.language_chosen';
  static const _kIntro = 'ui.intro_seen';
  static const _kMe = 'cache.me';
  static const _kLastSync = 'sync.last';
  static const _kAnnounced = 'alerts.announced';
  static const _kDemoMode = 'auth.demo_mode';

  String? get token => _prefs.getString(_kToken);
  Future<void> setToken(String? v) => v == null ? _prefs.remove(_kToken) : _prefs.setString(_kToken, v);

  String get language => _prefs.getString(_kLang) ?? 'en';
  Future<void> setLanguage(String v) => _prefs.setString(_kLang, v);

  bool get languageChosen => _prefs.getBool(_kLangChosen) ?? false;
  Future<void> setLanguageChosen(bool v) => _prefs.setBool(_kLangChosen, v);

  bool get introSeen => _prefs.getBool(_kIntro) ?? false;
  Future<void> setIntroSeen() => _prefs.setBool(_kIntro, true);

  bool get lastDemoMode => _prefs.getBool(_kDemoMode) ?? false;
  Future<void> setLastDemoMode(bool v) => _prefs.setBool(_kDemoMode, v);

  /// Cached `/me` so the app can start offline after a restart.
  Json? get cachedMe {
    final s = _prefs.getString(_kMe);
    if (s == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<void> setCachedMe(Json? me) => me == null ? _prefs.remove(_kMe) : _prefs.setString(_kMe, jsonEncode(me));

  DateTime? get lastSync {
    final s = _prefs.getString(_kLastSync);
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> setLastSync(DateTime t) => _prefs.setString(_kLastSync, t.toUtc().toIso8601String());

  /// Alert/task ids we already raised a notification for (so a restart does not re-alarm).
  Set<String> get announced => (_prefs.getStringList(_kAnnounced) ?? const []).toSet();
  Future<void> addAnnounced(String id) {
    final list = (_prefs.getStringList(_kAnnounced) ?? <String>[])..add(id);
    // Keep the list bounded.
    final trimmed = list.length > 200 ? list.sublist(list.length - 200) : list;
    return _prefs.setStringList(_kAnnounced, trimmed);
  }

  Future<void> clearSession() async {
    await _prefs.remove(_kToken);
    await _prefs.remove(_kMe);
    await _prefs.remove(_kAnnounced);
    await _prefs.remove(_kLastSync);
  }
}
