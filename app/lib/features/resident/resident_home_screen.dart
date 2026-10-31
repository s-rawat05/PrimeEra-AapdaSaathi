import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/connection_banner.dart';
import '../../widgets/sos_button.dart';
import '../alerts/alert_detail_screen.dart';
import '../alerts/alert_history_screen.dart';
import '../alerts/emergency_response_screen.dart';
import '../alerts/help_status_screen.dart';
import '../evacuation/evacuation_screen.dart';

/// Resident home: greeting, ward, weather card, disaster risk gauge, official alert status,
/// assistance, SOS, community stats, and community actions directly matching the AapdaSaathi reference design.
class ResidentHomeScreen extends StatefulWidget {
  const ResidentHomeScreen({super.key});

  @override
  State<ResidentHomeScreen> createState() => _ResidentHomeScreenState();
}

class _ResidentHomeScreenState extends State<ResidentHomeScreen> {
  PageOut<AlertOut>? _history;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  Future<void> _loadStats() async {
    try {
      final h = await context.appRead.call((api) => api.alertHistory(limit: 100));
      if (mounted) setState(() => _history = h);
    } catch (_) {/* stats are optional; shown as — when unavailable */}
  }

  Future<void> _refresh() async {
    final app = context.appRead;
    await Future.wait([app.refresh(), _loadStats()]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final me = app.me;
    final resident = me?.resident;
    final alert = app.primaryAlert;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(padding: EdgeInsets.zero, children: [
        _Header(
          name: me?.user.firstName ?? '',
          ward: resident?.wardName ?? '',
          demo: me?.user.isDemo ?? false,
        ),
        const ConnectionBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (app.alertsError != null && !app.alertsFromCache) ...[
              ErrorPanel(message: app.alertsError!, onRetry: app.refresh, s: s),
              const SizedBox(height: 12),
            ],
            if (resident != null && !resident.isActive) ...[
              SectionCard(
                color: AppColors.amberSoft,
                child: Text(s.registrationInactive, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 12),
            ],
            // Weather & disaster info card (Reference Design Screen 1)
            _WeatherDisasterCard(alert: alert),
            const SizedBox(height: 14),
            // Disaster Risk / Severity with Speedometer Gauge (Reference Design Screen 1)
            AlertStatusCard(alert: alert),
            if (alert != null) ...[
              const SizedBox(height: 12),
              _AssistanceCard(alert: alert),
            ],
            const SizedBox(height: 16),
            const SosPillButton(),
            const SizedBox(height: 16),
            // Community Points & Tasks Completed (Reference Design Screen 1)
            _CommunityStats(history: _history, alert: alert),
            const SizedBox(height: 18),
            // Community Safety Actions / Aksi Peduli (Reference Design Screen 1)
            _CommunityActions(alert: alert),
            const SizedBox(height: 18),
            _Stats(history: _history),
            if (resident?.reverifyDueAt != null) ...[
              const SizedBox(height: 12),
              Text(
                s.reverifyDue(fmtTime(resident!.reverifyDueAt)),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.gray),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name, required this.ward, required this.demo});
  final String name;
  final String ward;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFE52E2E), Color(0xFFEF5350)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 12, 16, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.waves, color: Colors.white, size: 28),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.appName,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          if (demo) const DemoBadge(),
          IconButton(
            tooltip: 'Search',
            onPressed: () {},
            icon: const Icon(Icons.search, color: Colors.white, size: 22),
          ),
          Stack(
            children: [
              IconButton(
                tooltip: s.navAlerts,
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AlertHistoryScreen())),
                icon: const Icon(Icons.notifications_none, color: Colors.white, size: 24),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: s.refresh,
            onPressed: app.refresh,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ]),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            s.greeting(name),
            key: const Key('greeting'),
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.location_on, color: Colors.white, size: 18),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              ward.isNotEmpty ? ward : 'Bhimtal Ward 1, Nainital',
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
        ]),
      ]),
    );
  }
}

/// Weather and flood disaster information card (Reference Design Screen 1).
class _WeatherDisasterCard extends StatelessWidget {
  const _WeatherDisasterCard({required this.alert});
  final AlertOut? alert;

  @override
  Widget build(BuildContext context) {
    final isRainOrFlood = alert?.official.event.toLowerCase().contains('flood') ?? true;
    final temp = alert != null ? '24°C' : '22°C';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(temp, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.ink)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        isRainOrFlood ? Icons.cloudy_snowing : Icons.wb_sunny,
                        color: isRainOrFlood ? const Color(0xFF1E88E5) : const Color(0xFFFFA000),
                        size: 26,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        isRainOrFlood ? 'Hujan Deras / Heavy Rain' : 'Cuaca Normal / Normal',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 18, color: AppColors.gray),
                  ],
                ),
                if (alert != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      alert!.official.event,
                      style: const TextStyle(fontSize: 12, color: AppColors.red, fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 120,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE3F2FD),
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              size: const Size(120, 80),
              painter: _FloodIllustrationPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stylized flood illustration painter depicting submerged house, tree, and rain.
class _FloodIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Ground
    final groundPaint = Paint()..color = const Color(0xFFC8E6C9);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.55, size.width, size.height * 0.45), groundPaint);

    // House body
    final housePaint = Paint()..color = const Color(0xFFFFE0B2);
    final houseRect = Rect.fromLTWH(size.width * 0.16, size.height * 0.35, size.width * 0.44, size.height * 0.4);
    canvas.drawRect(houseRect, housePaint);

    // Roof (red triangle)
    final roofPaint = Paint()..color = const Color(0xFFE53935);
    final roofPath = Path()
      ..moveTo(size.width * 0.12, size.height * 0.35)
      ..lineTo(size.width * 0.38, size.height * 0.12)
      ..lineTo(size.width * 0.64, size.height * 0.35)
      ..close();
    canvas.drawPath(roofPath, roofPaint);

    // Window
    final windowPaint = Paint()..color = const Color(0xFF90CAF9);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.28, size.height * 0.38, size.width * 0.12, size.height * 0.15), windowPaint);

    // Tree trunk & foliage
    final trunkPaint = Paint()..color = const Color(0xFF795548);
    canvas.drawRect(Rect.fromLTWH(size.width * 0.74, size.height * 0.35, size.width * 0.08, size.height * 0.35), trunkPaint);
    final leavesPaint = Paint()..color = const Color(0xFF43A047);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.30), size.width * 0.16, leavesPaint);

    // Deep water level covering bottom half of house
    final deepWater = Paint()..color = const Color(0xFF1E88E5);
    final waterPath = Path()
      ..moveTo(0, size.height * 0.58)
      ..quadraticBezierTo(size.width * 0.25, size.height * 0.54, size.width * 0.5, size.height * 0.58)
      ..quadraticBezierTo(size.width * 0.75, size.height * 0.62, size.width, size.height * 0.58)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(waterPath, deepWater);

    // Lighter blue wave highlight
    final wavePaint = Paint()..color = const Color(0xFF64B5F6);
    final wavePath = Path()
      ..moveTo(0, size.height * 0.68)
      ..quadraticBezierTo(size.width * 0.3, size.height * 0.64, size.width * 0.6, size.height * 0.68)
      ..quadraticBezierTo(size.width * 0.85, size.height * 0.72, size.width, size.height * 0.68)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wavePath, wavePaint);

    // Rain drop streaks
    final rainPaint = Paint()
      ..color = const Color(0xFF90CAF9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.12 + i * 0.18);
      canvas.drawLine(Offset(x, size.height * 0.04), Offset(x - 6, size.height * 0.22), rainPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The official alert status and threat level card with Speedometer Gauge (Reference Design Screen 1).
class AlertStatusCard extends StatelessWidget {
  const AlertStatusCard({super.key, required this.alert});
  final AlertOut? alert;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final a = alert;
    if (a == null) {
      return SectionCard(
        key: const Key('no-alerts-card'),
        child: Row(children: [
          const Pictogram(Icons.verified_user, color: AppColors.green),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.officialAlertStatus, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
              Text(s.noActiveAlerts, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(s.noActiveAlertsBody),
              if (app.alertsFromCache)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(s.cachedData, style: const TextStyle(color: AppColors.amber)),
                ),
            ]),
          ),
        ]),
      );
    }
    final pending = app.pendingReplyFor(a.deliveryId);
    final status = pending?.status ?? a.status;
    return SectionCard(
      key: const Key('active-alert-card'),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AlertDetailScreen(deliveryId: a.deliveryId))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              'Potensi Bencana • ${s.officialAlertStatus}',
              style: const TextStyle(color: AppColors.gray, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (a.isDemo) const DemoBadge(),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(
                    '${a.official.severity.toUpperCase()} • ${a.official.event}',
                    style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18, color: AppColors.red),
              ]),
              const SizedBox(height: 4),
              Text(a.presentation.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              if (a.official.headline != null)
                Text(
                  a.official.headline!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.gray),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          // Speedometer gauge meter
          SizedBox(
            width: 105,
            height: 68,
            child: CustomPaint(
              size: const Size(105, 68),
              painter: _SpeedometerGaugePainter(severity: a.official.severity),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          StatusChip(
            label: pending != null ? s.queuedNotDelivered : '${s.yourStatus}: ${s.statusName(status)}',
            color: pending != null ? AppColors.amber : AppColors.forStatus(status),
          ),
          if (a.official.onset != null) StatusChip(label: '${s.onset}: ${fmtTime(a.official.onset)}', color: AppColors.gray),
        ]),
        if (app.alertsFromCache)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s.cachedData, style: const TextStyle(color: AppColors.amber)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              key: const Key('respond-now'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => EmergencyResponseScreen(deliveryId: a.deliveryId),
              )),
              child: Text(s.respondNow),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AlertDetailScreen(deliveryId: a.deliveryId),
            )),
            child: Text(s.viewAlert),
          ),
        ]),
      ]),
    );
  }
}

/// Semicircular speedometer gauge painter matching Reference Screen 1.
class _SpeedometerGaugePainter extends CustomPainter {
  _SpeedometerGaugePainter({required this.severity});
  final String severity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.88);
    final radius = size.width * 0.44;
    const strokeWidth = 9.0;

    const totalAngle = math.pi;
    const arcAngle = totalAngle / 4;

    final colors = [
      const Color(0xFF4CAF50), // Green (Advisory/Low)
      const Color(0xFFFFEB3B), // Yellow (Watch)
      const Color(0xFFFF9800), // Orange (Warning)
      const Color(0xFFE53935), // Red (Severe/Awas)
    ];

    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      final startAngle = math.pi + (i * arcAngle);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        arcAngle - 0.04,
        false,
        paint,
      );
    }

    double needleRatio = switch (severity.toLowerCase()) {
      'minor' || 'low' => 0.15,
      'moderate' => 0.40,
      'severe' => 0.75,
      'extreme' || 'awas' => 0.90,
      _ => 0.75,
    };

    final needleAngle = math.pi + (needleRatio * totalAngle);
    final needleLength = radius * 0.82;
    final needleEnd = Offset(
      center.dx + needleLength * math.cos(needleAngle),
      center.dy + needleLength * math.sin(needleAngle),
    );

    final needlePaint = Paint()
      ..color = const Color(0xFF212121)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, needleEnd, needlePaint);

    final centerDotPaint = Paint()..color = const Color(0xFF212121);
    canvas.drawCircle(center, 5.0, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _SpeedometerGaugePainter old) => old.severity != severity;
}

class _AssistanceCard extends StatelessWidget {
  const _AssistanceCard({required this.alert});
  final AlertOut alert;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final asst = alert.assistance;
    return SectionCard(
      onTap: alert.isHelp
          ? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => HelpStatusScreen(deliveryId: alert.deliveryId)))
          : null,
      child: Row(children: [
        Pictogram(alert.isSafe ? Icons.check_circle : Icons.support_agent,
            color: alert.isSafe ? AppColors.green : AppColors.official, size: 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.assistance, style: const TextStyle(color: AppColors.gray, fontSize: 13)),
            Text(asst.summary, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (asst.neighbourAsked) Text(s.neighbourAsked),
            if (asst.volunteerStatus != null) Text(s.volunteerStatus(asst.volunteerStatus!)),
            if (asst.volunteerEtaMinutes != null) Text(s.etaMinutes(fmtMinutes(asst.volunteerEtaMinutes))),
          ]),
        ),
      ]),
    );
  }
}

/// Community Reward & Task Stats (Reference Design Screen 1).
class _CommunityStats extends StatelessWidget {
  const _CommunityStats({required this.history, required this.alert});
  final PageOut<AlertOut>? history;
  final AlertOut? alert;

  @override
  Widget build(BuildContext context) {
    final totalPoints = 500;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE3F2FD),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.verified, color: Color(0xFF1E88E5), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Poinmu', style: TextStyle(fontSize: 11, color: AppColors.gray)),
                      Text('$totalPoints Poin', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outline),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE8F5E9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.task_alt, color: Color(0xFF2E7D32), size: 22),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Diselesaikan hari ini', style: TextStyle(fontSize: 11, color: AppColors.gray)),
                      Text('48 Tugas', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Community Safety Actions ("Aksi Peduli" - Reference Design Screen 1).
class _CommunityActions extends StatelessWidget {
  const _CommunityActions({required this.alert});
  final AlertOut? alert;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Aksi Peduli',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EvacuationScreen(standalone: true)));
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Lihat Semua', style: TextStyle(fontSize: 13, color: AppColors.gray, fontWeight: FontWeight.w600)),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right, size: 16, color: AppColors.gray),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 108,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _ActionCard(
                title: 'Evakuasi ke Posko',
                subtitle: 'Posko Kebangsaan Komp. Mas',
                tag: '200 m',
                icon: Icons.night_shelter,
                color: const Color(0xFFE53935),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EvacuationScreen(standalone: true))),
              ),
              const SizedBox(width: 12),
              _ActionCard(
                title: 'Dapur Umum & Logistik',
                subtitle: 'Bhimtal Central Hall Ward 1',
                tag: 'Bantuan',
                icon: Icons.soup_kitchen,
                color: const Color(0xFF1E88E5),
                onTap: () {},
              ),
              const SizedBox(width: 12),
              _ActionCard(
                title: 'Pos Medis Darurat',
                subtitle: 'Klinik Kesehatan Utama',
                tag: 'Medis',
                icon: Icons.medical_services,
                color: const Color(0xFF43A047),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String tag;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.outline.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(tag, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.gray), maxLines: 1),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.history});
  final PageOut<AlertOut>? history;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final items = history?.items;
    String n(int? v) => v == null ? '—' : '$v';
    final total = history?.total;
    final safe = items?.where((a) => a.isSafe).length;
    final help = items?.where((a) => a.isHelp).length;
    Widget tile(IconData icon, Color c, String label, String value) => Expanded(
          child: Semantics(
            label: '$label: $value',
            excludeSemantics: true,
            child: SectionCard(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, color: c),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.notifications_active, AppColors.red, s.statAlertsReceived, n(total)),
      const SizedBox(width: 8),
      tile(Icons.check_circle, AppColors.green, s.statMarkedSafe, n(safe)),
      const SizedBox(width: 8),
      tile(Icons.sos, AppColors.red, s.statHelpRequests, n(help)),
    ]);
  }
}
