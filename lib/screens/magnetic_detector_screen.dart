import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';

/// ══════════════════════════════════════════════════════════════════════════════
/// Magnetic Detector — works exactly like EMF Detector on Play Store
///
/// KEY INSIGHT: EMF Detector shows RAW µT value directly from magnetometer.
///   It does NOT subtract a baseline — just displays the absolute field strength.
///   High µT = something magnetic nearby. Earth's field = 25-65 µT.
///
/// Our previous approach (baseline subtraction) was fundamentally wrong:
///   If the magnet is already there during calibration → baseline = high value
///   → deviation = 0 always.
///
/// New approach: Raw magnitude → fixed thresholds → gauge
///   < 65 µT   → clean (earth field only)
///   65-100 µT → low anomaly
///   100-200 µT→ medium anomaly
///   > 200 µT  → strong magnetic source detected
/// ══════════════════════════════════════════════════════════════════════════════
class MagneticDetectorScreen extends StatefulWidget {
  const MagneticDetectorScreen({super.key});
  @override State<MagneticDetectorScreen> createState() => _MagState();
}

class _MagState extends State<MagneticDetectorScreen>
    with TickerProviderStateMixin {

  late AnimationController _pulse;
  late AnimationController _needle;

  static const _channel =
      EventChannel('tn.gov.education.examguard/magnetometer');
  StreamSubscription? _sub;
  Timer? _simTimer;

  // ── Raw sensor values ──────────────────────────────────────────────────────
  double _rawX = 0, _rawY = 0, _rawZ = 0;
  double _rawMag = 0.0;   // sqrt(x²+y²+z²) — the TOTAL field strength
  double _emaMag = 0.0;   // EMA-smoothed for stable display
  double _peakMag = 0.0;  // peak value since scan started

  // ── Thresholds (µT) — fixed, not relative to baseline ─────────────────────
  static const double _t1 = 65.0;   // earth field normal max
  static const double _t2 = 120.0;  // anomaly detected
  static const double _t3 = 250.0;  // strong source (earpiece coil range)
  static const double _tMax = 600.0; // gauge full scale

  // ── State ──────────────────────────────────────────────────────────────────
  bool _scanning = false;
  bool _alerted  = false;
  int  _samples  = 0;

  final _player = AudioPlayer();

  // ── Zone from raw magnitude ────────────────────────────────────────────────
  _MagZone get _zone {
    if (_emaMag >= _t3)  return _MagZone.danger;
    if (_emaMag >= _t2)  return _MagZone.caution;
    return _MagZone.clear;
  }

  // ── Gauge 0-1 mapped to 0-600 µT ──────────────────────────────────────────
  double get _gaugeValue => (_emaMag / _tMax).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _pulse  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _needle = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _simTimer?.cancel();
    _pulse.dispose();
    _needle.dispose();
    _player.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _scanning = true;
      _emaMag = 0; _rawMag = 0; _peakMag = 0; _samples = 0;
      _alerted = false;
    });

    _sub = _channel.receiveBroadcastStream().listen(
      (data) {
        if (!mounted || !_scanning) return;
        final x = (data[0] as num).toDouble();
        final y = (data[1] as num).toDouble();
        final z = (data[2] as num).toDouble();
        _onSample(x, y, z);
      },
      onError: (_) => _startSimulation(),
    );
  }

  void _stopScan() {
    _sub?.cancel();
    _simTimer?.cancel();
    _sub = null; _simTimer = null;
    setState(() { _scanning = false; _alerted = false; });
  }

  // Simulation for testing (mimics EMF behavior near magnet)
  void _startSimulation() {
    final rng = Random();
    _simTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!mounted || !_scanning) { _simTimer?.cancel(); return; }
      // Simulate earth field ~50 µT with noise
      final noise = (rng.nextDouble() - 0.5) * 4;
      _onSample(30 + noise, 35 + noise * 0.5, 20 + noise * 0.3);
    });
  }

  void _onSample(double x, double y, double z) {
    // RAW MAGNITUDE — absolute total field strength in µT
    final mag = sqrt(x * x + y * y + z * z);

    // Fast EMA: alpha=0.35 → reacts quickly, still smooth
    // This mimics EMF Detector's responsive needle
    _emaMag = _emaMag == 0.0 ? mag : 0.35 * mag + 0.65 * _emaMag;

    // Animate needle to new gauge value
    _needle.animateTo(_gaugeValue,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);

    // Update peak
    final newPeak = _emaMag > _peakMag ? _emaMag : _peakMag;

    setState(() {
      _rawX = x; _rawY = y; _rawZ = z;
      _rawMag = mag;
      _peakMag = newPeak;
      _samples++;
    });

    // Alert on danger zone
    if (_zone == _MagZone.danger && !_alerted) {
      _alerted = true;
      HapticFeedback.heavyImpact();
      _player.play(AssetSource('beep_critical.mp3'), volume: 1.0)
          .catchError((_) {});
      Future.delayed(
          const Duration(milliseconds: 300), HapticFeedback.heavyImpact);
    } else if (_zone != _MagZone.danger) {
      _alerted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final z = _zone;
    final c = z.color;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('كاشف المجال المغناطيسي',
                style: TextStyle(color: AppColors.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => Opacity(
                opacity: _scanning ? 0.5 + _pulse.value * 0.5 : 0.4,
                child: Text(
                  _scanning ? '🔴 يرصد الآن — $_samples عينة' : '⏸ اضغط ابدأ',
                  style: TextStyle(
                      color: _scanning ? c : AppColors.textMuted,
                      fontSize: 10, fontWeight: FontWeight.w600)))),
          ]),
        actions: [
          // Reset peak button
          if (_scanning && _peakMag > 0)
            IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: AppColors.textSecondary, size: 20),
              onPressed: () => setState(() => _peakMag = 0),
              tooltip: 'إعادة الذروة'),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: ElevatedButton(
              onPressed: _scanning ? _stopScan : _startScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: _scanning
                    ? AppColors.critical.withOpacity(0.85)
                    : AppColors.safe,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
              child: Text(_scanning ? 'إيقاف' : 'ابدأ',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)))),
        ]),

      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        child: Column(children: [

          // ── DANGER BANNER ──────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: z == _MagZone.danger && _scanning
                ? _dangerBanner()
                : const SizedBox.shrink()),
          if (z == _MagZone.danger && _scanning)
            const SizedBox(height: 10),

          // ── MAIN EMF GAUGE — like the reference app ───────────────────
          _emfGauge(c),

          const SizedBox(height: 14),

          // ── RAW VALUES CARD ────────────────────────────────────────────
          _rawCard(c),

          const SizedBox(height: 14),

          // ── THRESHOLDS GUIDE ───────────────────────────────────────────
          _thresholdsCard(),

          const SizedBox(height: 14),

          if (!_scanning) _infoCard(),
        ]),
      ));
  }

  // ── DANGER BANNER ─────────────────────────────────────────────────────────
  Widget _dangerBanner() => AnimatedBuilder(
    animation: _pulse,
    builder: (_, __) => Container(
      key: const ValueKey('d'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.critical.withOpacity(
                0.5 + _pulse.value * 0.5), width: 2)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
              color: AppColors.critical, shape: BoxShape.circle),
          child: const Icon(Icons.hearing_rounded,
              color: Colors.white, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚠  مجال مغناطيسي قوي مشبوه',
              style: TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('${_emaMag.toStringAsFixed(1)} µT — سماعة مغناطيسية أو جهاز مخفي',
              style: const TextStyle(color: Color(0xFFFFD600),
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ])),
      ])));

  // ── MAIN EMF GAUGE ────────────────────────────────────────────────────────
  Widget _emfGauge(Color c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.withOpacity(0.45), width: 1.2),
        boxShadow: [BoxShadow(
            color: c.withOpacity(0.18), blurRadius: 22, spreadRadius: 2)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('قوة المجال المغناطيسي',
              style: TextStyle(color: Color(0xFF4A7A9B), fontSize: 11)),
          if (_peakMag > 0) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFF6D00).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: const Color(0xFFFF6D00).withOpacity(0.35))),
            child: Text('ذروة: ${_peakMag.toStringAsFixed(0)} µT',
                style: const TextStyle(color: Color(0xFFFF6D00),
                    fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),

        // ── Speedometer gauge ──────────────────────────────────────────
        SizedBox(
          height: 210,
          child: AnimatedBuilder(
            animation: _needle,
            builder: (_, __) => CustomPaint(
              painter: _EmfGaugePainter(
                  value:    _scanning ? _needle.value : 0.0,
                  scanning: _scanning),
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Big µT value — exactly like EMF Detector app
                  Text(
                    _scanning
                        ? '${_emaMag.toStringAsFixed(1)}'
                        : '--',
                    style: TextStyle(
                        color: c,
                        fontSize: 60,
                        fontWeight: FontWeight.w900,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: [Shadow(
                            color: c.withOpacity(0.5), blurRadius: 20)]),
                  ),
                  Text('µT',
                      style: TextStyle(
                          color: c.withOpacity(0.7),
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                ])))));

        const SizedBox(height: 6),

        // Scale labels
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _lbl('0', const Color(0xFF00E676),    'نظيف'),
              _lbl('120', const Color(0xFFFFD600),  'تنبّه'),
              _lbl('250', const Color(0xFFFF6D00),  'خطر'),
              _lbl('600+', const Color(0xFFFF1744), 'حرج'),
            ])),
      ]));
  }

  Widget _lbl(String v, Color c, String lbl) => Column(
    mainAxisSize: MainAxisSize.min, children: [
    Text(v, style: TextStyle(color: c, fontSize: 10,
        fontWeight: FontWeight.w700, fontFamily: 'monospace')),
    Text(lbl, style: TextStyle(color: c.withOpacity(0.6), fontSize: 9)),
  ]);

  // ── RAW VALUES CARD ────────────────────────────────────────────────────────
  Widget _rawCard(Color c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('القيم الخام',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
            border: Border.all(color: c.withOpacity(0.35))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_zone.icon, color: c, size: 14),
            const SizedBox(width: 5),
            Text(_zone.label, style: TextStyle(
                color: c, fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
      ]),
      const SizedBox(height: 12),
      // X Y Z + Total
      Row(children: [
        _axisBox('X', _rawX, const Color(0xFF00BCD4)),
        const SizedBox(width: 6),
        _axisBox('Y', _rawY, const Color(0xFF8BC34A)),
        const SizedBox(width: 6),
        _axisBox('Z', _rawZ, const Color(0xFFFF9800)),
        const SizedBox(width: 6),
        _axisBox('|B|', _rawMag, c, bold: true),
      ]),
    ]));

  Widget _axisBox(String axis, double val, Color c, {bool bold = false}) =>
    Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.25))),
      child: Column(children: [
        Text(axis, style: TextStyle(color: c, fontSize: 11,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(val.toStringAsFixed(1),
            style: TextStyle(color: c, fontSize: 13,
                fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
                fontFamily: 'monospace')),
        Text('µT', style: TextStyle(color: c.withOpacity(0.5), fontSize: 9)),
      ])));

  // ── THRESHOLDS GUIDE ──────────────────────────────────────────────────────
  Widget _thresholdsCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('مرجع العتبات',
          style: TextStyle(color: AppColors.textMuted,
              fontSize: 10, letterSpacing: 0.5)),
      const SizedBox(height: 10),
      _threshRow('< 65 µT',    '🟢 طبيعي', 'المجال المغناطيسي للأرض فقط',
          const Color(0xFF00E676)),
      _threshRow('65–120 µT',  '🟡 منخفض', 'معدن قريب أو جهاز كهربائي',
          const Color(0xFFFFD600)),
      _threshRow('120–250 µT', '🟠 متوسط', 'مصدر مغناطيسي قوي — تحقق',
          const Color(0xFFFF6D00)),
      _threshRow('> 250 µT',   '🔴 خطر',   'سماعة VIP Pro أو ايمان أو محرك',
          const Color(0xFFFF1744)),
    ]));

  Widget _threshRow(String range, String status, String desc, Color c) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(width: 80,
          child: Text(range, style: const TextStyle(
              color: AppColors.textMuted, fontSize: 11,
              fontFamily: 'monospace'))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(5),
            border: Border.all(color: c.withOpacity(0.35))),
          child: Text(status, style: TextStyle(
              color: c, fontSize: 10, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Expanded(child: Text(desc, style: const TextStyle(
            color: AppColors.textMuted, fontSize: 11))),
      ]));

  // ── INFO CARD ─────────────────────────────────────────────────────────────
  Widget _infoCard() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.lightbulb_outline_rounded,
            color: Color(0xFFFFD600), size: 18),
        SizedBox(width: 8),
        Text('كيفية الاستخدام',
            style: TextStyle(color: Color(0xFFFFD600),
                fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 12),
      _tip('①', 'اضغط «ابدأ» — القراءة فورية بدون معايرة'),
      _tip('②', 'القراءة الطبيعية في الهواء الطلق: 25-65 µT'),
      _tip('③', 'مرّر الهاتف فوق الطالب — إذا تجاوزت 120 µT تنبّه'),
      _tip('④', 'قراءة > 250 µT = مصدر مغناطيسي قوي — تحقق فوراً'),
      _tip('⑤', 'ابتعد عن الجدران المسلّحة والأجهزة الكهربائية'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFB044FF).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB044FF).withOpacity(0.2))),
        child: const Text(
          'المبدأ: نعرض القيمة الخام مباشرة من المستشعر (مثل تطبيق EMF Detector)'
          ' — بدون طرح baseline — فورية وحساسة',
          style: TextStyle(color: Color(0xFFB044FF),
              fontSize: 11, height: 1.5),
          textAlign: TextAlign.center)),
    ]));

  Widget _tip(String n, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$n  ', style: const TextStyle(
          color: Color(0xFF0E7C7B), fontWeight: FontWeight.w800, fontSize: 12)),
      Expanded(child: Text(t, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 11))),
    ]));
}

// ── Zone enum ──────────────────────────────────────────────────────────────────
enum _MagZone {
  clear, caution, danger;
  Color get color => switch (this) {
    _MagZone.clear   => const Color(0xFF00E676),
    _MagZone.caution => const Color(0xFFFF6D00),
    _MagZone.danger  => const Color(0xFFFF1744),
  };
  String get label => switch (this) {
    _MagZone.clear   => 'طبيعي',
    _MagZone.caution => 'تنبّه',
    _MagZone.danger  => 'خطر',
  };
  IconData get icon => switch (this) {
    _MagZone.clear   => Icons.check_circle_outline,
    _MagZone.caution => Icons.warning_amber_rounded,
    _MagZone.danger  => Icons.hearing_rounded,
  };
}

// ── EMF Gauge Painter — speedometer style like the reference app ───────────────
class _EmfGaugePainter extends CustomPainter {
  final double value;   // 0.0 → 1.0
  final bool   scanning;
  const _EmfGaugePainter({required this.value, required this.scanning});

  static const double _start = pi * 0.75;
  static const double _sweep = pi * 1.5;

  @override
  void paint(Canvas canvas, Size sz) {
    final cx = sz.width / 2;
    final cy = sz.height * 0.86;
    final r  = sz.width * 0.44;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Background track
    canvas.drawArc(rect, _start, _sweep, false,
        Paint()
          ..color = const Color(0xFF1E3050)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 20
          ..strokeCap = StrokeCap.round);

    if (!scanning) return;

    final glowC = value < 0.20 ? const Color(0xFF00E676)
        : value < 0.42 ? const Color(0xFFFFD600)
        : value < 0.70 ? const Color(0xFFFF6D00)
        : const Color(0xFFFF1744);

    // Glow
    if (value > 0.01) {
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          _start, _sweep * value, false,
          Paint()
            ..color = glowC.withOpacity(0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 28
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }

    // Colored arc in 4 segments
    const segs = [
      (end: 0.20, c: Color(0xFF00E676)),
      (end: 0.42, c: Color(0xFFFFD600)),
      (end: 0.70, c: Color(0xFFFF6D00)),
      (end: 1.00, c: Color(0xFFFF1744)),
    ];
    double prev = 0.0;
    for (final s in segs) {
      final drawn = value.clamp(prev, s.end);
      if (drawn > prev) {
        canvas.drawArc(
            rect, _start + _sweep * prev, _sweep * (drawn - prev), false,
            Paint()
              ..color = s.c
              ..style = PaintingStyle.stroke
              ..strokeWidth = 20
              ..strokeCap = StrokeCap.round);
      }
      prev = s.end;
    }

    // Tick marks + labels
    for (int i = 0; i <= 12; i++) {
      final a     = _start + _sweep * (i / 12);
      final isMaj = i % 3 == 0;
      final inner = r - (isMaj ? 32 : 24);
      canvas.drawLine(
          Offset(cx + inner * cos(a), cy + inner * sin(a)),
          Offset(cx + (r - 8) * cos(a), cy + (r - 8) * sin(a)),
          Paint()
            ..color = (isMaj ? Colors.white : const Color(0xFF4A7A9B))
                .withOpacity(0.5)
            ..strokeWidth = isMaj ? 2.0 : 1.0);

      if (isMaj) {
        final µtVal = (i / 12 * 600).round();
        final tp = TextPainter(
          text: TextSpan(
            text: '$µtVal',
            style: const TextStyle(color: Color(0xFF4A7A9B),
                fontSize: 9, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr)..layout();
        final lx = cx + (inner - 13) * cos(a) - tp.width / 2;
        final ly = cy + (inner - 13) * sin(a) - tp.height / 2;
        tp.paint(canvas, Offset(lx, ly));
      }
    }

    // Needle
    final na  = _start + _sweep * value;
    final nx  = cx + (r - 28) * cos(na);
    final ny  = cy + (r - 28) * sin(na);
    // Glow
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()..color = glowC.withOpacity(0.35)
            ..strokeWidth = 8..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    // Body
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()..color = glowC..strokeWidth = 4..strokeCap = StrokeCap.round);

    // Centre cap
    canvas.drawCircle(Offset(cx, cy), 12,
        Paint()..color = glowC.withOpacity(0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(Offset(cx, cy), 9,
        Paint()..color = const Color(0xFF0D1B2A));
    canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = glowC);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_EmfGaugePainter o) =>
      o.value != value || o.scanning != scanning;
}
