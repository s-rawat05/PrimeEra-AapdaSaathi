import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

/// Tasks & approvals for the selected incident (`GET /incidents/{id}/tasks`).
class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.api,
    required this.tasks,
    required this.onChanged,
    required this.onOpenCase,
    this.error,
    this.incidentActive = true,
  });

  final AapdaApi api;
  final List<TaskOut> tasks;
  final Future<void> Function() onChanged;
  final ValueChanged<String> onOpenCase;
  final Object? error;
  final bool incidentActive;

  @override
  State<TasksPanel> createState() => _TasksPanelState();
}

class _TasksPanelState extends State<TasksPanel> {
  final Set<String> _busy = {};
  bool _showClosed = false;

  Future<void> _run(String taskId, Future<Object?> Function() f, String success) async {
    setState(() => _busy.add(taskId));
    try {
      var ok = false;
      await runAction(context, () async {
        await f();
        ok = true;
      }, success: success);
      // Refetch either way: a 409 usually means the task changed state underneath us.
      await widget.onChanged();
      if (!ok) return;
    } finally {
      if (mounted) setState(() => _busy.remove(taskId));
    }
  }

  Future<void> _approve(TaskOut t) =>
      _run(t.id, () => widget.api.approveTask(t.id), 'Approved — ${t.assigneeName ?? 'volunteer'} has been notified');

  Future<void> _reject(TaskOut t) async {
    final reason = await reasonDialog(
      context,
      title: 'Reject dispatch to ${t.assigneeName ?? 'volunteer'}?',
      message: 'The volunteer will not be sent. Give a reason for the audit log (e.g. route flooded).',
      confirmLabel: 'Reject',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _run(t.id, () => widget.api.rejectTask(t.id, reason), 'Dispatch rejected');
  }

  Future<void> _reassign(TaskOut t) async {
    final res = await showDialog<_ReassignResult>(
      context: context,
      builder: (_) => ReassignDialog(api: widget.api, task: t),
    );
    if (res == null || !mounted) return;
    setState(() => _busy.add(t.id));
    try {
      var called = false;
      TaskOut? created;
      await runAction(context, () async {
        created = await widget.api.reassignTask(t.id, toVolunteerId: res.volunteerId, reason: res.reason);
        called = true;
      });
      if (called && mounted) {
        showSnack(
          context,
          created == null
              ? 'Task closed, but no other eligible volunteer was available.'
              : 'Reassigned to ${created!.assigneeName ?? 'volunteer'} · ${created!.status.replaceAll('_', ' ')}',
          error: created == null,
        );
      }
      await widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy.remove(t.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.tasks.where((t) => t.isPendingApproval).toList();
    final open = widget.tasks.where((t) => t.isOpen && !t.isPendingApproval).toList();
    final closed = widget.tasks.where((t) => !t.isOpen).toList();
    return SectionCard(
      title: 'Tasks & approvals',
      icon: Icons.assignment_turned_in_outlined,
      subtitle: '${pending.length} awaiting approval · ${open.length} open · ${closed.length} closed',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.error != null) ...[ErrorPanel(error: widget.error!), gap8],
        if (widget.tasks.isEmpty) const EmptyState('No neighbour checks or volunteer tasks yet.', icon: Icons.assignment_outlined),
        if (pending.isNotEmpty) ...[
          const _GroupLabel('Awaiting your approval', AppColors.noReply),
          for (final t in pending) _row(t),
        ],
        if (open.isNotEmpty) ...[
          const _GroupLabel('Open', AppColors.info),
          for (final t in open) _row(t),
        ],
        if (closed.isNotEmpty) ...[
          TextButton.icon(
            onPressed: () => setState(() => _showClosed = !_showClosed),
            icon: Icon(_showClosed ? Icons.expand_less : Icons.expand_more),
            label: Text('${_showClosed ? 'Hide' : 'Show'} ${closed.length} closed tasks'),
          ),
          if (_showClosed) for (final t in closed) _row(t),
        ],
      ]),
    );
  }

  Widget _row(TaskOut t) {
    final busy = _busy.contains(t.id);
    final active = widget.incidentActive;
    return Container(
      key: ValueKey('task-${t.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.isPendingApproval ? AppColors.warningBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.isPendingApproval ? AppColors.noReply : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(t.isVolunteerTask ? Icons.directions_walk : Icons.home_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: () => widget.onOpenCase(t.deliveryId),
              child: Text(
                '${t.isVolunteerTask ? 'Volunteer assist' : 'Neighbour check'} → ${t.residentFirstName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          TaskStatusChip(t.status),
        ]),
        const SizedBox(height: 4),
        Text(
          '${t.assigneeName ?? 'Unassigned'}'
          '${t.distanceM != null ? ' · ${fmtMeters(t.distanceM)}' : ''}'
          '${t.estWalkMinutes != null ? ' · ~${t.estWalkMinutes!.toStringAsFixed(0)} min walk' : ''}'
          ' · attempt ${t.attemptNo} · created ${fmtTime(t.createdAt)}',
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        Text(t.reason, style: const TextStyle(fontSize: 12.5)),
        if (t.outcome != null || t.cantGoReason != null)
          Text(
            [
              if (t.outcome != null) 'Outcome: ${humanize(t.outcome!)}',
              if (t.cantGoReason != null) "Can't go: ${humanize(t.cantGoReason!)}",
              if (t.outcomeNote != null) '“${t.outcomeNote}”',
            ].join(' · '),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        if (active && (t.isPendingApproval || t.canReassign)) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (t.isPendingApproval) ...[
              FilledButton.icon(
                key: Key('approve-${t.id}'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.safe, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                onPressed: busy ? null : () => _approve(t),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Approve'),
              ),
              OutlinedButton.icon(
                key: Key('reject-${t.id}'),
                onPressed: busy ? null : () => _reject(t),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Reject'),
              ),
            ],
            if (t.canReassign)
              OutlinedButton.icon(
                key: Key('reassign-${t.id}'),
                onPressed: busy ? null : () => _reassign(t),
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Reassign'),
              ),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ],
      ]),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.6)),
      );
}

class _ReassignResult {
  const _ReassignResult(this.volunteerId, this.reason);

  final String? volunteerId;
  final String reason;
}

/// Pick a specific volunteer (with eligibility shown) or let the dispatcher choose; reason required.
class ReassignDialog extends StatefulWidget {
  const ReassignDialog({super.key, required this.api, required this.task});

  final AapdaApi api;
  final TaskOut task;

  @override
  State<ReassignDialog> createState() => _ReassignDialogState();
}

class _ReassignDialogState extends State<ReassignDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late final Future<List<CandidateOut>> _candidates = widget.api.candidates(widget.task.deliveryId);
  String? _volunteerId;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Reassign task for ${widget.task.residentFirstName}'),
        content: SizedBox(
          width: 480,
          child: Form(
            key: _form,
            child: FutureBuilder<List<CandidateOut>>(
              future: _candidates,
              builder: (context, snap) {
                final list = (snap.data ?? const <CandidateOut>[])
                    .where((c) => c.volunteerId != widget.task.volunteerId)
                    .toList();
                return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Currently: ${widget.task.assigneeName ?? '—'} (${widget.task.status.replaceAll('_', ' ')})'),
                  gap12,
                  if (snap.hasError) ErrorPanel(error: snap.error!),
                  if (!snap.hasData && !snap.hasError) const LinearProgressIndicator(),
                  DropdownButtonFormField<String?>(
                    initialValue: _volunteerId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Assign to'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Auto — best eligible volunteer')),
                      for (final c in list)
                        DropdownMenuItem<String?>(
                          value: c.volunteerId,
                          child: Text(
                            '${c.name} · ${fmtMeters(c.distanceM)} · ${c.eligible ? 'eligible' : 'not eligible: ${c.reason}'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _volunteerId = v),
                  ),
                  gap12,
                  TextFormField(
                    controller: _reason,
                    maxLines: 2,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'Reason (required)', helperText: 'At least 5 characters'),
                    validator: (v) => (v ?? '').trim().length < 5 ? 'A reason of at least 5 characters is required' : null,
                  ),
                  const Text('The server re-checks eligibility; ineligible choices are refused with the reason.',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]);
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _ReassignResult(_volunteerId, _reason.text.trim()));
              }
            },
            child: const Text('Reassign'),
          ),
        ],
      );
}
