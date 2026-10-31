import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../evacuation/evacuation_screen.dart';
import 'alert_loader.dart';
import 'emergency_response_screen.dart';

/// Active alert: AapdaSaathi's framing (clearly labelled) and, separately, the official CAP text
/// verbatim.
class AlertDetailScreen extends StatelessWidget {
  const AlertDetailScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    return AlertLoader(
      deliveryId: deliveryId,
      builder: (context, a) {
        final app = context.app;
        final s = app.s;
        final modes = app.modesFor(a);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * app.extraTextScaleFor(a)),
          ),
          child: Scaffold(
            appBar: AppBar(
              title: Text(s.alertTitle),
              actions: [
                IconButton(
                  tooltip: s.readAloud,
                  icon: const Icon(Icons.volume_up),
                  onPressed: () => app.effects.speak(app.speechFor(a), s.ttsLocale),
                ),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              PresentationCard(alert: a, s: s, largePictogram: modes.pictograms),
              const SizedBox(height: 16),
              OfficialTextCard(official: a.official, s: s),
              const SizedBox(height: 16),
              if (a.isActiveIncident)
                FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: Size.fromHeight(modes.controlHeight)),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EmergencyResponseScreen(deliveryId: a.deliveryId),
                  )),
                  icon: const Icon(Icons.touch_app),
                  label: Text(s.respondNow),
                ),
              const SizedBox(height: 12),
              if (a.isActiveIncident)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const EvacuationScreen(standalone: true),
                  )),
                  icon: const Icon(Icons.map),
                  label: Text(s.evacuationTitle),
                ),
            ]),
          ),
        );
      },
    );
  }
}

/// `presentation.*`, always captioned with `presentation.label`.
class PresentationCard extends StatelessWidget {
  const PresentationCard({super.key, required this.alert, required this.s, this.largePictogram = false});
  final AlertOut alert;
  final Strings s;
  final bool largePictogram;

  @override
  Widget build(BuildContext context) {
    final p = alert.presentation;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Align(
          alignment: Alignment.centerLeft,
          child: StatusChip(label: p.label, color: AppColors.red, icon: Icons.info_outline),
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pictogram(hazardIcon(p.pictogram), size: largePictogram ? 80 : 56, semanticLabel: alert.official.event),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, key: const Key('presentation-title'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (alert.isDemo) const Padding(padding: EdgeInsets.only(top: 6), child: DemoBadge()),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Text(p.body, style: const TextStyle(fontSize: 16, height: 1.4)),
        if (p.easyReadSteps.isNotEmpty) ...[
          const SizedBox(height: 12),
          for (final (i, step) in p.easyReadSteps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Pictogram(stepIcon(step), size: 40),
                const SizedBox(width: 12),
                Expanded(child: Text('${i + 1}. $step', style: const TextStyle(fontSize: 17))),
              ]),
            ),
        ],
      ]),
    );
  }
}

/// `official.*` verbatim, visually separated (blue) from AapdaSaathi's framing.
class OfficialTextCard extends StatelessWidget {
  const OfficialTextCard({super.key, required this.official, required this.s});
  final OfficialAlert official;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final o = official;
    return Container(
      key: const Key('official-section'),
      decoration: BoxDecoration(
        color: AppColors.officialSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.official, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_balance, color: AppColors.official),
          const SizedBox(width: 8),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(s.officialText,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.official)),
            ),
          ),
        ]),
        Text(s.officialTextNote, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
        const SizedBox(height: 8),
        if (o.sourceLabel.isNotEmpty)
          StatusChip(label: o.sourceLabel, color: AppColors.official, icon: Icons.verified_user),
        const SizedBox(height: 8),
        FieldRow(s.headline, o.headline),
        FieldRow(s.description, o.description),
        FieldRow(s.instruction, o.instruction ?? s.noInstruction),
        FieldRow(s.sender, o.sender),
        FieldRow(s.event, o.event),
        FieldRow('${s.severity} / ${s.urgency} / ${s.certainty}', '${o.severity} / ${o.urgency} / ${o.certainty}'),
        FieldRow(s.onset, o.onset == null ? null : fmtTime(o.onset)),
        FieldRow(s.expires, o.expires == null ? null : fmtTime(o.expires)),
        FieldRow(s.area, o.areaDesc),
        if (o.onsetNote != null && o.onsetNote!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.schedule, color: AppColors.amber, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text(o.onsetNote!, style: const TextStyle(color: AppColors.amber))),
            ]),
          ),
        if (o.officialUrl != null && o.officialUrl!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: () async {
                final uri = Uri.tryParse(o.officialUrl!);
                if (uri == null || !await app.launcher.open(uri)) {
                  if (context.mounted) showSnack(context, s.couldNotOpen, error: true);
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(s.openOfficialLink),
            ),
          ),
      ]),
    );
  }
}
