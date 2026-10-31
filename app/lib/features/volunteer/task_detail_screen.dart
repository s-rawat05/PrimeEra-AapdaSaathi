import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/device_services.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import 'task_actions.dart';

/// Task detail (`GET /tasks/{id}`): the exact location and phone are returned only while the task
/// is active; the screen never stores them.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({super.key, required this.taskId});
  final String taskId;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskDetailOut? _task;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.appRead;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await app.call((api) => api.taskDetail(widget.taskId));
      if (mounted) setState(() => _task = t);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _after(Future<TaskOut?> action) async {
    final r = await action;
    if (r != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final t = _task;
    return Scaffold(
      appBar: AppBar(title: Text(s.taskDetail), actions: [
        IconButton(tooltip: s.refresh, onPressed: _load, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (_error != null) ErrorPanel(message: errorText(_error!, s), onRetry: _load, s: s),
              if (_loading && t == null) const Center(child: CircularProgressIndicator()),
              if (t != null) ...[
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(t.residentFullName ?? t.residentFirstName,
                            key: const Key('task-resident-name'),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                      if (t.isDemo) const DemoBadge(),
                    ]),
                    Text('${s.taskKind(t.kind)} · ${t.incidentTitle}', style: const TextStyle(color: AppColors.gray)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      StatusChip(label: s.taskStatusName(t.status), color: t.isOpen ? AppColors.amber : AppColors.gray),
                      for (final n in t.residentNeeds) StatusChip(label: s.needShort(n), color: AppColors.official),
                      if (t.outcome != null) StatusChip(label: s.outcomeName(t.outcome!), color: AppColors.green),
                    ]),
                    if (t.reason.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(t.reason),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),
                SectionCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.exactLocation, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    if (t.exactLocation != null) ...[
                      Text(t.exactLocation!.addressText ?? '', style: const TextStyle(fontSize: 16)),
                      if (t.exactLocation!.landmark != null) Text(t.exactLocation!.landmark!),
                      Text('${t.exactLocation!.lat.toStringAsFixed(5)}, ${t.exactLocation!.lng.toStringAsFixed(5)}',
                          style: const TextStyle(color: AppColors.gray)),
                    ],
                    Text(t.locationNote, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
                    const Divider(height: 20),
                    Row(children: [
                      Expanded(child: FieldRow(s.distance, fmtDistance(t.distanceM))),
                      Expanded(
                        child: FieldRow('${s.walk} (${s.estimate})',
                            t.estWalkMinutes == null ? null : '${fmtMinutes(t.estWalkMinutes)} min'),
                      ),
                    ]),
                    Text(t.walkEstimateNote, key: const Key('walk-note'), style: const TextStyle(fontSize: 12, color: AppColors.amber)),
                  ]),
                ),
                if (t.officialInstruction != null) ...[
                  const SizedBox(height: 12),
                  SectionCard(color: AppColors.officialSoft, child: FieldRow(s.officialInstruction, t.officialInstruction)),
                ],
                if (t.shelters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.reliefPost, style: const TextStyle(fontWeight: FontWeight.w800)),
                      for (final sh in t.shelters)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.night_shelter, color: AppColors.red),
                          title: Text(sh.name),
                          subtitle: Text('${sh.address}\n${fmtDistance(sh.distanceM)}'),
                          isThreeLine: true,
                          trailing: IconButton(
                            tooltip: s.openInMaps,
                            icon: const Icon(Icons.directions),
                            onPressed: () => app.launcher.open(Links.mapsDirections(sh.lat, sh.lng)),
                          ),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                ..._actions(context, t),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  List<Widget> _actions(BuildContext context, TaskDetailOut t) {
    final app = context.app;
    final s = app.s;
    final out = <Widget>[];
    if (t.isAssigned) {
      out.add(FilledButton.icon(
        key: const Key('detail-accept'),
        style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size.fromHeight(60)),
        onPressed: () => _after(acceptTask(context, t)),
        icon: const Icon(Icons.check),
        label: Text(s.accept),
      ));
    }
    if (t.isAccepted || t.isAssigned) {
      if (t.residentPhone != null) {
        out.add(const SizedBox(height: 8));
        out.add(OutlinedButton.icon(
          key: const Key('call-resident'),
          onPressed: () async {
            final ok = await app.launcher.open(Links.tel(t.residentPhone!));
            if (!ok && context.mounted) showSnack(context, s.couldNotOpen, error: true);
          },
          icon: const Icon(Icons.call),
          label: Text('${s.callResident} (${t.residentPhone})'),
        ));
      }
      if (t.exactLocation != null) {
        out.add(const SizedBox(height: 8));
        out.add(OutlinedButton.icon(
          key: const Key('navigate'),
          onPressed: () async {
            final ok = await app.launcher.open(Links.mapsDirections(t.exactLocation!.lat, t.exactLocation!.lng));
            if (!ok && context.mounted) showSnack(context, s.couldNotOpen, error: true);
          },
          icon: const Icon(Icons.directions),
          label: Text(s.navigate),
        ));
      }
    }
    if (t.isAccepted) {
      out.add(const SizedBox(height: 8));
      out.add(FilledButton.icon(
        key: const Key('detail-reached'),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
        onPressed: () => _after(showReachedSheet(context, t)),
        icon: const Icon(Icons.flag),
        label: Text(s.reachedTitle),
      ));
    }
    if (t.isAssigned || t.isAccepted) {
      out.add(const SizedBox(height: 8));
      out.add(TextButton.icon(
        key: const Key('detail-cantgo'),
        onPressed: () => _after(showCantGoSheet(context, t)),
        icon: const Icon(Icons.block),
        label: Text(s.cantGo),
      ));
    }
    return out;
  }
}
