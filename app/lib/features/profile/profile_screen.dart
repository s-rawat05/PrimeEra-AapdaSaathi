import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../accessibility/modes.dart';
import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/device_services.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import '../onboarding/language_screen.dart';

/// Profile: language, needs, permissions, consent, sign out.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final me = app.me;
    final resident = me?.resident;
    return Scaffold(
      appBar: AppBar(title: Text(s.profileTitle)),
      body: Column(children: [
        const ConnectionBanner(showWhenOnline: true),
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
            if (me != null)
              SectionCard(
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppColors.redSoft,
                    child: Text(me.user.fullName.isEmpty ? '?' : me.user.fullName[0],
                        style: const TextStyle(fontSize: 24, color: AppColors.red, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(me.user.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('${s.roleName(me.user.roleRaw)} · ${me.user.phoneMasked}',
                          style: const TextStyle(color: AppColors.gray)),
                      if (resident != null) Text(resident.wardName, style: const TextStyle(color: AppColors.gray)),
                    ]),
                  ),
                  if (me.user.isDemo) const DemoBadge(),
                ]),
              ),
            SectionTitle(s.language),
            LanguagePicker(
              selected: app.lang,
              onSelected: (l) => app.setLanguage(l),
            ),
            if (resident != null) ...[
              SectionTitle(s.myNeeds),
              _NeedsEditor(resident: resident),
              SectionTitle(s.consent),
              _ConsentCard(resident: resident),
            ],
            SectionTitle(s.permissions),
            const _PermissionsCard(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const Key('logout'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.redDark),
              onPressed: app.logout,
              icon: const Icon(Icons.logout),
              label: Text(s.logout),
            ),
            const SizedBox(height: 12),
            Text('${s.serverLabel}: ${app.config.apiBaseUrl}',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

/// Editable list of needs (shared with onboarding).
class NeedsChecklist extends StatelessWidget {
  const NeedsChecklist({super.key, required this.selected, required this.onChanged});
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Column(children: [
      for (final n in kNeeds)
        CheckboxListTile(
          key: Key('need-$n'),
          value: selected.contains(n),
          title: Text(s.needLabel(n)),
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (v) {
            final next = {...selected};
            if (v == true) {
              next.add(n);
            } else {
              next.remove(n);
            }
            onChanged(next);
          },
        ),
    ]);
  }
}

class _NeedsEditor extends StatefulWidget {
  const _NeedsEditor({required this.resident});
  final ResidentOut resident;

  @override
  State<_NeedsEditor> createState() => _NeedsEditorState();
}

class _NeedsEditorState extends State<_NeedsEditor> {
  late Set<String> _needs = widget.resident.needs.toSet();
  late bool _alone = widget.resident.livesAlone;
  late bool _smart = widget.resident.hasSmartphone;
  bool _busy = false;

  Future<void> _save() async {
    final app = context.appRead;
    setState(() => _busy = true);
    try {
      final r = await app.call((api) => api.patchResident({
            'needs': _needs.toList(),
            'lives_alone': _alone,
            'has_smartphone': _smart,
          }));
      app.applyResident(r);
      if (mounted) showSnack(context, app.s.saved);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return SectionCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: [
        NeedsChecklist(selected: _needs, onChanged: (v) => setState(() => _needs = v)),
        SwitchListTile(title: Text(s.livesAlone), value: _alone, onChanged: (v) => setState(() => _alone = v)),
        SwitchListTile(title: Text(s.hasSmartphone), value: _smart, onChanged: (v) => setState(() => _smart = v)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton(
            key: const Key('save-needs'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: Text(s.saveNeeds),
          ),
        ),
      ]),
    );
  }
}

class _ConsentCard extends StatefulWidget {
  const _ConsentCard({required this.resident});
  final ResidentOut resident;

  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  bool _busy = false;

  Future<void> _run(Future<ResidentOut> Function() f) async {
    final app = context.appRead;
    setState(() => _busy = true);
    try {
      final r = await f();
      app.applyResident(r);
      if (mounted) showSnack(context, app.s.saved);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final reg = widget.resident.consent('registry');
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          reg != null ? s.consentValidUntil(fmtTime(reg.expiresAt)) : s.consentInactive,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text('${s.statusName(widget.resident.registrationStatus)} (${widget.resident.registrationStatus})',
            style: const TextStyle(color: AppColors.gray)),
        const SizedBox(height: 4),
        for (final c in widget.resident.consents)
          Text('• ${c.consentType}: ${c.isActive ? s.permGranted : s.permDenied}',
              style: const TextStyle(fontSize: 13, color: AppColors.gray)),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('renew-consent'),
          onPressed: _busy ? null : () => _run(() => app.call((api) => api.renewConsent())),
          child: Text(s.renewConsent),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('withdraw-consent'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.redDark),
          onPressed: _busy
              ? null
              : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.withdrawConsent),
                      content: Text(s.withdrawConfirm),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.confirm)),
                      ],
                    ),
                  );
                  if (ok == true) await _run(() => app.call((api) => api.withdrawConsent()));
                },
          child: Text(s.withdrawConsent),
        ),
      ]),
    );
  }
}

class _PermissionsCard extends StatefulWidget {
  const _PermissionsCard();

  @override
  State<_PermissionsCard> createState() => _PermissionsCardState();
}

class _PermissionsCardState extends State<_PermissionsCard> {
  final Map<AppPermission, PermState> _states = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final g = context.appRead.permissions;
    for (final p in AppPermission.values) {
      final st = await g.status(p);
      if (!mounted) return;
      setState(() => _states[p] = st);
    }
  }

  Future<void> _request(AppPermission p) async {
    final app = context.appRead;
    if (_states[p] == PermState.permanentlyDenied) {
      await app.permissions.openSettings();
    } else if (p == AppPermission.notifications) {
      // Also asks for the Android 14+ full-screen intent permission.
      await app.notifier.requestPermission();
      await app.permissions.request(p);
    } else {
      await app.permissions.request(p);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    String label(AppPermission p) => switch (p) {
          AppPermission.notifications => s.permNotifications,
          AppPermission.location => s.permLocation,
          AppPermission.camera => s.permCamera,
          AppPermission.microphone => s.micPermission,
        };
    String stateText(PermState? st) => switch (st) {
          PermState.granted => s.permGranted,
          PermState.permanentlyDenied => s.permPermanentlyDenied,
          PermState.unsupported => '—',
          _ => s.permDenied,
        };
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (kIsWeb) Text(s.permWebNote, style: const TextStyle(color: AppColors.amber)),
        for (final p in AppPermission.values)
          ListTile(
            key: Key('perm-${p.name}'),
            contentPadding: EdgeInsets.zero,
            title: Text(label(p)),
            subtitle: Text(stateText(_states[p])),
            trailing: _states[p] == PermState.granted || _states[p] == PermState.unsupported
                ? const Icon(Icons.check_circle, color: AppColors.green)
                : OutlinedButton(
                    onPressed: () => _request(p),
                    child: Text(_states[p] == PermState.permanentlyDenied ? s.openSettings : s.permRequest),
                  ),
          ),
        const SizedBox(height: 8),
        Text(s.dndNote, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text(s.torchNote, style: const TextStyle(fontSize: 13, color: AppColors.gray)),
        const SizedBox(height: 12),
        ValueListenableBuilder<bool>(
          valueListenable: app.effects.active,
          builder: (context, on, _) => on
              ? FilledButton.icon(
                  key: const Key('stop-test'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.ink),
                  onPressed: app.effects.stop,
                  icon: const Icon(Icons.stop),
                  label: Text(s.stopAlarm),
                )
              : OutlinedButton.icon(
                  key: const Key('test-effects'),
                  onPressed: () => app.effects.start(
                    app.profileModes.union(AlertModes(const ['vibrate'])),
                    speech: [s.testAlarmBody],
                    ttsLocale: s.ttsLocale,
                  ),
                  icon: const Icon(Icons.notifications_active),
                  label: Text(s.testAlarm),
                ),
        ),
      ]),
    );
  }
}
