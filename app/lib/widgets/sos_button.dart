import 'package:flutter/material.dart';

import '../features/alerts/emergency_response_screen.dart';
import '../services/device_services.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';

/// Persistent SOS. With an active official alert it opens the HELP confirmation; without one it
/// says so honestly and offers to call 112 (the backend only accepts HELP for an official alert).
Future<void> onSosPressed(BuildContext context) async {
  final app = context.appRead;
  final s = app.s;
  final alert = app.primaryAlert;
  if (alert != null && alert.isActiveIncident) {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EmergencyResponseScreen(deliveryId: alert.deliveryId, preselectHelp: true),
    ));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.sosNoAlertTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(s.sosNoAlertBody, style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64)),
            onPressed: () async {
              final ok = await app.launcher.open(Links.tel('112'));
              if (!ok && ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(s.couldNotOpen)));
              }
            },
            icon: const Icon(Icons.call),
            label: Text(s.call112),
          ),
        ]),
      ),
    ),
  );
}

/// Big red pill, as on the home screen.
class SosPillButton extends StatelessWidget {
  const SosPillButton({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final h = context.app.profileModes.controlHeight;
    return Semantics(
      button: true,
      label: s.sosSemantics,
      excludeSemantics: true,
      child: SizedBox(
        height: h,
        child: FilledButton.icon(
          key: const Key('sos-pill'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.red,
            minimumSize: Size.fromHeight(h),
            textStyle: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          onPressed: () => onSosPressed(context),
          icon: const Icon(Icons.sos, size: 30),
          label: Text(s.sosLabel),
        ),
      ),
    );
  }
}

/// Floating round SOS, shown on every resident screen.
class SosFab extends StatelessWidget {
  const SosFab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Semantics(
      button: true,
      label: s.sosSemantics,
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.redSoft, width: 6),
          boxShadow: const [BoxShadow(color: Color(0x55E53935), blurRadius: 16, spreadRadius: 2)],
        ),
        child: SizedBox(
          width: 76,
          height: 76,
          child: FloatingActionButton(
            key: const Key('sos-fab'),
            heroTag: 'sos',
            backgroundColor: AppColors.red,
            foregroundColor: Colors.white,
            shape: const CircleBorder(),
            onPressed: () => onSosPressed(context),
            child: const Text('SOS', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ),
        ),
      ),
    );
  }
}
