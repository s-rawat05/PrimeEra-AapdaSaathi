import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';

/// Neighbour check requests: answer SAFE / HELP / CANNOT_REACH with an optional note.
class NeighbourChecksScreen extends StatefulWidget {
  const NeighbourChecksScreen({super.key, this.focusTaskId});

  /// Opened from a notification: scroll/highlight this check.
  final String? focusTaskId;

  @override
  State<NeighbourChecksScreen> createState() => _NeighbourChecksScreenState();
}

class _NeighbourChecksScreenState extends State<NeighbourChecksScreen> {
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final open = app.neighbourChecks.where((t) => t.isOpen).toList();
    final closed = app.neighbourChecks.where((t) => !t.isOpen).toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.checksTitle), actions: [
        IconButton(tooltip: s.refresh, onPressed: app.refresh, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (app.responderError != null) ErrorPanel(message: app.responderError!, onRetry: app.refresh, s: s),
              if (open.isEmpty) EmptyState(icon: Icons.house, text: s.noChecks),
              for (final t in open)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CheckCard(task: t, highlighted: t.id == widget.focusTaskId),
                ),
              SwitchListTile(
                title: Text(s.showClosed),
                value: _showClosed,
                onChanged: (v) => setState(() => _showClosed = v),
              ),
              if (_showClosed)
                for (final t in closed)
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: CheckCard(task: t)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class CheckCard extends StatefulWidget {
  const CheckCard({super.key, required this.task, this.highlighted = false});
  final TaskOut task;
  final bool highlighted;

  @override
  State<CheckCard> createState() => _CheckCardState();
}

class _CheckCardState extends State<CheckCard> {
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(String outcome) async {
    final app = context.appRead;
    final s = app.s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.outcomeName(outcome)),
        content: Text(s.checkOn(widget.task.residentFirstName)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(key: const Key('check-confirm'), onPressed: () => Navigator.pop(ctx, true), child: Text(s.confirm)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await app.call((api) => api.neighbourRespond(widget.task.id, outcome, note: _note.text.trim()));
      if (mounted) showSnack(context, s.recorded);
      await app.refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final t = widget.task;
    return SectionCard(
      color: widget.highlighted ? AppColors.redSoft : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Pictogram(Icons.house, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.checkOn(t.residentFirstName), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(t.incidentTitle, style: const TextStyle(color: AppColors.gray)),
            ]),
          ),
          if (t.isDemo) const DemoBadge(),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          StatusChip(label: s.taskStatusName(t.status), color: t.isOpen ? AppColors.amber : AppColors.gray),
          for (final n in t.residentNeeds) StatusChip(label: s.needShort(n), color: AppColors.official),
          if (t.distanceM != null) StatusChip(label: fmtDistance(t.distanceM), color: AppColors.gray),
          if (t.outcome != null) StatusChip(label: s.outcomeName(t.outcome!), color: AppColors.green),
        ]),
        if (t.isOpen) ...[
          const SizedBox(height: 8),
          Text(s.onlyIfSafe, style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: InputDecoration(labelText: s.optionalNote),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            key: Key('check-safe-${t.id}'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            onPressed: _busy ? null : () => _send('SAFE'),
            icon: const Icon(Icons.check_circle),
            label: Text(s.theyAreSafe),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: Key('check-help-${t.id}'),
            onPressed: _busy ? null : () => _send('HELP'),
            icon: const Icon(Icons.sos),
            label: Text(s.theyNeedHelp),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: Key('check-cannot-${t.id}'),
            onPressed: _busy ? null : () => _send('CANNOT_REACH'),
            icon: const Icon(Icons.block),
            label: Text(s.cannotReach),
          ),
        ],
      ]),
    );
  }
}
