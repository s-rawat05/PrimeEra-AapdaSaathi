import 'package:flutter/material.dart';

import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';

/// Shown to signed-in users whose role is not admin/operator.
class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.services.auth;
    final user = auth.user;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.block, color: AppColors.primary, size: 48),
                const SizedBox(height: 12),
                const Text('This console is for operations staff',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  'You are signed in as ${user?.fullName ?? 'unknown'} (${user?.role ?? '—'}). '
                  'Residents, caregivers, neighbours and volunteers should use the AapdaSaathi mobile app.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const Key('denied-signout'),
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
