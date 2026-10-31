import 'package:flutter/material.dart';

import '../features/audit/audit_page.dart';
import '../features/incidents/incidents_page.dart';
import '../features/neighbour_links/neighbour_links_page.dart';
import '../features/overview/command_centre_controller.dart';
import '../features/overview/command_centre_page.dart';
import '../features/residents/residents_page.dart';
import '../features/settings/settings_page.dart';
import '../features/settings/templates_page.dart';
import '../features/settings/users_page.dart';
import '../features/volunteers/volunteers_page.dart';
import '../features/wards/wards_page.dart';
import '../models/models.dart';
import '../services/app_scope.dart';
import '../theme/app_theme.dart';
import 'sections.dart';

/// Responsive shell: NavigationRail on wide screens, drawer on narrow ones.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppSection _section = AppSection.commandCentre;
  CommandCentreController? _cc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cc == null) {
      final s = context.services;
      _cc = CommandCentreController(api: s.api, realtime: s.realtime)..start();
    }
  }

  @override
  void dispose() {
    _cc?.dispose();
    super.dispose();
  }

  void _go(AppSection s) => setState(() => _section = s);

  void _openIncident(Incident inc) {
    _cc!.focusIncident(inc);
    _go(AppSection.commandCentre);
  }

  Widget _page() {
    final cc = _cc!;
    switch (_section) {
      case AppSection.commandCentre:
        return CommandCentrePage(controller: cc);
      case AppSection.incidents:
        return IncidentsPage(onOpenIncident: _openIncident);
      case AppSection.residents:
        return const ResidentsPage();
      case AppSection.wards:
        return const WardsPage();
      case AppSection.volunteers:
        return const VolunteersPage();
      case AppSection.neighbourLinks:
        return const NeighbourLinksPage();
      case AppSection.templates:
        return const TemplatesPage();
      case AppSection.users:
        return const UsersPage();
      case AppSection.audit:
        return const AuditPage();
      case AppSection.settings:
        return SettingsPage(controller: cc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    final sections = AppSection.forRole(isAdmin: auth.isAdmin);
    if (!sections.contains(_section)) _section = AppSection.commandCentre;
    final index = sections.indexOf(_section);
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final page = KeyedSubtree(key: ValueKey(_section), child: _page());

    if (wide) {
      return Scaffold(
        body: Row(children: [
          _Rail(sections: sections, index: index, onSelect: (i) => _go(sections[i])),
          const VerticalDivider(width: 1),
          Expanded(child: page),
        ]),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_section.label, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [_UserBadge(compact: true)],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(children: [
            const _Logo(),
            const Divider(),
            for (final s in sections)
              ListTile(
                leading: Icon(s.icon, color: s == _section ? AppColors.primary : null),
                title: Text(s.label),
                selected: s == _section,
                onTap: () {
                  Navigator.pop(context);
                  _go(s);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => auth.logout(),
            ),
          ]),
        ),
      ),
      body: page,
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({required this.sections, required this.index, required this.onSelect});

  final List<AppSection> sections;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: index,
              onDestinationSelected: onSelect,
              labelType: NavigationRailLabelType.all,
              minWidth: 92,
              leading: const Padding(padding: EdgeInsets.only(bottom: 8), child: _Logo(compact: true)),
              trailing: const Expanded(
                child: Align(alignment: Alignment.bottomCenter, child: Padding(padding: EdgeInsets.only(bottom: 16), child: _UserBadge())),
              ),
              destinations: [
                for (final s in sections)
                  NavigationRailDestination(
                    icon: Icon(s.icon),
                    label: SizedBox(width: 80, child: Text(s.label, textAlign: TextAlign.center, maxLines: 2)),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.crisis_alert, color: Colors.white),
          ),
          if (!compact) ...[
            const SizedBox(height: 8),
            const Text('AapdaSaathi Command', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ]),
      );
}

class _UserBadge extends StatelessWidget {
  const _UserBadge({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    final user = auth.user;
    final initials = (user?.fullName ?? '?').trim().split(RegExp(r'\s+')).take(2).map((w) => w.isEmpty ? '' : w[0]).join();
    return PopupMenuButton<String>(
      tooltip: '${user?.fullName} (${user?.role})',
      onSelected: (v) {
        if (v == 'logout') auth.logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text('${user?.fullName}\n${user?.role.toUpperCase()}${user?.isDemo == true ? ' · DEMO' : ''}'),
        ),
        const PopupMenuItem(value: 'logout', child: ListTile(leading: Icon(Icons.logout), title: Text('Sign out'))),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: auth.isAdmin ? AppColors.primary : AppColors.info,
            child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          if (!compact) ...[
            const SizedBox(height: 4),
            Text(user?.role.toUpperCase() ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ],
        ]),
      ),
    );
  }
}
