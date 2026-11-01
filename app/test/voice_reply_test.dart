import 'package:aapda_saathi/accessibility/voice_input.dart';
import 'package:aapda_saathi/accessibility/voice_reply.dart';
import 'package:aapda_saathi/accessibility/voice_responder.dart';
import 'package:aapda_saathi/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('interpretAnswer', () {
    test('safe in English, Hindi and Hinglish', () {
      for (final t in [
        'safe',
        'I am safe',
        'Yes I am fine',
        'surakshit',
        'main theek hoon',
        'मैं सुरक्षित हूँ',
        'मैं सुरक्षित हूँ।',
        'ठीक हूँ',
        'सेफ',
      ]) {
        expect(interpretAnswer(t), VoiceIntent.safe, reason: t);
      }
    });

    test('help wins, including negated safe', () {
      for (final t in [
        'help',
        'Help me',
        'madad chahiye',
        'bachao',
        'मदद',
        'बचाओ',
        'not safe',
        'I am not safe',
        'surakshit nahi',
        'मैं सुरक्षित नहीं हूँ',
        'ठीक नहीं',
        'safe help',
        'unsafe',
      ]) {
        expect(interpretAnswer(t), VoiceIntent.help, reason: t);
      }
    });

    test('silence, noise and unrelated speech are never safe', () {
      for (final t in [null, '', '   ', 'hello', 'what', 'kahan ho', 'कहाँ']) {
        expect(interpretAnswer(t), VoiceIntent.unknown, reason: '$t');
      }
    });
  });

  group('interpretConfirmation', () {
    test('yes / no / help', () {
      for (final t in ['yes', 'yeah', 'haan', 'हाँ', 'हां', 'yes confirm', 'सही']) {
        expect(interpretConfirmation(t), VoiceIntent.yes, reason: t);
      }
      for (final t in ['no', 'nahi', 'नहीं', 'cancel', 'galat']) {
        expect(interpretConfirmation(t), VoiceIntent.no, reason: t);
      }
      expect(interpretConfirmation('no help me'), VoiceIntent.help);
      expect(interpretConfirmation('मदद'), VoiceIntent.help);
    });

    test('unclear or contradictory confirmation is not a yes', () {
      for (final t in [null, '', 'maybe', 'yes no', 'कहाँ', 'जीवन']) {
        expect(interpretConfirmation(t), VoiceIntent.unknown, reason: '$t');
      }
    });
  });

  group('VoiceResponder', () {
    late List<String> said;
    late List<(String, String)> sent;
    late bool alarmStopped;
    late VoiceSendOutcome outcome;

    VoiceResponder make(ScriptedVoiceInput input, {String lang = 'en'}) => VoiceResponder(
      input: input,
      strings: Strings(lang),
      speak: (t) async => said.add(t),
      stopAlarm: () async => alarmStopped = true,
      send: (status, note) async {
        sent.add((status, note));
        return outcome;
      },
      alarmDuration: Duration.zero,
    );

    setUp(() {
      said = [];
      sent = [];
      alarmStopped = false;
      outcome = VoiceSendOutcome.delivered;
    });

    test('HELP is sent immediately, without a confirmation step', () async {
      final v = make(ScriptedVoiceInput(['help me']));
      await v.run(intro: 'Flood alert');
      expect(sent, [('HELP', 'Requested by voice — heard: "help me"')]);
      expect(v.phase, VoicePhase.sentHelp);
      expect(alarmStopped, isTrue);
      expect(said.first, startsWith('Flood alert. Are you safe?'));
      expect(said.last, Strings('en').voiceHelpSent);
    });

    test('SAFE needs a spoken YES', () async {
      final v = make(ScriptedVoiceInput(['I am safe', 'yes']));
      await v.run();
      expect(sent, [('SAFE', 'Confirmed by voice — heard: "I am safe" / "yes"')]);
      expect(v.phase, VoicePhase.sentSafe);
      expect(said, contains(Strings('en').voiceConfirmSafe));
    });

    test('SAFE then NO asks again; silence after that gives up and sends nothing', () async {
      final v = make(ScriptedVoiceInput(['safe', 'no', null]));
      await v.run();
      expect(sent, isEmpty);
      expect(v.phase, VoicePhase.gaveUp);
      expect(said.last, Strings('en').voiceGaveUp);
    });

    test('silence twice never marks anyone safe', () async {
      final v = make(ScriptedVoiceInput([null, null]));
      await v.run();
      expect(sent, isEmpty);
      expect(v.phase, VoicePhase.gaveUp);
    });

    test('second attempt can succeed', () async {
      final v = make(ScriptedVoiceInput(['umm', 'safe', 'haan']));
      await v.run();
      expect(sent, [('SAFE', 'Confirmed by voice — heard: "umm" / "safe" / "haan"')]);
    });

    test('note quotes what was heard, capped so it fits the server limit', () async {
      final long = 'help ${'please come quickly ' * 10}';
      final v = make(ScriptedVoiceInput([long]));
      await v.run();
      final note = sent.single.$2;
      expect(note, startsWith('Requested by voice — heard: "help please'));
      expect(note.length, lessThan(300));
    });

    test('HELP during the confirmation step is sent as HELP', () async {
      final v = make(ScriptedVoiceInput(['safe', 'no, help']));
      await v.run();
      expect(sent, [('HELP', 'Requested by voice — heard: "safe" / "no, help"')]);
    });

    test('no microphone: alarm keeps ringing, nothing is sent', () async {
      final v = make(ScriptedVoiceInput(['safe', 'yes'], available: false));
      await v.run();
      expect(v.phase, VoicePhase.unavailable);
      expect(alarmStopped, isFalse);
      expect(sent, isEmpty);
    });

    test('offline: reply is queued and the person is told so', () async {
      outcome = VoiceSendOutcome.queued;
      final v = make(ScriptedVoiceInput(['help']));
      await v.run();
      expect(v.phase, VoicePhase.queued);
      expect(said.last, Strings('en').voiceQueued);
    });

    test('Hindi profile listens in Hindi and speaks Hindi', () async {
      final input = ScriptedVoiceInput(['सुरक्षित', 'हाँ']);
      final v = make(input, lang: 'hi');
      await v.run();
      expect(input.localesHeard, everyElement('hi_IN'));
      expect(said.first, Strings('hi').voiceAsk);
      expect(sent.single.$1, 'SAFE');
    });

    test('cancelling (a button was tapped) stops the flow before anything is sent', () async {
      final v = VoiceResponder(
        input: ScriptedVoiceInput(['safe', 'yes']),
        strings: Strings('en'),
        speak: (t) async => said.add(t),
        stopAlarm: () async => alarmStopped = true,
        send: (s, n) async {
          sent.add((s, n));
          return VoiceSendOutcome.delivered;
        },
        alarmDuration: const Duration(milliseconds: 50),
      );
      final running = v.run();
      await v.cancel();
      await running;
      expect(v.phase, VoicePhase.cancelled);
      expect(sent, isEmpty);
    });
  });
}
