import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/api_error.dart';
import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

const severities = ['Extreme', 'Severe', 'Moderate', 'Minor', 'Unknown'];
const urgencies = ['Immediate', 'Expected', 'Future', 'Past', 'Unknown'];

/// `POST /incidents/{id}/close {note}` — returns the closed incident.
Future<Incident?> showCloseIncidentDialog(BuildContext context, AapdaApi api, Incident inc) async {
  final note = TextEditingController();
  final r = await showDialog<Object?>(
    context: context,
    builder: (_) => FormDialog(
      title: 'Close incident',
      submitLabel: 'Close incident',
      builder: (context, setState) => [
        Text(inc.title, style: const TextStyle(fontWeight: FontWeight.w700)),
        gap8,
        Text(
          'Open: ${inc.counts.help} HELP, ${inc.counts.noReply} NO REPLY, ${inc.counts.unreachable} UNREACHABLE. '
          'Closing stops escalation and cancels open tasks. A closing report is generated.',
          style: const TextStyle(color: AppColors.muted),
        ),
        gap12,
        TextFormField(
          key: const Key('close-note'),
          controller: note,
          maxLines: 3,
          maxLength: 1000,
          decoration: const InputDecoration(labelText: 'Closing note (required)', helperText: 'At least 3 characters'),
          validator: (v) => requiredText(v, min: 3, field: 'Closing note'),
        ),
      ],
      onSubmit: () => api.closeIncident(inc.id, note.text.trim()),
    ),
  );
  return r is Incident ? r : null;
}

/// `POST /incidents` — manual incident (e.g. from a control-room phone call).
Future<Incident?> showCreateIncidentDialog(BuildContext context, AapdaApi api) async {
  final wards = await runAction(context, () => api.wards());
  if (wards == null || !context.mounted) return null;
  final title = TextEditingController();
  final hazard = TextEditingController(text: 'Flood');
  final headline = TextEditingController();
  final instruction = TextEditingController();
  final onset = TextEditingController(text: '45');
  final selected = <String>{};
  var severity = 'Severe';
  var urgency = 'Expected';
  var isDemo = true;
  var wardError = false;
  final r = await showDialog<Object?>(
    context: context,
    builder: (_) => FormDialog(
      title: 'Create manual incident',
      submitLabel: 'Create & alert',
      width: 620,
      builder: (context, setState) => [
        const InfoBanner('Creating an incident immediately alerts registered residents in the selected wards. '
            'Keep "Demo / drill" on unless this is a real emergency.', color: AppColors.noReply, icon: Icons.warning_amber),
        gap12,
        TextFormField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => requiredText(v, min: 3, field: 'Title'),
        ),
        gap12,
        TextFormField(
          controller: hazard,
          decoration: const InputDecoration(labelText: 'Hazard type', hintText: 'Flood, Landslide, Cloudburst…'),
          validator: (v) => requiredText(v, min: 2, field: 'Hazard type'),
        ),
        gap12,
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: severity,
              decoration: const InputDecoration(labelText: 'Severity'),
              items: [for (final s in severities) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => severity = v ?? severity,
            ),
          ),
          gap12,
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: urgency,
              decoration: const InputDecoration(labelText: 'Urgency'),
              items: [for (final s in urgencies) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => urgency = v ?? urgency,
            ),
          ),
          gap12,
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: onset,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Onset in minutes', hintText: 'blank = unknown'),
              validator: (v) {
                if ((v ?? '').trim().isEmpty) return null;
                final n = int.tryParse(v!.trim());
                if (n == null) return 'Whole minutes';
                if (n < -1440 || n > 10080) return '−1440…10080';
                return null;
              },
            ),
          ),
        ]),
        gap12,
        TextFormField(controller: headline, decoration: const InputDecoration(labelText: 'Headline (official wording)')),
        gap12,
        TextFormField(
          controller: instruction,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Instruction (official wording)'),
        ),
        gap12,
        Text('Wards${wardError ? ' — select at least one' : ''}',
            style: TextStyle(fontWeight: FontWeight.w700, color: wardError ? AppColors.help : null)),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final w in wards)
            FilterChip(
              label: Text('${w.code} · ${w.name}${w.isDemo ? ' (demo)' : ''}'),
              selected: selected.contains(w.id),
              onSelected: (v) => setState(() {
                v ? selected.add(w.id) : selected.remove(w.id);
                wardError = false;
              }),
            ),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: isDemo,
          onChanged: (v) => setState(() => isDemo = v),
          title: const Text('Demo / drill incident'),
          subtitle: const Text('Marked DEMO everywhere; real-resident notifications follow the server safety switch.'),
        ),
      ],
      onSubmit: () async {
        if (selected.isEmpty) {
          wardError = true;
          throw const InputError('Select at least one ward');
        }
        return api.createIncident(
          title: title.text.trim(),
          hazardType: hazard.text.trim(),
          wardIds: selected.toList(),
          severity: severity,
          urgency: urgency,
          onsetInMinutes: onset.text.trim().isEmpty ? null : int.parse(onset.text.trim()),
          headline: headline.text.trim().isEmpty ? null : headline.text.trim(),
          instruction: instruction.text.trim().isEmpty ? null : instruction.text.trim(),
          isDemo: isDemo,
        );
      },
    ),
  );
  return r is Incident ? r : null;
}

/// `PATCH /incidents/{id}` — reason required (audited).
Future<Incident?> showEditIncidentDialog(BuildContext context, AapdaApi api, Incident inc) async {
  final title = TextEditingController(text: inc.title);
  final onset = TextEditingController();
  final reason = TextEditingController();
  var severity = severities.contains(inc.severity) ? inc.severity : 'Unknown';
  var approval = inc.requiresDispatchApproval;
  final r = await showDialog<Object?>(
    context: context,
    builder: (_) => FormDialog(
      title: 'Edit incident',
      builder: (context, setState) => [
        TextFormField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Title'),
          validator: (v) => requiredText(v, min: 3, field: 'Title'),
        ),
        gap12,
        DropdownButtonFormField<String>(
          initialValue: severity,
          decoration: const InputDecoration(labelText: 'Severity'),
          items: [for (final s in severities) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) => severity = v ?? severity,
        ),
        gap12,
        TextFormField(
          controller: onset,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Reset onset to now + N minutes (optional)',
            helperText: 'Re-selects the escalation mode; recorded as an operator onset override.',
          ),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final n = int.tryParse(v!.trim());
            if (n == null) return 'Whole minutes';
            if (n < -1440 || n > 10080) return '−1440…10080';
            return null;
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: approval,
          onChanged: (v) => setState(() => approval = v),
          title: const Text('Volunteer dispatch requires operator approval'),
        ),
        TextFormField(
          key: const Key('edit-reason'),
          controller: reason,
          maxLength: 500,
          decoration: const InputDecoration(labelText: 'Reason for change (required)', helperText: 'At least 5 characters'),
          validator: (v) => requiredText(v, min: 5, field: 'Reason'),
        ),
      ],
      onSubmit: () => api.patchIncident(
        inc.id,
        title: title.text.trim() != inc.title ? title.text.trim() : null,
        severity: severity != inc.severity ? severity : null,
        onsetInMinutes: onset.text.trim().isEmpty ? null : int.parse(onset.text.trim()),
        requiresDispatchApproval: approval != inc.requiresDispatchApproval ? approval : null,
        reason: reason.text.trim(),
      ),
    ),
  );
  return r is Incident ? r : null;
}
