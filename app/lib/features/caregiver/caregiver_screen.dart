import 'package:flutter/material.dart';

import '../../core/api_exception.dart';
import '../../models/models.dart';
import '../../services/device_services.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';

/// Caregiver dashboard: linked residents, their active alert rows, location if consented, and
/// SAFE/HELP on their behalf with a note.
class CaregiverScreen extends StatelessWidget {
  const CaregiverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final rows = app.caregiverResidents;
    return Scaffold(
      appBar: AppBar(title: Text(s.caregiverTitle), actions: [
        IconButton(tooltip: s.refresh, onPressed: app.refresh, icon: const Icon(Icons.refresh)),
      ]),
      body: Column(children: [
        const ConnectionBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: app.refresh,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (app.responderError != null) ErrorPanel(message: app.responderError!, onRetry: app.refresh, s: s),
              if (rows.isEmpty && app.responderError == null)
                EmptyState(icon: Icons.family_restroom, text: s.noLinkedResidents),
              for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: 12), child: _PersonCard(row: r)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.row});
  final CaregiverResidentOut row;

  Future<void> _respond(BuildContext context, PriorityItem item, String status) async {
    final app = context.appRead;
    final s = app.s;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(status == DeliveryStatus.safe ? s.markSafeOnBehalf : s.requestHelpOnBehalf),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.onBehalfConfirm(row.resident.fullName, s.statusName(status))),
          const SizedBox(height: 12),
          TextField(
            key: const Key('caregiver-note'),
            controller: note,
            maxLength: 300,
            decoration: InputDecoration(labelText: s.optionalNote),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(
            key: const Key('caregiver-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: status == DeliveryStatus.safe ? AppColors.green : AppColors.red,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await app.call((api) => api.caregiverRespond(item.deliveryId, status, note: note.text.trim()));
      if (context.mounted) showSnack(context, s.recorded);
      await app.refresh();
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final r = row.resident;
    final loc = row.exactLocation;
    return SectionCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.redSoft,
            child: Text(r.fullName.isEmpty ? '?' : r.fullName[0],
                style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text('${r.wardName} · ${r.phoneMasked}', style: const TextStyle(color: AppColors.gray)),
            ]),
          ),
          if (r.isDemo) const DemoBadge(),
        ]),
        if (r.needs.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in r.needs) StatusChip(label: s.needShort(n), color: AppColors.official),
          ]),
        ],
        const SizedBox(height: 8),
        Row(children: [
          Icon(loc != null ? Icons.location_on : Icons.location_off, color: AppColors.gray, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              loc != null
                  ? '${s.locationShared}: ${loc.addressText ?? '${loc.lat.toStringAsFixed(5)}, ${loc.lng.toStringAsFixed(5)}'}'
                  : s.locationNotShared,
              style: const TextStyle(color: AppColors.gray),
            ),
          ),
          if (loc != null)
            TextButton(
              onPressed: () => app.launcher.open(Links.mapsDirections(loc.lat, loc.lng)),
              child: Text(s.openInMaps),
            ),
        ]),
        const Divider(height: 24),
        if (row.activeAlerts.isEmpty)
          Text(s.noAlertForPerson, style: const TextStyle(color: AppColors.gray))
        else
          for (final al in row.activeAlerts) ...[
            Row(children: [
              StatusChip(label: s.statusName(al.status), color: AppColors.forStatus(al.status)),
              const SizedBox(width: 8),
              Expanded(child: Text(fmtTime(al.alertedAt), style: const TextStyle(color: AppColors.gray))),
              if (al.replyChannel != null) Text(s.repliedVia(al.replyChannel!), style: const TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton(
                  key: Key('cg-safe-${al.deliveryId}'),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                  onPressed: () => _respond(context, al, DeliveryStatus.safe),
                  child: Text(s.markSafeOnBehalf, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: Key('cg-help-${al.deliveryId}'),
                  onPressed: () => _respond(context, al, DeliveryStatus.help),
                  child: Text(s.requestHelpOnBehalf, textAlign: TextAlign.center),
                ),
              ),
            ]),
            const SizedBox(height: 8),
          ],
      ]),
    );
  }
}
