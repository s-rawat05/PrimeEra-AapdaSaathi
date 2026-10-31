import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../incidents/timeline_panel.dart';
import '../overview/command_centre_controller.dart';
import '../overview/priority_list.dart';

/// Opens the case side-sheet for one delivery (resident × incident).
Future<void> openCasePanel(BuildContext context, CommandCentreController cc, String deliveryId) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close case',
    barrierColor: Colors.black38,
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        elevation: 12,
        color: AppColors.background,
        child: SizedBox(
          width: MediaQuery.sizeOf(ctx).width < 640 ? MediaQuery.sizeOf(ctx).width : 600,
          height: double.infinity,
          child: CasePanel(controller: cc, deliveryId: deliveryId),
        ),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
      child: child,
    ),
  );
}

class CasePanel extends StatefulWidget {
  const CasePanel({super.key, required this.controller, required this.deliveryId});

  final CommandCentreController controller;
  final String deliveryId;

  @override
  State<CasePanel> createState() => _CasePanelState();
}

class _CasePanelState extends State<CasePanel> {
  PriorityItem? _local;
  List<TimelineEvent>? _timeline;
  List<CandidateOut>? _candidates;
  Object? _timelineError;
  Object? _candidatesError;
  String? _sig;
  bool _busy = false;

  AapdaApi get _api => widget.controller.api;

  PriorityItem? get _item => widget.controller.priorityFor(widget.deliveryId) ?? _local;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
    _sig = _signature();
    _loadDetails();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  String _signature() {
    final p = _item;
    return p == null ? '' : '${p.status}|${p.escalationLevel}|${p.openTasks.map((t) => t.status).join(',')}|${p.repliedAt}';
  }

  void _onController() {
    final sig = _signature();
    if (sig != _sig) {
      _sig = sig;
      _loadDetails();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadDetails() async {
    final id = widget.deliveryId;
    try {
      final t = await _api.deliveryTimeline(id);
      if (mounted) {
        setState(() {
          _timeline = t;
          _timelineError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _timelineError = e);
    }
    try {
      final c = await _api.candidates(id);
      if (mounted) {
        setState(() {
          _candidates = c;
          _candidatesError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _candidatesError = e);
    }
  }

  Future<void> _after(PriorityItem? updated) async {
    if (updated != null) _local = updated;
    await widget.controller.refreshIncident();
    await _loadDetails();
  }

  Future<void> _act(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() => _act(() async {
        final r = await runAction(context, () => _api.resend(widget.deliveryId), success: 'Alert re-sent on all channels');
        if (r != null) await _after(r);
      });

  Future<void> _override() async {
    final p = _item;
    final r = await showDialog<PriorityItem>(
      context: context,
      builder: (_) => OverrideDialog(api: _api, deliveryId: widget.deliveryId, currentStatus: p?.status),
    );
    if (r != null) {
      if (mounted) showSnack(context, 'Status set to ${statusLabel(r.status)} (audited)');
      await _after(r);
    }
  }

  Future<void> _dispatch() => _act(() async {
        final ok = await confirmDialog(context,
            title: 'Dispatch a volunteer now?',
            message: 'The dispatcher will pick the best eligible volunteer using the eligibility rules shown below. '
                'If the incident requires approval, the task waits for approval.',
            confirmLabel: 'Dispatch');
        if (!ok || !mounted) return;
        var called = false;
        TaskOut? task;
        await runAction(context, () async {
          task = await _api.dispatchNow(widget.deliveryId);
          called = true;
        });
        if (!called || !mounted) return;
        showSnack(
          context,
          task == null
              ? 'No eligible volunteer could be dispatched — see the eligibility reasons.'
              : 'Task created for ${task!.assigneeName ?? 'volunteer'} · ${task!.status.replaceAll('_', ' ')}',
          error: task == null,
        );
        await _after(null);
      });

  Future<void> _location() async {
    final ok = await confirmDialog(
      context,
      title: 'View exact location?',
      message: 'Exact resident locations are personal data. This access is audited with your name and the incident, '
          'and is only allowed during an active incident.',
      confirmLabel: 'View (audited)',
    );
    if (!ok || !mounted) return;
    var called = false;
    ExactLocationOut? loc;
    await runAction(context, () async {
      loc = await _api.exactLocation(widget.deliveryId);
      called = true;
    });
    if (!called || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.location_on, color: AppColors.primary), SizedBox(width: 8), Text('Exact location')]),
        content: SizedBox(
          width: 420,
          child: loc == null
              ? const Text('No exact location is on record for this resident (or location consent was withdrawn).')
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  KeyValue('Latitude', loc!.lat.toStringAsFixed(6)),
                  KeyValue('Longitude', loc!.lng.toStringAsFixed(6)),
                  KeyValue('Address', loc!.addressText),
                  KeyValue('Landmark', loc!.landmark),
                  KeyValue('Source', loc!.source),
                  const SizedBox(height: 8),
                  const InfoBanner('This view was recorded in the audit log.', icon: Icons.policy_outlined),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _item;
    final active = widget.controller.incident?.isActive ?? true;
    return Column(children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(children: [
          const Icon(Icons.person_pin_circle, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p?.residentName ?? 'Case',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
          ),
          if (p != null) StatusChip(p.status),
          IconButton(tooltip: 'Refresh', onPressed: () => _after(null), icon: const Icon(Icons.refresh)),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
      ),
      const Divider(),
      Expanded(
        child: p == null
            ? const EmptyState('This resident is not in the current incident list.')
            : ListView(padding: const EdgeInsets.all(16), children: [
                if (p.needsRescue) ...[
                  InfoBanner('RESCUE PRIORITY — ${p.rescueReason ?? 'no safe helper can arrive in time'}',
                      color: AppColors.help, icon: Icons.emergency),
                  gap12,
                ],
                if (p.needsOperator) ...[
                  const InfoBanner('Escalated to the command centre: an operator must act on this case.',
                      color: AppColors.noReply, icon: Icons.headset_mic),
                  gap12,
                ],
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    key: const Key('case-resend'),
                    onPressed: _busy || !active ? null : _resend,
                    icon: const Icon(Icons.send),
                    label: const Text('Resend'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('case-override'),
                    onPressed: _busy || !active ? null : _override,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('Override status'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('case-dispatch'),
                    onPressed: _busy || !active || p.status == 'SAFE' ? null : _dispatch,
                    icon: const Icon(Icons.directions_walk),
                    label: const Text('Dispatch now'),
                  ),
                  OutlinedButton.icon(
                    key: const Key('case-location'),
                    onPressed: _busy || !active ? null : _location,
                    icon: const Icon(Icons.my_location),
                    label: const Text('View exact location'),
                  ),
                ]),
                if (!active) ...[
                  gap8,
                  const InfoBanner('Incident is closed — case actions are disabled.', color: AppColors.unreachable),
                ],
                gap16,
                SectionCard(
                  title: 'Resident',
                  icon: Icons.badge_outlined,
                  child: Column(children: [
                    KeyValue('Ward', p.wardName),
                    KeyValue('Phone', p.phoneMasked),
                    KeyValue('Needs', p.needs.isEmpty ? 'None declared' : p.needs.map(needLabel).join(', ')),
                    KeyValue('Lives alone', p.livesAlone ? 'Yes' : 'No'),
                    KeyValue('Channels', p.channels.join(', ')),
                    KeyValue('Alerted', fmtDateTime(p.alertedAt)),
                    KeyValue('Seen in app', fmtDateTime(p.seenAt)),
                    KeyValue('Replied', p.repliedAt == null ? null : '${fmtDateTime(p.repliedAt)} via ${p.replyChannel ?? '—'}'),
                    KeyValue('Resolved by', p.resolvedBy),
                    KeyValue('Escalation', '${humanize(p.escalationStep)} · level ${p.escalationLevel}'),
                    KeyValue('Next action',
                        p.nextActionAt == null ? null : '${fmtTime(p.nextActionAt)} (${fmtRelative(p.nextActionAt)})'),
                  ]),
                ),
                gap12,
                SectionCard(
                  title: 'Priority score ${p.priorityTotal}',
                  icon: Icons.calculate_outlined,
                  child: PriorityBreakdown(item: p),
                ),
                gap12,
                SectionCard(
                  title: 'Open tasks',
                  icon: Icons.assignment_outlined,
                  child: p.openTasks.isEmpty
                      ? const Text('No open tasks.', style: TextStyle(color: AppColors.muted))
                      : Column(children: [
                          for (final t in p.openTasks)
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(t.kind == 'volunteer_assist' ? Icons.directions_walk : Icons.home_outlined),
                              title: Text('${humanize(t.kind)} · ${t.assigneeName ?? '—'}'),
                              subtitle: t.estWalkMinutes == null ? null : Text('Est. walk ${t.estWalkMinutes!.toStringAsFixed(0)} min'),
                              trailing: TaskStatusChip(t.status),
                            ),
                        ]),
                ),
                gap12,
                SectionCard(
                  title: 'Volunteer eligibility',
                  subtitle: 'Why each volunteer can or cannot be dispatched',
                  icon: Icons.rule,
                  child: _candidatesError != null
                      ? ErrorPanel(error: _candidatesError!, onRetry: _loadDetails)
                      : _candidates == null
                          ? const LinearProgressIndicator()
                          : _candidates!.isEmpty
                              ? const Text('No volunteers registered.', style: TextStyle(color: AppColors.muted))
                              : Column(children: [for (final c in _candidates!) _CandidateRow(c)]),
                ),
                gap12,
                SectionCard(
                  title: 'Case timeline',
                  icon: Icons.timeline,
                  child: _timelineError != null
                      ? ErrorPanel(error: _timelineError!, onRetry: _loadDetails)
                      : _timeline == null
                          ? const LinearProgressIndicator()
                          : TimelineList(events: _timeline!, newestFirst: false),
                ),
              ]),
      ),
    ]);
  }
}

class _CandidateRow extends StatelessWidget {
  const _CandidateRow(this.c);

  final CandidateOut c;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(c.eligible ? Icons.check_circle : Icons.cancel, color: c.eligible ? AppColors.safe : AppColors.help, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${fmtMeters(c.distanceM)} · ~${c.walkMinutes.toStringAsFixed(0)} min walk (estimate)',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Text(c.reason, style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
          Pill(c.eligible ? 'ELIGIBLE' : 'NOT ELIGIBLE', color: c.eligible ? AppColors.safe : AppColors.help, dense: true),
        ]),
      );
}

/// Manual status override. The backend requires a reason of at least 5 characters; it is audited.
class OverrideDialog extends StatefulWidget {
  const OverrideDialog({super.key, required this.api, required this.deliveryId, this.currentStatus});

  final AapdaApi api;
  final String deliveryId;
  final String? currentStatus;

  @override
  State<OverrideDialog> createState() => _OverrideDialogState();
}

class _OverrideDialogState extends State<OverrideDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late String _status = widget.currentStatus == 'SAFE' ? 'HELP' : 'SAFE';
  bool _busy = false;
  Object? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.api.overrideStatus(widget.deliveryId, status: _status, reason: _reason.text.trim());
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Override status'),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Use when status was confirmed by another channel (e.g. a phone call). '
                  'The change, your name and the reason are written to the audit log.'),
              gap12,
              DropdownButtonFormField<String>(
                key: const Key('override-status'),
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'New status'),
                items: [
                  for (final s in DeliveryStatus.overridable) DropdownMenuItem(value: s, child: Text(statusLabel(s))),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              gap12,
              TextFormField(
                key: const Key('override-reason'),
                controller: _reason,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Reason (required)', helperText: 'At least 5 characters'),
                validator: (v) => (v ?? '').trim().length < 5 ? 'A reason of at least 5 characters is required' : null,
              ),
              if (_error != null) ...[gap8, ErrorPanel(error: _error!)],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('override-submit'),
            onPressed: _busy ? null : _submit,
            child: const Text('Override'),
          ),
        ],
      );
}
