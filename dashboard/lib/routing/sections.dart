import 'package:flutter/material.dart';

/// Top-level navigation destinations. `adminOnly` sections are hidden for operators
/// (the backend enforces the same rules — this only avoids dead ends).
enum AppSection {
  commandCentre('Command centre', Icons.crisis_alert, adminOnly: false),
  incidents('Incidents', Icons.warning_amber_rounded, adminOnly: false),
  residents('Residents', Icons.people_alt_outlined, adminOnly: true),
  wards('Wards & posts', Icons.map_outlined, adminOnly: false),
  volunteers('Volunteers', Icons.volunteer_activism_outlined, adminOnly: false),
  neighbourLinks('Neighbours', Icons.diversity_3_outlined, adminOnly: true),
  templates('Templates', Icons.sms_outlined, adminOnly: true),
  users('Users & roles', Icons.manage_accounts_outlined, adminOnly: true),
  audit('Audit', Icons.policy_outlined, adminOnly: false),
  settings('Settings', Icons.settings_outlined, adminOnly: false);

  const AppSection(this.label, this.icon, {required this.adminOnly});

  final String label;
  final IconData icon;
  final bool adminOnly;

  static List<AppSection> forRole({required bool isAdmin}) =>
      AppSection.values.where((s) => isAdmin || !s.adminOnly).toList();
}
