import 'package:flutter/material.dart';

import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../overview/command_centre_controller.dart';
import '../overview/command_centre_page.dart';

/// Account, connection and safety settings (read-only; server settings are not editable from the client).
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  Widget build(BuildContext context) {
    final s = context.services;
    final me = s.auth.me;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final feed = controller.feedStatus;
        final demo = controller.demoStatus;
        return PageBody(children: [
          const PageHeader(title: 'Settings', subtitle: 'Session, connection and safety switches'),
          SectionCard(
            title: 'Signed in',
            icon: Icons.account_circle_outlined,
            child: Column(children: [
              KeyValue('Name', me?.user.fullName),
              KeyValue('Role', me?.user.role),
              KeyValue('Email', me?.user.email),
              KeyValue('Phone', me?.user.phoneMasked),
              KeyValue('Demo account', (me?.user.isDemo ?? false) ? 'Yes (fictional)' : 'No'),
              gap8,
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => s.auth.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ),
            ]),
          ),
          gap16,
          SectionCard(
            title: 'Connection',
            icon: Icons.lan_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeyValue('API server', s.config.apiRoot),
              KeyValue('Realtime', s.config.realtimeUri('<ticket>').replace(queryParameters: {}).toString()),
              KeyValue('Last data refresh', fmtDateTime(controller.lastRefresh)),
              KeyValue('Fallback polling', 'every ${controller.pollInterval.inSeconds} s'),
              KeyValue('Realtime status', null, valueWidget: Align(
                alignment: Alignment.centerLeft,
                child: RealtimeIndicator(hub: s.realtime, lastRefresh: controller.lastRefresh),
              )),
            ]),
          ),
          gap16,
          SectionCard(
            title: 'Safety switches (server-side)',
            icon: Icons.shield_outlined,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              KeyValue('Real-resident notifications', (feed?.notifyRealResidents ?? me?.notifyRealResidents ?? false) ? 'ON' : 'OFF',
                  labelWidth: 220),
              KeyValue('Demo mode', (demo?.demoModeEnabled ?? me?.demoMode ?? false) ? 'ON' : 'OFF', labelWidth: 220),
              KeyValue('SACHET polling', feed == null ? '—' : (feed.pollingEnabled ? 'ON' : 'OFF'), labelWidth: 220),
              KeyValue('Demo escalation interval', demo == null ? '—' : '${demo.escalationIntervalSeconds} s', labelWidth: 220),
              gap8,
              const InfoBanner(
                'These switches are configured on the server (environment variables) and cannot be changed from this console.',
                color: AppColors.muted,
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
