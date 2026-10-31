import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../overview/command_centre_controller.dart';

String fixtureLabel(String f) => switch (f) {
      'demo_flash_flood_alert' => 'Flash flood — alert (Mode C, <30 min)',
      'demo_flash_flood_update' => 'Flash flood — update',
      'demo_flash_flood_cancel' => 'Flash flood — cancel',
      'demo_landslide_long_lead' => 'Landslide — long lead time',
      _ => f.startsWith('sachet_') ? 'Real SACHET sample: $f' : f,
    };

/// Drill controls (`GET /demo/status`, `POST /demo/simulate|reset|seed`).
class DemoPanel extends StatefulWidget {
  const DemoPanel({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  State<DemoPanel> createState() => _DemoPanelState();
}

class _DemoPanelState extends State<DemoPanel> {
  final _onset = TextEditingController(text: '20');
  String? _fixture;
  final Set<String> _wards = {};
  bool _busy = false;
  String? _onsetError;

  CommandCentreController get cc => widget.controller;

  @override
  void dispose() {
    _onset.dispose();
    super.dispose();
  }

  Future<void> _wrap(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulate(String fixture) => _wrap(() async {
        final n = int.tryParse(_onset.text.trim());
        if (n == null || n < -60 || n > 1440) {
          setState(() => _onsetError = 'Whole minutes between −60 and 1440');
          return;
        }
        setState(() => _onsetError = null);
        final inc = await runAction(
          context,
          () => cc.api.simulate(fixture, onsetInMinutes: n, wardIds: _wards.isEmpty ? null : _wards.toList()),
          success: 'Drill started: ${fixtureLabel(fixture)}',
        );
        if (inc != null) await cc.focusIncident(inc);
      });

  Future<void> _reset() async {
    final ok = await confirmDialog(
      context,
      title: 'Reset demo?',
      message: 'Removes all DEMO incidents, tasks and simulated SMS, and resets demo volunteers. '
          'Real residents and real incidents are never touched.',
      confirmLabel: 'Reset demo',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _wrap(() async {
      final r = await runAction(context, () => cc.api.demoReset());
      if (r != null && mounted) {
        showSnack(context,
            'Demo reset: ${r.incidentsRemoved} incidents, ${r.smsRemoved} SMS removed, ${r.volunteersReset} volunteers reset'
            '${r.realDataUntouched ? ' · real data untouched' : ''}');
        cc.select(null);
        await cc.refreshAll();
      }
    });
  }

  Future<void> _seed() => _wrap(() async {
        final r = await runAction(context, () => cc.api.demoSeed());
        if (r != null && mounted) {
          showSnack(context, 'Seed complete (added: ${r.entries.map((e) => '${e.key} ${e.value}').join(', ')})');
          await cc.refreshDemoStatus();
        }
      });

  @override
  Widget build(BuildContext context) {
    final s = cc.demoStatus;
    final err = cc.errors['demo'];
    if (s == null) {
      return ListView(padding: const EdgeInsets.all(12), children: [
        if (err != null) ErrorPanel(error: err, onRetry: cc.refreshDemoStatus) else const LinearProgressIndicator(),
      ]);
    }
    final fixtures = s.fixtures;
    _fixture ??= fixtures.contains('demo_flash_flood_alert') ? 'demo_flash_flood_alert' : fixtures.firstOrNull;
    final enabled = s.demoModeEnabled && !_busy;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Wrap(spacing: 6, runSpacing: 6, children: [
        Pill(s.demoModeEnabled ? 'DEMO MODE ON' : 'DEMO MODE OFF',
            color: s.demoModeEnabled ? AppColors.drill : AppColors.unreachable, filled: s.demoModeEnabled, dense: true),
        Pill(s.notifyRealResidents ? 'REAL NOTIFICATIONS ON' : 'REAL NOTIFICATIONS OFF',
            color: s.notifyRealResidents ? AppColors.help : AppColors.safe, dense: true, icon: Icons.shield_outlined),
        Pill('Escalation every ${s.escalationIntervalSeconds} s (demo)', color: AppColors.info, dense: true, icon: Icons.timer_outlined),
      ]),
      gap8,
      Text('${s.demoResidents} fictional residents · ${s.demoWards.length} demo wards · '
          '${s.activeDemoIncidents} active demo incidents',
          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
      if (!s.demoModeEnabled) ...[
        gap8,
        const InfoBanner('Demo mode is disabled on this deployment. Drill controls are unavailable.',
            color: AppColors.unreachable),
      ],
      gap12,
      const Text('Simulate a saved CAP fixture', style: TextStyle(fontWeight: FontWeight.w800)),
      gap8,
      RadioGroup<String>(
        groupValue: _fixture,
        onChanged: (v) {
          if (enabled) setState(() => _fixture = v);
        },
        child: Column(children: [
          for (final f in fixtures)
            RadioListTile<String>(
              key: Key('fixture-$f'),
              dense: true,
              enabled: enabled,
              contentPadding: EdgeInsets.zero,
              value: f,
              title: Text(fixtureLabel(f), style: const TextStyle(fontSize: 13)),
              subtitle: Text(f, style: const TextStyle(fontSize: 11)),
            ),
        ]),
      ),
      if (s.demoWards.length > 1) ...[
        const Text('Target demo wards (none = default)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
        Wrap(spacing: 6, children: [
          for (final w in s.demoWards)
            FilterChip(
              label: Text(w.code),
              tooltip: w.name,
              selected: _wards.contains(w.id),
              onSelected: enabled ? (v) => setState(() => v ? _wards.add(w.id) : _wards.remove(w.id)) : null,
            ),
        ]),
        gap8,
      ],
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 150,
          child: TextField(
            key: const Key('simulate-onset'),
            controller: _onset,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: 'Onset in min', errorText: _onsetError, errorMaxLines: 2),
          ),
        ),
        gap8,
        Expanded(
          child: FilledButton.icon(
            key: const Key('simulate-button'),
            onPressed: enabled && _fixture != null ? () => _simulate(_fixture!) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start drill'),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Onset < 30 min → Mode C (parallel); 30 min–6 h → Mode B; > 6 h → Mode A.',
          style: TextStyle(fontSize: 11, color: AppColors.muted)),
      const Divider(height: 28),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('demo-reset'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.primaryDark),
          onPressed: enabled ? _reset : null,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset demo'),
        ),
        OutlinedButton.icon(
          onPressed: enabled ? _seed : null,
          icon: const Icon(Icons.spa_outlined),
          label: const Text('Seed missing demo data'),
        ),
      ]),
      gap12,
      if (s.demoWards.isNotEmpty) ...[
        const Text('Demo wards', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final w in s.demoWards)
          Text('• ${w.code} — ${w.name} (access: ${w.accessStatus})', style: const TextStyle(fontSize: 12)),
      ],
    ]);
  }
}
