import 'package:flutter/material.dart';

import 'features/authentication/access_denied_page.dart';
import 'features/authentication/login_page.dart';
import 'routing/app_shell.dart';
import 'services/app_scope.dart';
import 'services/auth_controller.dart';
import 'theme/app_theme.dart';

class AapdaCommandApp extends StatefulWidget {
  const AapdaCommandApp({super.key, required this.services, this.restoreOnStart = true});

  final AppServices services;
  final bool restoreOnStart;

  @override
  State<AapdaCommandApp> createState() => _AapdaCommandAppState();
}

class _AapdaCommandAppState extends State<AapdaCommandApp> {
  @override
  void initState() {
    super.initState();
    if (widget.restoreOnStart) widget.services.auth.restore();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        title: 'AapdaSaathi Command',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: ListenableBuilder(
          listenable: widget.services.auth,
          builder: (context, _) {
            final auth = widget.services.auth;
            switch (auth.phase) {
              case AuthPhase.restoring:
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              case AuthPhase.signedOut:
                return const LoginPage();
              case AuthPhase.signedIn:
                if (!auth.isOps) return const AccessDeniedPage();
                return AppShell(key: ValueKey(auth.user!.id));
            }
          },
        ),
      ),
    );
  }
}
