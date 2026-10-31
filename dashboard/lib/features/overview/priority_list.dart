import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

enum PriorityFilter { attention, all, help, noReply, unreachable, safe }

extension on PriorityFilter {
  String get label => switch (this) {
        PriorityFilter.attention => 'Needs action',
        PriorityFilter.all => 'All',
        PriorityFilter.help => 'Help',
        PriorityFilter.noReply => 'No reply',
        PriorityFilter.unreachable => 'Unreachable',
        PriorityFilter.safe => 'Safe',
      };

  bool matches(PriorityItem p) => switch (this) {
        PriorityFilter.attention => p.status != 'SAFE',
        PriorityFilter.all => true,
        PriorityFilter.help => p.status == 'HELP',
        PriorityFilter.noReply => p.status == 'NO_REPLY',
        PriorityFilter.unreachable => p.status == 'UNREACHABLE',
        PriorityFilter.safe => p.status == 'SAFE',
      };
}

/// Ranked list from `GET /incidents/{id}/priority` (already sorted by the server).
class PriorityListPanel extends StatefulWidget {
  const PriorityListPanel({super.key, required this.items, required this.onOpen, this.error, this.onRetry});

  final List<PriorityItem> items;
  final ValueChanged<PriorityItem> onOpen;
  final Object? error;
  final VoidCallback? onRetry;

  @override
  State<PriorityListPanel> createState() => _PriorityListPanelState();
}

class _PriorityListPanelState extends State<PriorityListPanel> {
  PriorityFilter _filter = PriorityFilter.attention;

  @override
  Widget build(BuildContext context) {
    final rows = widget.items.where(_filter.matches).toList();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            const Icon(Icons.format_list_numbered, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Priority list', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
            Text('${rows.length} of ${widget.items.length}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Ranked by a transparent score — every point is listed.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final f in PriorityFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(f.label, style: const TextStyle(fontSize: 12)),
                    selected: _filter == f,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _filter = f),
                  ),
                ),
            ],
          ),
        ),
        if (widget.error != null)
          Padding(padding: const EdgeInsets.all(12), child: ErrorPanel(error: widget.error!, onRetry: widget.onRetry)),
        const Divider(),
        Expanded(
          child: rows.isEmpty
              ? EmptyState(widget.items.isEmpty ? 'No residents alerted yet.' : 'Nobody in this filter.',
                  icon: Icons.verified_user_outlined)
              : ListView.separated(
                  padding: const EdgeInsets.all(10),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => PriorityTile(
                    item: rows[i],
                    rank: widget.items.indexOf(rows[i]) + 1,
                    onTap: () => widget.onOpen(rows[i]),
                  ),
                ),
        ),
      ]),
    );
  }
}

class PriorityTile extends StatelessWidget {
  const PriorityTile({super.key, required this.item, required this.rank, required this.onTap});

  final PriorityItem item;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = item;
    final accent = p.needsRescue
        ? AppColors.help
        : p.needsOperator
            ? AppColors.noReply
            : AppColors.border;
    return Material(
      color: p.needsRescue ? AppColors.dangerBg : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: accent, width: p.needsRescue || p.needsOperator ? 1.6 : 1),
      ),
      child: InkWell(
        key: ValueKey('priority-${p.deliveryId}'),
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: AppColors.text,
                child: Text('$rank', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(p.residentName,
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
              ),
              StatusChip(p.status, dense: true),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Priority score',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.text, borderRadius: BorderRadius.circular(8)),
                  child: Text('${p.priorityTotal}',
                      key: ValueKey('score-${p.deliveryId}'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              for (final n in p.needs)
                Tooltip(message: needLabel(n), child: Icon(needIcon(n), size: 16, color: AppColors.muted)),
              if (p.livesAlone) const Pill('Lives alone', color: AppColors.muted, dense: true),
              if (p.needsRescue) const Pill('RESCUE', color: AppColors.help, icon: Icons.emergency, filled: true, dense: true),
              if (p.needsOperator)
                const Pill('NEEDS OPERATOR', color: AppColors.noReply, icon: Icons.headset_mic, filled: true, dense: true),
              Text(p.phoneMasked, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
            ]),
            if (p.needsRescue && p.rescueReason != null) ...[
              const SizedBox(height: 6),
              Text(p.rescueReason!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.primaryDark, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 6),
            PriorityBreakdown(item: p, compact: true),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 2, children: [
              _meta(Icons.stairs_outlined, 'Step: ${humanize(p.escalationStep)} (L${p.escalationLevel})'),
              if (p.nextActionAt != null && p.status != 'SAFE')
                _meta(Icons.alarm, 'Next action ${fmtRelative(p.nextActionAt)}'),
              if (p.repliedAt != null) _meta(Icons.reply, 'Replied ${fmtTime(p.repliedAt)} via ${p.replyChannel ?? '—'}'),
            ]),
            if (p.openTasks.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final t in p.openTasks)
                  Pill(
                    '${t.kind == 'volunteer_assist' ? 'Volunteer' : 'Neighbour'}: ${t.assigneeName ?? '—'} · '
                    '${t.status.replaceAll('_', ' ')}${t.estWalkMinutes != null ? ' · ${t.estWalkMinutes!.toStringAsFixed(0)} min' : ''}',
                    color: AppColors.taskStatus(t.status),
                    icon: t.kind == 'volunteer_assist' ? Icons.directions_walk : Icons.home_outlined,
                    dense: true,
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: AppColors.muted),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 11.5, color: AppColors.muted)),
      ]);
}

/// Every `priority_components` factor with its points, and the total.
class PriorityBreakdown extends StatelessWidget {
  const PriorityBreakdown({super.key, required this.item, this.compact = false});

  final PriorityItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final comps = item.priorityComponents;
    if (compact) {
      return Wrap(spacing: 4, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final c in comps)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: const Color(0xFFF1F2F5), borderRadius: BorderRadius.circular(6)),
            child: Text('+${c.points} ${c.factor}', style: const TextStyle(fontSize: 11)),
          ),
        Text('= ${item.priorityTotal}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900)),
      ]);
    }
    final sum = comps.fold<int>(0, (a, c) => a + c.points);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final c in comps)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(c.factor, style: const TextStyle(fontSize: 13))),
            Text('+${c.points}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      const Divider(),
      Row(children: [
        const Expanded(child: Text('Total priority', style: TextStyle(fontWeight: FontWeight.w800))),
        Text('${item.priorityTotal}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
      ]),
      if (sum != item.priorityTotal)
        Text('Server total differs from the listed factors (sum $sum).',
            style: const TextStyle(color: AppColors.muted, fontSize: 11)),
    ]);
  }
}
