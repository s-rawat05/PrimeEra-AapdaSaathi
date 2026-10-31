import 'package:flutter/material.dart';

import '../core/api_error.dart';
import '../theme/app_theme.dart';
import 'format.dart';

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.color, this.icon, this.filled = false, this.tooltip, this.dense = false});

  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  final String? tooltip;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 10, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: dense ? 12 : 14, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: dense ? 11 : 12, letterSpacing: 0.2),
          ),
        ),
      ]),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) => Pill(
        statusLabel(status).toUpperCase(),
        color: AppColors.status(status),
        icon: statusIcon(status),
        filled: true,
        dense: dense,
      );
}

class TaskStatusChip extends StatelessWidget {
  const TaskStatusChip(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) =>
      Pill(status.replaceAll('_', ' '), color: AppColors.taskStatus(status), dense: true);
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 16),
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(children: [
            if (icon != null) ...[Icon(icon, size: 20, color: AppColors.primary), const SizedBox(width: 8)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (subtitle != null)
                  Text(subtitle!, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ]),
            ),
            ?trailing,
          ]),
        ),
        Flexible(child: Padding(padding: padding, child: child)),
      ]),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner(this.text, {super.key, this.color = AppColors.info, this.icon = Icons.info_outline, this.action});

  final String text;
  final Color color;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color.withValues(alpha: 0.95), fontSize: 13))),
          ?action,
        ]),
      );
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => InfoBanner(
        errorText(error),
        color: AppColors.help,
        icon: Icons.error_outline,
        action: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('Retry')),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppColors.muted, size: 32),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
        ]),
      );
}

class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.valueWidget, this.labelWidth = 150});

  final String label;
  final String? value;
  final Widget? valueWidget;
  final double labelWidth;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: valueWidget ??
                SelectableText(value == null || value!.isEmpty ? '—' : value!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      );
}

/// Loads a future and renders loading / error (with retry) / data.
class AsyncBuilder<T> extends StatefulWidget {
  const AsyncBuilder({super.key, required this.load, required this.builder});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, VoidCallback reload) builder;

  @override
  State<AsyncBuilder<T>> createState() => _AsyncBuilderState<T>();
}

class _AsyncBuilderState<T> extends State<AsyncBuilder<T>> {
  late Future<T> _future = widget.load();

  void _reload() => setState(() => _future = widget.load());

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return ErrorPanel(error: snap.error!, onRetry: _reload);
          if (!snap.hasData && snap.connectionState != ConnectionState.done) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          }
          return widget.builder(context, snap.data as T, _reload);
        },
      );
}

// ----------------------------------------------------------------------------- feedback helpers
void showSnack(BuildContext context, String message, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? AppColors.primaryDark : const Color(0xFF1F2937),
    duration: Duration(seconds: error ? 6 : 3),
  ));
}

/// Runs a backend action, shows the backend's error message (e.g. 409 conflicts) on failure.
/// Returns the result or null on failure.
Future<T?> runAction<T>(BuildContext context, Future<T> Function() action, {String? success}) async {
  try {
    final result = await action();
    if (success != null && context.mounted) showSnack(context, success);
    return result;
  } catch (e) {
    if (context.mounted) {
      final prefix = e is ApiException && e.statusCode > 0 ? '${e.statusCode} · ' : '';
      showSnack(context, '$prefix${errorText(e)}', error: true);
    }
    return null;
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppColors.primaryDark) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Asks for a free-text reason with a minimum length (backend rule: usually ≥ 5 chars).
Future<String?> reasonDialog(
  BuildContext context, {
  required String title,
  String? message,
  String label = 'Reason',
  String confirmLabel = 'Submit',
  int minLength = 5,
  int maxLength = 500,
  bool destructive = false,
}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _ReasonDialog(
        title: title,
        message: message,
        label: label,
        confirmLabel: confirmLabel,
        minLength: minLength,
        maxLength: maxLength,
        destructive: destructive,
      ),
    );

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.label,
    required this.confirmLabel,
    required this.minLength,
    required this.maxLength,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String label;
  final String confirmLabel;
  final int minLength;
  final int maxLength;
  final bool destructive;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_form.currentState!.validate()) Navigator.pop(context, _ctrl.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 440,
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.message != null) ...[Text(widget.message!), const SizedBox(height: 12)],
              TextFormField(
                key: const Key('reason-field'),
                controller: _ctrl,
                autofocus: true,
                maxLines: 3,
                maxLength: widget.maxLength,
                decoration: InputDecoration(labelText: widget.label, helperText: 'At least ${widget.minLength} characters'),
                validator: (v) => (v ?? '').trim().length < widget.minLength
                    ? '${widget.label} must be at least ${widget.minLength} characters'
                    : null,
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('reason-submit'),
            style: widget.destructive ? FilledButton.styleFrom(backgroundColor: AppColors.primaryDark) : null,
            onPressed: _submit,
            child: Text(widget.confirmLabel),
          ),
        ],
      );
}

/// Page header used by admin pages.
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 12,
          children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              if (subtitle != null) Text(subtitle!, style: const TextStyle(color: AppColors.muted)),
            ]),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ),
      );
}

/// Scrollable padded page body for admin pages.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: children,
      );
}

/// Wraps a form dialog with consistent sizing and a busy-aware submit button.
class FormDialog extends StatefulWidget {
  const FormDialog({
    super.key,
    required this.title,
    required this.builder,
    required this.onSubmit,
    this.submitLabel = 'Save',
    this.width = 520,
  });

  final String title;
  final List<Widget> Function(BuildContext context, StateSetter setState) builder;

  /// Returns a result to pop with; throw to show the error inline.
  final Future<Object?> Function() onSubmit;
  final String submitLabel;
  final double width;

  @override
  State<FormDialog> createState() => _FormDialogState();
}

class _FormDialogState extends State<FormDialog> {
  final _form = GlobalKey<FormState>();
  bool _busy = false;
  Object? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await widget.onSubmit();
      if (mounted) Navigator.pop(context, r ?? true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: widget.width,
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ...widget.builder(context, setState),
                if (_error != null) ...[const SizedBox(height: 12), ErrorPanel(error: _error!)],
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(widget.submitLabel),
          ),
        ],
      );
}

const gap8 = SizedBox(height: 8, width: 8);
const gap12 = SizedBox(height: 12, width: 12);
const gap16 = SizedBox(height: 16, width: 16);

String? requiredText(String? v, {int min = 1, String field = 'This field'}) =>
    (v ?? '').trim().length < min ? (min <= 1 ? '$field is required' : '$field needs at least $min characters') : null;

String? numberIn(String? v, {required double min, required double max, bool required = true, String field = 'Value'}) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return required ? '$field is required' : null;
  final n = double.tryParse(s);
  if (n == null) return '$field must be a number';
  if (n < min || n > max) return '$field must be between ${min.toStringAsFixed(min % 1 == 0 ? 0 : 1)} and ${max.toStringAsFixed(max % 1 == 0 ? 0 : 1)}';
  return null;
}

String shortRelative(DateTime? t) => fmtRelative(t);
