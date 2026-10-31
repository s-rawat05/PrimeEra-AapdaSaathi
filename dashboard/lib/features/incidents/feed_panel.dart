import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../overview/command_centre_controller.dart';

/// Feed health chip for the command centre header (`GET /feed/status`).
class FeedHealthChip extends StatelessWidget {
  const FeedHealthChip({super.key, required this.status});

  final FeedStatus? status;

  @override
  Widget build(BuildContext context) {
    final s = status;
    if (s == null) return const Pill('SACHET: unknown', color: AppColors.unreachable, icon: Icons.rss_feed, dense: true);
    final f = s.feeds.isEmpty ? null : s.feeds.first;
    final tip = StringBuffer('SACHET CAP feed\n')
      ..writeln('Polling: ${s.pollingEnabled ? 'enabled' : 'disabled'}');
    for (final x in s.feeds) {
      tip
        ..writeln(x.url)
        ..writeln('Healthy: ${x.healthy ? 'yes' : 'no'} · failures in a row: ${x.consecutiveFailures}')
        ..writeln('Last success: ${fmtDateTime(x.lastSuccessAt)}')
        ..writeln('Last fetch: ${fmtDateTime(x.lastFetchAt)} (HTTP ${x.lastStatusCode ?? '—'})')
        ..writeln('Last error: ${x.lastError ?? 'none'}')
        ..writeln('ETag: ${x.etag ?? '—'}');
    }
    final String label;
    final Color color;
    if (s.allHealthy) {
      label = 'SACHET healthy · ${fmtRelative(f?.lastSuccessAt)}';
      color = AppColors.safe;
    } else if (!s.pollingEnabled && (f?.lastSuccessAt == null)) {
      label = 'SACHET polling off';
      color = AppColors.unreachable;
    } else {
      label = f?.lastError != null ? 'SACHET error' : 'SACHET stale';
      color = AppColors.help;
    }
    return Pill(label, color: color, icon: Icons.rss_feed, dense: true, tooltip: tip.toString().trim());
  }
}

/// SACHET panel: health, "Fetch now", message list, original XML, replay into the demo ward.
class FeedPanel extends StatefulWidget {
  const FeedPanel({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  State<FeedPanel> createState() => _FeedPanelState();
}

class _FeedPanelState extends State<FeedPanel> {
  PageOf<CapMessage>? _page;
  Object? _error;
  bool _includeFixtures = false;
  bool _polling = false;
  List<FeedPollResult>? _lastPoll;
  int _rev = -1;

  CommandCentreController get cc => widget.controller;

  @override
  void initState() {
    super.initState();
    cc.addListener(_onCc);
    _load();
  }

  @override
  void dispose() {
    cc.removeListener(_onCc);
    super.dispose();
  }

  void _onCc() {
    if (cc.feedRevision != _rev) _load();
  }

  Future<void> _load() async {
    _rev = cc.feedRevision;
    try {
      final p = await cc.api.feedMessages(includeFixtures: _includeFixtures, limit: 50);
      if (mounted) {
        setState(() {
          _page = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _poll() async {
    setState(() => _polling = true);
    final r = await runAction(context, () => cc.api.feedPoll());
    if (mounted) {
      setState(() {
        _polling = false;
        if (r != null) _lastPoll = r;
      });
    }
    await cc.refreshAll(quiet: true);
    await _load();
  }

  Future<void> _showXml(CapMessage m) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Original CAP XML · ${m.identifier}', overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: 760,
          height: 520,
          child: FutureBuilder<String>(
            future: cc.api.feedMessageXml(m.id),
            builder: (context, snap) {
              if (snap.hasError) return ErrorPanel(error: snap.error!);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return Container(
                decoration: BoxDecoration(color: const Color(0xFF111827), borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(12),
                child: SingleChildScrollView(
                  child: SelectableText(
                    snap.data!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Color(0xFFE5E7EB), height: 1.35),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _replay(CapMessage m) async {
    final wards = cc.demoStatus?.demoWards ?? const <WardOut>[];
    final res = await showDialog<_ReplayChoice>(context: context, builder: (_) => _ReplayDialog(message: m, demoWards: wards));
    if (res == null || !mounted) return;
    final inc = await runAction(
      context,
      () => cc.api.replayMessage(m.id, onsetInMinutes: res.onset, wardIds: res.wardIds),
      success: 'Replayed into the demo ward as a drill',
    );
    if (inc != null) await cc.focusIncident(inc);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final status = cc.feedStatus;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (status != null) ...[
        for (final f in status.feeds)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: f.healthy ? AppColors.okBg : AppColors.warningBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: f.healthy ? AppColors.safe : AppColors.noReply),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(f.healthy ? Icons.check_circle : Icons.warning_amber, color: f.healthy ? AppColors.safe : AppColors.noReply, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text(f.healthy ? 'Feed healthy' : 'Feed not healthy', style: const TextStyle(fontWeight: FontWeight.w800))),
                Pill(status.pollingEnabled ? 'POLLING ON' : 'POLLING OFF',
                    color: status.pollingEnabled ? AppColors.safe : AppColors.unreachable, dense: true),
              ]),
              const SizedBox(height: 4),
              SelectableText(f.url, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
              KeyValue('Last success', fmtDateTime(f.lastSuccessAt), labelWidth: 110),
              KeyValue('Last fetch', '${fmtDateTime(f.lastFetchAt)} · HTTP ${f.lastStatusCode ?? '—'}', labelWidth: 110),
              KeyValue('Last error', f.lastError ?? 'none', labelWidth: 110),
              KeyValue('ETag', f.etag, labelWidth: 110),
              KeyValue('Items seen', '${f.itemsSeen} · failures in a row ${f.consecutiveFailures}', labelWidth: 110),
              KeyValue('Next fetch', fmtDateTime(f.nextFetchAt), labelWidth: 110),
            ]),
          ),
      ],
      if (cc.errors['feed'] != null) ErrorPanel(error: cc.errors['feed']!),
      Row(children: [
        FilledButton.icon(
          key: const Key('feed-poll'),
          onPressed: _polling ? null : _poll,
          icon: _polling
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.cloud_download_outlined),
          label: const Text('Fetch now'),
        ),
        const Spacer(),
        const Text('Fixtures', style: TextStyle(fontSize: 12)),
        Switch(
          value: _includeFixtures,
          onChanged: (v) {
            setState(() => _includeFixtures = v);
            _load();
          },
        ),
      ]),
      if (_lastPoll != null) ...[
        gap8,
        for (final r in _lastPoll!) InfoBanner('Fetch result: ${r.summary}', icon: Icons.sync),
      ],
      gap12,
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (_page == null && _error == null) const LinearProgressIndicator(),
      if (_page != null && _page!.items.isEmpty)
        EmptyState(_includeFixtures ? 'No CAP messages stored yet.' : 'No official SACHET messages received yet. '
            'Use "Fetch now", or include fixtures.', icon: Icons.rss_feed),
      if (_page != null)
        for (final m in _page!.items) _messageCard(m),
      if (_page != null && _page!.total > _page!.items.length)
        Text('Showing ${_page!.items.length} of ${_page!.total}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }

  Widget _messageCard(CapMessage m) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (m.severity != null) Pill(m.severity!, color: AppColors.severity(m.severity!), dense: true),
            if (m.msgType != null) Pill(m.msgType!.toUpperCase(), color: AppColors.info, dense: true),
            if (m.status != null) Pill(m.status!.toUpperCase(), color: AppColors.drill, dense: true),
            Pill(m.isValid ? 'VALID CAP' : 'INVALID', color: m.isValid ? AppColors.safe : AppColors.help, dense: true),
            if (m.isFixture) const Pill('FIXTURE', color: AppColors.unreachable, dense: true),
            if (m.supersededBy != null) const Pill('SUPERSEDED', color: AppColors.unreachable, dense: true),
          ]),
          const SizedBox(height: 6),
          Text(m.event ?? '(no event)', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (m.headline != null) Text(m.headline!, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 4),
          Text('Sender: ${m.sender ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text('Area: ${m.areaDesc ?? '—'}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text('Sent ${fmtShort(m.sent)} · onset ${fmtShort(m.onset)} · expires ${fmtShort(m.expires)}',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          if (m.validationErrors.isNotEmpty)
            Text('Validation: ${m.validationErrors.join('; ')}', style: const TextStyle(fontSize: 12, color: AppColors.help)),
          if (m.incidentIds.isNotEmpty)
            Text('Linked incidents: ${m.incidentIds.length}', style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, children: [
            TextButton.icon(onPressed: () => _showXml(m), icon: const Icon(Icons.code, size: 18), label: const Text('Original XML')),
            TextButton.icon(
              onPressed: (cc.demoStatus?.demoModeEnabled ?? false) ? () => _replay(m) : null,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('Replay into demo ward'),
            ),
          ]),
        ]),
      );
}

class _ReplayChoice {
  const _ReplayChoice(this.onset, this.wardIds);

  final int onset;
  final List<String>? wardIds;
}

class _ReplayDialog extends StatefulWidget {
  const _ReplayDialog({required this.message, required this.demoWards});

  final CapMessage message;
  final List<WardOut> demoWards;

  @override
  State<_ReplayDialog> createState() => _ReplayDialogState();
}

class _ReplayDialogState extends State<_ReplayDialog> {
  final _form = GlobalKey<FormState>();
  final _onset = TextEditingController(text: '20');
  final Set<String> _wards = {};

  @override
  void dispose() {
    _onset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Replay into demo ward'),
        content: SizedBox(
          width: 460,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(widget.message.headline ?? widget.message.event ?? widget.message.identifier),
              gap12,
              const InfoBanner('Creates a REPLAY drill that only alerts fictional demo residents. '
                  'The official text is shown verbatim; only the timing is shifted.', color: AppColors.drill),
              gap12,
              TextFormField(
                controller: _onset,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Onset in minutes (−60 to 1440)'),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter whole minutes';
                  if (n < -60 || n > 1440) return 'Must be between −60 and 1440';
                  return null;
                },
              ),
              if (widget.demoWards.length > 1) ...[
                gap12,
                const Text('Demo wards (none selected = default demo ward)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
                for (final w in widget.demoWards)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _wards.contains(w.id),
                    title: Text(w.name),
                    onChanged: (v) => setState(() => v == true ? _wards.add(w.id) : _wards.remove(w.id)),
                  ),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, _ReplayChoice(int.parse(_onset.text.trim()), _wards.isEmpty ? null : _wards.toList()));
              }
            },
            child: const Text('Replay as drill'),
          ),
        ],
      );
}
