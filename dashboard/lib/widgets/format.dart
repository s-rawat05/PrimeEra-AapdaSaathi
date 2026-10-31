import 'package:intl/intl.dart';

final _time = DateFormat('HH:mm:ss');
final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _short = DateFormat('d MMM, HH:mm');

/// All timestamps arrive in UTC; show them in the operator's local time.
String fmtTime(DateTime? t) => t == null ? '—' : _time.format(t.toLocal());
String fmtDateTime(DateTime? t) => t == null ? '—' : _dateTime.format(t.toLocal());
String fmtShort(DateTime? t) => t == null ? '—' : _short.format(t.toLocal());

/// "in 12 min", "3 min ago", "in 2 h 5 min".
String fmtRelative(DateTime? t, {DateTime? now}) {
  if (t == null) return '—';
  final n = now ?? DateTime.now();
  final diff = t.difference(n);
  final future = !diff.isNegative;
  final d = diff.abs();
  String body;
  if (d.inSeconds < 60) {
    body = '${d.inSeconds} s';
  } else if (d.inMinutes < 60) {
    body = '${d.inMinutes} min';
  } else if (d.inHours < 48) {
    final m = d.inMinutes % 60;
    body = '${d.inHours} h${m > 0 ? ' $m min' : ''}';
  } else {
    body = '${d.inDays} days';
  }
  return future ? 'in $body' : '$body ago';
}

/// Countdown like `T-12:04` or `T+03:10` (after onset).
String fmtCountdown(DateTime target, DateTime now) {
  final diff = target.difference(now);
  final sign = diff.isNegative ? '+' : '-';
  final d = diff.abs();
  final h = d.inHours;
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? 'T$sign$h:$m:$s' : 'T$sign$m:$s';
}

String fmtSeconds(double? s) {
  if (s == null) return '—';
  if (s < 60) return '${s.toStringAsFixed(0)} s';
  final m = s / 60;
  if (m < 60) return '${m.toStringAsFixed(1)} min';
  return '${(m / 60).toStringAsFixed(1)} h';
}

String fmtMeters(double? m) {
  if (m == null) return '—';
  return m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';
}

String humanize(String s) {
  final t = s.replaceAll('_', ' ').replaceAll('.', ' · ');
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}
