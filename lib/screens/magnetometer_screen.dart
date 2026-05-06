import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';

// ══════════════════════════════════════════════════════════════════════════════
// MagnetometerScreen — كشف سماعات الحث المغناطيسي (VIP Pro Max)
//
// المبدأ العلمي:
//   سماعة الحث تحتوي على ملف كهربائي (coil) يولّد مجالاً مغناطيسياً
//   مستمراً أقوى من المجال الأرضي الطبيعي.
//   المجال الأرضي الطبيعي: 25–65 µT
//   الملف المخفي تحت الملابس: يضيف 15–80 µT إضافية
//   → الكشف: إذا كانت δ = magnitude_actuelle - baseline > seuil
// ══════════════════════════════════════════════════════════════════════════════
class MagnetometerScreen extends StatefulWidget {
  const MagnetometerScreen({super.key});
  @override State<MagnetometerScreen> createState() => _MagState();
}

class _MagState extends State<MagnetometerScreen>
    with TickerProviderStateMixin {

  // ── Animations ─────────────────────────────────────────────────────────────
  late AnimationController _needleCtrl;   // speedometer needle
  late AnimationController _pulseCtrl;    // danger pulse
  late AnimationController _scanCtrl;     // scan ripple

  // ── Sensor state ───────────────────────────────────────────────────────────
  double _x = 0, _y = 0, _z = 0;
  double _magnitude   = 0;      // √(x²+y²+z²) en µT
  double _baseline    = -1;     // calibrated ambient field
  double _delta       = 0;      // magnitude - baseline
  double _smoothDelta = 0;      // EMA-filtered delta
  double _peakDelta   = 0;      // max delta seen in session

  // ── Stability filter ───────────────────────────────────────────────────────
  final List<double> _buf = [];  // rolling buffer (last 20 readings)
  static const int _N = 20;
  int _dangerVotes = 0;          // consecutive above-threshold readings
  static const int _VOTES = 5;  // need 5 consecutive → real detection

  // ── Alert thresholds (µT) ──────────────────────────────────────────────────
  static const double _THRESH_WARN   = 20.0;  // orange: suspicious
  static const double _THRESH_DANGER = 35.0;  // red: induction coil detected

  // ── State ──────────────────────────────────────────────────────────────────
  bool _calibrated   = false;
  bool _calibrating  = false;
  bool _isDetected   = false;
  bool _alerted      = false;
  bool _scanning     = false;
  int  _sampleCount  = 0;
  final List<double> _calSamples = [];

  // ── Needle target (0.0 → 1.0) ─────────────────────────────────────────────
  double _needleTarget = 0.0;

  final AudioPlayer _player = AudioPlayer();
  StreamSubscription? _magSub;

  @override
  void initState() {
    super.initState();
    _needleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _pulseCtrl  = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _scanCtrl   = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat();
  }

  @override
  void dispose() {
    _magSub?.cancel();
    _needleCtrl.dispose();
    _pulseCtrl.dispose();
    _scanCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  // ── Start / Stop ───────────────────────────────────────────────────────────
  void _startScan() {
    setState(() { _scanning = true; _sampleCount = 0; });
    _magSub?.cancel();
    _magSub = magnetometerEventStream(
        samplingPeriod: SensorInterval.gameInterval)  // ~50ms
        .listen(_onMagEvent);
  }

  void _stopScan() {
    _magSub?.cancel();
    setState(() { _scanning = false; });
  }

  // ── Sensor event processing ────────────────────────────────────────────────
  void _onMagEvent(MagnetometerEvent e) {
    _x = e.x; _y = e.y; _z = e.z;
    final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _sampleCount++;

    // Calibration phase — collect 40 samples (~2 seconds)
    if (_calibrating) {
      _calSamples.add(mag);
      if (_calSamples.length >= 40) {
        _calSamples.sort();
        // Median as baseline (robust to outliers)
        _baseline = _calSamples[20];
        setState(() { _calibrating = false; _calibrated = true; });
      }
      return;
    }

    if (!_calibrated || !_scanning) return;

    // Rolling buffer
    _buf.add(mag);
    if (_buf.length > _N) _buf.removeAt(0);

    // Median of buffer
    final sorted = List<double>.from(_buf)..sort();
    final median = sorted[sorted.length ~/ 2];

    // Delta from baseline
    final delta = (median - _baseline).clamp(0.0, 150.0);

    // EMA smoothing (alpha=0.25)
    _smoothDelta = 0.25 * delta + 0.75 * _smoothDelta;

    // Peak tracking
    if (_smoothDelta > _peakDelta) _peakDelta = _smoothDelta;

    // Needle target: 0% = 0µT delta, 100% = 60µT delta
    final target = (_smoothDelta / 60.0).clamp(0.0, 1.0);

    // Voting system for detection
    if (_smoothDelta >= _THRESH_DANGER) {
      _dangerVotes++;
    } else {
      _dangerVotes = 0;
    }

    final detected = _dangerVotes >= _VOTES;

    // Alert
    if (detected && !_alerted) {
      _alerted = true;
      HapticFeedback.heavyImpact();
      _player.play(AssetSource('beep_critical.mp3'), volume: 1.0)
          .catchError((_) {});
      Future.delayed(const Duration(milliseconds: 400), HapticFeedback.heavyImpact);
    } else if (!detected) {
      _alerted = false;
    }

    setState(() {
      _magnitude   = mag;
      _delta       = delta;
      _smoothDelta = _smoothDelta;
      _isDetected  = detected;
      _needleTarget = target;
    });

    // Animate needle
    _needleCtrl.animateTo(target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut);
  }

  // ── Calibration ────────────────────────────────────────────────────────────
  void _startCalibration() {
    _calSamples.clear();
    _baseline    = -1;
    _calibrated  = false;
    _peakDelta   = 0;
    _smoothDelta = 0;
    _dangerVotes = 0;
    setState(() { _calibrating = true; });
    if (!_scanning) _startScan();
  }

  // ── Level ──────────────────────────────────────────────────────────────────
  _Level get _level {
    if (!_calibrated) return _Level.idle;
    if (_isDetected)             return _Level.danger;
    if (_smoothDelta >= _THRESH_WARN) return _Level.warning;
    return _Level.safe;
  }

  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final lv = _level;
    final c  = lv.color;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () { _stopScan(); Navigator.pop(context); }),
        title: Row(children: [
          const Icon(Icons.sensors_rounded, color: Color(0xFF7B68EE), size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('كشف سماعة الحث المغناطيسي',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700))),
          // Field value live
          if (_calibrated) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: c.withOpacity(0.4))),
            child: Text('δ ${_smoothDelta.toStringAsFixed(1)} µT',
                style: TextStyle(color: c, fontSize: 10,
                    fontWeight: FontWeight.w700))),
        ]),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [

          // ── Alert banner ────────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _isDetected ? _dangerBanner() : const SizedBox.shrink()),
          if (_isDetected) const SizedBox(height: 10),

          // ── Main speedometer ─────────────────────────────────────────────
          _speedometer(c, lv),

          const SizedBox(height: 14),

          // ── Status cards row ─────────────────────────────────────────────
          Row(children: [
            Expanded(child: _statCard('المجال الكلي',
                '${_magnitude.toStringAsFixed(1)} µT',
                Icons.radar_rounded, AppColors.accent)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('الزيادة (δ)',
                '${_smoothDelta.toStringAsFixed(1)} µT',
                Icons.trending_up_rounded, c)),
            const SizedBox(width: 10),
            Expanded(child: _statCard('الذروة',
                '${_peakDelta.toStringAsFixed(1)} µT',
                Icons.show_chart_rounded, AppColors.high)),
          ]),

          const SizedBox(height: 14),

          // ── Axes display ─────────────────────────────────────────────────
          _axesCard(),

          const SizedBox(height: 14),

          // ── Control buttons ──────────────────────────────────────────────
          _controls(),

          const SizedBox(height: 14),

          // ── How to use guide ─────────────────────────────────────────────
          _guide(),
        ]),
      ),
    );
  }

  // ── Danger banner ─────────────────────────────────────────────────────────
  Widget _dangerBanner() => AnimatedBuilder(
    animation: _pulseCtrl,
    builder: (_, __) => Container(
      key: const ValueKey('mag_danger'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0000),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.critical.withOpacity(
                0.5 + _pulseCtrl.value * 0.5), width: 2.0)),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
              color: AppColors.critical, shape: BoxShape.circle),
          child: const Icon(Icons.settings_input_antenna_rounded,
              color: Colors.white, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚠  كُشفت سماعة حث مغناطيسي',
              style: TextStyle(color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 5),
          Row(children: [
            _pill('VIP Pro / بوبي', const Color(0xFFFFD600)),
            const SizedBox(width: 8),
            _pill('δ ${_smoothDelta.toStringAsFixed(0)} µT',
                AppColors.critical),
          ]),
        ])),
      ])));

  // ── Speedometer ───────────────────────────────────────────────────────────
  Widget _speedometer(Color c, _Level lv) => Container(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 14),
    decoration: BoxDecoration(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: c.withOpacity(0.45), width: 1.2),
      boxShadow: [BoxShadow(
          color: _isDetected ? c.withOpacity(0.2) : Colors.transparent,
          blurRadius: 24, spreadRadius: 2)]),
    child: Column(children: [
      // Title
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('مقياس الحقل المغناطيسي',
            style: TextStyle(color: Color(0xFF4A7A9B),
                fontSize: 11, letterSpacing: 0.5)),
        Text(lv.label,
            style: TextStyle(color: c, fontSize: 11,
                fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 10),

      // Arc gauge
      SizedBox(
        height: 200,
        child: AnimatedBuilder(
          animation: _needleCtrl,
          builder: (_, __) => CustomPaint(
            painter: _MagGaugePainter(
                value: _needleCtrl.value,
                threshWarn: _THRESH_WARN / 60.0,
                threshDanger: _THRESH_DANGER / 60.0),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Big value
                  TweenAnimationBuilder<double>(
                    tween: Tween(end: _smoothDelta),
                    duration: const Duration(milliseconds: 500),
                    builder: (_, v, __) => Text(
                      v.toStringAsFixed(1),
                      style: TextStyle(color: c, fontSize: 52,
                          fontWeight: FontWeight.w900, height: 1.0,
                          shadows: [Shadow(
                              color: c.withOpacity(0.5), blurRadius: 18)])),
                  ),
                  Text('µT', style: TextStyle(
                      color: c.withOpacity(0.7), fontSize: 18,
                      fontWeight: FontWeight.w600)),
                ])))),
        )),

      const SizedBox(height: 8),
      // Scale labels
      Directionality(
        textDirection: TextDirection.ltr,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _scaleLbl('0', '● طبيعي',    const Color(0xFF00E676)),
            _scaleLbl('20',  '● مريب',   const Color(0xFFFF6D00)),
            _scaleLbl('35+', '● خطر',    const Color(0xFFFF1744)),
          ])),
    ]));

  Widget _scaleLbl(String v, String t, Color c) => Column(
    children: [
    Text(v, style: TextStyle(color: c, fontSize: 11,
        fontWeight: FontWeight.w700)),
    Text(t, style: TextStyle(color: c.withOpacity(0.6), fontSize: 9)),
  ]);

  // ── Axes card ─────────────────────────────────────────────────────────────
  Widget _axesCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Column(children: [
      const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
        Text('محاور المجال المغناطيسي',
            style: TextStyle(color: AppColors.textMuted,
                fontSize: 11, letterSpacing: 0.5)),
        Text('(µT)',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]),
      const SizedBox(height: 10),
      _axisBar('X', _x, const Color(0xFFFF6B6B)),
      const SizedBox(height: 6),
      _axisBar('Y', _y, const Color(0xFF6BCB77)),
      const SizedBox(height: 6),
      _axisBar('Z', _z, const Color(0xFF4D96FF)),
    ]));

  Widget _axisBar(String axis, double val, Color c) {
    final norm = (val.abs() / 100.0).clamp(0.0, 1.0);
    return Row(children: [
      SizedBox(width: 16, child: Text(axis,
          style: TextStyle(color: c, fontSize: 11,
              fontWeight: FontWeight.w700))),
      const SizedBox(width: 8),
      Expanded(child: Stack(children: [
        Container(height: 14,
            decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(7))),
        AnimatedFractionallySizedBox(
          duration: const Duration(milliseconds: 200),
          widthFactor: norm,
          alignment: Alignment.centerLeft,
          child: Container(
            height: 14,
            decoration: BoxDecoration(
                color: c.withOpacity(0.7),
                borderRadius: BorderRadius.circular(7),
                boxShadow: [BoxShadow(
                    color: c.withOpacity(0.4), blurRadius: 6)]))),
      ])),
      const SizedBox(width: 8),
      SizedBox(width: 55,
          child: Text('${val.toStringAsFixed(1)} µT',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
              textDirection: TextDirection.ltr)),
    ]);
  }

  // ── Controls ──────────────────────────────────────────────────────────────
  Widget _controls() => Column(children: [
    // Calibration button
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _calibrating ? null : _startCalibration,
        icon: _calibrating
            ? const SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.tune_rounded, size: 18),
        label: Text(_calibrating
            ? 'جارٍ المعايرة... (${_calSamples.length}/40)'
            : _calibrated ? 'إعادة المعايرة' : 'معايرة البيئة'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7B68EE),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))))),
    const SizedBox(height: 10),
    // Start/Stop
    SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: !_calibrated ? null
            : _scanning ? _stopScan : _startScan,
        icon: Icon(_scanning ? Icons.stop_rounded : Icons.search_rounded,
            size: 18),
        label: Text(_scanning ? 'إيقاف الكشف' : 'بدء الكشف'),
        style: ElevatedButton.styleFrom(
          backgroundColor: _scanning
              ? const Color(0xFFFF1744) : const Color(0xFF00803C),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12))))),
  ]);

  // ── Usage guide ───────────────────────────────────────────────────────────
  Widget _guide() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF7B68EE).withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
          color: const Color(0xFF7B68EE).withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.lightbulb_outline_rounded,
            color: Color(0xFF7B68EE), size: 16),
        SizedBox(width: 8),
        Text('دليل الاستخدام الميداني',
            style: TextStyle(color: Color(0xFF7B68EE),
                fontWeight: FontWeight.w700, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      _guideStep('①', 'اضغط «معايرة» في منتصف القاعة بعيداً عن أي أجهزة'),
      _guideStep('②', 'بعد المعايرة اضغط «بدء الكشف»'),
      _guideStep('③', 'اقترب ببطء من الطالب — المقياس يتصاعد عند وجود ملف'),
      _guideStep('④', 'عند الاقتراب من الصدر/الخصر — المجال يرتفع بشكل واضح'),
      _guideStep('⑤', 'التنبيه الأحمر يُشغَّل عند δ > 35 µT لأكثر من ثانية'),
    ]));

  Widget _guideStep(String n, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$n  ', style: const TextStyle(
          color: Color(0xFF7B68EE),
          fontWeight: FontWeight.w800, fontSize: 11)),
      Expanded(child: Text(t, style: const TextStyle(
          color: AppColors.textMuted, fontSize: 11, height: 1.4))),
    ]));

  Widget _statCard(String lbl, String val, IconData icon, Color c) =>
    Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.25), width: 0.5)),
      child: Column(children: [
        Icon(icon, color: c, size: 20),
        const SizedBox(height: 6),
        Text(val, style: TextStyle(color: c, fontSize: 12,
            fontWeight: FontWeight.w800), textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(lbl, style: const TextStyle(
            color: AppColors.textMuted, fontSize: 9),
            textAlign: TextAlign.center),
      ]));

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12),
      borderRadius: BorderRadius.circular(7),
      border: Border.all(color: c.withOpacity(0.5), width: 0.8)),
    child: Text(t, style: TextStyle(color: c, fontSize: 11,
        fontWeight: FontWeight.w700)));
}

// ── Gauge Painter ──────────────────────────────────────────────────────────────
class _MagGaugePainter extends CustomPainter {
  final double value;
  final double threshWarn, threshDanger;
  const _MagGaugePainter({
    required this.value,
    required this.threshWarn,
    required this.threshDanger,
  });

  static const double _start = pi * 0.75;
  static const double _sweep = pi * 1.5;

  @override
  void paint(Canvas canvas, Size sz) {
    final cx = sz.width / 2;
    final cy = sz.height * 0.86;
    final r  = sz.width * 0.42;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // Background track
    canvas.drawArc(rect, _start, _sweep, false,
        Paint()..color = const Color(0xFF1E3050)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 22..strokeCap = StrokeCap.round);

    // Glow behind active arc
    if (value > 0) {
      final glowC = value >= threshDanger
          ? const Color(0xFFFF1744)
          : value >= threshWarn
              ? const Color(0xFFFF6D00)
              : const Color(0xFF00E676);
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          _start, _sweep * value, false,
          Paint()..color = glowC.withOpacity(0.15)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 30..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }

    // 3-color arc segments
    final segs = [
      (end: threshWarn,   c: const Color(0xFF00E676)),
      (end: threshDanger, c: const Color(0xFFFF6D00)),
      (end: 1.0,          c: const Color(0xFFFF1744)),
    ];
    double prev = 0.0;
    for (final s in segs) {
      final drawn = value.clamp(prev, s.end);
      if (drawn > prev) {
        canvas.drawArc(rect, _start + _sweep * prev,
            _sweep * (drawn - prev), false,
            Paint()..color = s.c
                ..style = PaintingStyle.stroke
                ..strokeWidth = 22..strokeCap = StrokeCap.round);
      }
      prev = s.end;
    }

    // Tick marks
    for (int i = 0; i <= 10; i++) {
      final a     = _start + _sweep * (i / 10);
      final isMaj = i % 2 == 0;
      final inner = r - (isMaj ? 32 : 24);
      final outer = r - 8;
      canvas.drawLine(
          Offset(cx + inner * cos(a), cy + inner * sin(a)),
          Offset(cx + outer * cos(a), cy + outer * sin(a)),
          Paint()
            ..color = (isMaj ? Colors.white : const Color(0xFF4A7A9B))
                .withOpacity(0.45)
            ..strokeWidth = isMaj ? 2.0 : 1.0);
      if (isMaj) {
        final lbl = '${(i * 6).toString()}';
        final tp = TextPainter(
            text: TextSpan(text: lbl,
                style: const TextStyle(color: Color(0xFF4A7A9B), fontSize: 8)),
            textDirection: TextDirection.ltr)..layout();
        final lx = cx + (inner - 12) * cos(a) - tp.width / 2;
        final ly = cy + (inner - 12) * sin(a) - tp.height / 2;
        tp.paint(canvas, Offset(lx, ly));
      }
    }

    // Threshold markers
    for (final (thresh, color) in [
      (threshWarn, const Color(0xFFFF6D00)),
      (threshDanger, const Color(0xFFFF1744)),
    ]) {
      final a  = _start + _sweep * thresh;
      final x1 = cx + (r - 36) * cos(a);
      final y1 = cy + (r - 36) * sin(a);
      final x2 = cx + (r + 2) * cos(a);
      final y2 = cy + (r + 2) * sin(a);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2),
          Paint()..color = color..strokeWidth = 2.5);
    }

    // Needle
    final na = _start + _sweep * value;
    final nC = value >= threshDanger
        ? const Color(0xFFFF1744)
        : value >= threshWarn
            ? const Color(0xFFFF6D00)
            : const Color(0xFF00E676);
    final nx = cx + (r - 30) * cos(na);
    final ny = cy + (r - 30) * sin(na);

    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()..color = nC.withOpacity(0.3)..strokeWidth = 8
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()..color = nC..strokeWidth = 4
            ..strokeCap = StrokeCap.round);

    canvas.drawCircle(Offset(cx, cy), 12,
        Paint()..color = nC.withOpacity(0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    canvas.drawCircle(Offset(cx, cy), 9,
        Paint()..color = const Color(0xFF1E3050));
    canvas.drawCircle(Offset(cx, cy), 7, Paint()..color = nC);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MagGaugePainter o) => o.value != value;
}

// ── Level enum ─────────────────────────────────────────────────────────────────
enum _Level {
  idle, safe, warning, danger;
  Color get color => switch (this) {
    _Level.idle    => const Color(0xFF4A7A9B),
    _Level.safe    => const Color(0xFF00E676),
    _Level.warning => const Color(0xFFFF6D00),
    _Level.danger  => const Color(0xFFFF1744),
  };
  String get label => switch (this) {
    _Level.idle    => 'في انتظار المعايرة',
    _Level.safe    => 'لا يوجد حث مغناطيسي',
    _Level.warning => 'مجال مريب — اقترب أكثر',
    _Level.danger  => 'كُشفت سماعة حث !',
  };
}
