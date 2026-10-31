import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

const _entityTypes = [
  'incident',
  'delivery',
  'task',
  'resident',
  'ward',
  'shelter',
  'volunteer',
  'neighbour_link',
  'pre_assigned_helper',
  'alert_template',
  'user',
  'feed',
  'demo',
];

/// Audit history (`GET /audit`), paginated with filters.
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _action = TextEditingController();
  final _entityId = TextEditingController();
  String? _entityType;
  int _offset = 0;
  static const _limit = 50;
  PageOf<AuditOut>? _page;
  Object? _error;
  bool _loading = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _action.dispose();
    _entityId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await context.api.audit(
        entityType: _entityType,
        action: _action.text.trim().isEmpty ? null : _action.text.trim(),
        entityId: _entityId.text.trim().isEmpty ? null : _entityId.text.trim(),
        limit: _limit,
        offset: _offset,
      );
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

  void _apply() {
    _offset = 0;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PageBody(children: [
      PageHeader(
        title: 'Audit history',
        subtitle: 'Every state change, override, location view and login — who, when, why.',
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh))],
      ),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            initialValue: _entityType,
            decoration: const InputDecoration(labelText: 'Entity type'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All')),
              for (final t in _entityTypes) DropdownMenuItem<String?>(value: t, child: Text(t)),
            ],
            onChanged: (v) {
              _entityType = v;
              _apply();
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: TextField(
            controller: _action,
            decoration: const InputDecoration(labelText: 'Action starts with', hintText: 'e.g. delivery.override'),
            onSubmitted: (_) => _apply(),
          ),
        ),
        SizedBox(
          width: 300,
          child: TextField(
            controller: _entityId,
            decoration: const InputDecoration(labelText: 'Entity id (exact)'),
            onSubmitted: (_) => _apply(),
          ),
        ),
        FilledButton.tonal(onPressed: _apply, child: const Text('Apply')),
      ]),
      gap16,
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (page != null && page.items.isEmpty) const EmptyState('No audit entries match.'),
      if (page != null)
        Card(
          child: Column(children: [
            for (final a in page.items) _AuditRow(a),
          ]),
        ),
      if (page != null && page.total > 0)
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('${page.offset + 1}–${page.offset + page.items.length} of ${page.total}'),
          IconButton(
            onPressed: page.hasPrevious
                ? () {
                    _offset = (_offset - _limit).clamp(0, 1 << 30);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            onPressed: page.hasNext
                ? () {
                    _offset += _limit;
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
    ]);
  }
}

class _AuditRow extends StatelessWidget {
  const _AuditRow(this.a);

  final AuditOut a;

  @override
  Widget build(BuildContext context) {
    const enc = JsonEncoder.withIndent('  ');
    final hasDiff = a.before != null || a.after != null;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 14),
      leading: const Icon(Icons.policy_outlined, color: AppColors.info),
      title: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(a.action, style: const TextStyle(fontWeight: FontWeight.w800, fontFamily: 'monospace', fontSize: 13)),
        Pill(a.entityType, color: AppColors.info, dense: true),
      ]),
      subtitle: Text(
        '${fmtDateTime(a.createdAt)} · ${a.actorName ?? a.actorUserId ?? 'system'}'
        '${a.actorRole != null ? ' (${a.actorRole})' : ''}'
        '${a.reason != null ? ' · reason: ${a.reason}' : ''}',
        style: const TextStyle(fontSize: 12.5),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        KeyValue('Entity id', a.entityId),
        KeyValue('Actor id', a.actorUserId),
        if (!hasDiff) const Text('No before/after snapshot.', style: TextStyle(color: AppColors.muted)),
        if (hasDiff)
          Wrap(spacing: 12, runSpacing: 12, children: [
            if (a.before != null) _json('Before', enc.convert(a.before)),
            if (a.after != null) _json('After', enc.convert(a.after)),
          ]),
      ],
    );
  }

  Widget _json(String label, String text) => Container(
        constraints: const BoxConstraints(maxWidth: 460),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
        ]),
      );
}
