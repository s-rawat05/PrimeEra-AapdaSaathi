import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../profile/profile_screen.dart';

/// New resident: (1) accessibility needs, (2) ward, consent, location and trusted contacts →
/// `POST /residents/me/registration`.
class ResidentOnboardingScreen extends StatefulWidget {
  const ResidentOnboardingScreen({super.key});

  @override
  State<ResidentOnboardingScreen> createState() => _ResidentOnboardingScreenState();
}

class _ContactDraft {
  final name = TextEditingController();
  final phone = TextEditingController();
  bool canViewLocation = false;

  void dispose() {
    name.dispose();
    phone.dispose();
  }
}

class _ResidentOnboardingScreenState extends State<ResidentOnboardingScreen> {
  int _step = 0;

  // step 1
  Set<String> _needs = {};
  bool _alone = false;
  bool _smart = true;

  // step 2
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _landmark = TextEditingController();
  final _guardian = TextEditingController();
  List<WardOut>? _wards;
  String? _wardId;
  Object? _wardsError;
  bool _consentRegistry = false;
  bool _consentLocation = false;
  bool _consentCaregiver = false;
  bool _byGuardian = false;
  double? _lat;
  double? _lng;
  bool _locating = false;
  bool _locationFailed = false;
  final List<_ContactDraft> _contacts = [];
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _name.text = context.appRead.me?.user.fullName ?? '';
      _loadWards();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _landmark.dispose();
    _guardian.dispose();
    for (final c in _contacts) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadWards() async {
    setState(() => _wardsError = null);
    try {
      final w = await context.appRead.call((api) => api.publicWards());
      if (mounted) {
        setState(() {
          _wards = w;
          if (w.length == 1) _wardId = w.first.id;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _wardsError = e);
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationFailed = false;
    });
    final p = await context.appRead.location.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (p == null) {
        _locationFailed = true;
      } else {
        _lat = p.lat;
        _lng = p.lng;
      }
    });
  }

  Future<void> _submit() async {
    final app = context.appRead;
    final s = app.s;
    if (!_consentRegistry) {
      setState(() => _error = s.registryRequired);
      return;
    }
    if (_wardId == null) {
      setState(() => _error = s.chooseWard);
      return;
    }
    if (_name.text.trim().length < 2) {
      setState(() => _error = s.fullName);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = RegistrationIn(
      fullName: _name.text.trim(),
      wardId: _wardId!,
      language: app.lang,
      needs: _needs.toList(),
      livesAlone: _alone,
      hasSmartphone: _smart,
      consentRegistry: true,
      consentLocation: _consentLocation,
      consentCaregiverShare: _consentCaregiver,
      grantedBy: _byGuardian ? 'guardian' : 'self',
      guardianName: _byGuardian ? _guardian.text.trim() : null,
      // Exact location is only sent with location consent.
      lat: _consentLocation ? _lat : null,
      lng: _consentLocation ? _lng : null,
      addressText: _address.text.trim(),
      landmark: _landmark.text.trim(),
      trustedContacts: [
        for (final c in _contacts)
          if (c.name.text.trim().length >= 2 && c.phone.text.trim().length >= 8)
            TrustedContactIn(
              fullName: c.name.text.trim(),
              phone: c.phone.text.trim(),
              canViewLocation: c.canViewLocation,
            ),
      ],
    );
    try {
      final r = await app.call((api) => api.register(body));
      app.applyResident(r);
      if (mounted) showSnack(context, s.registered);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 0 ? s.needsTitle : s.consentTitle),
        leading: _step == 1 ? BackButton(onPressed: () => setState(() => _step = 0)) : null,
        actions: [
          TextButton(
            onPressed: app.logout,
            child: Text(s.logout, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(child: _step == 0 ? _needsStep(context) : _consentStep(context)),
    );
  }

  Widget _needsStep(BuildContext context) {
    final s = context.s;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(s.needsNote, style: const TextStyle(color: AppColors.gray)),
      const SizedBox(height: 8),
      SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          NeedsChecklist(selected: _needs, onChanged: (v) => setState(() => _needs = v)),
          SwitchListTile(title: Text(s.livesAlone), value: _alone, onChanged: (v) => setState(() => _alone = v)),
          SwitchListTile(title: Text(s.hasSmartphone), value: _smart, onChanged: (v) => setState(() => _smart = v)),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton(key: const Key('needs-next'), onPressed: () => setState(() => _step = 1), child: Text(s.next)),
    ]);
  }

  Widget _consentStep(BuildContext context) {
    final s = context.s;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _name, decoration: InputDecoration(labelText: s.fullName)),
      const SizedBox(height: 12),
      if (_wardsError != null) ErrorPanel(message: errorText(_wardsError!, s), onRetry: _loadWards, s: s),
      if (_wards == null && _wardsError == null) const LinearProgressIndicator(),
      if (_wards != null)
        DropdownButtonFormField<String>(
          key: const Key('ward-picker'),
          initialValue: _wardId,
          isExpanded: true,
          decoration: InputDecoration(labelText: s.chooseWard),
          items: [
            for (final w in _wards!)
              DropdownMenuItem(value: w.id, child: Text('${w.name} · ${w.district}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _wardId = v),
        ),
      const SizedBox(height: 12),
      SectionCard(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          CheckboxListTile(
            key: const Key('consent-registry'),
            value: _consentRegistry,
            onChanged: (v) => setState(() => _consentRegistry = v ?? false),
            title: Text(s.consentRegistry),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            key: const Key('consent-location'),
            value: _consentLocation,
            onChanged: (v) => setState(() => _consentLocation = v ?? false),
            title: Text(s.consentLocation),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _consentCaregiver,
            onChanged: (v) => setState(() => _consentCaregiver = v ?? false),
            title: Text(s.consentCaregiver),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _byGuardian,
            onChanged: (v) => setState(() => _byGuardian = v ?? false),
            title: Text(s.guardianConsent),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (_byGuardian)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(controller: _guardian, decoration: InputDecoration(labelText: s.guardianName)),
            ),
        ]),
      ),
      if (_consentLocation) ...[
        const SizedBox(height: 12),
        SectionCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            OutlinedButton.icon(
              onPressed: _locating ? null : _locate,
              icon: const Icon(Icons.my_location),
              label: Text(_locating ? s.loading : s.useMyLocation),
            ),
            if (_lat != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${s.locationCaptured}: ${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}',
                    style: const TextStyle(color: AppColors.green)),
              ),
            if (_locationFailed)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(s.locationUnavailable, style: const TextStyle(color: AppColors.amber)),
              ),
            const SizedBox(height: 8),
            TextField(controller: _address, decoration: InputDecoration(labelText: s.addressOptional)),
            const SizedBox(height: 8),
            TextField(controller: _landmark, decoration: InputDecoration(labelText: s.landmarkOptional)),
          ]),
        ),
      ],
      SectionTitle(s.trustedContacts,
          trailing: TextButton.icon(
            onPressed: () => setState(() => _contacts.add(_ContactDraft())),
            icon: const Icon(Icons.person_add),
            label: Text(s.addContact),
          )),
      for (final (i, c) in _contacts.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SectionCard(
            child: Column(children: [
              Row(children: [
                Expanded(child: TextField(controller: c.name, decoration: InputDecoration(labelText: s.contactName))),
                IconButton(
                  tooltip: s.cancel,
                  onPressed: () => setState(() => _contacts.removeAt(i).dispose()),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: c.phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: s.contactPhone),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.contactCanSeeLocation),
                value: c.canViewLocation,
                onChanged: (v) => setState(() => c.canViewLocation = v),
              ),
            ]),
          ),
        ),
      if (_error != null) ...[const SizedBox(height: 8), ErrorPanel(message: _error!, s: s)],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('register'),
        onPressed: _busy ? null : _submit,
        child: Text(_busy ? s.sending : s.register),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
