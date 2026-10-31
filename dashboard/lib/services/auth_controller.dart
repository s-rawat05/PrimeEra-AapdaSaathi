import 'package:flutter/foundation.dart';

import '../core/api.dart';
import '../core/api_error.dart';
import '../core/session_store.dart';
import '../models/models.dart';

enum AuthPhase { restoring, signedOut, signedIn }

/// Owns the session: token persistence, `GET /me`, role, sign-in/out.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.store}) {
    api.onUnauthorized = _expired;
  }

  final AapdaApi api;
  final SessionStore store;

  AuthPhase phase = AuthPhase.restoring;
  MeOut? me;
  String? notice;

  UserOut? get user => me?.user;
  bool get isAdmin => user?.isAdmin ?? false;
  bool get isOps => user?.isOps ?? false;

  /// Restore a persisted session (validated with `GET /me`).
  Future<void> restore() async {
    final token = await store.readToken();
    if (token == null) {
      phase = AuthPhase.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      me = await api.me();
      phase = AuthPhase.signedIn;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await store.clear();
        api.token = null;
        notice = 'Your session expired. Please sign in again.';
      } else {
        notice = e.message;
      }
      phase = AuthPhase.signedOut;
    } catch (e) {
      notice = errorText(e);
      phase = AuthPhase.signedOut;
    }
    notifyListeners();
  }

  Future<void> login(String identifier, String password) async =>
      _accept(await api.login(identifier.trim(), password));

  Future<void> demoLogin(String userId) async => _accept(await api.demoLogin(userId));

  Future<void> _accept(TokenOut t) async {
    api.token = t.accessToken;
    me = await api.me();
    await store.writeToken(t.accessToken);
    notice = null;
    phase = AuthPhase.signedIn;
    notifyListeners();
  }

  Future<void> refreshMe() async {
    me = await api.me();
    notifyListeners();
  }

  Future<void> logout({String? reason}) async {
    api.token = null;
    me = null;
    notice = reason;
    await store.clear();
    phase = AuthPhase.signedOut;
    notifyListeners();
  }

  void _expired() {
    if (phase == AuthPhase.signedIn) {
      logout(reason: 'Your session expired or was revoked. Please sign in again.');
    }
  }
}
