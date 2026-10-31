import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';

/// Admin/operator accounts (and unknown roles) are directed to the web command centre.
class OpsNoticeScreen extends StatelessWidget {
  const OpsNoticeScreen({super.key, this.unknownRole = false});
  final bool unknownRole;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final me = app.me;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Icon(Icons.desktop_windows, size: 96, color: AppColors.red),
            const SizedBox(height: 16),
            Text(unknownRole ? s.unknownRole : s.opsTitle,
                key: const Key('ops-title'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (!unknownRole) Text(s.opsBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
            if (me != null) ...[
              const SizedBox(height: 12),
              Text('${me.user.fullName} · ${s.roleName(me.user.roleRaw)}',
                  textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray)),
            ],
            const SizedBox(height: 8),
            Text('${s.serverLabel}: ${app.config.apiBaseUrl}',
                textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray, fontSize: 12)),
            const Spacer(),
            FilledButton.icon(onPressed: app.logout, icon: const Icon(Icons.logout), label: Text(s.logout)),
          ]),
        ),
      ),
    );
  }
}
