import 'package:flutter/material.dart';

import '../../services/device_services.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// "Reply by SMS": opens the phone's SMS app with 1 (SAFE) or 2 (HELP) filled in.
/// The user must press Send; delivery is not guaranteed and we never mark it as delivered.
class SmsReplyPanel extends StatelessWidget {
  const SmsReplyPanel({super.key, this.hint});

  /// `sms_reply_hint` from the alert, e.g. "SMS 1 = SAFE, 2 = HELP".
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final number = app.config.smsGatewayNumber;

    Future<void> open(String body) async {
      final ok = await app.launcher.open(Links.sms(number, body));
      if (!ok && context.mounted) showSnack(context, s.couldNotOpen, error: true);
    }

    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.sms, color: AppColors.gray),
          const SizedBox(width: 8),
          Expanded(child: Text(s.replyBySms, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
        ]),
        if (hint != null && hint!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(hint!, style: const TextStyle(fontSize: 15)),
        ],
        const SizedBox(height: 4),
        Text(s.smsNotGuaranteed, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
        if (number.isEmpty) ...[
          const SizedBox(height: 4),
          Text(s.noSmsGateway, style: const TextStyle(color: AppColors.amber, fontSize: 13)),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: '${s.replyBySms}: 1 = ${s.iAmSafe}',
              excludeSemantics: true,
              child: OutlinedButton(
                key: const Key('sms-safe'),
                onPressed: () => open('1'),
                child: Text('SMS 1 · ${s.statusName('SAFE')}'),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              button: true,
              label: '${s.replyBySms}: 2 = ${s.iNeedHelp}',
              excludeSemantics: true,
              child: OutlinedButton(
                key: const Key('sms-help'),
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                onPressed: () => open('2'),
                child: Text('SMS 2 · ${s.statusName('HELP')}'),
              ),
            ),
          ),
        ]),
      ]),
    );
  }
}
