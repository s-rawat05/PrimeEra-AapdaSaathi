import 'dart:async';

import 'package:flutter/material.dart';

import '../accessibility/alert_effects.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';

/// High-contrast red/white flashing overlay for people who may not hear an alarm.
/// Always stoppable with a large button. Wraps the whole app (MaterialApp.builder).
class FlashOverlay extends StatefulWidget {
  const FlashOverlay({super.key, required this.effects, required this.strings, required this.child});

  final AlertEffects effects;
  final Strings strings;
  final Widget child;

  @override
  State<FlashOverlay> createState() => _FlashOverlayState();
}

class _FlashOverlayState extends State<FlashOverlay> {
  Timer? _timer;
  bool _red = true;

  @override
  void initState() {
    super.initState();
    widget.effects.flashing.addListener(_onChange);
    _onChange();
  }

  @override
  void didUpdateWidget(covariant FlashOverlay old) {
    super.didUpdateWidget(old);
    if (old.effects != widget.effects) {
      old.effects.flashing.removeListener(_onChange);
      widget.effects.flashing.addListener(_onChange);
    }
  }

  void _onChange() {
    final on = widget.effects.flashing.value;
    _timer?.cancel();
    if (on) {
      _timer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        if (mounted) setState(() => _red = !_red);
      });
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.effects.flashing.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.effects.flashing.value;
    return Stack(children: [
      widget.child,
      if (on)
        Positioned.fill(
          child: Material(
            color: _red ? AppColors.red : Colors.white,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.warning_rounded, size: 120, color: _red ? Colors.white : AppColors.red),
                    const SizedBox(height: 16),
                    Text(
                      widget.strings.activeAlert.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: _red ? Colors.white : AppColors.red,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Semantics(
                      button: true,
                      label: widget.strings.stopAlarm,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.ink,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(260, 80),
                          textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        onPressed: widget.effects.stopFlash,
                        icon: const Icon(Icons.touch_app, size: 32),
                        label: Text(widget.strings.stopAlarm),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}
