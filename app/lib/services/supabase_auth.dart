import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config.dart';

/// Alternate sign-in path: Supabase phone OTP. Enabled only when SUPABASE_URL and
/// SUPABASE_ANON_KEY dart-defines are set. The default path is the backend's own OTP.
///
/// UNVERIFIED: this path was written against the supabase_flutter API and the backend's
/// `AUTH_MODE=supabase` (which accepts the Supabase access token as the Bearer token), but it has
/// not been exercised against a live Supabase project.
class SupabaseAuth {
  SupabaseAuth(this.config);

  final AppConfig config;
  bool _ready = false;
  bool get enabled => _ready;

  Future<void> init() async {
    if (!config.hasSupabase) return;
    try {
      await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.supabaseAnonKey);
      _ready = true;
    } catch (e) {
      debugPrint('Supabase disabled: $e');
    }
  }

  Future<void> sendOtp(String phone) async {
    await Supabase.instance.client.auth.signInWithOtp(phone: phone);
  }

  /// Verifies the SMS code and returns the Supabase access token for the backend.
  Future<String> verify(String phone, String code) async {
    final res = await Supabase.instance.client.auth.verifyOTP(phone: phone, token: code, type: OtpType.sms);
    final token = res.session?.accessToken;
    if (token == null) throw Exception('Supabase did not return a session');
    return token;
  }

  Future<void> signOut() async {
    if (!_ready) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
  }
}
