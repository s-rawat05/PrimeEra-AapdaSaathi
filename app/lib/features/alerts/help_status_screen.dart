import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import '../evacuation/evacuation_screen.dart';
import 'alert_loader.dart';
import 'emergency_response_screen.dart';

/// Help request status, from `AlertOut.assistance` (refreshed by realtime + polling).
class HelpStatusScreen extends StatelessWidget {
  const HelpStatusScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context) {
    return AlertLoader(
      deliveryId: deliveryId,
      builder: (context, a) {
        final app = context.app;
        final s = app.s;
        final asst = a.assistance;
        return Scaffold(
          appBar: AppBar(title: Text(s.helpRequestedTitle)),
          body: Column(children: [
            const ConnectionBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: app.refresh,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  SectionCard(
                    color: AppColors.redSoft,
                    child: Row(children: [
                      const Pictogram(Icons.sos, size: 64),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                            a.isHelp ? s.helpRequestedTitle : s.statusName(a.status),
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(a.isHelp ? s.helpRequestedBody : asst.summary),
                        ]),
                      ),
                    ]),
                  ),
                  SectionTitle(s.assistance),
                  SectionCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Semantics(
                        liveRegion: true,
                        child: Text(asst.summary,
                            key: const Key('assistance-summary'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      const Divider(height: 24),
                      _Row(
                        icon: Icons.house,
                        text: asst.neighbourAsked ? s.neighbourAsked : s.neighbourNotAsked,
                        on: asst.neighbourAsked,
                      ),
                      _Row(
                        icon: Icons.directions_walk,
                        text: asst.volunteerStatus == null ? s.noVolunteerYet : s.volunteerStatus(asst.volunteerStatus!),
                        on: asst.volunteerStatus != null,
                      ),
                      if (asst.volunteerEtaMinutes != null)
                        _Row(icon: Icons.timer, text: s.etaMinutes(fmtMinutes(asst.volunteerEtaMinutes)), on: true),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  Text(s.lastSync(fmtTime(app.lastSync)), style: const TextStyle(color: AppColors.gray)),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const EvacuationScreen(standalone: true),
                    )),
                    icon: const Icon(Icons.map),
                    label: Text(s.evacuationTitle),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size.fromHeight(60)),
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => EmergencyResponseScreen(deliveryId: deliveryId),
                    )),
                    icon: const Icon(Icons.check_circle),
                    label: Text(s.iAmSafeNow),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                    child: Text(s.backHome),
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.text, required this.on});
  final IconData icon;
  final String text;
  final bool on;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, color: on ? AppColors.green : AppColors.gray),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ]),
      );
}
