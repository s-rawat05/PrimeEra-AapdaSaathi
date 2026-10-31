import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import 'task_actions.dart';
import 'task_detail_screen.dart';

/// Volunteer dashboard: availability toggle, open tasks (accept / can't go), closed tasks.
class VolunteerTasksScreen extends StatefulWidget {
  const VolunteerTasksScreen({super.key});

  @override
  State<VolunteerTasksScreen> createState() => _VolunteerTasksScreenState();
}

class _VolunteerTasksScreenState extends State<VolunteerTasksScreen> {
  bool _toggling = false;

  Future<void> _setAvailable(bool v) async {
    final app = context.appRead;
    setState(() => _toggling = true);
    try {
      final out = await app.call((api) => api.setAvailability(v));
      app.applyVolunteer(out);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final v = app.volunteer ?? app.me?.volunteer;
    final open = app.volunteerTasks.where((t) => t.isOpen).toList();
    final closed = app.volunteerTasks.where((t) => !t.isOpen).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.tasksTitle), actions: [
        IconButton(tooltip: s.refresh, onPressed: app.refresh, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (v == null)
                ErrorPanel(message: app.responderError ?? s.notVolunteerProfile, onRetry: app.refresh, s: s)
              else
                SectionCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile(
                    key: const Key('availability'),
                    title: Text(s.available, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                    subtitle: Text(
                      '${v.isAvailable ? s.availableOn : s.availableOff}\n${v.fullName}${v.wardName != null ? ' · ${v.wardName}' : ''}',
                    ),
                    isThreeLine: true,
                    value: v.isAvailable,
                    onChanged: _toggling ? null : _setAvailable,
                  ),
                ),
              if (app.responderError != null && v != null) ...[
                const SizedBox(height: 12),
                ErrorPanel(message: app.responderError!, onRetry: app.refresh, s: s),
              ],
              SectionTitle(s.openTasks),
              if (open.isEmpty) EmptyState(icon: Icons.assignment_turned_in, text: s.noOpenTasks),
              for (final t in open) Padding(padding: const EdgeInsets.only(bottom: 12), child: TaskCard(task: t)),
              SectionTitle(s.closedTasks),
              if (closed.isEmpty) EmptyState(icon: Icons.inventory_2_outlined, text: s.noClosedTasks),
              for (final t in closed) Padding(padding: const EdgeInsets.only(bottom: 8), child: TaskCard(task: t)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task});
  final TaskOut task;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = task;
    return SectionCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskDetailScreen(taskId: t.id))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pictogram(t.isOpen ? Icons.directions_run : Icons.task_alt, size: 48,
              color: t.isOpen ? AppColors.red : AppColors.gray),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t.residentFirstName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(s.taskKind(t.kind), style: const TextStyle(color: AppColors.gray)),
            ]),
          ),
          if (t.isDemo) const DemoBadge(),
        ]),
        const SizedBox(height: 6),
        Text(t.incidentTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusChip(label: s.taskStatusName(t.status), color: t.isOpen ? AppColors.amber : AppColors.gray),
          for (final n in t.residentNeeds) StatusChip(label: s.needShort(n), color: AppColors.official),
          if (t.distanceM != null) StatusChip(label: '${s.distance}: ${fmtDistance(t.distanceM)}', color: AppColors.gray),
          if (t.estWalkMinutes != null)
            StatusChip(label: '${s.walk}: ${fmtMinutes(t.estWalkMinutes)} min (${s.estimate})', color: AppColors.amber),
          if (t.outcome != null) StatusChip(label: s.outcomeName(t.outcome!), color: AppColors.green),
          if (t.cantGoReason != null) StatusChip(label: s.reasonName(t.cantGoReason!), color: AppColors.gray),
        ]),
        if (t.isAssigned) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                key: Key('accept-${t.id}'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                onPressed: () => acceptTask(context, t),
                child: Text(s.accept),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: Key('cantgo-${t.id}'),
                onPressed: () => showCantGoSheet(context, t),
                child: Text(s.cantGo),
              ),
            ),
          ]),
        ],
      ]),
    );
  }
}
