/// Accessibility modes from `AlertOut.accessibility_modes`, applied as a union.
class AlertModes {
  AlertModes(Iterable<String> modes) : raw = Set.unmodifiable(modes.toSet());

  static final none = AlertModes(const []);

  /// Mirrors the server's NEED_MODES mapping so the UI adapts even before an alert arrives
  /// (e.g. large text for an elderly resident on the home screen).
  static const needModes = <String, List<String>>{
    'hearing': ['vibrate', 'flash_screen', 'torch_blink', 'large_text', 'pictograms'],
    'vision': ['text_to_speech', 'voice_prompts', 'large_controls'],
    'mobility': ['assistance_prompt'],
    'bedridden': ['assistance_prompt'],
    'cognitive': ['easy_read', 'pictograms', 'step_by_step', 'large_controls'],
    'elderly_alone': ['large_text', 'repeat_reminders', 'large_controls'],
    'speech': ['no_voice_response'],
    'feature_phone': ['sms_only'],
  };

  factory AlertModes.fromNeeds(Iterable<String> needs) => AlertModes([for (final n in needs) ...?needModes[n]]);

  final Set<String> raw;

  AlertModes union(AlertModes other) => AlertModes({...raw, ...other.raw});

  bool get vibrate => raw.contains('vibrate');
  bool get flashScreen => raw.contains('flash_screen');
  bool get torchBlink => raw.contains('torch_blink');
  bool get largeText => raw.contains('large_text');
  bool get pictograms => raw.contains('pictograms');
  bool get textToSpeech => raw.contains('text_to_speech');
  bool get voicePrompts => raw.contains('voice_prompts');
  bool get largeControls => raw.contains('large_controls');
  bool get assistancePrompt => raw.contains('assistance_prompt');
  bool get easyRead => raw.contains('easy_read');
  bool get stepByStep => raw.contains('step_by_step');
  bool get repeatReminders => raw.contains('repeat_reminders');
  bool get noVoiceResponse => raw.contains('no_voice_response');
  bool get smsOnly => raw.contains('sms_only');

  bool get speaks => textToSpeech || voicePrompts;

  /// Text scale applied on top of the user's system setting.
  double get textScale => largeText ? 1.3 : 1.0;

  /// Minimum height of primary action buttons.
  double get controlHeight => largeControls ? 96 : 72;
}
