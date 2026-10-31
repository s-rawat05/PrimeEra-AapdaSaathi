import 'package:flutter/material.dart';

import '../../core/api_error.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';

const allRoles = ['admin', 'operator', 'volunteer', 'neighbour', 'caregiver', 'resident'];

/// Users & roles (admin): list/search, create, change role, activate/deactivate.
class UsersPage extends StatefulWidget {
  const UsersPage({super.key});

  @override
  State<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends State<UsersPage> {
  final _q = TextEditingController();
  String? _role;
  int _offset = 0;
  static const _limit = 30;
  PageOf<UserAdminOut>? _page;
  Object? _error;
  bool _started = false;
  final Set<String> _busy = {};

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
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await context.api.users(
          role: _role, q: _q.text.trim().isEmpty ? null : _q.text.trim(), limit: _limit, offset: _offset);
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

  Future<void> _patch(UserAdminOut u, {String? role, bool? isActive}) async {
    setState(() => _busy.add(u.user.id));
    final r = await runAction(context, () => context.api.patchUser(u.user.id, role: role, isActive: isActive),
        success: 'Updated ${u.user.fullName} (audited)');
    if (mounted) setState(() => _busy.remove(u.user.id));
    if (r != null) _load();
  }

  Future<void> _create() async {
    final api = context.api;
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    var role = 'operator';
    var language = 'en';
    var isDemo = false;
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: 'Create user',
        builder: (context, setState) {
          final ops = role == 'admin' || role == 'operator';
          return [
            TextFormField(controller: name, decoration: const InputDecoration(labelText: 'Full name'), validator: (v) => requiredText(v, min: 2, field: 'Name')),
            gap12,
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: [for (final r in allRoles) DropdownMenuItem(value: r, child: Text(r))],
                  onChanged: (v) => setState(() => role = v ?? role),
                ),
              ),
              gap12,
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: language,
                  decoration: const InputDecoration(labelText: 'Language'),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                  ],
                  onChanged: (v) => language = v ?? language,
                ),
              ),
            ]),
            gap12,
            TextFormField(controller: phone, decoration: const InputDecoration(labelText: 'Mobile number', hintText: '+91…')),
            gap12,
            TextFormField(
              controller: email,
              decoration: InputDecoration(labelText: ops ? 'Email (required for staff)' : 'Email (optional)'),
              validator: (v) => ops && !(v ?? '').contains('@') ? 'Staff accounts need an email' : null,
            ),
            if (ops) ...[
              gap12,
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Initial password', helperText: 'At least 10 characters'),
                validator: (v) => (v ?? '').length < 10 ? 'Password must be at least 10 characters' : null,
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isDemo,
              onChanged: (v) => setState(() => isDemo = v),
              title: const Text('Fictional demo account'),
            ),
          ];
        },
        onSubmit: () {
          if (phone.text.trim().isEmpty && email.text.trim().isEmpty) {
            throw const InputError('Enter a phone number or an email');
          }
          final ops = role == 'admin' || role == 'operator';
          return api.createUser({
            'full_name': name.text.trim(),
            'role': role,
            if (phone.text.trim().isNotEmpty) 'phone': phone.text.trim(),
            if (email.text.trim().isNotEmpty) 'email': email.text.trim(),
            if (ops) 'password': password.text,
            'language': language,
            'is_demo': isDemo,
          });
        },
      ),
    );
    if (r is UserAdminOut && mounted) {
      showSnack(context, 'Created ${r.user.fullName} (${r.user.role})');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final me = context.services.auth.user;
    return PageBody(children: [
      PageHeader(
        title: 'Users & roles',
        subtitle: 'Roles are enforced by the server on every request.',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.person_add), label: const Text('Create user')),
        ],
      ),
      Wrap(spacing: 10, runSpacing: 10, children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _q,
            decoration: const InputDecoration(labelText: 'Search name or email', prefixIcon: Icon(Icons.search)),
            onSubmitted: (_) {
              _offset = 0;
              _load();
            },
          ),
        ),
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String?>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All roles')),
              for (final r in allRoles) DropdownMenuItem<String?>(value: r, child: Text(r)),
            ],
            onChanged: (v) {
              _role = v;
              _offset = 0;
              _load();
            },
          ),
        ),
      ]),
      gap16,
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (page == null && _error == null) const LinearProgressIndicator(),
      if (page != null && page.items.isEmpty) const EmptyState('No users found.'),
      if (page != null)
        Card(
          child: Column(children: [
            for (final u in page.items)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: (u.isActive ? AppColors.info : AppColors.unreachable).withValues(alpha: 0.15),
                  child: Icon(Icons.person, color: u.isActive ? AppColors.info : AppColors.unreachable),
                ),
                title: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(u.user.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (u.user.isDemo) const Pill('DEMO', color: AppColors.drill, dense: true),
                  if (!u.isActive) const Pill('INACTIVE', color: AppColors.unreachable, dense: true),
                  if (u.user.id == me?.id) const Pill('YOU', color: AppColors.primary, dense: true),
                ]),
                subtitle: Text('${u.user.email ?? '—'} · ${u.user.phoneMasked} · since ${fmtShort(u.createdAt)}'),
                trailing: Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  DropdownButton<String>(
                    value: allRoles.contains(u.user.role) ? u.user.role : null,
                    items: [for (final r in allRoles) DropdownMenuItem(value: r, child: Text(r))],
                    onChanged: _busy.contains(u.user.id) || u.user.id == me?.id
                        ? null
                        : (v) async {
                            if (v == null || v == u.user.role) return;
                            final ok = await confirmDialog(context,
                                title: 'Change role?',
                                message: 'Change ${u.user.fullName} from ${u.user.role} to $v?',
                                confirmLabel: 'Change role');
                            if (ok) _patch(u, role: v);
                          },
                  ),
                  Tooltip(
                    message: u.isActive ? 'Active — switch off to deactivate' : 'Inactive',
                    child: Switch(
                      value: u.isActive,
                      onChanged: _busy.contains(u.user.id) || u.user.id == me?.id ? null : (v) => _patch(u, isActive: v),
                    ),
                  ),
                ]),
              ),
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
