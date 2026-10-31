import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../live_map/incident_map.dart';

/// Wards (access status, GeoJSON upload, map preview) and relief posts.
class WardsPage extends StatefulWidget {
  const WardsPage({super.key});

  @override
  State<WardsPage> createState() => _WardsPageState();
}

class _WardsPageState extends State<WardsPage> {
  List<WardOut>? _wards;
  List<ShelterOut>? _shelters;
  Object? _error;
  bool _started = false;
  bool _uploadDemo = false;
  bool _uploading = false;

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
      final r = await Future.wait([_api.wards(withGeometry: true), _api.shelters()]);
      if (mounted) {
        setState(() {
          _wards = r[0] as List<WardOut>;
          _shelters = r[1] as List<ShelterOut>;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _upload() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['geojson', 'json']);
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    setState(() => _uploading = true);
    try {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      final r = await runAction(context, () => _api.uploadWardsGeojson(bytes, f.name, isDemo: _uploadDemo));
      if (r != null && mounted) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('GeoJSON upload result'),
            content: SizedBox(
              width: 480,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('File: ${f.name}'),
                Text('Created: ${r.created} · Updated: ${r.updated} · Errors: ${r.errors.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (r.errors.isNotEmpty) ...[
                  gap8,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final e in r.errors) Text('• $e', style: const TextStyle(color: AppColors.help, fontSize: 12.5)),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
        _load();
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _setAccess(WardOut w) async {
    var status = w.accessStatus;
    final note = TextEditingController(text: w.accessNote ?? '');
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Access status · ${w.name}',
        builder: (context, setState) => [
          RadioGroup<String>(
            groupValue: status,
            onChanged: (v) => setState(() => status = v ?? status),
            child: const Column(children: [
              RadioListTile(value: 'open', title: Text('Open'), subtitle: Text('Normal automatic dispatch')),
              RadioListTile(
                  value: 'restricted',
                  title: Text('Restricted'),
                  subtitle: Text('Volunteer dispatch needs operator approval')),
              RadioListTile(
                  value: 'blocked', title: Text('Blocked'), subtitle: Text('No automatic dispatch (e.g. road washed away)')),
            ]),
          ),
          TextFormField(
            controller: note,
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Note (shown to operators, audited)'),
          ),
        ],
        onSubmit: () => _api.setWardAccess(w.id, status, note.text.trim().isEmpty ? null : note.text.trim()),
      ),
    );
    if (r is WardOut && mounted) {
      showSnack(context, '${r.name} is now ${r.accessStatus}');
      _load();
    }
  }

  Future<void> _createShelter() async {
    final wards = _wards ?? const <WardOut>[];
    final name = TextEditingController();
    final address = TextEditingController();
    final lat = TextEditingController();
    final lng = TextEditingController();
    final source = TextEditingController();
    String? wardId;
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Register relief post',
        builder: (context, setState) => [
          const InfoBanner('Only register posts officially designated by the district administration. '
              'Record the order or notification as the source.', icon: Icons.verified_outlined),
          gap12,
          DropdownButtonFormField<String>(
            initialValue: wardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ward'),
            items: [for (final w in wards) DropdownMenuItem(value: w.id, child: Text('${w.code} · ${w.name}'))],
            validator: (v) => v == null ? 'Select a ward' : null,
            onChanged: (v) => wardId = v,
          ),
          gap12,
          TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Name'), validator: (v) => requiredText(v, min: 3, field: 'Name')),
          gap12,
          TextFormField(controller: address, decoration: const InputDecoration(labelText: 'Address'), validator: (v) => requiredText(v, min: 3, field: 'Address')),
          gap12,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (v) => numberIn(v, min: -90, max: 90, field: 'Latitude'),
              ),
            ),
            gap12,
            Expanded(
              child: TextFormField(
                controller: lng,
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (v) => numberIn(v, min: -180, max: 180, field: 'Longitude'),
              ),
            ),
          ]),
          gap12,
          TextFormField(
            controller: source,
            decoration: const InputDecoration(labelText: 'Official source', hintText: 'e.g. DDMA order no. … dated …'),
            validator: (v) => requiredText(v, min: 3, field: 'Official source'),
          ),
        ],
        onSubmit: () => _api.createShelter(
          wardId: wardId!,
          name: name.text.trim(),
          address: address.text.trim(),
          lat: double.parse(lat.text.trim()),
          lng: double.parse(lng.text.trim()),
          source: source.text.trim(),
        ),
      ),
    );
    if (r is ShelterOut && mounted) {
      showSnack(context, 'Relief post registered');
      _load();
    }
  }

  Future<void> _deleteShelter(ShelterOut s) async {
    final ok = await confirmDialog(context,
        title: 'Remove relief post?', message: 'Remove "${s.name}"? Residents will no longer be directed to it.',
        confirmLabel: 'Remove', destructive: true);
    if (!ok || !mounted) return;
    var done = false;
    await runAction(context, () async {
      await _api.deleteShelter(s.id);
      done = true;
    }, success: 'Relief post removed');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.services.auth.isAdmin;
    final wards = _wards;
    final shelters = _shelters;
    final wardName = {for (final w in wards ?? const <WardOut>[]) w.id: w.name};
    return PageBody(children: [
      PageHeader(
        title: 'Wards & relief posts',
        subtitle: isAdmin
            ? 'Ward boundaries drive alert matching. Access status controls volunteer dispatch.'
            : 'Operators can change ward access status. Boundaries and relief posts are managed by admins.',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          if (isAdmin) ...[
            Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(value: _uploadDemo, onChanged: (v) => setState(() => _uploadDemo = v ?? false)),
              const Text('Upload as demo wards'),
            ]),
            FilledButton.icon(
              onPressed: _uploading ? null : _upload,
              icon: const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Uploading…' : 'Upload GeoJSON'),
            ),
          ],
        ],
      ),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (wards == null && _error == null) const LinearProgressIndicator(),
      if (wards != null) ...[
        SectionCard(
          title: 'Map preview',
          icon: Icons.map_outlined,
          child: WardMapPreview(wards: wards, shelters: shelters ?? const []),
        ),
        gap16,
        SectionCard(
          title: 'Wards (${wards.length})',
          icon: Icons.layers_outlined,
          child: wards.isEmpty
              ? const EmptyState('No wards yet. Upload a GeoJSON FeatureCollection with code and name properties.')
              : Column(children: [
                  for (final w in wards)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: _accessColor(w.accessStatus).withValues(alpha: 0.15),
                        child: Icon(Icons.location_city, color: _accessColor(w.accessStatus)),
                      ),
                      title: Text('${w.code} · ${w.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${w.district}, ${w.state}${w.lgdDistrictCode != null ? ' · LGD ${w.lgdDistrictCode}' : ''}'
                          '${w.accessNote != null ? '\nNote: ${w.accessNote}' : ''}'),
                      isThreeLine: w.accessNote != null,
                      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (w.isDemo) const Pill('DEMO', color: AppColors.drill, dense: true),
                        Pill(w.accessStatus.toUpperCase(), color: _accessColor(w.accessStatus), dense: true),
                        OutlinedButton(onPressed: () => _setAccess(w), child: const Text('Set access')),
                      ]),
                    ),
                ]),
        ),
        gap16,
        SectionCard(
          title: 'Relief posts (${shelters?.length ?? 0})',
          icon: Icons.house_outlined,
          trailing: isAdmin
              ? FilledButton.tonalIcon(onPressed: _createShelter, icon: const Icon(Icons.add), label: const Text('Add relief post'))
              : null,
          child: (shelters ?? const []).isEmpty
              ? const EmptyState('No relief posts registered.')
              : Column(children: [
                  for (final s in shelters!)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.house_rounded, color: AppColors.safe),
                      title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${wardName[s.wardId] ?? s.wardId} · ${s.address}\n'
                          '${s.lat.toStringAsFixed(5)}, ${s.lng.toStringAsFixed(5)} · Source: ${s.source}'),
                      isThreeLine: true,
                      trailing: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        if (s.isDemo) const Pill('DEMO', color: AppColors.drill, dense: true),
                        if (isAdmin)
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: () => _deleteShelter(s),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ]),
                    ),
                ]),
        ),
      ],
    ]);
  }

  static Color _accessColor(String s) => switch (s) {
        'blocked' => AppColors.help,
        'restricted' => AppColors.noReply,
        _ => AppColors.safe,
      };
}
