import 'package:flutter/material.dart';

import '../features/alerts/alert_history_screen.dart';
import '../features/caregiver/caregiver_screen.dart';
import '../features/evacuation/evacuation_screen.dart';
import '../features/neighbour/neighbour_checks_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/resident/resident_home_screen.dart';
import '../features/volunteer/volunteer_tasks_screen.dart';
import '../models/models.dart';
import '../state/app_scope.dart';
import '../widgets/sos_button.dart';

class ShellTab {
  const ShellTab({required this.icon, required this.label, required this.build, this.key});
  final IconData icon;
  final String label;
  final WidgetBuilder build;
  final Key? key;
}

/// Bottom-navigation shell. Each role gets its own tabs.
class RoleShell extends StatefulWidget {
  const RoleShell({super.key, required this.role});
  final UserRole role;

  @override
  State<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends State<RoleShell> {
  int _index = 0;

  List<ShellTab> _tabs(BuildContext context) {
    final s = context.s;
    return switch (widget.role) {
      UserRole.resident => [
          ShellTab(icon: Icons.home_rounded, label: s.navHome, build: (_) => const ResidentHomeScreen(), key: const Key('tab-home')),
          ShellTab(icon: Icons.map_rounded, label: s.navEvacuate, build: (_) => const EvacuationScreen(), key: const Key('tab-evacuate')),
          ShellTab(icon: Icons.history, label: s.navAlerts, build: (_) => const AlertHistoryScreen(), key: const Key('tab-alerts')),
          ShellTab(icon: Icons.person, label: s.navProfile, build: (_) => const ProfileScreen(), key: const Key('tab-profile')),
        ],
      UserRole.caregiver => [
          ShellTab(icon: Icons.family_restroom, label: s.navPeople, build: (_) => const CaregiverScreen(), key: const Key('tab-people')),
          ShellTab(icon: Icons.person, label: s.navProfile, build: (_) => const ProfileScreen(), key: const Key('tab-profile')),
        ],
      UserRole.neighbour => [
          ShellTab(icon: Icons.house_rounded, label: s.navChecks, build: (_) => const NeighbourChecksScreen(), key: const Key('tab-checks')),
          ShellTab(icon: Icons.person, label: s.navProfile, build: (_) => const ProfileScreen(), key: const Key('tab-profile')),
        ],
      UserRole.volunteer => [
          ShellTab(icon: Icons.assignment, label: s.navTasks, build: (_) => const VolunteerTasksScreen(), key: const Key('tab-tasks')),
          ShellTab(icon: Icons.person, label: s.navProfile, build: (_) => const ProfileScreen(), key: const Key('tab-profile')),
        ],
      _ => [ShellTab(icon: Icons.person, label: s.navProfile, build: (_) => const ProfileScreen())],
    };
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs(context);
    final i = _index.clamp(0, tabs.length - 1);
    final resident = widget.role == UserRole.resident;
    return Scaffold(
      body: tabs[i].build(context),
      floatingActionButton: resident ? const SosFab() : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: i,
        onDestinationSelected: (v) => setState(() => _index = v),
        destinations: [
          for (final t in tabs) NavigationDestination(key: t.key, icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
