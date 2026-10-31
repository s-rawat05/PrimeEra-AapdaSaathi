import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'emergency_response_screen.dart';

/// Shown only after the server confirmed SAFE (never for a queued reply).
class SafeConfirmationScreen extends StatelessWidget {
  const SafeConfirmationScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final alert = app.alertById(deliveryId);
    return Scaffold(
      backgroundColor: AppColors.greenSoft,
      appBar: AppBar(backgroundColor: AppColors.green, title: Text(s.safeConfirmedTitle)),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const SizedBox(height: 24),
          Semantics(
            label: s.safeConfirmedTitle,
            child: const Icon(Icons.verified, size: 140, color: AppColors.green),
          ),
          const SizedBox(height: 16),
          Text(
            s.safeConfirmedTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.green),
          ),
          const SizedBox(height: 12),
          Text(s.safeConfirmedBody, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
          if (alert?.repliedAt != null) ...[
            const SizedBox(height: 8),
            Text(fmtTime(alert!.repliedAt), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray)),
          ],
          if (alert?.official.instruction != null) ...[
            const SizedBox(height: 24),
            SectionCard(
              color: AppColors.officialSoft,
              child: FieldRow(s.officialInstruction, alert!.official.instruction),
            ),
          ],
          const SizedBox(height: 32),
          FilledButton.icon(
            key: const Key('back-home'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size.fromHeight(64)),
            onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
            icon: const Icon(Icons.home),
            label: Text(s.backHome),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, minimumSize: const Size.fromHeight(60)),
            onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
              builder: (_) => EmergencyResponseScreen(deliveryId: deliveryId, preselectHelp: true),
            )),
            icon: const Icon(Icons.sos),
            label: Text(s.changedMind),
          ),
        ]),
      ),
    );
  }
}
