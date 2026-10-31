import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../widgets/common.dart';

/// Resolves an alert by delivery id: from the live list if present, otherwise `GET /alerts/{id}`.
class AlertLoader extends StatefulWidget {
  const AlertLoader({super.key, required this.deliveryId, required this.builder});

  final String deliveryId;
  final Widget Function(BuildContext context, AlertOut alert) builder;

  @override
  State<AlertLoader> createState() => _AlertLoaderState();
}

class _AlertLoaderState extends State<AlertLoader> {
  AlertOut? _fetched;
  Object? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.app.alertById(widget.deliveryId) == null && _fetched == null && !_loading) _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final a = await context.appRead.call((api) => api.alert(widget.deliveryId));
      if (mounted) setState(() => _fetched = a);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final live = app.alertById(widget.deliveryId) ?? _fetched;
    if (live != null) return widget.builder(context, live);
    return Scaffold(
      appBar: AppBar(title: Text(app.s.alertTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _error != null
            ? ErrorPanel(message: errorText(_error!, app.s), onRetry: _fetch, s: app.s)
            : const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
