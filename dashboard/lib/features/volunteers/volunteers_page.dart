import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

/// Volunteers (list, create, availability, verify) and pre-assigned helpers.
class VolunteersPage extends StatefulWidget {
  const VolunteersPage({super.key});

  @override
  State<VolunteersPage> createState() => _VolunteersPageState();
}

class _VolunteersPageState extends State<VolunteersPage> {
  List<VolunteerOut>? _vols;
  List<PreAssignedOut>? _pre;
  List<WardOut> _wards = const [];
  Object? _error;
  Object? _preError;
  bool _started = false;
  final Set<String> _busy = {};

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
    final isAdmin = context.services.auth.isAdmin;
    try {
      final v = await _api.volunteers();
      if (mounted) {
        setState(() {
          _vols = v;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
    try {
      final w = await _api.wards();
      if (mounted) setState(() => _wards = w);
    } catch (_) {}
    if (isAdmin) {
      try {
        final p = await _api.preAssigned();
        if (mounted) {
          setState(() {
            _pre = p;
            _preError = null;
          });
        }
      } catch (e) {
        if (mounted) setState(() => _preError = e);
      }
    }
  }

  Future<void> _toggle(String id, Future<VolunteerOut> Function() f, String msg) async {
    setState(() => _busy.add(id));
    final r = await runAction(context, f, success: msg);
    if (mounted) setState(() => _busy.remove(id));
    if (r != null) _load();
  }

  Future<void> _create() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final radius = TextEditingController(text: '3000');
    final skills = TextEditingController(text: 'first_aid, evacuation_support');
    String? wardId;
    var isDemo = false;
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Register volunteer',
        builder: (context, setState) => [
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => requiredText(v, min: 2, field: 'Name')),
          gap12,
          TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+91…'), validator: (v) => requiredText(v, min: 8, field: 'Phone')),
          gap12,
          DropdownButtonFormField<String?>(
            initialValue: wardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Home ward (optional)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('None')),
              for (final w in _wards) DropdownMenuItem<String?>(value: w.id, child: Text('${w.code} · ${w.name}')),
            ],
            onChanged: (v) => wardId = v,
          ),
          gap12,
          Row(children: [
            Expanded(child: TextFormField(controller: lat, decoration: const InputDecoration(labelText: 'Base latitude'), validator: (v) => numberIn(v, min: -90, max: 90, field: 'Latitude'))),
            gap12,
            Expanded(child: TextFormField(controller: lng, decoration: const InputDecoration(labelText: 'Base longitude'), validator: (v) => numberIn(v, min: -180, max: 180, field: 'Longitude'))),
          ]),
          gap12,
          TextFormField(
            controller: radius,
            decoration: const InputDecoration(labelText: 'Max service radius (m)'),
            validator: (v) => numberIn(v, min: 1, max: 50000, field: 'Radius'),
          ),
          gap12,
          TextFormField(controller: skills, decoration: const InputDecoration(labelText: 'Skills (comma separated)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: isDemo,
            onChanged: (v) => setState(() => isDemo = v),
            title: const Text('Fictional demo volunteer'),
          ),
        ],
        onSubmit: () => _api.createVolunteer({
          'full_name': name.text.trim(),
          'phone': phone.text.trim(),
          'ward_id': wardId,
          'base_lat': double.parse(lat.text.trim()),
          'base_lng': double.parse(lng.text.trim()),
          'max_radius_m': double.parse(radius.text.trim()),
          'skills': skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
          'is_demo': isDemo,
        }),
      ),
    );
    if (r is VolunteerOut && mounted) {
      showSnack(context, '${r.fullName} registered as volunteer');
      _load();
    }
  }

  Future<void> _createPreAssigned() async {
    final residents = await runAction(context, () => _api.residents(limit: 500));
    if (residents == null || !mounted) return;
    final vols = _vols ?? const <VolunteerOut>[];
    String? residentId;
    String? volunteerId;
    final prio = TextEditingController(text: '1');
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Pre-assign a helper',
        builder: (context, setState) => [
          const Text('A pre-assigned volunteer is tried first for this resident.', style: TextStyle(color: AppColors.muted)),
          gap12,
          DropdownButtonFormField<String>(
            initialValue: residentId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Resident'),
            items: [for (final x in residents.items) DropdownMenuItem(value: x.id, child: Text('${x.fullName} · ${x.wardName}'))],
            validator: (v) => v == null ? 'Select a resident' : null,
            onChanged: (v) => residentId = v,
          ),
          gap12,
          DropdownButtonFormField<String>(
            initialValue: volunteerId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Volunteer'),
            items: [for (final v in vols) DropdownMenuItem(value: v.id, child: Text(v.fullName))],
            validator: (v) => v == null ? 'Select a volunteer' : null,
            onChanged: (v) => volunteerId = v,
          ),
          gap12,
          TextFormField(controller: prio, decoration: const InputDecoration(labelText: 'Priority (1 = first)'), validator: (v) => numberIn(v, min: 1, max: 10, field: 'Priority')),
        ],
        onSubmit: () => _api.createPreAssigned(
            residentId: residentId!, volunteerId: volunteerId!, priority: double.parse(prio.text.trim()).round()),
      ),
    );
    if (r is PreAssignedOut && mounted) {
      showSnack(context, 'Pre-assigned ${r.volunteerName} to ${r.residentName}');
      _load();
    }
  }

  Future<void> _deletePre(PreAssignedOut p) async {
    final ok = await confirmDialog(context,
        title: 'Remove pre-assignment?', message: 'Stop pre-assigning ${p.volunteerName} to ${p.residentName}?',
        confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    var done = false;
    await runAction(context, () async {
      await _api.deletePreAssigned(p.id);
      done = true;
    }, success: 'Pre-assignment removed');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.services.auth.isAdmin;
    final vols = _vols;
    return PageBody(children: [
      PageHeader(
        title: 'Volunteers',
        subtitle: 'Verified NSS / NCC / Civil Defence volunteers. Dispatch only uses verified, available volunteers within radius.',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          if (isAdmin)
            FilledButton.icon(onPressed: _create, icon: const Icon(Icons.person_add_alt), label: const Text('Register volunteer')),
        ],
      ),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (vols == null && _error == null) const LinearProgressIndicator(),
      if (vols != null && vols.isEmpty) const EmptyState('No volunteers registered.'),
      if (vols != null)
        for (final v in vols) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                CircleAvatar(
                  backgroundColor: (v.isAvailable ? AppColors.safe : AppColors.unreachable).withValues(alpha: 0.15),
                  child: Icon(Icons.directions_walk, color: v.isAvailable ? AppColors.safe : AppColors.unreachable),
                ),
                gap12,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text(v.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Pill(v.verified ? 'VERIFIED' : 'UNVERIFIED', color: v.verified ? AppColors.safe : AppColors.noReply, dense: true),
                      if (v.activeTaskId != null) const Pill('ON A TASK', color: AppColors.info, dense: true),
                      if (v.isDemo) const Pill('DEMO', color: AppColors.drill, dense: true),
                    ]),
                    Text(
                      '${v.phoneMasked} · ${v.wardName ?? 'No home ward'} · radius ${fmtMeters(v.maxRadiusM)} · '
                      'base ${v.baseLat.toStringAsFixed(4)}, ${v.baseLng.toStringAsFixed(4)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                    if (v.skills.isNotEmpty)
                      Text('Skills: ${v.skills.map(humanize).join(', ')}', style: const TextStyle(fontSize: 12.5)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Available', style: TextStyle(fontSize: 12)),
                    Switch(
                      key: Key('avail-${v.id}'),
                      value: v.isAvailable,
                      onChanged: _busy.contains(v.id)
                          ? null
                          : (x) => _toggle(v.id, () => _api.setVolunteerAvailability(v.id, x),
                              '${v.fullName} marked ${x ? 'available' : 'unavailable'}'),
                    ),
                  ]),
                  if (isAdmin)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Verified', style: TextStyle(fontSize: 12)),
                      Switch(
                        value: v.verified,
                        onChanged: _busy.contains(v.id)
                            ? null
                            : (x) => _toggle(v.id, () => _api.setVolunteerVerified(v.id, x),
                                '${v.fullName} ${x ? 'verified' : 'unverified'}'),
                      ),
                    ]),
                ]),
              ]),
            ),
          ),
          gap8,
        ],
      if (isAdmin) ...[
        gap16,
        SectionCard(
          title: 'Pre-assigned helpers',
          icon: Icons.handshake_outlined,
          subtitle: 'Volunteers tried first for specific high-need residents',
          trailing: FilledButton.tonalIcon(onPressed: _createPreAssigned, icon: const Icon(Icons.add), label: const Text('Pre-assign')),
          child: _preError != null
              ? ErrorPanel(error: _preError!, onRetry: _load)
              : _pre == null
                  ? const LinearProgressIndicator()
                  : _pre!.isEmpty
                      ? const EmptyState('No pre-assigned helpers.')
                      : Column(children: [
                          for (final p in _pre!)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(child: Text('${p.priority}')),
                              title: Text('${p.residentName} ← ${p.volunteerName}'),
                              subtitle: Text('Priority ${p.priority}'),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _deletePre(p),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ),
                        ]),
        ),
      ],
    ]);
  }
}
