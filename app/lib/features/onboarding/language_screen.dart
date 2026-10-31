import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';

/// Two large language buttons. Selecting switches the UI instantly.
class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key, required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = Strings(selected);
    Widget option(String code, String label) {
      final on = selected == code;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          label: label,
          excludeSemantics: true,
          child: Material(
            color: on ? AppColors.redSoft : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: on ? AppColors.red : AppColors.outline, width: on ? 2 : 1),
            ),
            child: InkWell(
              key: Key('lang-$code'),
              borderRadius: BorderRadius.circular(16),
              onTap: () => onSelected(code),
              child: SizedBox(
                height: 72,
                child: Center(
                  child: Text(label,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: on ? AppColors.red : AppColors.ink)),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      option('en', s.english),
      const SizedBox(width: 12),
      option('hi', s.hindi),
    ]);
  }
}

/// Onboarding step: choose language (persisted locally and sent with `PATCH /me`).
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Icon(Icons.translate, size: 72, color: AppColors.red),
            const SizedBox(height: 16),
            Text(s.chooseLanguage,
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(s.languageNote, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray)),
            const SizedBox(height: 24),
            LanguagePicker(selected: app.lang, onSelected: (l) => app.setLanguage(l, syncServer: false, markChosen: false)),
            const Spacer(),
            FilledButton(
              key: const Key('language-continue'),
              onPressed: () => app.setLanguage(app.lang),
              child: Text(s.next),
            ),
          ]),
        ),
      ),
    );
  }
}
