import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';

class MagneticDetectorScreen extends StatefulWidget {
  const MagneticDetectorScreen({super.key});
  @override State<MagneticDetectorScreen> createState() => _MagState();
}

class _MagState extends State<MagneticDetectorScreen>
    with TickerProviderStateMixin {

  late AnimationController _pulse;

  static const _channel = EventChannel('tn.gov.education.examguard/magnetometer');
  StreamSubscription? _sub;
  Timer? _simTimer;

  // ── Signal state ──────────────────────────────────────────────────────────
  final List<double> _buf = [];       // rolling 50-sample buffer (1 second)
  static const int   _bufSize = 50;
  double _ema       = 0.0;   // EMA-smoothed magnitude
  double _magnitude = 0.0;   // raw field magnitude for display
  double _baseline  = 0.0;
  double _gaugeVal = 0.0;           // 0.0 → 1.0 FAST responsive
  double _dispVal  = 0.0;           // smoothed display value
  bool   _calibrated = false;
  bool   _scanning   = false;
  bool   _alerted    = false;
  int    _calibTicks = 0;

  static const double _threshLow    = 20.0;   // µT² caution
  static const double _threshDanger = 45.0;   // µT² danger

  final _player = AudioPlayer();

  _MagZone get _zone => _gaugeVal > 0.72 ? _MagZone.danger
      : _gaugeVal > 0.40 ? _MagZone.caution
      : _MagZone.clear;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _simTimer?.cancel();
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _scanning    = true;
      _calibrated  = false;
      _calibTicks  = 0;
      _buf.clear();
      _ema         = 0.0;
      _baseline    = 0.0;
      _gaugeVal    = 0.0;
      _dispVal     = 0.0;
    });

    _sub = _channel.receiveBroadcastStream().listen(
      (data) {
        if (!mounted || !_scanning) return;
        final x = (data[0] as num).toDouble();
        final y = (data[1] as num).toDouble();
        final z = (data[2] as num).toDouble();
        _processSample(x, y, z);
      },
      onError: (_) => _startSimulation(),
    );
  }

  void _stopScan() {
    _sub?.cancel();
    _simTimer?.cancel();
    _sub = null;
    _simTimer = null;
    setState(() {
      _scanning = false;
      _gaugeVal = 0.0;
      _dispVal  = 0.0;
      _alerted  = false;
    });
  }

  // Simulation for devices without sensor (testing only)
  void _startSimulation() {
    final rng = Random();
    _simTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      if (!mounted || !_scanning) { _simTimer?.cancel(); return; }
      final noise = (rng.nextDouble() - 0.5) * 3;
      _processSample(48.0 + noise, noise * 0.4, noise * 0.2);
    });
  }

  void _processSample(double x, double y, double z) {
    final mag = sqrt(x * x + y * y + z * z);

    // Fast EMA alpha=0.3 → responsive
    _ema = _ema == 0.0 ? mag : 0.30 * mag + 0.70 * _ema;

    _buf.add(mag);
    if (_buf.length > _bufSize) _buf.removeAt(0);
    if (_buf.length < 5) return;

    // Calibration: first 50 samples (~1 second)
    _calibTicks++;
    if (!_calibrated) {
      if (_calibTicks >= 50) {
        _baseline   = _buf.reduce((a, b) => a + b) / _buf.length;
        _calibrated = true;
      }
      return;
    }

    // ── DUAL-MODE DETECTION ────────────────────────────────────────────────
    // Mode A: VARIANCE — active magnetic loop (VIP Pro oscillating field)
    double sumSq = 0;
    for (final v in _buf) sumSq += (v - _baseline) * (v - _baseline);
    final variance = sumSq / _buf.length;
    final scoreA = (variance / (_threshDanger * 1.5)).clamp(0.0, 1.0);

    // Mode B: AMPLITUDE — any strong static anomaly (magnet, transformer, coil)
    // Deviation = how far EMA is from baseline regardless of oscillation
    final deviation = (_ema - _baseline).abs();
    // 8 µT = caution (40%), 20 µT = danger zone (100%)
    final scoreB = (deviation / 20.0).clamp(0.0, 1.0);

    // Best of both: sensitive to oscillating AND static fields
    final rawScore = scoreA > scoreB ? scoreA : scoreB;
    final newGauge = 0.25 * rawScore + 0.75 * _gaugeVal;

    setState(() {
      _magnitude = mag;
      _gaugeVal  = newGauge;
      _dispVal   = newGauge;
    });

    // Alert
    // Alert
    if (_zone == _MagZone.danger && !_alerted) {
      _alerted = true;
      HapticFeedback.heavyImpact();
      _player.play(AssetSource('beep_critical.mp3'), volume: 1.0)
          .catchError((_) {});
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
          const Text('مسح سماعات مغناطيسية',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w700)),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Opacity(
              opacity: _scanning ? 0.5 + _pulse.value * 0.5 : 0.4,
              child: Text(
                !_scanning         ? '⏸ اضغط ابدأ'
                    : !_calibrated ? '⏳ معايرة...'
                    : '🔴 يرصد الآن',
                style: TextStyle(
                    color: _scanning && _calibrated ? c : AppColors.textMuted,
                    fontSize: 10, fontWeight: FontWeight.w600)))),
        ]),
        actions: [
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

          // ── Danger banner ──────────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: z == _MagZone.danger && _calibrated
                ? _dangerBanner()
                : const SizedBox.shrink()),
          if (z == _MagZone.danger && _calibrated)
            const SizedBox(height: 10),

          // ── GAUGE — completely different style from BT meter ───────────
          _ringGauge(c),

          const SizedBox(height: 14),

          // ── Signal bars strip ─────────────────────────────────────────
          _signalStrip(c),

          const SizedBox(height: 14),

          // ── Field values card ─────────────────────────────────────────
          _fieldCard(c),

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
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('⚠  مجال مغناطيسي مشبوه',
              style: TextStyle(color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w900)),
          SizedBox(height: 4),
          Text('سماعة مغناطيسية محتملة — تحقق فوراً',
              style: TextStyle(color: Color(0xFFFFD600),
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ])),
      ])));

  // ── RING GAUGE — unique style (not speedometer) ───────────────────────────
  // Concentric animated rings + big % in center
  Widget _ringGauge(Color c) {
    final pct = (_dispVal * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.withOpacity(0.4), width: 1.2),
        boxShadow: [BoxShadow(
            color: c.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('كاشف المجال المغناطيسي',
              style: TextStyle(color: Color(0xFF4A7A9B), fontSize: 11)),
          if (_calibrated) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.withOpacity(0.35))),
            child: Text('$pct %',
                style: TextStyle(color: c, fontSize: 11,
                    fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 12),

        // Concentric rings gauge
        SizedBox(
          height: 220,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => CustomPaint(
              painter: _RingGaugePainter(
                  value:    _scanning && _calibrated ? _dispVal : 0.0,
                  pulse:    _pulse.value,
                  scanning: _scanning && _calibrated),
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _scanning && _calibrated ? '$pct' : '--',
                    style: TextStyle(
                        color: c, fontSize: 68,
                        fontWeight: FontWeight.w900,
                        shadows: [Shadow(
                            color: c.withOpacity(0.5), blurRadius: 20)])),
                  Text('%', style: TextStyle(
                      color: c.withOpacity(0.7), fontSize: 20,
                      fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_zone.label,
                      style: TextStyle(color: c.withOpacity(0.6),
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ]))))),

        const SizedBox(height: 10),

        // Zone row
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(children: [
            _zonePill('نظيف',   const Color(0xFF00E676), _zone == _MagZone.clear),
            const SizedBox(width: 6),
            _zonePill('مشبوه',  const Color(0xFFFF6D00), _zone == _MagZone.caution),
            const SizedBox(width: 6),
            _zonePill('خطر',    const Color(0xFFFF1744), _zone == _MagZone.danger),
          ])),
      ]));
  }

  Widget _zonePill(String t, Color c, bool active) => Expanded(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: active ? c.withOpacity(0.15) : c.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: active ? c.withOpacity(0.7) : c.withOpacity(0.15),
            width: active ? 1.2 : 0.5)),
      child: Text(t, textAlign: TextAlign.center,
          style: TextStyle(
              color: active ? c : c.withOpacity(0.3),
              fontSize: 11,
              fontWeight: active ? FontWeight.w800 : FontWeight.w400))));

  // ── SIGNAL STRIP — 20 vertical bars ──────────────────────────────────────
  Widget _signalStrip(Color c) {
    const bars = 20;
    final filled = (_dispVal * bars).round().clamp(0, bars);

    // Build bar widgets explicitly to avoid Dart parser issues
    final barWidgets = <Widget>[];
    for (int i = 0; i < bars; i++) {
      final on   = i < filled;
      final frac = (i + 1) / bars;
      final barC = frac < 0.40
          ? const Color(0xFF00E676)
          : frac < 0.72
              ? const Color(0xFFFF6D00)
              : const Color(0xFFFF1744);
      barWidgets.add(Expanded(child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 10.0 + (i / bars) * 28,
        margin: const EdgeInsets.symmetric(horizontal: 1.5),
        decoration: BoxDecoration(
          color: on ? barC : barC.withOpacity(0.1),
          borderRadius: BorderRadius.circular(3),
          boxShadow: on
              ? [BoxShadow(color: barC.withOpacity(0.4), blurRadius: 4)]
              : []))));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border, width: 0.5)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('شدة الإشارة',
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          Text('${(_dispVal * 100).toStringAsFixed(0)} %',
              style: TextStyle(color: c, fontSize: 10,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: barWidgets)),
      ]));
  }
  // ── FIELD VALUES CARD ─────────────────────────────────────────────────────
  Widget _fieldCard(Color c) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.withOpacity(0.10),
          border: Border.all(color: c.withOpacity(0.35))),
        child: Icon(Icons.settings_input_antenna_rounded, color: c, size: 22)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        const Text('قيم المجال المغناطيسي',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        const SizedBox(height: 3),
        Text('${_ema.toStringAsFixed(1)} µT',
            style: TextStyle(color: c, fontSize: 20,
                fontWeight: FontWeight.w800)),
        Text('خط الأساس: ${_baseline.toStringAsFixed(1)} µT',
            style: const TextStyle(
                color: AppColors.textMuted, fontSize: 10)),
      ])),
      Column(children: [
        Icon(_zone.icon, color: c, size: 22),
        const SizedBox(height: 3),
        Text(_zone.label, style: TextStyle(
            color: c, fontSize: 11, fontWeight: FontWeight.w700)),
      ]),
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
        Text('كيف يعمل الكشف؟',
            style: TextStyle(color: Color(0xFFFFD600),
                fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 12),
      _tip('🎧', 'السماعة VIP Pro تعمل بحلقة مغناطيسية تحت الملابس لا تحتاج Bluetooth'),
      _tip('📡', 'الحلقة تولّد مجالاً مغناطيسياً متغيراً يُرسل الصوت للسماعة'),
      _tip('📱', 'مستشعر المغناطيس في هاتفك يرصد هذه التغيّرات بدقة عالية'),
      _tip('📏', 'مرّر الهاتف على ارتفاع 20-30 سم فوق الطالب بحركة بطيئة'),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFB044FF).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: const Color(0xFFB044FF).withOpacity(0.2))),
        child: const Text(
            'هذا الكاشف مستقل تماماً عن Bluetooth ويعمل حتى مع هواتف في وضع الطيران',
            style: TextStyle(color: Color(0xFFB044FF),
                fontSize: 11, height: 1.5),
            textAlign: TextAlign.center)),
    ]));

  Widget _tip(String icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$icon  ', style: const TextStyle(fontSize: 14)),
      Expanded(child: Text(text, style: const TextStyle(
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
    _MagZone.clear   => 'نظيف',
    _MagZone.caution => 'مشبوه',
    _MagZone.danger  => 'خطر',
  };
  IconData get icon => switch (this) {
    _MagZone.clear   => Icons.check_circle_outline,
    _MagZone.caution => Icons.warning_amber_rounded,
    _MagZone.danger  => Icons.hearing_rounded,
  };
}

// ── Concentric Ring Gauge Painter — completely different from speedometer ──────
class _RingGaugePainter extends CustomPainter {
  final double value;
  final double pulse;
  final bool   scanning;
  const _RingGaugePainter({
      required this.value, required this.pulse, required this.scanning});

  @override
  void paint(Canvas canvas, Size sz) {
    final cx = sz.width  / 2;
    final cy = sz.height / 2;

    // 3 concentric rings — thin, medium, thick
    final rings = [
      (r: sz.width * 0.42, w: 6.0,  pct: value.clamp(0.0, 1.0)),
      (r: sz.width * 0.32, w: 10.0, pct: (value * 1.3).clamp(0.0, 1.0)),
      (r: sz.width * 0.20, w: 16.0, pct: (value * 1.6).clamp(0.0, 1.0)),
    ];

    for (final ring in rings) {
      final rect = Rect.fromCircle(
          center: Offset(cx, cy), radius: ring.r);

      // Background track
      canvas.drawArc(rect, -pi / 2, 2 * pi, false,
          Paint()
            ..color = const Color(0xFF1E3050)
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring.w);

      if (!scanning || ring.pct <= 0) continue;

      // Color based on value
      final c = ring.pct < 0.4 ? const Color(0xFF00E676)
          : ring.pct < 0.72 ? const Color(0xFFFF6D00)
          : const Color(0xFFFF1744);

      // Glow
      if (ring.pct > 0.1) {
        canvas.drawArc(rect, -pi / 2, 2 * pi * ring.pct, false,
            Paint()
              ..color = c.withOpacity(0.15 + pulse * 0.08)
              ..style = PaintingStyle.stroke
              ..strokeWidth = ring.w + 8
              ..strokeCap = StrokeCap.round
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      }

      // Arc
      canvas.drawArc(rect, -pi / 2, 2 * pi * ring.pct, false,
          Paint()
            ..color = c
            ..style = PaintingStyle.stroke
            ..strokeWidth = ring.w
            ..strokeCap = StrokeCap.round);

      // Tip dot
      final tipAngle = -pi / 2 + 2 * pi * ring.pct;
      canvas.drawCircle(
          Offset(cx + ring.r * cos(tipAngle), cy + ring.r * sin(tipAngle)),
          ring.w / 2 + 2,
          Paint()..color = c
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    }

    // Centre dot
    if (scanning) {
      final c = value < 0.4 ? const Color(0xFF00E676)
          : value < 0.72 ? const Color(0xFFFF6D00)
          : const Color(0xFFFF1744);
      canvas.drawCircle(Offset(cx, cy), 8 + pulse * 4,
          Paint()..color = c.withOpacity(0.2 + pulse * 0.2)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
      canvas.drawCircle(Offset(cx, cy), 6, Paint()..color = c);
    }
  }

  @override
  bool shouldRepaint(_RingGaugePainter o) =>
      o.value != value || o.pulse != pulse || o.scanning != scanning;
}
