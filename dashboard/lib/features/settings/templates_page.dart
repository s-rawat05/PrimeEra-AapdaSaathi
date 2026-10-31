import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Alert templates — AapdaSaathi's framing around the official text. Body must contain `{headline}`.
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  List<TemplateOut>? _items;
  Object? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final t = await context.api.templates();
      if (mounted) {
        setState(() {
          _items = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit([TemplateOut? t]) async {
    final api = context.api;
    final hazard = TextEditingController(text: t?.hazardType ?? '*');
    final title = TextEditingController(text: t?.title ?? '');
    final body = TextEditingController(text: t?.body ?? '');
    final pictogram = TextEditingController(text: t?.pictogram ?? '');
    final audio = TextEditingController(text: t?.audioAssetUrl ?? '');
    var language = t?.language ?? 'hi';
    var style = t?.style ?? 'standard';
    var active = t?.isActive ?? true;
    final r = await showDialog<Object?>(
      context: context,
      builder: (_) => FormDialog(
        title: t == null ? 'New template' : 'Edit template',
        width: 620,
        builder: (context, setState) => [
          const InfoBanner('Templates frame the alert. The official CAP text is always inserted via {headline} and '
              'shown verbatim. Placeholders: {headline}, {event}, {instruction}, {sender}.', icon: Icons.gavel),
          gap12,
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: hazard,
                enabled: t == null,
                decoration: const InputDecoration(labelText: 'Hazard type', helperText: "'*' = any hazard"),
                validator: (v) => requiredText(v, field: 'Hazard type'),
              ),
            ),
            gap12,
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: language,
                decoration: const InputDecoration(labelText: 'Language'),
                items: const [
                  DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: t == null ? (v) => language = v ?? language : null,
              ),
            ),
            gap12,
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: style,
                decoration: const InputDecoration(labelText: 'Style'),
                items: const [
                  DropdownMenuItem(value: 'standard', child: Text('Standard')),
                  DropdownMenuItem(value: 'easy_read', child: Text('Easy read')),
                  DropdownMenuItem(value: 'sms', child: Text('SMS')),
                ],
                onChanged: t == null ? (v) => style = v ?? style : null,
              ),
            ),
          ]),
          gap12,
          TextFormField(
            controller: title,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Title'),
            validator: (v) => requiredText(v, field: 'Title'),
          ),
          TextFormField(
            key: const Key('template-body'),
            controller: body,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'Body', helperText: 'Must include {headline}'),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Body is required';
              if (!s.contains('{headline}')) return 'Body must include {headline} so the official text is always shown';
              return null;
            },
          ),
          TextFormField(controller: pictogram, decoration: const InputDecoration(labelText: 'Pictogram key (optional)')),
          gap12,
          TextFormField(controller: audio, decoration: const InputDecoration(labelText: 'Audio asset URL (optional)')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: active,
            onChanged: (v) => setState(() => active = v),
            title: const Text('Active'),
          ),
        ],
        onSubmit: () => api.upsertTemplate({
          'hazard_type': hazard.text.trim(),
          'language': language,
          'style': style,
          'title': title.text.trim(),
          'body': body.text.trim(),
          'pictogram': pictogram.text.trim().isEmpty ? null : pictogram.text.trim(),
          'audio_asset_url': audio.text.trim().isEmpty ? null : audio.text.trim(),
          'is_active': active,
        }),
      ),
    );
    if (r is TemplateOut && mounted) {
      showSnack(context, 'Template saved (audited)');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return PageBody(children: [
      PageHeader(
        title: 'Alert templates',
        subtitle: 'One template per hazard × language × style. Saving an existing combination updates it.',
        actions: [
          IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh)),
          FilledButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New template')),
        ],
      ),
      if (_error != null) ErrorPanel(error: _error!, onRetry: _load),
      if (items == null && _error == null) const LinearProgressIndicator(),
      if (items != null && items.isEmpty) const EmptyState('No templates.'),
      if (items != null)
        for (final t in items) ...[
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              title: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(t.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                Pill('hazard: ${t.hazardType}', color: AppColors.info, dense: true),
                Pill(t.language.toUpperCase(), color: AppColors.info, dense: true),
                Pill(t.style, color: AppColors.drill, dense: true),
                if (!t.isActive) const Pill('INACTIVE', color: AppColors.unreachable, dense: true),
              ]),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(t.body, style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
              ),
              trailing: OutlinedButton(onPressed: () => _edit(t), child: const Text('Edit')),
            ),
          ),
          gap8,
        ],
    ]);
  }
}
