import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

/// Live countdown to onset (ticks every second, local only — no data is changed).
class OnsetCountdown extends StatefulWidget {
  const OnsetCountdown({super.key, required this.onset, this.style});

  final DateTime onset;
  final TextStyle? style;

  @override
  State<OnsetCountdown> createState() => _OnsetCountdownState();
}

class _OnsetCountdownState extends State<OnsetCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final passed = widget.onset.isBefore(now);
    return Text(
      fmtCountdown(widget.onset, now),
      style: (widget.style ?? const TextStyle()).copyWith(
        color: passed ? AppColors.help : AppColors.text,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class IncidentSummaryCard extends StatelessWidget {
  const IncidentSummaryCard({super.key, required this.incident});

  final Incident incident;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(12)),
              child: Icon(_hazardIcon(i.hazardType), color: AppColors.primary, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  Pill(i.hazardType, color: AppColors.primary, icon: Icons.warning_amber_rounded, dense: true),
                  Pill('Severity: ${i.severity}', color: AppColors.severity(i.severity), filled: true, dense: true),
                  Pill('Urgency: ${i.urgency}', color: AppColors.info, dense: true),
                  Pill('Certainty: ${i.certainty}', color: AppColors.info, dense: true),
                  Pill('Mode ${i.escalationMode} · ${i.modeLabel}', color: AppColors.drill, icon: Icons.account_tree_outlined, dense: true),
                  if (i.requiresDispatchApproval)
                    const Pill('Dispatch needs approval', color: AppColors.noReply, icon: Icons.approval, dense: true)
                  else
                    const Pill('Auto-dispatch', color: AppColors.safe, icon: Icons.bolt, dense: true),
                  if (i.pendingApprovals > 0)
                    Pill('${i.pendingApprovals} awaiting approval', color: AppColors.noReply, filled: true, dense: true),
                  if (!i.isActive) Pill(i.status.toUpperCase(), color: AppColors.unreachable, filled: true, dense: true),
                ]),
              ]),
            ),
            if (i.onset != null)
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                const Text('ONSET', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w800)),
                OnsetCountdown(onset: i.onset!, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                Text(fmtTime(i.onset), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              ]),
          ]),
          if (i.onsetFallbackUsed && i.onsetFallbackNote != null) ...[
            gap12,
            InfoBanner(i.onsetFallbackNote!, color: AppColors.drill, icon: Icons.schedule),
          ],
          gap12,
          Wrap(spacing: 24, runSpacing: 4, children: [
            _kv('Sent', fmtShort(i.sent)),
            _kv('Onset', fmtShort(i.onset)),
            _kv('Expires', i.expires == null ? '—' : '${fmtShort(i.expires)} (${fmtRelative(i.expires)})'),
            _kv('Sender', i.capSender ?? '—'),
            if (i.capIdentifier != null) _kv('CAP id', i.capIdentifier!),
          ]),
          gap12,
          const Text('MATCHED WARDS', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final w in i.wards)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: w.wardName, style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: ' · ${humanize(w.matchMethod)}', style: const TextStyle(color: AppColors.info)),
                if (w.matchNote != null) TextSpan(text: ' — ${w.matchNote}', style: const TextStyle(color: AppColors.muted)),
              ]), style: const TextStyle(fontSize: 13)),
            ),
          if (i.headline != null || i.instruction != null) ...[
            gap12,
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('OFFICIAL TEXT (CAP, verbatim)',
                    style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w800)),
                if (i.headline != null) Text(i.headline!, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (i.instruction != null) Text(i.instruction!, style: const TextStyle(fontSize: 13)),
              ]),
            ),
          ],
          if (i.closeNote != null) ...[gap8, Text('Close note: ${i.closeNote}', style: const TextStyle(color: AppColors.muted))],
        ]),
      ),
    );
  }

  Widget _kv(String k, String v) => Text.rich(TextSpan(children: [
        TextSpan(text: '$k: ', style: const TextStyle(color: AppColors.muted)),
        TextSpan(text: v, style: const TextStyle(fontWeight: FontWeight.w600)),
      ]), style: const TextStyle(fontSize: 12.5));

  static IconData _hazardIcon(String h) {
    final s = h.toLowerCase();
    if (s.contains('flood') || s.contains('rain') || s.contains('cloudburst')) return Icons.flood;
    if (s.contains('landslide')) return Icons.landslide;
    if (s.contains('fire')) return Icons.local_fire_department;
    if (s.contains('earthquake')) return Icons.vibration;
    if (s.contains('thunder') || s.contains('cyclone')) return Icons.thunderstorm;
    if (s.contains('snow') || s.contains('avalanche')) return Icons.ac_unit;
    if (s.contains('heat')) return Icons.wb_sunny;
    return Icons.warning_amber_rounded;
  }
}

class CountersRow extends StatelessWidget {
  const CountersRow({super.key, required this.counts});

  final Counts counts;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      _Counter('Safe', counts.safe, AppColors.safe, Icons.check_circle, 'counter-safe'),
      _Counter('Help', counts.help, AppColors.help, Icons.sos, 'counter-help'),
      _Counter('No reply', counts.noReply, AppColors.noReply, Icons.hourglass_bottom, 'counter-noreply'),
      _Counter('Unreachable', counts.unreachable, AppColors.unreachable, Icons.phone_disabled, 'counter-unreachable'),
      _Counter('Total alerted', counts.total, AppColors.text, Icons.groups, 'counter-total',
          sub: counts.pending > 0 ? '${counts.pending} pending' : null),
    ];
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth > 760 ? 5 : (c.maxWidth > 460 ? 3 : 2);
      final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
      return Wrap(spacing: 10, runSpacing: 10, children: [for (final t in tiles) SizedBox(width: w, child: t)]);
    });
  }
}

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.value, this.color, this.icon, this.keyName, {this.sub});

  final String label;
  final int value;
  final Color color;
  final IconData icon;
  final String keyName;
  final String? sub;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: value > 0 && color != AppColors.text ? color.withValues(alpha: 0.6) : AppColors.border, width: 1.4),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value',
                  key: Key(keyName),
                  style: TextStyle(fontSize: 26, height: 1.1, fontWeight: FontWeight.w900, color: color)),
              Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              if (sub != null) Text(sub!, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ]),
          ),
        ]),
      );
}
