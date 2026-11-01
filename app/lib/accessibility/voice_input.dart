import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Speech recognition behind an interface so the voice reply flow can be tested without a microphone.
abstract class VoiceInput {
  /// Initialise the recogniser (asks for microphone permission the first time). False = unavailable.
  Future<bool> ensureReady();

  /// Listen once and return the recognised words, or null on silence / error / timeout.
  Future<String?> listen({required String localeId, required Duration listenFor});

  Future<void> cancel();
}

class DeviceVoiceInput implements VoiceInput {
  final SpeechToText _stt = SpeechToText();
  bool? _ready;
  Completer<String?>? _pending;
  String _lastWords = '';

  @override
  Future<bool> ensureReady() async {
    if (_ready == true) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) => _finish(null),
        onStatus: (status) {
          // 'done' / 'notListening' arrive when the recogniser ends without a final result.
          if (status == SpeechToText.doneStatus || status == SpeechToText.notListeningStatus) {
            _finish(_lastWords.isEmpty ? null : _lastWords);
          }
        },
      );
    } catch (e) {
      debugPrint('Speech recognition unavailable: $e');
      _ready = false;
    }
    return _ready!;
  }

  void _finish(String? words) {
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(words);
  }

  @override
  Future<String?> listen({required String localeId, required Duration listenFor}) async {
    if (!await ensureReady()) return null;
    _lastWords = '';
    final c = _pending = Completer<String?>();
    try {
      await _stt.listen(
        onResult: (r) {
          _lastWords = r.recognizedWords;
          if (r.finalResult) _finish(r.recognizedWords);
        },
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenFor: listenFor,
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (e) {
      debugPrint('Speech listen failed: $e');
      _finish(null);
    }
    // Hard stop in case the platform never reports completion.
    return c.future.timeout(
      listenFor + const Duration(seconds: 3),
      onTimeout: () {
        _stt.stop();
        return _lastWords.isEmpty ? null : _lastWords;
      },
    );
  }

  @override
  Future<void> cancel() async {
    _finish(null);
    try {
      await _stt.cancel();
    } catch (_) {}
  }
}

/// Test double: returns scripted transcripts in order (null = silence).
class ScriptedVoiceInput implements VoiceInput {
  ScriptedVoiceInput(List<String?> script, {this.available = true}) : _script = List.of(script);

  final List<String?> _script;
  final bool available;
  final List<String> localesHeard = [];
  bool cancelled = false;

  @override
  Future<bool> ensureReady() async => available;

  @override
  Future<String?> listen({required String localeId, required Duration listenFor}) async {
    localesHeard.add(localeId);
    return _script.isEmpty ? null : _script.removeAt(0);
  }

  @override
  Future<void> cancel() async => cancelled = true;
}
