import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/format.dart';
import '../overview/command_centre_controller.dart';

class _SentReply {
  const _SentReply(this.phone, this.body, this.at, this.result);

  final String phone;
  final String body;
  final DateTime at;
  final SmsResult result;
}

/// Feature-phone simulator: shows the simulated inbox of a fictional demo number
/// (`GET /demo/sms/outbox?phone=`) and sends replies through the real SMS pipeline
/// (`POST /demo/sms/inbound`).
class SmsSimulatorPanel extends StatefulWidget {
  const SmsSimulatorPanel({super.key, required this.controller});

  final CommandCentreController controller;

  @override
  State<SmsSimulatorPanel> createState() => _SmsSimulatorPanelState();
}

class _SmsSimulatorPanelState extends State<SmsSimulatorPanel> {
  final _phoneCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  Map<String, String> _directory = {};
  String? _phone;
  List<OutboxItem>? _inbox;
  Object? _error;
  bool _sending = false;
  final List<_SentReply> _sent = [];
  int _rev = -1;

  CommandCentreController get cc => widget.controller;

  @override
  void initState() {
    super.initState();
    cc.addListener(_onCc);
    _refresh();
  }

  @override
  void dispose() {
    cc.removeListener(_onCc);
    _phoneCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _onCc() {
    if (cc.smsRevision != _rev) _refresh();
  }

  /// Builds the phone picker from numbers that actually received demo SMS, labelled with the
  /// resident name when the masked phone in the priority list matches (last 4 digits).
  Future<void> _refresh() async {
    _rev = cc.smsRevision;
    try {
      final all = await cc.api.smsOutbox(limit: 300);
      final dir = <String, String>{};
      for (final m in all) {
        final p = m.recipientPhone;
        if (p == null || dir.containsKey(p)) continue;
        final tail = p.length >= 4 ? p.substring(p.length - 4) : p;
        final match = cc.priority.where((x) => x.phoneMasked.endsWith(tail)).firstOrNull;
        dir[p] = match != null ? '${match.residentName} (resident)' : humanize(m.recipientKind);
      }
      if (!mounted) return;
      setState(() {
        _directory = dir;
        _phone ??= dir.keys.firstOrNull;
        if (_phone != null && _phoneCtrl.text.isEmpty) _phoneCtrl.text = _phone!;
      });
      await _loadInbox();
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadInbox() async {
    final phone = _phone;
    if (phone == null) return;
    try {
      final items = await cc.api.smsOutbox(phone: phone, limit: 50);
      if (mounted && phone == _phone) {
        setState(() {
          _inbox = items;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _pick(String phone) {
    setState(() {
      _phone = phone.trim();
      _phoneCtrl.text = _phone!;
      _inbox = null;
    });
    _loadInbox();
  }

  Future<void> _send(String body) async {
    final phone = _phone;
    if (phone == null || body.trim().isEmpty) return;
    setState(() => _sending = true);
    final r = await runAction(context, () => cc.api.smsInbound(phone, body.trim()));
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (r != null) {
        _sent.insert(0, _SentReply(phone, body.trim(), DateTime.now(), r));
        _bodyCtrl.clear();
      }
    });
    if (r != null) {
      await cc.refreshIncident();
      await _loadInbox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentHere = _sent.where((s) => s.phone == _phone).toList();
    return ListView(padding: const EdgeInsets.all(12), children: [
      const InfoBanner('Simulates a basic feature phone. Only fictional demo numbers are accepted by the server.',
          icon: Icons.phone_android, color: AppColors.drill),
      gap12,
      if (_directory.isNotEmpty)
        DropdownButtonFormField<String>(
          key: ValueKey('sms-dir-${_directory.length}-$_phone'),
          initialValue: _directory.containsKey(_phone) ? _phone : null,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Demo phone (received SMS)'),
          items: [
            for (final e in _directory.entries)
              DropdownMenuItem(value: e.key, child: Text('${e.value} · ${e.key}', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => v == null ? null : _pick(v),
        ),
      gap8,
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('sms-phone'),
            controller: _phoneCtrl,
            decoration: const InputDecoration(labelText: 'Or enter a demo number', hintText: '+919000000003'),
            onSubmitted: _pick,
          ),
        ),
        IconButton(tooltip: 'Open inbox', onPressed: () => _pick(_phoneCtrl.text), icon: const Icon(Icons.inbox_outlined)),
        IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
      ]),
      gap12,
      // Phone mock-up
      Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFFDDE7D0), borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.all(10),
          constraints: const BoxConstraints(minHeight: 160),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_phone == null ? 'No phone selected' : 'Inbox · $_phone',
                style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 12)),
            const Divider(color: Colors.black26),
            if (_error != null) ErrorPanel(error: _error!, onRetry: _refresh),
            if (_phone != null && _inbox == null && _error == null) const LinearProgressIndicator(),
            if (_inbox != null && _inbox!.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No messages for this number yet.', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
            for (final m in (_inbox ?? const <OutboxItem>[]).take(12))
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${fmtTime(m.createdAt)} · ${m.round} · ${m.status}${m.error != null ? ' · ${m.error}' : ''}',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: Colors.black54)),
                  Text(m.body ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
                ]),
              ),
          ]),
        ),
      ),
      gap12,
      const Text('Reply from this phone', style: TextStyle(fontWeight: FontWeight.w800)),
      gap8,
      Wrap(spacing: 8, runSpacing: 8, children: [
        _quick('1', 'Safe', AppColors.safe),
        _quick('2', 'Help', AppColors.help),
        _quick('3', "Can't reach (neighbour)", AppColors.unreachable),
      ]),
      gap8,
      Row(children: [
        Expanded(
          child: TextField(
            key: const Key('sms-body'),
            controller: _bodyCtrl,
            maxLength: 320,
            decoration: const InputDecoration(labelText: 'Free text reply', counterText: ''),
            onSubmitted: _send,
          ),
        ),
        gap8,
        FilledButton(
          key: const Key('sms-send'),
          onPressed: _sending || _phone == null ? null : () => _send(_bodyCtrl.text),
          child: const Text('Send'),
        ),
      ]),
      if (sentHere.isNotEmpty) ...[
        gap12,
        const Text('Replies sent (server result)', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final s in sentHere.take(8))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.outbox, size: 18),
            title: Text('“${s.body}” at ${fmtTime(s.at)}'),
            subtitle: Text([
              'result: ${s.result.result}',
              if (s.result.action != null) 'action: ${s.result.action}',
              if (s.result.detail != null) s.result.detail!,
            ].join(' · ')),
            trailing: Pill(s.result.result.toUpperCase(),
                color: s.result.result == 'applied' ? AppColors.safe : AppColors.noReply, dense: true),
          ),
      ],
    ]);
  }

  Widget _quick(String body, String label, Color color) => OutlinedButton(
        key: Key('sms-quick-$body'),
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color)),
        onPressed: _sending || _phone == null ? null : () => _send(body),
        child: Text('$body  ·  $label'),
      );
}
