import 'package:flutter/material.dart';

import '../../accessibility/modes.dart';
import '../../accessibility/voice_responder.dart';
import '../../core/api_exception.dart';
import '../../l10n/strings.dart';
import '../../models/models.dart';
import '../../services/offline_queue.dart';
import '../../state/app_controller.dart';
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

  VoiceResponder? _voice;

  @override
  void initState() {
    super.initState();
    if (widget.preselectHelp) _confirming = DeliveryStatus.help;
    // Hands-free reply for residents who cannot see the screen: starts by itself only when this
    // screen was opened by a ringing alarm. Otherwise the "Answer by voice" button starts it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.appRead;
      if (_voiceEligible(app) && app.effects.active.value && !widget.preselectHelp) _startVoice(ringFirst: true);
    });
  }

  bool _voiceEligible(AppController app) {
    final a = widget.alert;
    final modes = app.modesFor(a);
    return app.voice != null && modes.speaks && !modes.noVoiceResponse && a.awaitingReply && a.isActiveIncident;
  }

  void _startVoice({required bool ringFirst}) {
    final app = context.appRead;
    final s = app.s;
    final a = widget.alert;
    final v = _voice ??=
        VoiceResponder(
          input: app.voice!,
          strings: s,
          speak: (text) => app.effects.speakAndWait(text, s.ttsLocale),
          stopAlarm: app.effects.stop,
          send: _sendByVoice,
        )..addListener(() {
          if (mounted) setState(() {});
        });
    final intro = [a.presentation.title, a.official.headline ?? ''].where((t) => t.trim().isNotEmpty).join('. ');
    v.run(intro: intro, ringFirst: ringFirst).then((_) {
      // After the spoken confirmation, show the same screens as a tapped reply.
      if (!mounted) return;
      if (v.phase == VoicePhase.sentSafe || v.phase == VoicePhase.sentHelp) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => v.phase == VoicePhase.sentSafe
                ? SafeConfirmationScreen(deliveryId: a.deliveryId)
                : HelpStatusScreen(deliveryId: a.deliveryId),
          ),
        );
      }
    });
  }

  Future<VoiceSendOutcome> _sendByVoice(String status, String note) async {
    try {
      final r = await context.appRead.respond(widget.alert, status, note: note);
      return r.isDelivered ? VoiceSendOutcome.delivered : VoiceSendOutcome.queued;
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      return VoiceSendOutcome.failed;
    }
  }

  /// Any manual action takes over from the voice flow.
  void _takeOver(VoidCallback action) {
    _voice?.cancel();
    action();
  }

  @override
  void dispose() {
    _voice?.cancel();
    _voice?.dispose();
    super.dispose();
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
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => status == DeliveryStatus.safe
                ? SafeConfirmationScreen(deliveryId: widget.alert.deliveryId)
                : HelpStatusScreen(deliveryId: widget.alert.deliveryId),
          ),
        );
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
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(MediaQuery.textScalerOf(context).scale(1) * app.extraTextScaleFor(a))),
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
        body: Column(
          children: [
            const ConnectionBanner(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
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
                  if (pending != null) ...[const SizedBox(height: 12), _QueuedPanel(pending: pending, s: s)],
                  if (_error != null) ...[const SizedBox(height: 12), ErrorPanel(message: _error!, s: s)],
                  if (_voice != null || _voiceEligible(app)) ...[
                    const SizedBox(height: 12),
                    _VoicePanel(
                      voice: _voice,
                      s: s,
                      onStart: () => _startVoice(ringFirst: false),
                      onStop: () => _voice?.cancel(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_confirming == null)
                    _ResponseButtons(
                      modes: modes,
                      s: s,
                      onSafe: () => _takeOver(() => setState(() => _confirming = DeliveryStatus.safe)),
                      onHelp: () => _takeOver(() => setState(() => _confirming = DeliveryStatus.help)),
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
                      onPressed: () =>
                          Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => EasyReadScreen(deliveryId: a.deliveryId))),
                      icon: const Icon(Icons.format_list_numbered),
                      label: Text(s.easyReadSteps),
                    ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => AlertDetailScreen(deliveryId: a.deliveryId))),
                    icon: const Icon(Icons.article_outlined),
                    label: Text(s.viewAlert),
                  ),
                  const SizedBox(height: 16),
                  SmsReplyPanel(hint: a.smsReplyHint),
                ],
              ),
            ),
          ],
        ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Pictogram(hazardIcon(p.pictogram), size: modes.pictograms ? 72 : 56, semanticLabel: alert.official.event),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${alert.official.severity.toUpperCase()} • ${alert.official.event}',
                      style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, letterSpacing: 1),
                    ),
                    Text(p.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              if (alert.isDemo) const DemoBadge(),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.label,
            style: const TextStyle(fontSize: 12, color: AppColors.gray, fontStyle: FontStyle.italic),
          ),
          if (alert.official.headline != null) ...[
            const SizedBox(height: 8),
            Text(alert.official.headline!, style: const TextStyle(fontSize: 16)),
          ],
        ],
      ),
    );
  }
}

/// Status of the hands-free reply, announced to screen readers (live region).
class _VoicePanel extends StatelessWidget {
  const _VoicePanel({required this.voice, required this.s, required this.onStart, required this.onStop});
  final VoiceResponder? voice;
  final Strings s;
  final VoidCallback onStart;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final v = voice;
    final running = v?.isRunning ?? false;
    final (IconData icon, String text) = switch (v?.phase) {
      VoicePhase.ringing => (Icons.notifications_active, s.voiceRinging),
      VoicePhase.asking => (Icons.record_voice_over, s.voiceSpeaking),
      VoicePhase.confirming => (Icons.record_voice_over, s.voiceConfirming),
      VoicePhase.listening => (Icons.mic, s.voiceListening),
      VoicePhase.sending => (Icons.send, s.voiceSendingStatus),
      VoicePhase.sentSafe => (Icons.check_circle, s.voiceDoneSafe),
      VoicePhase.sentHelp => (Icons.sos, s.voiceDoneHelp),
      VoicePhase.queued => (Icons.schedule_send, s.voiceQueuedStatus),
      VoicePhase.gaveUp => (Icons.hearing_disabled, s.voiceGaveUpStatus),
      VoicePhase.unavailable => (Icons.mic_off, s.voiceUnavailable),
      _ => (Icons.mic_none, s.voiceAnswerButton),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: SectionCard(
        color: AppColors.officialSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.official, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    key: const Key('voice-status'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (v?.lastHeard != null && v!.lastHeard!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(s.voiceHeard(v.lastHeard!), style: const TextStyle(color: AppColors.gray)),
            ],
            const SizedBox(height: 10),
            if (running)
              OutlinedButton.icon(
                key: const Key('voice-stop'),
                onPressed: onStop,
                icon: const Icon(Icons.mic_off),
                label: Text(s.voiceStop),
              )
            else if (v == null || const {VoicePhase.idle, VoicePhase.cancelled, VoicePhase.gaveUp}.contains(v.phase))
              FilledButton.icon(
                key: const Key('voice-start'),
                onPressed: onStart,
                icon: const Icon(Icons.mic),
                label: Text(s.voiceAnswerButton),
              ),
          ],
        ),
      ),
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
      child: Row(
        children: [
          Icon(icon, color: AppColors.official),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    );
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          OutlinedButton(key: const Key('btn-cancel'), onPressed: sending ? null : onCancel, child: Text(s.cancel)),
        ],
      ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.schedule_send, color: AppColors.amber),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.queuedNotDelivered}: ${s.statusName(pending.status)}',
                    key: const Key('queued-label'),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.amber, fontSize: 16),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(s.queuedExplain),
          ],
        ),
      ),
    );
  }
}
