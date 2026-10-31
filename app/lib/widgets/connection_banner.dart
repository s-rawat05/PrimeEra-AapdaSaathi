import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Online/offline/reconnecting banner + queued replies + last successful sync.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, this.showWhenOnline = false});

  final bool showWhenOnline;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final status = app.connectivity.status;
    final queued = app.queue.length;
    final error = app.queueError;

    if (status == ConnectionStatus.online && queued == 0 && error == null && !showWhenOnline) {
      return const SizedBox.shrink();
    }

    final (Color bg, Color fg, IconData icon, String text) = switch (status) {
      ConnectionStatus.offline => (AppColors.ink, Colors.white, Icons.cloud_off, s.offline),
      ConnectionStatus.reconnecting => (AppColors.amberSoft, AppColors.amber, Icons.sync, s.reconnecting),
      ConnectionStatus.online => (AppColors.greenSoft, AppColors.green, Icons.cloud_done, s.online),
    };
    final sync = app.lastSync == null ? s.neverSynced : s.lastSync(fmtTime(app.lastSync));

    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(icon, color: fg, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700))),
              const SizedBox(width: 8),
              Flexible(child: Text(sync, textAlign: TextAlign.end, style: TextStyle(color: fg, fontSize: 12))),
            ]),
            if (queued > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.schedule_send, color: fg, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.queuedCount(queued), style: TextStyle(color: fg))),
                ]),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Icon(Icons.error_outline, color: fg, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.queueFailed(error), style: TextStyle(color: fg))),
                  IconButton(
                    tooltip: s.close,
                    onPressed: app.clearQueueError,
                    icon: Icon(Icons.close, color: fg, size: 18),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}
