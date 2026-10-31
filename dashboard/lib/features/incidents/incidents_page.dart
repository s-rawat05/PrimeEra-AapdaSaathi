import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../reports/report_page.dart';
import 'incident_dialogs.dart';

/// Incident overview: list/filter, create manual incident, edit (reason), close, report.
class IncidentsPage extends StatefulWidget {
  const IncidentsPage({super.key, required this.onOpenIncident});

  final ValueChanged<Incident> onOpenIncident;

  @override
  State<IncidentsPage> createState() => _IncidentsPageState();
}

class _IncidentsPageState extends State<IncidentsPage> {
  String? _status = 'active';
  bool? _demo;
  int _offset = 0;
  static const _limit = 25;
  PageOf<Incident>? _page;
  Object? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == null && !_loading) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await context.api.listIncidents(status: _status, demo: _demo, limit: _limit, offset: _offset);
      if (mounted) {
        setState(() {
          _page = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final inc = await showCreateIncidentDialog(context, context.api);
    if (inc != null && mounted) {
      showSnack(context, 'Incident created — residents in ${inc.wards.length} ward(s) are being alerted');
      widget.onOpenIncident(inc);
    }
  }

  Future<void> _edit(Incident i) async {
    final r = await showEditIncidentDialog(context, context.api, i);
    if (r != null && mounted) {
      showSnack(context, 'Incident updated (audited)');
      _load();
    }
  }

  Future<void> _close(Incident i) async {
    final api = context.api;
    final r = await showCloseIncidentDialog(context, api, i);
    if (r != null && mounted) {
      showSnack(context, 'Incident closed');
      await _load();
      if (mounted) await openReport(context, api, r.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PageBody(children: [
      PageHeader(
        title: 'Incidents',
        subtitle: 'Official (SACHET), replayed, simulated and manually created incidents',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          FilledButton.icon(
            key: const Key('create-incident'),
            onPressed: _create,
            icon: const Icon(Icons.add_alert),
            label: const Text('Create manual incident'),
          ),
        ],
      ),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Status:', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final s in <String?>['active', 'closed', 'cancelled', null])
          ChoiceChip(
            label: Text(s ?? 'All'),
            selected: _status == s,
            onSelected: (_) {
              setState(() {
                _status = s;
                _offset = 0;
              });
              _load();
            },
          ),
        const SizedBox(width: 12),
        const Text('Type:', style: TextStyle(fontWeight: FontWeight.w700)),
        for (final d in <bool?>[null, true, false])
          ChoiceChip(
            label: Text(d == null ? 'All' : (d ? 'Demo / drill' : 'Real')),
            selected: _demo == d,
            onSelected: (_) {
              setState(() {
                _demo = d;
                _offset = 0;
              });
              _load();
            },
          ),
      ]),
      gap16,
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (page != null && page.items.isEmpty) const EmptyState('No incidents match these filters.'),
      if (page != null)
        for (final i in page.items) ...[_IncidentRow(
          incident: i,
          onOpen: () => widget.onOpenIncident(i),
          onEdit: i.isActive ? () => _edit(i) : null,
          onClose: i.isActive ? () => _close(i) : null,
          onReport: () => openReport(context, context.api, i.id),
        ), gap8],
      if (page != null && page.total > 0)
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('${page.offset + 1}–${page.offset + page.items.length} of ${page.total}'),
          IconButton(
            onPressed: page.hasPrevious
                ? () {
                    setState(() => _offset = (_offset - _limit).clamp(0, 1 << 30));
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: page.hasNext
                ? () {
                    setState(() => _offset += _limit);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
    ]);
  }
}

class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident, required this.onOpen, this.onEdit, this.onClose, required this.onReport});

  final Incident incident;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onClose;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final i = incident;
    final c = i.counts;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (i.isDemo) const Pill('DEMO / DRILL', color: AppColors.drill, filled: true, dense: true),
            Pill(i.sourceTag, color: i.source == 'live' ? AppColors.live : AppColors.drill, dense: true, tooltip: i.sourceLabel),
            Pill(i.status.toUpperCase(), color: i.isActive ? AppColors.safe : AppColors.unreachable, dense: true),
            Pill(i.severity, color: AppColors.severity(i.severity), dense: true),
            Pill('Mode ${i.escalationMode}', color: AppColors.info, dense: true, tooltip: i.modeLabel),
            if (i.pendingApprovals > 0) Pill('${i.pendingApprovals} awaiting approval', color: AppColors.noReply, dense: true),
          ]),
          const SizedBox(height: 6),
          Text(i.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          Text(
            '${i.hazardType} · ${i.wards.map((w) => w.wardName).join(', ')} · created ${fmtDateTime(i.createdAt)}'
            '${i.onset != null ? ' · onset ${fmtShort(i.onset)}' : ''}'
            '${i.closedAt != null ? ' · closed ${fmtShort(i.closedAt)}' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 12, children: [
            _count('Safe', c.safe, AppColors.safe),
            _count('Help', c.help, AppColors.help),
            _count('No reply', c.noReply, AppColors.noReply),
            _count('Unreachable', c.unreachable, AppColors.unreachable),
            _count('Total', c.total, AppColors.text),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            FilledButton.tonalIcon(onPressed: onOpen, icon: const Icon(Icons.crisis_alert, size: 18), label: const Text('Open in command centre')),
            if (onEdit != null) OutlinedButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit, size: 18), label: const Text('Edit')),
            if (onClose != null)
              OutlinedButton.icon(onPressed: onClose, icon: const Icon(Icons.flag, size: 18), label: const Text('Close')),
            OutlinedButton.icon(onPressed: onReport, icon: const Icon(Icons.summarize_outlined, size: 18), label: const Text('Report')),
          ]),
        ]),
      ),
    );
  }

  Widget _count(String l, int v, Color c) => Text.rich(TextSpan(children: [
        TextSpan(text: '$v ', style: TextStyle(color: c, fontWeight: FontWeight.w900)),
        TextSpan(text: l, style: const TextStyle(color: AppColors.muted)),
      ]));
}
