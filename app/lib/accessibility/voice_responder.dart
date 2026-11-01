import 'package:flutter/foundation.dart';

import '../l10n/strings.dart';
import '../models/models.dart';
import 'voice_input.dart';
import 'voice_reply.dart';

enum VoicePhase {
  idle,
  ringing,
  asking,
  listening,
  confirming,
  sending,
  sentSafe,
  sentHelp,
  queued,
  gaveUp,
  unavailable,
  cancelled,
}

/// Outcome of sending a reply: delivered to the server, or saved on the phone to send later.
enum VoiceSendOutcome { delivered, queued, failed }

/// Hands-free SAFE / HELP for residents who cannot see the screen (vision profile).
///
/// Ring the alarm for a few seconds → stop it so the microphone can hear → speak the question →
/// listen. HELP is sent at once. SAFE is sent only after a spoken YES. Silence or unclear speech is
/// never treated as SAFE: after [maxAttempts] the flow stops, the case stays "no reply" and the normal
/// escalation (neighbour → volunteer → control room) continues. Buttons and SMS keep working throughout.
class VoiceResponder extends ChangeNotifier {
  VoiceResponder({
    required this.input,
    required this.strings,
    required this.speak,
    required this.stopAlarm,
    required this.send,
    this.alarmDuration = const Duration(seconds: 8),
    this.listenFor = const Duration(seconds: 7),
    this.maxAttempts = 2,
  });

  final VoiceInput input;
  final Strings strings;

  /// Speaks and completes when speech has finished (so we don't listen to ourselves).
  final Future<void> Function(String text) speak;
  final Future<void> Function() stopAlarm;
  final Future<VoiceSendOutcome> Function(String status, String note) send;

  final Duration alarmDuration;
  final Duration listenFor;
  final int maxAttempts;

  VoicePhase phase = VoicePhase.idle;
  String? lastHeard;
  bool _cancelled = false;

  /// Everything recognised in this run, sent with the reply so operators can see what was heard.
  final List<String> _heard = [];

  bool get isRunning => const {
    VoicePhase.ringing,
    VoicePhase.asking,
    VoicePhase.listening,
    VoicePhase.confirming,
    VoicePhase.sending,
  }.contains(phase);

  String get _locale => strings.isHi ? 'hi_IN' : 'en_IN';

  void _set(VoicePhase p) {
    phase = p;
    notifyListeners();
  }

  /// [intro] (alert title/headline) is spoken once before the first question.
  /// [ringFirst] = true when started by an incoming alarm; false when the user pressed "Answer by voice".
  Future<void> run({String intro = '', bool ringFirst = true}) async {
    if (isRunning) return;
    _cancelled = false;
    _heard.clear();
    if (ringFirst) {
      _set(VoicePhase.ringing);
      await Future<void>.delayed(alarmDuration);
      if (_cancelled) return;
    }
    if (!await input.ensureReady()) {
      if (!_cancelled) _set(VoicePhase.unavailable);
      return;
    }
    await stopAlarm(); // the microphone cannot hear the person over the alarm
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (_cancelled) return;
      _set(VoicePhase.asking);
      await speak(attempt == 1 && intro.isNotEmpty ? '$intro. ${strings.voiceAsk}' : strings.voiceAsk);
      if (_cancelled) return;
      _set(VoicePhase.listening);
      lastHeard = await _listen();
      if (_cancelled) return;
      final answer = interpretAnswer(lastHeard);
      if (answer == VoiceIntent.help) return _deliver(DeliveryStatus.help);
      if (answer == VoiceIntent.safe) {
        _set(VoicePhase.confirming);
        await speak(strings.voiceConfirmSafe);
        if (_cancelled) return;
        _set(VoicePhase.listening);
        lastHeard = await _listen();
        if (_cancelled) return;
        final confirm = interpretConfirmation(lastHeard);
        if (confirm == VoiceIntent.help) return _deliver(DeliveryStatus.help);
        if (confirm == VoiceIntent.yes) return _deliver(DeliveryStatus.safe);
        // NO or unclear: ask the original question again (counts as an attempt).
      }
    }
    if (_cancelled) return;
    _set(VoicePhase.gaveUp);
    await speak(strings.voiceGaveUp);
  }

  Future<String?> _listen() async {
    final words = await input.listen(localeId: _locale, listenFor: listenFor);
    if (words != null && words.trim().isNotEmpty) _heard.add(words.trim());
    return words;
  }

  /// e.g. `Confirmed by voice — heard: "I am safe" / "yes"` (each phrase capped at 40 characters).
  String _note(bool safe) {
    final base = safe ? 'Confirmed by voice' : 'Requested by voice';
    if (_heard.isEmpty) return base;
    final quoted = _heard.map((w) => '"${w.length > 40 ? '${w.substring(0, 40)}…' : w}"').join(' / ');
    return '$base — heard: $quoted';
  }

  Future<void> _deliver(String status) async {
    _set(VoicePhase.sending);
    final safe = status == DeliveryStatus.safe;
    final outcome = await send(status, _note(safe));
    if (_cancelled) return;
    switch (outcome) {
      case VoiceSendOutcome.delivered:
        _set(safe ? VoicePhase.sentSafe : VoicePhase.sentHelp);
        await speak(safe ? strings.voiceSafeSent : strings.voiceHelpSent);
      case VoiceSendOutcome.queued:
        _set(VoicePhase.queued);
        await speak(strings.voiceQueued);
      case VoiceSendOutcome.failed:
        _set(VoicePhase.gaveUp);
        await speak(strings.voiceGaveUp);
    }
  }

  /// Stop listening/speaking — e.g. the person tapped a button or left the screen.
  Future<void> cancel() async {
    if (!isRunning) return;
    _cancelled = true;
    await input.cancel();
    _set(VoicePhase.cancelled);
  }
}
