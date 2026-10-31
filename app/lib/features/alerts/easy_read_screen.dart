import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import 'alert_loader.dart';
import 'emergency_response_screen.dart';

/// Easy-read / step-by-step: one AapdaSaathi step per screen with a pictogram. Steps come from the
/// API (`presentation.easy_read_steps`); nothing is invented on the device.
class EasyReadScreen extends StatefulWidget {
  const EasyReadScreen({super.key, required this.deliveryId});
  final String deliveryId;

  @override
  State<EasyReadScreen> createState() => _EasyReadScreenState();
}

class _EasyReadScreenState extends State<EasyReadScreen> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return AlertLoader(
      deliveryId: widget.deliveryId,
      builder: (context, a) {
        final app = context.app;
        final s = app.s;
        final steps = a.presentation.easyReadSteps;
        if (steps.isEmpty) {
          return Scaffold(appBar: AppBar(title: Text(s.easyReadSteps)), body: EmptyState(icon: Icons.list, text: s.noHistory));
        }
        final i = _i.clamp(0, steps.length - 1);
        final last = i == steps.length - 1;
        final modes = app.modesFor(a);
        return Scaffold(
          appBar: AppBar(title: Text(s.stepOf(i + 1, steps.length))),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(s.aapdaSteps, style: const TextStyle(color: AppColors.gray)),
                const Spacer(),
                Center(child: Pictogram(stepIcon(steps[i]), size: 160)),
                const SizedBox(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(steps[i],
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                if (modes.speaks)
                  TextButton.icon(
                    onPressed: () => app.effects.speak([steps[i]], s.ttsLocale),
                    icon: const Icon(Icons.volume_up),
                    label: Text(s.readAloud),
                  ),
                const Spacer(),
                if (last && a.isActiveIncident)
                  FilledButton(
                    style: FilledButton.styleFrom(minimumSize: Size.fromHeight(modes.controlHeight)),
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => EmergencyResponseScreen(deliveryId: a.deliveryId),
                    )),
                    child: Text(s.respondNow),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: Size.fromHeight(modes.controlHeight * 0.8)),
                      onPressed: i == 0 ? null : () => setState(() => _i = i - 1),
                      child: Text(s.back),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: Size.fromHeight(modes.controlHeight * 0.8)),
                      onPressed: last ? null : () => setState(() => _i = i + 1),
                      child: Text(s.next),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        );
      },
    );
  }
}
