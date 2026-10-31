import 'package:flutter/material.dart';

import '../../accessibility/modes.dart';
import '../../core/api_exception.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../services/offline_queue.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import 'alert_detail_screen.dart';
import 'alert_loader.dart';
import 'easy_read_screen.dart';
import 'help_status_screen.dart';
import 'safe_confirmation_screen.dart';
import 'sms_reply.dart';

/// Full-screen emergency response: huge SAFE (green) and HELP (red) buttons, a confirm step, then
/// `POST /alerts/{id}/respond` with an Idempotency-Key (queued on the phone when offline).
class EmergencyResponseScreen extends StatelessWidget {
  const EmergencyResponseScreen({super.key, required this.deliveryId, this.preselectHelp = false});

  final String deliveryId;
  final bool preselectHelp;

  @override
  Widget build(BuildContext context) {
    return AlertLoader(
      deliveryId: deliveryId,
      builder: (context, alert) => _EmergencyBody(alert: alert, preselectHelp: preselectHelp),
    );
  }
}

class _EmergencyBody extends StatefulWidget {
  const _EmergencyBody({required this.alert, required this.preselectHelp});
  final AlertOut alert;
  final bool preselectHelp;

  @override
  State<_EmergencyBody> createState() => _EmergencyBodyState();
}

class _EmergencyBodyState extends State<_EmergencyBody> {
  String? _confirming; // 'SAFE' | 'HELP'
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preselectHelp) _confirming = DeliveryStatus.help;
  }

  Future<void> _send(String status) async {
    final app = context.appRead;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final SendResult r = await app.respond(widget.alert, status);
      if (!mounted) return;
      if (r.isDelivered) {
        await Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => status == DeliveryStatus.safe
              ? SafeConfirmationScreen(deliveryId: widget.alert.deliveryId)
              : HelpStatusScreen(deliveryId: widget.alert.deliveryId),
        ));
        return;
      }
      setState(() => _confirming = null); // queued: the queued panel is shown below
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final a = widget.alert;
    final modes = app.modesFor(a);
    final pending = app.pendingReplyFor(a.deliveryId);

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * app.extraTextScaleFor(a)),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(s.areYouSafe),
          actions: [
            if (modes.speaks)
              IconButton(
                tooltip: s.readAloud,
                icon: const Icon(Icons.volume_up),
                onPressed: () => app.effects.speak(app.speechFor(a), s.ttsLocale),
              ),
          ],
        ),
        body: Column(children: [
          const ConnectionBanner(),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              _AlertHeader(alert: a, modes: modes, s: s),
              ValueListenableBuilder<bool>(
                valueListenable: app.effects.active,
                builder: (context, on, _) => !on
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: OutlinedButton.icon(
                          key: const Key('stop-alarm'),
                          onPressed: app.effects.stop,
                          icon: const Icon(Icons.notifications_off),
                          label: Text(s.stopAlarm),
                        ),
                      ),
              ),
              if (modes.noVoiceResponse) _Note(icon: Icons.touch_app, text: s.noVoiceNote),
              if (modes.assistancePrompt) _Note(icon: Icons.accessible, text: s.assistancePrompt),
              if (modes.smsOnly) _Note(icon: Icons.sms, text: s.smsOnlyNote),
              if (!a.awaitingReply) ...[
                const SizedBox(height: 12),
                StatusChip(
                  label: '${s.yourStatus}: ${s.statusName(a.status)}',
                  color: AppColors.forStatus(a.status),
                  icon: a.isSafe ? Icons.check_circle : Icons.sos,
                ),
              ],
              if (pending != null) ...[
                const SizedBox(height: 12),
                _QueuedPanel(pending: pending, s: s),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                ErrorPanel(message: _error!, s: s),
              ],
              const SizedBox(height: 16),
              if (_confirming == null)
                _ResponseButtons(
                  modes: modes,
                  s: s,
                  onSafe: () => setState(() => _confirming = DeliveryStatus.safe),
                  onHelp: () => setState(() => _confirming = DeliveryStatus.help),
                )
              else
                _ConfirmPanel(
                  status: _confirming!,
                  sending: _sending,
                  modes: modes,
                  s: s,
                  onConfirm: () => _send(_confirming!),
                  onCancel: () => setState(() => _confirming = null),
                ),
              const SizedBox(height: 16),
              if (modes.stepByStep && a.presentation.easyReadSteps.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => EasyReadScreen(deliveryId: a.deliveryId),
                  )),
                  icon: const Icon(Icons.format_list_numbered),
                  label: Text(s.easyReadSteps),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AlertDetailScreen(deliveryId: a.deliveryId),
                )),
                icon: const Icon(Icons.article_outlined),
                label: Text(s.viewAlert),
              ),
              const SizedBox(height: 16),
              SmsReplyPanel(hint: a.smsReplyHint),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _AlertHeader extends StatelessWidget {
  const _AlertHeader({required this.alert, required this.modes, required this.s});
  final AlertOut alert;
  final AlertModes modes;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    final p = alert.presentation;
    return SectionCard(
      color: AppColors.redSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Pictogram(hazardIcon(p.pictogram), size: modes.pictograms ? 72 : 56, semanticLabel: alert.official.event),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                '${alert.official.severity.toUpperCase()} • ${alert.official.event}',
                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
              Text(p.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ]),
          ),
          if (alert.isDemo) const DemoBadge(),
        ]),
        const SizedBox(height: 8),
        Text(p.label, style: const TextStyle(fontSize: 12, color: AppColors.gray, fontStyle: FontStyle.italic)),
        if (alert.official.headline != null) ...[
          const SizedBox(height: 8),
          Text(alert.official.headline!, style: const TextStyle(fontSize: 16)),
        ],
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SectionCard(
          color: AppColors.officialSoft,
          child: Row(children: [
            Icon(icon, color: AppColors.official),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
          ]),
        ),
      );
}

class _ResponseButtons extends StatelessWidget {
  const _ResponseButtons({required this.modes, required this.s, required this.onSafe, required this.onHelp});
  final AlertModes modes;
  final Strings s;
  final VoidCallback onSafe;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    final h = modes.largeControls ? 150.0 : 120.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      BigResponseButton(
        key: const Key('btn-safe'),
        label: s.iAmSafe,
        semantics: s.safeSemantics,
        icon: Icons.check_circle,
        color: AppColors.green,
        height: h,
        onPressed: onSafe,
      ),
      const SizedBox(height: 16),
      BigResponseButton(
        key: const Key('btn-help'),
        label: s.iNeedHelp,
        semantics: s.helpSemantics,
        icon: Icons.sos,
        color: AppColors.red,
        height: h,
        onPressed: onHelp,
      ),
    ]);
  }
}

class BigResponseButton extends StatelessWidget {
  const BigResponseButton({
    super.key,
    required this.label,
    required this.semantics,
    required this.icon,
    required this.color,
    required this.height,
    required this.onPressed,
  });

  final String label;
  final String semantics;
  final IconData icon;
  final Color color;
  final double height;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            textStyle: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 48),
          label: FittedBox(child: Text(label)),
        ),
      ),
    );
  }
}

class _ConfirmPanel extends StatelessWidget {
  const _ConfirmPanel({
    required this.status,
    required this.sending,
    required this.modes,
    required this.s,
    required this.onConfirm,
    required this.onCancel,
  });

  final String status;
  final bool sending;
  final AlertModes modes;
  final Strings s;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final safe = status == DeliveryStatus.safe;
    final color = safe ? AppColors.green : AppColors.red;
    return SectionCard(
      color: safe ? AppColors.greenSoft : AppColors.redSoft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            safe ? s.confirmSafe : s.confirmHelp,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color),
          ),
        ),
        const SizedBox(height: 16),
        BigResponseButton(
          key: const Key('btn-confirm'),
          label: sending ? s.sending : (safe ? s.confirmSafeYes : s.confirmHelpYes),
          semantics: safe ? s.confirmSafeYes : s.confirmHelpYes,
          icon: safe ? Icons.check : Icons.sos,
          color: color,
          height: modes.controlHeight,
          onPressed: sending ? null : onConfirm,
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('btn-cancel'),
          onPressed: sending ? null : onCancel,
          child: Text(s.cancel),
        ),
      ]),
    );
  }
}

class _QueuedPanel extends StatelessWidget {
  const _QueuedPanel({required this.pending, required this.s});
  final QueuedReply pending;
  final Strings s;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: SectionCard(
        color: AppColors.amberSoft,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.schedule_send, color: AppColors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${s.queuedNotDelivered}: ${s.statusName(pending.status)}',
                key: const Key('queued-label'),
                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber, fontSize: 16),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Text(s.queuedExplain),
        ]),
      ),
    );
  }
}
