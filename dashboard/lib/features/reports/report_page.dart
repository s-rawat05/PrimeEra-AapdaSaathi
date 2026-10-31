import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../services/file_saver.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

Future<void> openReport(BuildContext context, AapdaApi api, String incidentId) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ReportPage(api: api, incidentId: incidentId)),
    );

/// Closing report (`GET /incidents/{id}/report`) with CSV download (`report.csv`, auth header).
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.api, required this.incidentId});

  final AapdaApi api;
  final String incidentId;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  late Future<IncidentReport> _future = widget.api.report(widget.incidentId);
  bool _downloading = false;

  Future<void> _download() async {
    setState(() => _downloading = true);
    final csv = await runAction(context, () => widget.api.reportCsv(widget.incidentId));
    if (mounted) setState(() => _downloading = false);
    if (csv == null || !mounted) return;
    final ok = saveTextFile('aapdasaathi-report-${widget.incidentId}.csv', csv);
    if (ok) {
      showSnack(context, 'CSV downloaded');
    } else {
      // Non-web fallback: show the CSV so it can be copied.
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Report CSV'),
          content: SizedBox(width: 640, child: SingleChildScrollView(child: SelectableText(csv))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Closing report', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              tooltip: 'Regenerate',
              onPressed: () => setState(() => _future = widget.api.report(widget.incidentId)),
              icon: const Icon(Icons.refresh),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                key: const Key('report-download'),
                onPressed: _downloading ? null : _download,
                icon: const Icon(Icons.download),
                label: const Text('Download CSV'),
              ),
            ),
          ],
        ),
        body: FutureBuilder<IncidentReport>(
          future: _future,
          builder: (context, snap) {
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: ErrorPanel(
                    error: snap.error!,
                    onRetry: () => setState(() => _future = widget.api.report(widget.incidentId))),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            return ReportView(report: snap.data!);
          },
        ),
      );
}

class ReportView extends StatelessWidget {
  const ReportView({super.key, required this.report});

  final IncidentReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final inc = r.incident;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (inc.isDemo) const Pill('DEMO / DRILL', color: AppColors.drill, filled: true, icon: Icons.theater_comedy),
        Pill(inc.sourceLabel, color: inc.source == 'live' ? AppColors.live : AppColors.drill),
        Pill(inc.status.toUpperCase(), color: inc.isActive ? AppColors.safe : AppColors.unreachable),
      ]),
      gap8,
      Text(inc.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
      Text('Generated ${fmtDateTime(r.generatedAt)} · created ${fmtDateTime(inc.createdAt)}'
          '${inc.closedAt != null ? ' · closed ${fmtDateTime(inc.closedAt)}' : ''}',
          style: const TextStyle(color: AppColors.muted)),
      if (inc.closeNote != null) Text('Close note: ${inc.closeNote}'),
      gap16,
      Wrap(spacing: 12, runSpacing: 12, children: [
        _tile('Safe', r.counts.safe, AppColors.safe),
        _tile('Help', r.counts.help, AppColors.help),
        _tile('No reply', r.counts.noReply, AppColors.noReply),
        _tile('Unreachable', r.counts.unreachable, AppColors.unreachable),
        if (r.counts.pending > 0) _tile('Pending', r.counts.pending, AppColors.pending),
        _tile('Total', r.counts.total, AppColors.text),
        _textTile('Safe rate', r.safeRate == null ? '—' : '${(r.safeRate! * 100).toStringAsFixed(1)} %', AppColors.safe),
      ]),
      gap16,
      SectionCard(
        title: 'Alert-to-safe time',
        icon: Icons.timer_outlined,
        subtitle: 'From first alert to confirmed safe',
        child: _statsTable({'All channels': r.alertToSafe, ...r.alertToSafeByChannel}),
      ),
      gap16,
      SectionCard(
        title: 'Unresolved (${r.unresolved.length})',
        icon: Icons.report_problem_outlined,
        child: r.unresolved.isEmpty
            ? const Text('Every alerted resident was confirmed safe.', style: TextStyle(color: AppColors.safe))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 36,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 72,
                  columns: const [
                    DataColumn(label: Text('Resident')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('Priority'), numeric: true),
                    DataColumn(label: Text('Needs')),
                    DataColumn(label: Text('Step')),
                    DataColumn(label: Text('Rescue')),
                  ],
                  rows: [
                    for (final u in r.unresolved)
                      DataRow(cells: [
                        DataCell(Text(u.residentName)),
                        DataCell(StatusChip(u.status, dense: true)),
                        DataCell(Text('${u.priority ?? '—'}')),
                        DataCell(Text(u.needs.map(needLabel).join(', '))),
                        DataCell(Text(u.escalationStep == null ? '—' : humanize(u.escalationStep!))),
                        DataCell(SizedBox(
                          width: 320,
                          child: Text(u.needsRescue ? (u.rescueReason ?? 'Yes') : 'No',
                              maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                        )),
                      ]),
                  ],
                ),
              ),
      ),
      gap16,
      SectionCard(
        title: 'Assistance tasks (${r.tasks.total})',
        icon: Icons.assignment_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _counter('By kind & status', r.tasks.byKindStatus),
          _counter('Outcomes', r.tasks.outcomes),
          _counter("Can't-go reasons", r.tasks.cantGoReasons),
          gap8,
          _statsTable({'Time to accept': r.tasks.timeToAccept, 'Time to reach': r.tasks.timeToReach}),
          if (r.tasks.items.isNotEmpty) ...[
            gap8,
            for (final t in r.tasks.items)
              Text(
                '• ${humanize(t.kind)} — ${t.assignee ?? '—'} · ${t.status}'
                '${t.outcome != null ? ' · ${humanize(t.outcome!)}' : ''}'
                '${t.cantGoReason != null ? " · can't go: ${humanize(t.cantGoReason!)}" : ''} · attempt ${t.attemptNo}',
                style: const TextStyle(fontSize: 12.5),
              ),
          ],
        ]),
      ),
      gap16,
      SectionCard(
        title: 'Notifications',
        icon: Icons.notifications_active_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _counter('By channel & status', r.notificationsByChannelStatus),
          KeyValue('Blocked by safety switch', '${r.blockedBySafetySwitch}', labelWidth: 200),
        ]),
      ),
      gap16,
      SectionCard(
        title: 'Notes',
        icon: Icons.sticky_note_2_outlined,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final n in r.notes) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $n')),
        ]),
      ),
    ]);
  }

  Widget _tile(String label, int value, Color color) => _textTile(label, '$value', color);

  Widget _textTile(String label, String value, Color color) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Container(width: 5, height: 46, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
            ]),
          ),
        ]),
      );

  Widget _statsTable(Map<String, DurationStats> rows) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 36,
          dataRowMinHeight: 32,
          dataRowMaxHeight: 40,
          columns: const [
            DataColumn(label: Text('')),
            DataColumn(label: Text('Count'), numeric: true),
            DataColumn(label: Text('Median'), numeric: true),
            DataColumn(label: Text('P90'), numeric: true),
            DataColumn(label: Text('Max'), numeric: true),
          ],
          rows: [
            for (final e in rows.entries)
              DataRow(cells: [
                DataCell(Text(humanize(e.key), style: const TextStyle(fontWeight: FontWeight.w700))),
                DataCell(Text('${e.value.count}')),
                DataCell(Text(fmtSeconds(e.value.medianSeconds))),
                DataCell(Text(fmtSeconds(e.value.p90Seconds))),
                DataCell(Text(fmtSeconds(e.value.maxSeconds))),
              ]),
          ],
        ),
      );

  Widget _counter(String title, Map<String, int> m) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(width: 150, child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 13))),
          if (m.isEmpty) const Text('—'),
          for (final e in m.entries) Pill('${e.key.replaceAll('_', ' ')}: ${e.value}', color: AppColors.info, dense: true),
        ]),
      );
}
