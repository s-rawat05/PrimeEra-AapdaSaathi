import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/format.dart';

IconData _iconFor(String type) {
  if (type.contains('safe')) return Icons.check_circle_outline;
  if (type.contains('help')) return Icons.sos;
  if (type.contains('alert') || type.contains('sent') || type.contains('resend')) return Icons.campaign_outlined;
  if (type.contains('escalat')) return Icons.trending_up;
  if (type.contains('task') || type.contains('dispatch') || type.contains('volunteer')) return Icons.directions_walk;
  if (type.contains('neighbour')) return Icons.home_outlined;
  if (type.contains('override')) return Icons.edit_note;
  if (type.contains('unreach') || type.contains('fail')) return Icons.phone_disabled;
  if (type.contains('incident') || type.contains('closed')) return Icons.flag_outlined;
  if (type.contains('sms') || type.contains('reply')) return Icons.sms_outlined;
  return Icons.circle_outlined;
}

Color _colorFor(String type) {
  if (type.contains('safe')) return AppColors.safe;
  if (type.contains('help') || type.contains('rescue')) return AppColors.help;
  if (type.contains('unreach') || type.contains('fail')) return AppColors.unreachable;
  if (type.contains('escalat') || type.contains('approval')) return AppColors.noReply;
  return AppColors.info;
}

/// Renders `TimelineOut` rows (incident or case timeline).
class TimelineList extends StatelessWidget {
  const TimelineList({super.key, required this.events, this.newestFirst = true, this.maxItems});

  final List<TimelineEvent> events;
  final bool newestFirst;
  final int? maxItems;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text('No events yet.', style: TextStyle(color: AppColors.muted)),
      );
    }
    final sorted = [...events]..sort((a, b) => newestFirst ? b.createdAt.compareTo(a.createdAt) : a.createdAt.compareTo(b.createdAt));
    final shown = maxItems == null ? sorted : sorted.take(maxItems!).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final e in shown)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 64,
              child: Text(fmtTime(e.createdAt), style: const TextStyle(fontSize: 12, color: AppColors.muted, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            Icon(_iconFor(e.eventType), size: 16, color: _colorFor(e.eventType)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.message, style: const TextStyle(fontSize: 13)),
                Text(
                  '${humanize(e.eventType)} · ${e.actorName ?? e.actorKind}',
                  style: const TextStyle(fontSize: 11, color: AppColors.muted),
                ),
              ]),
            ),
          ]),
        ),
      if (maxItems != null && sorted.length > maxItems!)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('+ ${sorted.length - maxItems!} older events', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
    ]);
  }
}
