import 'package:flutter/material.dart';

import '../../core/realtime.dart';
import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../demo_controls/demo_panel.dart';
import '../demo_controls/sms_simulator.dart';
import '../dispatch/case_panel.dart';
import '../dispatch/tasks_panel.dart';
import '../incidents/feed_panel.dart';
import '../incidents/incident_dialogs.dart';
import '../incidents/timeline_panel.dart';
import '../live_map/incident_map.dart';
import '../reports/report_page.dart';
import 'command_centre_controller.dart';
import 'incident_summary.dart';
import 'priority_list.dart';

/// The live command centre — the main demo screen.
class CommandCentrePage extends StatelessWidget {
  const CommandCentrePage({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cc = controller;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          CommandHeader(controller: cc),
          const Divider(),
          Expanded(child: _body(context, cc)),
        ]);
      },
    );
  }

  Widget _body(BuildContext context, CommandCentreController cc) {
    if (cc.initialLoad && cc.incident == null) return const Center(child: CircularProgressIndicator());
    final inc = cc.incident;
    final tools = ToolsPanel(controller: cc);
    if (inc == null) {
      return LayoutBuilder(builder: (context, c) {
        final noIncident = Column(mainAxisSize: MainAxisSize.min, children: [
          if (cc.errors['incidents'] != null) ErrorPanel(error: cc.errors['incidents']!, onRetry: cc.refreshAll),
          if (cc.errors['incident'] != null) ErrorPanel(error: cc.errors['incident']!, onRetry: cc.refreshIncident),
          const EmptyState('No active incident.\nStart a drill from Demo controls, replay a SACHET alert, '
              'or create a manual incident.', icon: Icons.shield_moon_outlined),
        ]);
        if (c.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Padding(padding: const EdgeInsets.all(16), child: noIncident)),
            SizedBox(width: 440, child: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: tools)),
          ]);
        }
        return ListView(padding: const EdgeInsets.all(12), children: [
          noIncident,
          SizedBox(height: 640, child: tools),
        ]);
      });
    }

    void openCase(String deliveryId) => openCasePanel(context, cc, deliveryId);

    final summary = IncidentSummaryCard(incident: inc);
    final counters = CountersRow(counts: inc.counts);
    final map = SectionCard(
      title: 'Live map',
      icon: Icons.map_outlined,
      subtitle: '${cc.map?.markers.length ?? 0} residents · ${cc.map?.volunteers.length ?? 0} volunteers · '
          '${cc.map?.shelters.length ?? 0} relief posts — click a resident to open the case',
      child: cc.errors['map'] != null
          ? ErrorPanel(error: cc.errors['map']!, onRetry: cc.refreshIncident)
          : cc.map == null
              ? const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))
              : IncidentMapView(key: ValueKey('map-${inc.id}'), data: cc.map!, onOpenCase: openCase),
    );
    final tasks = TasksPanel(
      api: cc.api,
      tasks: cc.tasks,
      error: cc.errors['tasks'],
      incidentActive: inc.isActive,
      onChanged: cc.refreshIncident,
      onOpenCase: openCase,
    );
    final timeline = SectionCard(
      title: 'Incident timeline',
      icon: Icons.timeline,
      subtitle: '${cc.timeline.length} events (newest first)',
      child: cc.errors['timeline'] != null
          ? ErrorPanel(error: cc.errors['timeline']!, onRetry: cc.refreshIncident)
          : TimelineList(events: cc.timeline, maxItems: 60),
    );
    PriorityListPanel priority() => PriorityListPanel(
          items: cc.priority,
          error: cc.errors['priority'],
          onRetry: cc.refreshIncident,
          onOpen: (p) => openCase(p.deliveryId),
        );
    final incidentError = cc.errors['incident'];

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      if (w >= 1500) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (incidentError != null) ...[ErrorPanel(error: incidentError, onRetry: cc.refreshIncident), gap12],
              summary,
              gap12,
              counters,
              gap12,
              map,
              gap12,
              tasks,
              gap12,
              timeline,
            ]),
          ),
          SizedBox(width: 430, child: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 12, 16), child: priority())),
          SizedBox(width: 400, child: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: tools)),
        ]);
      }
      if (w >= 1000) {
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (incidentError != null) ...[ErrorPanel(error: incidentError, onRetry: cc.refreshIncident), gap12],
              summary,
              gap12,
              counters,
              gap12,
              map,
              gap12,
              tasks,
              gap12,
              SizedBox(height: 620, child: tools),
              gap12,
              timeline,
            ]),
          ),
          SizedBox(width: 420, child: Padding(padding: const EdgeInsets.fromLTRB(0, 16, 16, 16), child: priority())),
        ]);
      }
      return ListView(padding: const EdgeInsets.all(12), children: [
        if (incidentError != null) ...[ErrorPanel(error: incidentError, onRetry: cc.refreshIncident), gap12],
        summary,
        gap12,
        counters,
        gap12,
        SizedBox(height: 620, child: priority()),
        gap12,
        map,
        gap12,
        tasks,
        gap12,
        SizedBox(height: 620, child: tools),
        gap12,
        timeline,
      ]);
    });
  }
}

/// Header: incident selector, DEMO/DRILL + source badges, feed health, safety switch, realtime status, actions.
class CommandHeader extends StatelessWidget {
  const CommandHeader({super.key, required this.controller});

  final CommandCentreController controller;

  Future<void> _close(BuildContext context, Incident inc) async {
    final closed = await showCloseIncidentDialog(context, controller.api, inc);
    if (closed == null || !context.mounted) return;
    showSnack(context, 'Incident closed. Opening the closing report…');
    await controller.refreshAll();
    if (context.mounted) await openReport(context, controller.api, closed.id);
  }

  @override
  Widget build(BuildContext context) {
    final cc = controller;
    final services = context.services;
    final me = services.auth.me;
    final inc = cc.incident;
    final notifyReal = cc.feedStatus?.notifyRealResidents ?? cc.demoStatus?.notifyRealResidents ?? me?.notifyRealResidents ?? false;
    final demoMode = cc.demoStatus?.demoModeEnabled ?? me?.demoMode ?? false;
    final showDrill = (inc?.isDemo ?? false) || demoMode;
    final incidents = cc.selectableIncidents;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('Command centre', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            if (showDrill)
              Container(
                key: const Key('drill-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: AppColors.drill, borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.theater_comedy, color: Colors.white, size: 18),
                  SizedBox(width: 6),
                  Text('DEMO / DRILL',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1)),
                ]),
              ),
            if (inc != null)
              Pill(
                inc.sourceTag,
                key: const Key('source-badge'),
                color: inc.source == 'live' ? AppColors.live : (inc.source == 'manual' ? AppColors.info : AppColors.drill),
                filled: inc.source == 'live',
                icon: inc.source == 'live' ? Icons.sensors : Icons.replay_circle_filled_outlined,
                tooltip: inc.sourceLabel,
              ),
            if (incidents.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, minWidth: 200),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    key: const Key('incident-selector'),
                    isExpanded: true,
                    value: incidents.any((i) => i.id == cc.selectedId) ? cc.selectedId : null,
                    hint: const Text('Select incident'),
                    items: [
                      for (final i in incidents)
                        DropdownMenuItem(
                          value: i.id,
                          child: Text(
                            '${i.isDemo ? '[DEMO] ' : ''}${i.hazardType} · ${i.wards.map((w) => w.wardName).join(', ')}'
                            '${i.isActive ? '' : ' (closed)'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: cc.select,
                  ),
                ),
              ),
            if (cc.activeIncidents.length > 1)
              Pill('${cc.activeIncidents.length} active', color: AppColors.primary, dense: true),
          ]),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            FeedHealthChip(status: cc.feedStatus),
            Pill(
              'Real-resident notifications: ${notifyReal ? 'ON' : 'OFF'}',
              key: const Key('notify-real'),
              color: notifyReal ? AppColors.help : AppColors.safe,
              icon: notifyReal ? Icons.notifications_active : Icons.shield_outlined,
              filled: notifyReal,
              dense: true,
              tooltip: notifyReal
                  ? 'Server safety switch is ON: real (non-demo) residents can receive alerts.'
                  : 'Server safety switch is OFF: only fictional demo residents receive messages.',
            ),
            RealtimeIndicator(hub: services.realtime, lastRefresh: cc.lastRefresh),
            IconButton(
              tooltip: 'Refresh now',
              onPressed: () => cc.refreshAll(),
              icon: const Icon(Icons.refresh),
            ),
            if (inc != null)
              OutlinedButton.icon(
                key: const Key('open-report'),
                onPressed: () => openReport(context, cc.api, inc.id),
                icon: const Icon(Icons.summarize_outlined),
                label: const Text('Report'),
              ),
            if (inc != null && inc.isActive)
              FilledButton.icon(
                key: const Key('close-incident'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
                onPressed: () => _close(context, inc),
                icon: const Icon(Icons.flag),
                label: const Text('Close incident'),
              ),
          ]),
        ],
      ),
    );
  }
}

class RealtimeIndicator extends StatelessWidget {
  const RealtimeIndicator({super.key, required this.hub, this.lastRefresh});

  final RealtimeHub hub;
  final DateTime? lastRefresh;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<RealtimeState>(
        valueListenable: hub.state,
        builder: (context, s, _) {
          final (label, color, icon) = switch (s) {
            RealtimeState.live => ('LIVE', AppColors.safe, Icons.wifi_tethering),
            RealtimeState.connecting => ('Connecting…', AppColors.noReply, Icons.sync),
            RealtimeState.reconnecting => ('Reconnecting · polling 10 s', AppColors.noReply, Icons.sync_problem),
            RealtimeState.offline => ('Polling 10 s', AppColors.unreachable, Icons.wifi_tethering_off),
          };
          return Pill(
            label,
            key: const Key('realtime-indicator'),
            color: color,
            icon: icon,
            dense: true,
            tooltip: 'Realtime WebSocket: ${s.name}. Data last refreshed ${fmtTime(lastRefresh)}.\n'
                'Events trigger refetches; a 10-second poll runs as a fallback.',
          );
        },
      );
}

/// Right-hand tools: Demo controls, SMS simulator, SACHET feed.
class ToolsPanel extends StatelessWidget {
  const ToolsPanel({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: DefaultTabController(
          length: 3,
          child: Column(children: [
            const TabBar(
              labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              tabs: [
                Tab(icon: Icon(Icons.theater_comedy_outlined, size: 20), text: 'Demo'),
                Tab(icon: Icon(Icons.phone_android, size: 20), text: 'SMS phone'),
                Tab(icon: Icon(Icons.rss_feed, size: 20), text: 'SACHET'),
              ],
            ),
            Expanded(
              child: TabBarView(children: [
                DemoPanel(controller: controller),
                SmsSimulatorPanel(controller: controller),
                FeedPanel(controller: controller),
              ]),
            ),
          ]),
        ),
      );
}
