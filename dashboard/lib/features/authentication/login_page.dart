import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscure = true;
  Future<List<DemoPersona>>? _personas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _personas ??= context.api.demoPersonas();
  }

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final auth = context.services.auth;
    _run(() => auth.login(_identifier.text, _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _Brand(),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: AutofillGroup(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const Text('Operations sign-in', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        const Text('For district control-room operators and administrators.',
                            style: TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 20),
                        if (auth.notice != null) ...[
                          InfoBanner(auth.notice!, color: AppColors.noReply, icon: Icons.lock_clock),
                          gap12,
                        ],
                        TextFormField(
                          key: const Key('login-identifier'),
                          controller: _identifier,
                          autofillHints: const [AutofillHints.email, AutofillHints.username],
                          decoration: const InputDecoration(labelText: 'Email or phone', prefixIcon: Icon(Icons.person_outline)),
                          validator: (v) => (v ?? '').trim().length < 3 ? 'Enter your email or phone' : null,
                          textInputAction: TextInputAction.next,
                        ),
                        gap12,
                        TextFormField(
                          key: const Key('login-password'),
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Show password' : 'Hide password',
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v ?? '').length < 6 ? 'Password must be at least 6 characters' : null,
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (_error != null) ...[
                          gap12,
                          InfoBanner(_error!, color: AppColors.help, icon: Icons.error_outline),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          key: const Key('login-submit'),
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.login),
                          label: const Text('Sign in'),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<DemoPersona>>(
                future: _personas,
                builder: (context, snap) {
                  final ops = (snap.data ?? const <DemoPersona>[]).where((p) => p.isOps).toList();
                  if (ops.isEmpty) return const SizedBox.shrink();
                  return _DemoPicker(
                    personas: ops,
                    busy: _busy,
                    onPick: (p) => _run(() => auth.demoLogin(p.userId)),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text('Server: ${context.services.config.apiBaseUrl}',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Column(children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.crisis_alert, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 12),
        const Text('AapdaSaathi Command', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        const Text('Disaster-alert accountability console', style: TextStyle(color: AppColors.muted)),
      ]);
}

class _DemoPicker extends StatelessWidget {
  const _DemoPicker({required this.personas, required this.onPick, required this.busy});

  final List<DemoPersona> personas;
  final ValueChanged<DemoPersona> onPick;
  final bool busy;

  @override
  Widget build(BuildContext context) => Card(
        key: const Key('demo-picker'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Row(children: [
              Icon(Icons.theater_comedy_outlined, color: AppColors.drill),
              SizedBox(width: 8),
              Text('Demo accounts', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              SizedBox(width: 8),
              Pill('FICTIONAL', color: AppColors.drill, dense: true),
            ]),
            const SizedBox(height: 4),
            const Text('Demo mode is on. These fictional staff accounts work only on demo data.',
                style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 8),
            for (final p in personas)
              ListTile(
                key: Key('persona-${p.role}'),
                contentPadding: EdgeInsets.zero,
                enabled: !busy,
                leading: CircleAvatar(
                  backgroundColor: (p.role == 'admin' ? AppColors.primary : AppColors.info).withValues(alpha: 0.12),
                  child: Icon(p.role == 'admin' ? Icons.admin_panel_settings : Icons.headset_mic,
                      color: p.role == 'admin' ? AppColors.primary : AppColors.info),
                ),
                title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${p.role.toUpperCase()} · ${p.description}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onPick(p),
              ),
          ]),
        ),
      );
}
