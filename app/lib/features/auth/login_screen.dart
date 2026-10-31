import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';

/// Phone + SMS code sign-in (`/auth/otp/request` → `/auth/otp/verify`), plus a DEMO persona picker
/// when the backend runs in demo mode. Optional Supabase phone OTP when configured (unverified).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _name = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _needName = false;
  bool _useSupabase = false;
  String? _note;
  String? _error;

  List<DemoPersona>? _personas;
  Object? _personaError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPersonas());
  }

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadPersonas() async {
    setState(() => _personaError = null);
    try {
      final p = await context.appRead.call((api) => api.demoPersonas());
      if (mounted) setState(() => _personas = p);
    } catch (e) {
      if (mounted) setState(() => _personaError = e);
    }
  }

  bool get _demoMode => (_personas?.isNotEmpty ?? false) || _note?.contains('simulator') == true;

  String _normalisedPhone() {
    var p = _phone.text.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^\d{10}$').hasMatch(p)) p = '+91$p';
    return p;
  }

  Future<void> _sendCode() async {
    final app = context.appRead;
    final s = app.s;
    final phone = _normalisedPhone();
    if (phone.length < 8 || phone.length > 20) {
      setState(() => _error = s.invalidPhone);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_useSupabase) {
        await app.supabase!.sendOtp(phone);
        _note = null;
      } else {
        final r = await app.call((api) => api.requestOtp(phone));
        _note = r.note;
      }
      setState(() => _codeSent = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = s.errorPrefix('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final app = context.appRead;
    final s = app.s;
    final code = _code.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => _error = s.invalidCode);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final String token;
      if (_useSupabase) {
        token = await app.supabase!.verify(_normalisedPhone(), code);
      } else {
        final t = await app.call((api) => api.verifyOtp(_normalisedPhone(), code, fullName: _name.text.trim()));
        token = t.accessToken;
      }
      await app.signIn(token);
    } on ApiException catch (e) {
      setState(() {
        if (e.code == 'name_required') {
          _needName = true;
          _error = s.nameRequired;
        } else {
          _error = e.message;
        }
      });
    } catch (e) {
      setState(() => _error = s.errorPrefix('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _demoLogin(DemoPersona p) async {
    final app = context.appRead;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await app.call((api) => api.demoLogin(p.userId));
      await app.signIn(t.accessToken);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.signIn),
        actions: [
          TextButton(
            key: const Key('toggle-language'),
            onPressed: () => app.setLanguage(app.lang == 'en' ? 'hi' : 'en'),
            child: Text(app.lang == 'en' ? s.hindi : s.english, style: const TextStyle(color: Colors.white, fontSize: 16)),
          ),
        ],
      ),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              const Icon(Icons.shield_moon, color: AppColors.red, size: 36),
              const SizedBox(width: 8),
              Text(s.appName, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppColors.red)),
            ]),
            const SizedBox(height: 4),
            Text(s.tagline, style: const TextStyle(color: AppColors.gray)),
            const SizedBox(height: 20),
            SectionCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  key: const Key('phone-field'),
                  controller: _phone,
                  enabled: !_codeSent,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(labelText: s.phoneNumber, hintText: s.phoneHint, prefixIcon: const Icon(Icons.phone)),
                ),
                const SizedBox(height: 12),
                if (!_codeSent)
                  FilledButton(
                    key: const Key('send-code'),
                    onPressed: _busy ? null : _sendCode,
                    child: Text(_busy ? s.sending : s.sendCode),
                  )
                else ...[
                  if (_note != null) Text(_note!, style: const TextStyle(color: AppColors.green)),
                  if (_demoMode)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(s.demoOtpHint, key: const Key('demo-otp-hint'), style: const TextStyle(color: AppColors.amber)),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('code-field'),
                    controller: _code,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: InputDecoration(labelText: s.enterCode, prefixIcon: const Icon(Icons.pin)),
                  ),
                  if (!_useSupabase)
                    TextField(
                      key: const Key('name-field'),
                      controller: _name,
                      decoration: InputDecoration(
                        labelText: s.yourName,
                        prefixIcon: const Icon(Icons.person),
                        errorText: _needName && _name.text.trim().isEmpty ? s.nameRequired : null,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('verify'),
                    onPressed: _busy ? null : _verify,
                    child: Text(_busy ? s.sending : s.verify),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _codeSent = false;
                              _code.clear();
                              _error = null;
                            }),
                    child: Text(s.changeNumber),
                  ),
                ],
                if (app.supabase?.enabled ?? false)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.supabaseSignIn),
                    value: _useSupabase,
                    onChanged: _codeSent ? null : (v) => setState(() => _useSupabase = v),
                  ),
                if (_error != null) ...[const SizedBox(height: 8), ErrorPanel(message: _error!, s: s)],
              ]),
            ),
            if (_personaError != null) ...[
              const SizedBox(height: 16),
              ErrorPanel(message: errorText(_personaError!, s), onRetry: _loadPersonas, s: s),
            ],
            if (_personas != null && _personas!.isNotEmpty) ...[
              SectionTitle(s.demoPersonas, trailing: DemoBadge(label: s.demo)),
              Text(s.demoPersonasHint, style: const TextStyle(color: AppColors.gray)),
              const SizedBox(height: 8),
              _PersonaList(personas: _personas!, busy: _busy, onPick: _demoLogin),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _PersonaList extends StatelessWidget {
  const _PersonaList({required this.personas, required this.busy, required this.onPick});
  final List<DemoPersona> personas;
  final bool busy;
  final ValueChanged<DemoPersona> onPick;

  static const _order = [
    UserRole.resident,
    UserRole.caregiver,
    UserRole.neighbour,
    UserRole.volunteer,
    UserRole.operator,
    UserRole.admin,
    UserRole.unknown,
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final groups = <UserRole, List<DemoPersona>>{};
    for (final p in personas) {
      groups.putIfAbsent(p.role, () => []).add(p);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final role in _order)
        if (groups[role] != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
            child: Text(s.roleName(role.name).toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.gray, letterSpacing: 1)),
          ),
          for (final p in groups[role]!)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  key: Key('persona-${p.userId}'),
                  enabled: !busy,
                  onTap: () => onPick(p),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.amberSoft,
                    child: Text(p.fullName.isEmpty ? '?' : p.fullName[0],
                        style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(p.description),
                  trailing: const Icon(Icons.login),
                ),
              ),
            ),
        ],
    ]);
  }
}
