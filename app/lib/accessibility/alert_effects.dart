import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:torch_light/torch_light.dart';
import 'package:vibration/vibration.dart';

import 'modes.dart';

/// Sensory effects for an incoming alert: alarm sound, vibration, torch blink, screen flash and
/// speech. Modes come from `AlertOut.accessibility_modes` and are applied as a UNION.
///
/// Every hardware call is guarded: an unavailable capability is skipped, never a crash.
abstract class AlertEffects {
  /// True while the high-contrast flashing overlay should be shown.
  final ValueNotifier<bool> flashing = ValueNotifier(false);

  /// True while any effect (sound/vibration/torch/flash/repeat) is running.
  final ValueNotifier<bool> active = ValueNotifier(false);

  Future<void> start(AlertModes modes, {required List<String> speech, required String ttsLocale});
  Future<void> speak(List<String> lines, String ttsLocale);
  Future<void> stop();

  /// Stops only the flashing overlay (the user asked to stop it); other effects continue.
  void stopFlash() => flashing.value = false;
}

/// Test/no-op implementation that only records what it was asked to do.
class RecordingAlertEffects extends AlertEffects {
  final List<String> log = [];

  @override
  Future<void> start(AlertModes modes, {required List<String> speech, required String ttsLocale}) async {
    log.add('start:${modes.raw.join(',')}');
    active.value = true;
    flashing.value = modes.flashScreen;
  }

  @override
  Future<void> speak(List<String> lines, String ttsLocale) async => log.add('speak:${lines.length}');

  @override
  Future<void> stop() async {
    log.add('stop');
    active.value = false;
    flashing.value = false;
  }
}

class DeviceAlertEffects extends AlertEffects {
  AudioPlayer? _player;
  FlutterTts? _tts;
  Timer? _torchTimer;
  Timer? _repeatTimer;
  Timer? _autoStop;
  bool _torchOn = false;
  bool _torchUsable = true;

  static const _vibrationPattern = [0, 800, 400, 800, 400, 800, 1200];

  @override
  Future<void> start(AlertModes modes, {required List<String> speech, required String ttsLocale}) async {
    await stop();
    active.value = true;
    flashing.value = modes.flashScreen;

    // Alarm sound for everyone; loops until acknowledged when repeat_reminders is on.
    await _playAlarm(loop: true);

    if (modes.vibrate || modes.repeatReminders) await _vibrate();
    if (modes.torchBlink) _startTorch();
    if (modes.speaks) await speak(speech, ttsLocale);

    if (modes.repeatReminders) {
      // Re-alert every 30 s until the person responds or taps "Stop alarm".
      _repeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
        await _vibrate();
        if (modes.speaks) await speak(speech, ttsLocale);
      });
    } else {
      // Without repeat reminders, stop sound/torch after one minute; the alert screen stays open.
      _autoStop = Timer(const Duration(minutes: 1), () {
        _player?.stop();
        _stopTorch();
      });
    }
  }

  Future<void> _playAlarm({required bool loop}) async {
    try {
      final p = _player ??= AudioPlayer();
      await p.setAsset('assets/sounds/alarm.wav');
      await p.setLoopMode(loop ? LoopMode.one : LoopMode.off);
      await p.setVolume(1.0);
      unawaited(p.play());
    } catch (e) {
      debugPrint('Alarm sound unavailable: $e');
    }
  }

  Future<void> _vibrate() async {
    if (kIsWeb) return;
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: _vibrationPattern);
      }
    } catch (e) {
      debugPrint('Vibration unavailable: $e');
    }
  }

  void _startTorch() {
    if (kIsWeb || !_torchUsable) return;
    () async {
      try {
        if (!await TorchLight.isTorchAvailable()) {
          _torchUsable = false;
          return;
        }
      } catch (_) {
        _torchUsable = false;
        return;
      }
      _torchTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          if (_torchOn) {
            await TorchLight.disableTorch();
          } else {
            await TorchLight.enableTorch();
          }
          _torchOn = !_torchOn;
        } catch (e) {
          // Camera in use / permission denied: stop trying for this alert.
          _torchTimer?.cancel();
          debugPrint('Torch unavailable: $e');
        }
      });
    }();
  }

  void _stopTorch() {
    _torchTimer?.cancel();
    _torchTimer = null;
    if (_torchOn && !kIsWeb) {
      TorchLight.disableTorch().catchError((_) {});
    }
    _torchOn = false;
  }

  @override
  Future<void> speak(List<String> lines, String ttsLocale) async {
    final text = lines.where((l) => l.trim().isNotEmpty).join('. ');
    if (text.isEmpty) return;
    try {
      final tts = _tts ??= FlutterTts();
      await tts.setLanguage(ttsLocale);
      await tts.setSpeechRate(kIsWeb ? 0.9 : 0.45);
      await tts.stop();
      await tts.speak(text);
    } catch (e) {
      debugPrint('Text-to-speech unavailable: $e');
    }
  }

  @override
  Future<void> stop() async {
    _repeatTimer?.cancel();
    _autoStop?.cancel();
    _stopTorch();
    try {
      await _player?.stop();
    } catch (_) {}
    try {
      await _tts?.stop();
    } catch (_) {}
    if (!kIsWeb) {
      try {
        await Vibration.cancel();
      } catch (_) {}
    }
    flashing.value = false;
    active.value = false;
  }
}
