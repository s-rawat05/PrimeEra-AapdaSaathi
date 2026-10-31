import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/api_exception.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

String fmtTime(DateTime? t) {
  if (t == null) return '—';
  return DateFormat('d MMM, HH:mm').format(t.toLocal());
}

String fmtDistance(double? m) {
  if (m == null) return '—';
  if (m < 1000) return '${m.round()} m';
  return '${(m / 1000).toStringAsFixed(1)} km';
}

String fmtMinutes(double? m) => m == null ? '—' : m.round().toString();

String errorText(Object e, Strings s) {
  if (e is ApiException) return e.message;
  return s.errorPrefix(e.toString());
}

void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? AppColors.redDark : null,
      behavior: SnackBarBehavior.floating,
    ));
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color, this.onTap});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.background, this.icon});

  final String label;
  final Color color;
  final Color? background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: background ?? color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text.rich(
        TextSpan(children: [
          if (icon != null) ...[
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(icon, size: 16, color: color)),
            const TextSpan(text: ' '),
          ],
          TextSpan(text: label),
        ]),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class DemoBadge extends StatelessWidget {
  const DemoBadge({super.key, this.label = 'DEMO'});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Demo data',
        child: StatusChip(label: label, color: AppColors.amber, background: AppColors.amberSoft, icon: Icons.science),
      );
}

/// Hazard pictogram from `presentation.pictogram`.
IconData hazardIcon(String pictogram) => switch (pictogram) {
      'flood' => Icons.flood,
      'landslide' => Icons.landslide,
      'storm' => Icons.thunderstorm,
      'earthquake' => Icons.crisis_alert,
      'fire' => Icons.local_fire_department,
      _ => Icons.warning_amber_rounded,
    };

/// A simple pictogram for an easy-read step, chosen from the step's own words.
IconData stepIcon(String step) {
  final t = step.toLowerCase();
  if (t.contains('help') || t.contains('मदद')) return Icons.sos;
  if (t.contains('safe') || t.contains('सुरक्षित')) return Icons.check_circle;
  if (t.contains('calm') || t.contains('शांत')) return Icons.self_improvement;
  if (t.contains('message') || t.contains('listen') || t.contains('संदेश')) return Icons.campaign;
  if (t.contains('family') || t.contains('neighbour') || t.contains('volunteer') || t.contains('परिवार')) {
    return Icons.groups;
  }
  return Icons.arrow_forward;
}

class Pictogram extends StatelessWidget {
  const Pictogram(this.icon, {super.key, this.size = 56, this.color = AppColors.red, this.semanticLabel});
  final IconData icon;
  final double size;
  final Color color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(size / 3.5)),
      child: Icon(icon, size: size * 0.6, color: color, semanticLabel: semanticLabel),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message, this.onRetry, required this.s});
  final String message;
  final VoidCallback? onRetry;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      color: AppColors.redSoft,
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.redDark),
        const SizedBox(width: 12),
        Expanded(child: Text(message, style: const TextStyle(color: AppColors.redDark))),
        if (onRetry != null) TextButton(onPressed: onRetry, child: Text(s.retry)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(children: [
        Icon(icon, size: 48, color: AppColors.gray),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray, fontSize: 16)),
      ]),
    );
  }
}

/// Key/value row used for official alert fields.
class FieldRow extends StatelessWidget {
  const FieldRow(this.label, this.value, {super.key});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.gray, fontWeight: FontWeight.w600)),
        SelectableText(value!, style: const TextStyle(fontSize: 15)),
      ]),
    );
  }
}

/// Labelled section header.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
          ),
          ?trailing,
        ]),
      );
}
