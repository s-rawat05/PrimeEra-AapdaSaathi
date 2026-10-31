import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/api_error.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

/// Resident registry (admin): search/filter, consent records, assisted registration, reverify, withdraw, erase.
class ResidentsPage extends StatefulWidget {
  const ResidentsPage({super.key});

  @override
  State<ResidentsPage> createState() => _ResidentsPageState();
}

class _ResidentsPageState extends State<ResidentsPage> {
  final _q = TextEditingController();
  String? _wardId;
  String? _status;
  String? _need;
  int _offset = 0;
  static const _limit = 25;
  PageOf<ResidentOut>? _page;
  List<WardOut> _wards = const [];
  Object? _error;
  bool _loading = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadWards();
      _load();
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _loadWards() async {
    try {
      final w = await context.api.wards();
      if (mounted) setState(() => _wards = w);
    } catch (_) {
      // Ward filter is optional; the list still works.
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final p = await context.api.residents(
        q: _q.text.trim().isEmpty ? null : _q.text.trim(),
        wardId: _wardId,
        status: _status,
        need: _need,
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

  void _search() {
    _offset = 0;
    _load();
  }

  Future<void> _register() async {
    final r = await showDialog<Object?>(context: context, builder: (_) => RegistrationDialog(api: context.api, wards: _wards));
    if (r is ResidentOut && mounted) {
      showSnack(context, '${r.fullName} registered (consent recorded, audited)');
      _load();
    }
  }

  Future<void> _reverify(ResidentOut r) async {
    final ok = await confirmDialog(context,
        title: 'Re-verify ${r.fullName}?',
        message: 'Confirms the resident (or their guardian) re-consented today, renewing consent for 90 days. '
            'Recorded as assisted re-verification.',
        confirmLabel: 'Re-verify');
    if (!ok || !mounted) return;
    final res = await runAction(context, () => context.api.reverifyResident(r.id), success: 'Consent renewed');
    if (res != null) _load();
  }

  Future<void> _withdraw(ResidentOut r) async {
    final reason = await reasonDialog(context,
        title: 'Withdraw consent for ${r.fullName}?',
        message: 'The resident stops receiving alerts and their exact location is deleted.',
        confirmLabel: 'Withdraw',
        destructive: true);
    if (reason == null || !mounted) return;
    final res = await runAction(context, () => context.api.withdrawResident(r.id, reason), success: 'Consent withdrawn');
    if (res != null) _load();
  }

  Future<void> _erase(ResidentOut r) async {
    final reason = await reasonDialog(context,
        title: 'Erase ${r.fullName}?',
        message: 'Permanently erases this registry record (deletion request). This cannot be undone. '
            'The reason is written to the audit log.',
        confirmLabel: 'Continue',
        destructive: true,
        maxLength: 300);
    if (reason == null || !mounted) return;
    final ok = await confirmDialog(context,
        title: 'Permanently erase?',
        message: 'Erase ${r.fullName} from the registry now?',
        confirmLabel: 'Erase permanently',
        destructive: true);
    if (!ok || !mounted) return;
    var done = false;
    await runAction(context, () async {
      await context.api.eraseResident(r.id, reason);
      done = true;
    }, success: 'Record erased');
    if (done) _load();
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return PageBody(children: [
      PageHeader(
        title: 'Resident registry',
        subtitle: 'Consent-based registry of residents who need assistance. Every view is audited.',
        actions: [
          FilledButton.icon(
            key: const Key('register-resident'),
            onPressed: _register,
            icon: const Icon(Icons.person_add_alt_1),
            label: const Text('Assisted registration'),
          ),
        ],
      ),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _q,
            decoration: InputDecoration(
              labelText: 'Search by name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(onPressed: _search, icon: const Icon(Icons.arrow_forward)),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        SizedBox(
          width: 240,
          child: DropdownButtonFormField<String?>(
            initialValue: _wardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ward'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All wards')),
              for (final w in _wards) DropdownMenuItem<String?>(value: w.id, child: Text('${w.code} · ${w.name}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              _wardId = v;
              _search();
            },
          ),
        ),
        SizedBox(
          width: 170,
          child: DropdownButtonFormField<String?>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: const [
              DropdownMenuItem<String?>(value: null, child: Text('Any status')),
              DropdownMenuItem<String?>(value: 'active', child: Text('Active')),
              DropdownMenuItem<String?>(value: 'expired', child: Text('Consent expired')),
              DropdownMenuItem<String?>(value: 'withdrawn', child: Text('Withdrawn')),
            ],
            onChanged: (v) {
              _status = v;
              _search();
            },
          ),
        ),
        SizedBox(
          width: 190,
          child: DropdownButtonFormField<String?>(
            initialValue: _need,
            decoration: const InputDecoration(labelText: 'Need'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Any need')),
              for (final n in allNeeds) DropdownMenuItem<String?>(value: n, child: Text(needLabel(n))),
            ],
            onChanged: (v) {
              _need = v;
              _search();
            },
          ),
        ),
      ]),
      if (_need != null)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Note: the need filter is applied by the server within each page.',
              style: TextStyle(fontSize: 12, color: AppColors.muted)),
        ),
      gap16,
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (page != null && page.items.isEmpty) const EmptyState('No residents found.'),
      if (page != null)
        for (final r in page.items) ...[
          _ResidentCard(
            resident: r,
            onReverify: () => _reverify(r),
            onWithdraw: r.registrationStatus == 'withdrawn' ? null : () => _withdraw(r),
            onErase: () => _erase(r),
          ),
          gap8,
        ],
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

class _ResidentCard extends StatelessWidget {
  const _ResidentCard({required this.resident, required this.onReverify, required this.onWithdraw, required this.onErase});

  final ResidentOut resident;
  final VoidCallback onReverify;
  final VoidCallback? onWithdraw;
  final VoidCallback onErase;

  @override
  Widget build(BuildContext context) {
    final r = resident;
    final now = DateTime.now();
    final due = r.reverifyDueAt;
    final overdue = due != null && due.isBefore(now);
    final statusColor = switch (r.registrationStatus) {
      'active' => AppColors.safe,
      'expired' => AppColors.noReply,
      'withdrawn' => AppColors.unreachable,
      _ => AppColors.info,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(r.fullName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Pill(r.registrationStatus.toUpperCase(), color: statusColor, dense: true),
                if (r.isDemo) const Pill('DEMO', color: AppColors.drill, dense: true),
                if (r.hasExactLocation) const Pill('Exact location on file', color: AppColors.info, icon: Icons.location_on, dense: true),
              ]),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => switch (v) {
                'reverify' => onReverify(),
                'withdraw' => onWithdraw?.call(),
                'erase' => onErase(),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'reverify', child: Text('Re-verify consent')),
                if (onWithdraw != null) const PopupMenuItem(value: 'withdraw', child: Text('Withdraw consent…')),
                const PopupMenuItem(value: 'erase', child: Text('Erase record…', style: TextStyle(color: AppColors.primaryDark))),
              ],
            ),
          ]),
          Text(
            '${r.wardName} · ${r.phoneMasked} · language ${r.language} · registered via ${r.registeredVia}'
            ' · ${r.hasSmartphone ? 'smartphone' : 'feature phone'}${r.livesAlone ? ' · lives alone' : ''}',
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            if (r.needs.isEmpty) const Text('No declared needs', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            for (final n in r.needs) Pill(needLabel(n), color: AppColors.info, icon: needIcon(n), dense: true),
          ]),
          const SizedBox(height: 6),
          Text(
            'Re-verify due: ${fmtShort(due)}${overdue ? ' — OVERDUE' : ''}',
            style: TextStyle(fontSize: 12.5, color: overdue ? AppColors.help : AppColors.text, fontWeight: overdue ? FontWeight.w800 : null),
          ),
          if (r.consents.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final c in r.consents)
                Pill(
                  '${humanize(c.consentType)}: '
                  '${c.isWithdrawn ? 'withdrawn ${fmtShort(c.withdrawnAt)}' : c.isExpired(now) ? 'expired ${fmtShort(c.expiresAt)}' : (c.granted ? 'until ${fmtShort(c.expiresAt)}' : 'refused')}'
                  ' · by ${c.grantedBy}${c.guardianName != null ? ' (${c.guardianName})' : ''}',
                  color: c.isWithdrawn || c.isExpired(now) || !c.granted ? AppColors.unreachable : AppColors.safe,
                  dense: true,
                ),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Assisted registration form (`POST /admin/residents`).
class RegistrationDialog extends StatefulWidget {
  const RegistrationDialog({super.key, required this.api, required this.wards});

  final AapdaApi api;
  final List<WardOut> wards;

  @override
  State<RegistrationDialog> createState() => _RegistrationDialogState();
}

class _ContactRow {
  final name = TextEditingController();
  final phone = TextEditingController();
  final relationship = TextEditingController(text: 'family');
  bool canViewLocation = false;

  void dispose() {
    name.dispose();
    phone.dispose();
    relationship.dispose();
  }
}

class _RegistrationDialogState extends State<RegistrationDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _guardian = TextEditingController();
  String? _wardId;
  String _language = 'hi';
  final Set<String> _needs = {};
  bool _livesAlone = false;
  bool _smartphone = true;
  bool _consentRegistry = false;
  bool _consentLocation = false;
  bool _consentCaregiver = false;
  String _grantedBy = 'assisted';
  bool _isDemo = false;
  final List<_ContactRow> _contacts = [];

  @override
  void dispose() {
    for (final c in [_name, _phone, _lat, _lng, _address, _landmark, _guardian]) {
      c.dispose();
    }
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<Object?> _submit() async {
    if (_wardId == null) throw const InputError('Select a ward');
    if (!_consentRegistry) throw const InputError('Registry consent is required to register');
    final hasLat = _lat.text.trim().isNotEmpty;
    final hasLng = _lng.text.trim().isNotEmpty;
    if (hasLat != hasLng) throw const InputError('Enter both latitude and longitude, or neither');
    if (hasLat && !_consentLocation) throw const InputError('Location consent is required to store an exact location');
    return widget.api.registerResident({
      'full_name': _name.text.trim(),
      'ward_id': _wardId,
      'language': _language,
      'needs': _needs.toList(),
      'lives_alone': _livesAlone,
      'has_smartphone': _smartphone,
      if (hasLat) 'lat': double.parse(_lat.text.trim()),
      if (hasLng) 'lng': double.parse(_lng.text.trim()),
      if (_address.text.trim().isNotEmpty) 'address_text': _address.text.trim(),
      if (_landmark.text.trim().isNotEmpty) 'landmark': _landmark.text.trim(),
      'consent_registry': _consentRegistry,
      'consent_location': _consentLocation,
      'consent_caregiver_share': _consentCaregiver,
      'granted_by': _grantedBy,
      if (_grantedBy == 'guardian') 'guardian_name': _guardian.text.trim(),
      if (_phone.text.trim().isNotEmpty) 'phone': _phone.text.trim(),
      'is_demo': _isDemo,
      'trusted_contacts': [
        for (final c in _contacts)
          {
            'full_name': c.name.text.trim(),
            'phone': c.phone.text.trim(),
            'relationship': c.relationship.text.trim().isEmpty ? 'family' : c.relationship.text.trim(),
            'can_view_location': c.canViewLocation,
          },
      ],
    });
  }

  @override
  Widget build(BuildContext context) => FormDialog(
        title: 'Assisted registration',
        submitLabel: 'Register',
        width: 640,
        onSubmit: _submit,
        builder: (context, _) => [
          const InfoBanner('Use when an ASHA worker, ward officer or volunteer registers someone in person. '
              'Explain what is stored and record consent truthfully.', icon: Icons.volunteer_activism),
          gap12,
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Full name'),
            validator: (v) => requiredText(v, min: 2, field: 'Name'),
          ),
          gap12,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Mobile number (optional)', hintText: '+91…'),
              ),
            ),
            gap12,
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (v) => setState(() => _language = v ?? _language),
              ),
            ),
          ]),
          gap12,
          DropdownButtonFormField<String>(
            initialValue: _wardId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Ward'),
            items: [
              for (final w in widget.wards)
                DropdownMenuItem(value: w.id, child: Text('${w.code} · ${w.name}${w.isDemo ? ' (demo)' : ''}')),
            ],
            validator: (v) => v == null ? 'Select a ward' : null,
            onChanged: (v) => setState(() => _wardId = v),
          ),
          gap12,
          const Text('Needs', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in allNeeds)
              FilterChip(
                avatar: Icon(needIcon(n), size: 16),
                label: Text(needLabel(n)),
                selected: _needs.contains(n),
                onSelected: (v) => setState(() => v ? _needs.add(n) : _needs.remove(n)),
              ),
          ]),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _livesAlone,
            onChanged: (v) => setState(() => _livesAlone = v ?? false),
            title: const Text('Lives alone'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _smartphone,
            onChanged: (v) => setState(() => _smartphone = v ?? true),
            title: const Text('Has a smartphone (otherwise SMS only)'),
          ),
          const Divider(),
          const Text('Location (optional, needs location consent)', style: TextStyle(fontWeight: FontWeight.w700)),
          gap8,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _lat,
                decoration: const InputDecoration(labelText: 'Latitude'),
                validator: (v) => numberIn(v, min: -90, max: 90, required: false, field: 'Latitude'),
              ),
            ),
            gap12,
            Expanded(
              child: TextFormField(
                controller: _lng,
                decoration: const InputDecoration(labelText: 'Longitude'),
                validator: (v) => numberIn(v, min: -180, max: 180, required: false, field: 'Longitude'),
              ),
            ),
          ]),
          gap12,
          TextFormField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          gap12,
          TextFormField(controller: _landmark, decoration: const InputDecoration(labelText: 'Landmark')),
          const Divider(height: 28),
          const Text('Consent', style: TextStyle(fontWeight: FontWeight.w700)),
          DropdownButtonFormField<String>(
            initialValue: _grantedBy,
            decoration: const InputDecoration(labelText: 'Consent given by'),
            items: const [
              DropdownMenuItem(value: 'assisted', child: Text('Resident, assisted by registrar')),
              DropdownMenuItem(value: 'self', child: Text('Resident (self)')),
              DropdownMenuItem(value: 'guardian', child: Text('Guardian on behalf of resident')),
            ],
            onChanged: (v) => setState(() => _grantedBy = v ?? _grantedBy),
          ),
          if (_grantedBy == 'guardian') ...[
            gap12,
            TextFormField(
              controller: _guardian,
              decoration: const InputDecoration(labelText: 'Guardian name'),
              validator: (v) => requiredText(v, min: 2, field: 'Guardian name'),
            ),
          ],
          CheckboxListTile(
            key: const Key('consent-registry'),
            contentPadding: EdgeInsets.zero,
            value: _consentRegistry,
            onChanged: (v) => setState(() => _consentRegistry = v ?? false),
            title: const Text('Registry consent (required)'),
            subtitle: const Text('Stored to send disaster alerts and organise help. Valid 90 days.'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consentLocation,
            onChanged: (v) => setState(() => _consentLocation = v ?? false),
            title: const Text('Exact location consent'),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _consentCaregiver,
            onChanged: (v) => setState(() => _consentCaregiver = v ?? false),
            title: const Text('Share status with caregiver / trusted contacts'),
          ),
          const Divider(height: 28),
          Row(children: [
            const Expanded(child: Text('Trusted contacts', style: TextStyle(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: () => setState(() => _contacts.add(_ContactRow())),
              icon: const Icon(Icons.add),
              label: const Text('Add contact'),
            ),
          ]),
          for (final c in _contacts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: c.name,
                    decoration: const InputDecoration(labelText: 'Name'),
                    validator: (v) => requiredText(v, min: 2, field: 'Name'),
                  ),
                ),
                gap8,
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: c.phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                    validator: (v) => requiredText(v, min: 8, field: 'Phone'),
                  ),
                ),
                gap8,
                Expanded(flex: 2, child: TextFormField(controller: c.relationship, decoration: const InputDecoration(labelText: 'Relation'))),
                Tooltip(
                  message: 'Can view location',
                  child: Checkbox(value: c.canViewLocation, onChanged: (v) => setState(() => c.canViewLocation = v ?? false)),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _contacts.remove(c);
                    c.dispose();
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _isDemo,
            onChanged: (v) => setState(() => _isDemo = v),
            title: const Text('Fictional demo resident'),
          ),
        ],
      );
}
