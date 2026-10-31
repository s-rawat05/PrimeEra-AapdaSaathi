import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import 'alert_detail_screen.dart';

/// `GET /alerts/history`.
class AlertHistoryScreen extends StatefulWidget {
  const AlertHistoryScreen({super.key});

  @override
  State<AlertHistoryScreen> createState() => _AlertHistoryScreenState();
}

class _AlertHistoryScreenState extends State<AlertHistoryScreen> {
  PageOut<AlertOut>? _page;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final app = context.appRead;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await app.call((api) => api.alertHistory());
      if (mounted) setState(() => _page = p);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = _page?.items ?? const <AlertOut>[];
    return Scaffold(
      appBar: AppBar(title: Text(s.alertHistory)),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 120), children: [
              if (_error != null) ErrorPanel(message: errorText(_error!, s), onRetry: _load, s: s),
              if (_loading && _page == null) const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
              if (!_loading && _error == null && items.isEmpty) EmptyState(icon: Icons.history, text: s.noHistory),
              for (final a in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: SectionCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AlertDetailScreen(deliveryId: a.deliveryId),
                    )),
                    child: Row(children: [
                      Pictogram(hazardIcon(a.presentation.pictogram), size: 48),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(a.presentation.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(fmtTime(a.alertedAt), style: const TextStyle(color: AppColors.gray)),
                          const SizedBox(height: 6),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            StatusChip(label: s.statusName(a.status), color: AppColors.forStatus(a.status)),
                            StatusChip(
                              label: a.isActiveIncident ? s.incidentActive : s.incidentClosed,
                              color: a.isActiveIncident ? AppColors.red : AppColors.gray,
                            ),
                            if (a.replyChannel != null)
                              StatusChip(label: s.repliedVia(a.replyChannel!), color: AppColors.gray),
                            if (a.isDemo) const DemoBadge(),
                          ]),
                        ]),
                      ),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
