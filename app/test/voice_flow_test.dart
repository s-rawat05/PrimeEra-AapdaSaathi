import 'package:aapda_saathi/accessibility/voice_input.dart';
import 'package:aapda_saathi/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

const en = Strings('en');
const visionModes = ['text_to_speech', 'voice_prompts', 'large_controls'];

void main() {
  testWidgets('blind resident: alarm rings, then voice "safe" + "yes" sends SAFE confirmed by voice', (tester) async {
    final api = FakeApi()..alerts = [alertJson(modes: visionModes)];
    final voice = ScriptedVoiceInput(['I am safe', 'yes']);
    final h = await pumpApp(tester, api: api, voice: voice, settleAfter: false);

    // The incoming alert opens the emergency screen with the alarm ringing; voice waits a few seconds.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(en.voiceRinging), findsOneWidget);
    expect(api.responds, isEmpty);

    await tester.pump(const Duration(seconds: 9));
    await settle(tester);

    expect(api.responds.single.$2, 'SAFE');
    expect(api.respondNotes.single, 'Confirmed by voice — heard: "I am safe" / "yes"');
    expect(h.effects.log.where((l) => l.startsWith('say:')).first, contains(en.voiceAsk));
    expect(h.effects.log, contains('say:${en.voiceConfirmSafe}'));
    expect(h.effects.log, contains('say:${en.voiceSafeSent}'));
    expect(find.text(en.safeConfirmedTitle), findsWidgets);
  });

  testWidgets('opened by hand: no auto-start, voice button offered, buttons still work without a voice note', (
    tester,
  ) async {
    final a = alertJson(modes: visionModes);
    final api = FakeApi()..alerts = [a];
    await pumpApp(tester, api: api, voice: ScriptedVoiceInput(['help']), announced: {'a:${a['delivery_id']}'});
    await tapVisible(tester, find.byKey(const Key('respond-now')));
    await settle(tester);

    expect(find.byKey(const Key('voice-start')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(api.responds, isEmpty); // nothing happens without the alarm or a tap

    await tapVisible(tester, find.byKey(const Key('btn-safe')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn-confirm')));
    await settle(tester);
    expect(api.responds.single.$2, 'SAFE');
    expect(api.respondNotes.single, isNull);
  });

  testWidgets('"Answer by voice" button: HELP is sent at once', (tester) async {
    final a = alertJson(modes: visionModes);
    final api = FakeApi()..alerts = [a];
    await pumpApp(tester, api: api, voice: ScriptedVoiceInput(['madad chahiye']), announced: {'a:${a['delivery_id']}'});
    await tapVisible(tester, find.byKey(const Key('respond-now')));
    await settle(tester);
    await tapVisible(tester, find.byKey(const Key('voice-start')));
    await settle(tester);
    expect(api.responds.single.$2, 'HELP');
    expect(api.respondNotes.single, 'Requested by voice — heard: "madad chahiye"');
  });

  testWidgets('no voice panel for residents without a vision profile', (tester) async {
    final a = alertJson(modes: ['flash_screen']);
    final api = FakeApi()..alerts = [a];
    await pumpApp(tester, api: api, voice: ScriptedVoiceInput([]), announced: {'a:${a['delivery_id']}'});
    await tapVisible(tester, find.byKey(const Key('respond-now')));
    await settle(tester);
    expect(find.byKey(const Key('voice-start')), findsNothing);
    expect(find.byKey(const Key('voice-status')), findsNothing);
  });
}
