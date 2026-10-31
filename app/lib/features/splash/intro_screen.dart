import 'package:flutter/material.dart';

import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../onboarding/language_screen.dart';

/// Shown while the session is restored.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: AppColors.red,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.shield_moon, size: 96, color: Colors.white),
          const SizedBox(height: 16),
          Text(s.appName, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: Colors.white),
        ]),
      ),
    );
  }
}

/// Three-page introduction, shown once before sign-in.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.onDone});
  final VoidCallback onDone;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final pages = [
      (Icons.campaign, s.introTitle1, s.introBody1),
      (Icons.touch_app, s.introTitle2, s.introBody2),
      (Icons.volunteer_activism, s.introTitle3, s.introBody3),
    ];
    final last = _page == pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Row(children: [
              const Icon(Icons.shield_moon, color: AppColors.red, size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.appName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.red)),
              ),
              TextButton(onPressed: widget.onDone, child: Text(s.skip)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: LanguagePicker(selected: app.lang, onSelected: (l) => app.setLanguage(l)),
          ),
          Expanded(
            child: PageView(
              controller: _pages,
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                for (final (icon, title, body) in pages)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 160,
                        height: 160,
                        decoration: const BoxDecoration(color: AppColors.redSoft, shape: BoxShape.circle),
                        child: Icon(icon, size: 84, color: AppColors.red),
                      ),
                      const SizedBox(height: 32),
                      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Text(body, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.4)),
                    ]),
                  ),
              ],
            ),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < pages.length; i++)
              Container(
                width: i == _page ? 22 : 8,
                height: 8,
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: i == _page ? AppColors.red : AppColors.outline,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ]),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text(s.tagline, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('intro-next'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                onPressed: last
                    ? widget.onDone
                    : () => _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                child: Text(last ? s.getStarted : s.next),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
