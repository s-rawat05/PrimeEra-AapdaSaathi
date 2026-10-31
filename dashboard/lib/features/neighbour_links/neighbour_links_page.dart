import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

/// Neighbour links: which neighbour is asked to check on which resident, in priority order.
class NeighbourLinksPage extends StatefulWidget {
  const NeighbourLinksPage({super.key});

  @override
  State<NeighbourLinksPage> createState() => _NeighbourLinksPageState();
}

class _NeighbourLinksPageState extends State<NeighbourLinksPage> {
  List<NeighbourLinkOut>? _links;
  Object? _error;
  bool _started = false;

  AapdaApi get _api => context.api;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final l = await _api.neighbourLinks();
      if (mounted) {
        setState(() {
          _links = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    final data = await runAction(context, () async {
      final r = await _api.residents(limit: 500);
      final n = await _api.users(role: 'neighbour', limit: 500);
      return (r.items, n.items);
    });
    if (data == null || !mounted) return;
    final (residents, neighbours) = data;
    String? residentId;
    String? neighbourId;
    final prio = TextEditingController(text: '1');
    final dist = TextEditingController();
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Link a neighbour',
        builder: (context, setState) => [
          DropdownButtonFormField<String>(
            initialValue: residentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Resident'),
            items: [for (final x in residents) DropdownMenuItem(value: x.id, child: Text('${x.fullName} · ${x.wardName}${x.isDemo ? ' (demo)' : ''}'))],
            validator: (v) => v == null ? 'Select a resident' : null,
            onChanged: (v) => residentId = v,
          ),
          gap12,
          DropdownButtonFormField<String>(
            initialValue: neighbourId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Neighbour (user with neighbour role)'),
            items: [
              for (final u in neighbours)
                DropdownMenuItem(value: u.user.id, child: Text('${u.user.fullName} · ${u.user.phoneMasked}${u.user.isDemo ? ' (demo)' : ''}')),
            ],
            validator: (v) => v == null ? 'Select a neighbour' : null,
            onChanged: (v) => neighbourId = v,
          ),
          if (neighbours.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('No neighbour accounts yet — create one under Users & roles.', style: TextStyle(color: AppColors.help)),
            ),
          gap12,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: prio,
                decoration: const InputDecoration(labelText: 'Priority (1 = asked first)'),
                validator: (v) => numberIn(v, min: 1, max: 10, field: 'Priority'),
              ),
            ),
            gap12,
            Expanded(
              child: TextFormField(
                controller: dist,
                decoration: const InputDecoration(labelText: 'Distance (m, optional)'),
                validator: (v) => numberIn(v, min: 0, max: 100000, required: false, field: 'Distance'),
              ),
            ),
          ]),
        ],
        onSubmit: () => _api.createNeighbourLink(
          residentId: residentId!,
          neighbourUserId: neighbourId!,
          priority: double.parse(prio.text.trim()).round(),
          distanceM: dist.text.trim().isEmpty ? null : double.parse(dist.text.trim()),
        ),
      ),
    );
    if (r is NeighbourLinkOut && mounted) {
      showSnack(context, 'Linked ${r.neighbourName} → ${r.residentName}');
      _load();
    }
  }

  Future<void> _priority(NeighbourLinkOut l) async {
    final ctrl = TextEditingController(text: '${l.priority}');
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Change priority',
        builder: (context, setState) => [
          Text('${l.neighbourName} → ${l.residentName}'),
          gap12,
          TextFormField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Priority (1–10, 1 = asked first)'),
            validator: (v) => numberIn(v, min: 1, max: 10, field: 'Priority'),
          ),
        ],
        onSubmit: () => _api.setNeighbourLinkPriority(l.id, double.parse(ctrl.text.trim()).round()),
      ),
    );
    if (r is NeighbourLinkOut && mounted) {
      showSnack(context, 'Priority updated');
      _load();
    }
  }

  Future<void> _delete(NeighbourLinkOut l) async {
    final ok = await confirmDialog(context,
        title: 'Remove link?', message: '${l.neighbourName} will no longer be asked to check on ${l.residentName}.',
        confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    var done = false;
    await runAction(context, () async {
      await _api.deleteNeighbourLink(l.id);
      done = true;
    }, success: 'Link removed');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final links = _links;
    final byResident = <String, List<NeighbourLinkOut>>{};
    for (final l in links ?? const <NeighbourLinkOut>[]) {
      byResident.putIfAbsent(l.residentName, () => []).add(l);
    }
    return PageBody(children: [
      PageHeader(
        title: 'Neighbour links',
        subtitle: 'Neighbours are asked (in priority order) to check on residents who do not reply.',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_link), label: const Text('Link neighbour')),
        ],
      ),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (links == null && _error == null) const LinearProgressIndicator(),
      if (links != null && links.isEmpty) const EmptyState('No neighbour links yet.'),
      for (final e in byResident.entries) ...[
        SectionCard(
          title: e.key,
          icon: Icons.person_outline,
          child: Column(children: [
            for (final l in (e.value..sort((a, b) => a.priority.compareTo(b.priority))))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(child: Text('${l.priority}')),
                title: Text(l.neighbourName),
                subtitle: Text('Priority ${l.priority}${l.distanceM != null ? ' · ${fmtMeters(l.distanceM)} away' : ''}'),
                trailing: Wrap(children: [
                  IconButton(tooltip: 'Change priority', onPressed: () => _priority(l), icon: const Icon(Icons.low_priority)),
                  IconButton(tooltip: 'Remove', onPressed: () => _delete(l), icon: const Icon(Icons.delete_outline)),
                ]),
              ),
          ]),
        ),
        gap12,
      ],
    ]);
  }
}
