import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// A large single-choice row (used instead of radio buttons for bigger touch targets).
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? AppColors.redSoft : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: selected ? AppColors.red : AppColors.outline, width: selected ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: selected ? AppColors.red : AppColors.gray),
                const SizedBox(width: 12),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accept a task. Returns the updated task, or null on failure (a snackbar explains why).
Future<TaskOut?> acceptTask(BuildContext context, TaskOut task) async {
  final app = context.appRead;
  try {
    final t = await app.call((api) => api.acceptTask(task.id));
    if (context.mounted) showSnack(context, app.s.taskStatusName(t.status));
    await app.refresh();
    return t;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
    return null;
  }
}

/// "I can't go": reason is required; note optional. Returns the updated task or null.
Future<TaskOut?> showCantGoSheet(BuildContext context, TaskOut task) {
  return showModalBottomSheet<TaskOut>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CantGoSheet(task: task),
  );
}

class _CantGoSheet extends StatefulWidget {
  const _CantGoSheet({required this.task});
  final TaskOut task;

  @override
  State<_CantGoSheet> createState() => _CantGoSheetState();
}

class _CantGoSheetState extends State<_CantGoSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _busy = false;
  bool _triedWithoutReason = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _triedWithoutReason = true);
      return;
    }
    final app = context.appRead;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await app.call((api) => api.cantGo(widget.task.id, _reason!, note: _note.text.trim()));
      await app.refresh();
      if (mounted) Navigator.of(context).pop(t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.cantGoTitle, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final r in kCantGoReasons)
            ChoiceTile(
              key: Key('reason-$r'),
              label: s.reasonName(r),
              selected: _reason == r,
              onTap: () => setState(() {
                _reason = r;
                _triedWithoutReason = false;
              }),
            ),
          if (_triedWithoutReason)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(s.chooseReason, key: const Key('reason-required'), style: const TextStyle(color: AppColors.redDark)),
            ),
          TextField(controller: _note, maxLength: 300, decoration: InputDecoration(labelText: s.optionalNote)),
          if (_error != null) ErrorPanel(message: _error!, s: s),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('cant-go-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? s.sending : s.submit),
          ),
        ]),
      ),
    );
  }
}

/// "I have reached": outcome required; note required for needs_rescue / not_found.
Future<TaskOut?> showReachedSheet(BuildContext context, TaskOut task) {
  return showModalBottomSheet<TaskOut>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReachedSheet(task: task),
  );
}

class _ReachedSheet extends StatefulWidget {
  const _ReachedSheet({required this.task});
  final TaskOut task;

  @override
  State<_ReachedSheet> createState() => _ReachedSheetState();
}

class _ReachedSheetState extends State<_ReachedSheet> {
  String? _outcome;
  final _note = TextEditingController();
  bool _busy = false;
  String? _validation;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.s;
    if (_outcome == null) {
      setState(() => _validation = s.chooseReason);
      return;
    }
    if (kReachedNeedsNote.contains(_outcome) && _note.text.trim().isEmpty) {
      setState(() => _validation = s.noteRequiredForOutcome);
      return;
    }
    final app = context.appRead;
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
    });
    try {
      final t = await app.call((api) => api.reached(widget.task.id, _outcome!, note: _note.text.trim()));
      await app.refresh();
      if (mounted) Navigator.of(context).pop(t);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final needsNote = _outcome != null && kReachedNeedsNote.contains(_outcome);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(s.reachedOutcome, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          for (final o in kReachedOutcomes)
            ChoiceTile(
              key: Key('outcome-$o'),
              label: s.outcomeName(o),
              selected: _outcome == o,
              onTap: () => setState(() {
                _outcome = o;
                _validation = null;
              }),
            ),
          TextField(
            key: const Key('reached-note'),
            controller: _note,
            maxLength: 300,
            decoration: InputDecoration(labelText: needsNote ? s.requiredNote : s.optionalNote),
          ),
          if (_validation != null)
            Text(_validation!, key: const Key('reached-validation'), style: const TextStyle(color: AppColors.redDark)),
          if (_error != null) ErrorPanel(message: _error!, s: s),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('reached-submit'),
            onPressed: _busy ? null : _submit,
            child: Text(_busy ? s.sending : s.submit),
          ),
        ]),
      ),
    );
  }
}
