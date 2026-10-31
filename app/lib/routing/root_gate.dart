import 'package:flutter/material.dart';

import '../features/auth/login_screen.dart';
import '../features/onboarding/language_screen.dart';
import '../features/onboarding/resident_onboarding_screen.dart';
import '../features/ops/ops_notice_screen.dart';
import '../features/splash/intro_screen.dart';
import '../models/models.dart';
import '../state/app_controller.dart';
import '../state/app_scope.dart';
import 'role_shell.dart';

/// Decides the root screen from auth state, onboarding progress and `GET /me` → `user.role`.
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool _introDone = false;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    switch (app.stage) {
      case AuthStage.loading:
        return const SplashScreen();
      case AuthStage.signedOut:
        if (!app.session.introSeen && !_introDone) {
          return IntroScreen(onDone: () async {
            await app.session.setIntroSeen();
            if (mounted) setState(() => _introDone = true);
          });
        }
        return const LoginScreen();
      case AuthStage.signedIn:
        final me = app.me;
        if (me == null) return const LoginScreen();
        if (!app.languageChosen) return const LanguageScreen();
        final role = me.user.role;
        if (role.isOps) return const OpsNoticeScreen();
        if (role == UserRole.unknown) return const OpsNoticeScreen(unknownRole: true);
        if (role == UserRole.resident && me.resident == null) return const ResidentOnboardingScreen();
        // Key by user id so switching accounts resets tab state.
        return RoleShell(key: ValueKey('shell-${me.user.id}'), role: role);
    }
  }
}
