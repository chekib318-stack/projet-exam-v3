import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/constants.dart';
import '../services/classic_bt_service.dart';
import '../providers/ble_scanner.dart';

// ── Zone Detector — maximum stability ────────────────────────────────────────
// Two-stage filtering:
//   Stage 1: EMA on raw RSSI (alpha=0.15 → very slow to react = stable)
//   Stage 2: 30-sample median window (6 seconds)
//   Stage 3: Zone hysteresis with 5 consecutive votes needed
class _ZoneDetector {
  static const double _dIn=-60, _dOut=-68;   // 8 dBm gap
  static const double _nIn=-70, _nOut=-78;
  static const double _mIn=-80, _mOut=-88;

  final List<double> _buf = [];   // stores EMA values
  static const _N = 30;           // 6-second window at 5 Hz
  double _ema = -85.0;            // EMA state

  _Zone _state    = _Zone.far;
  _Zone _proposed = _Zone.far;
  int   _votes    = 0;
  static const _VOTES = 5;        // 5 consecutive = 1 second needed

  void add(int rssi) {
    // Stage 1: EMA — very slow alpha=0.12 smooths ±10 dBm fluctuations
    _ema = 0.12 * rssi + 0.88 * _ema;
    _buf.add(_ema);
    if (_buf.length > _N) _buf.removeAt(0);
    if (_buf.length >= 10) _eval();
  }

  // Stage 2: Median of EMA values
  double get median {
    if (_buf.isEmpty) return -90;
    final s = List<double>.from(_buf)..sort();
    return s[_buf.length ~/ 2];
  }

  // Gauge value uses EMA directly (smoother for visual)
  double get gaugeRssi => _ema;

  int get latest => _buf.isEmpty ? -90 : _buf.last.round();

  void _eval() {
    final r = median;
    _Zone n;
    switch (_state) {
      case _Zone.far:    n = r >= _mIn ? _Zone.medium : _Zone.far;
      case _Zone.medium: n = r >= _nIn ? _Zone.near   : r < _mOut ? _Zone.far    : _Zone.medium;
      case _Zone.near:   n = r >= _dIn ? _Zone.danger  : r < _nOut ? _Zone.medium : _Zone.near;
      case _Zone.danger: n = r < _dOut  ? _Zone.near   : _Zone.danger;
    }
    // Stage 3: voting hysteresis
    if (n == _state) {
      _votes = 0; _proposed = _state;
    } else if (n == _proposed) {
      if (++_votes >= _VOTES) { _state = n; _votes = 0; }
    } else {
      _proposed = n; _votes = 1;
    }
  }

  _Zone get zone => _state;

  int get bars {
    final r = median;
    if (r >= _dIn) return 5; if (r >= _nIn) return 4;
    if (r >= _mIn) return 3; if (r >= -88)  return 2;
    return 1;
  }
}

// ── Screen ─────────────────────────────────────────────────────────────────────
class FindDistanceScreen extends StatefulWidget {
  final NativeDevice device;
  final BleScanner   scanner;
  const FindDistanceScreen({super.key, required this.device, required this.scanner});
  @override State<FindDistanceScreen> createState() => _S();
}

class _S extends State<FindDistanceScreen> with TickerProviderStateMixin {
  // Pulse animation for danger alert text
  late AnimationController _dangerPulse;
  // Slow background pulse for the circle glow
  late AnimationController _glowPulse;

  final _det    = _ZoneDetector();
  final _player = AudioPlayer();

  _Zone _zone = _Zone.far, _prev = _Zone.far;
  int   _updates = 0;
  bool  _alerted = false;
  Timer? _timer;

  NativeDevice get _dev =>
      widget.scanner.devices[widget.device.address.replaceAll(':', '')]
      ?? widget.device;

  bool get _approaching => _zone.index > _prev.index;
  bool get _receding    => _zone.index < _prev.index;

  @override
  void initState() {
    super.initState();
    _dangerPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _glowPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);

    int tick = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      final dev = _dev;
      if (dev.rssi == 0 || dev.rssi < -110) return;
      _det.add(dev.rssi);
      if (++tick % 5 == 0) {
        final nz = _det.zone;
        setState(() { _prev = _zone; _zone = nz; _updates = dev.updateCount; });
        if (_zone == _Zone.danger && !_alerted) {
          _alerted = true;
          HapticFeedback.heavyImpact();
          _player.play(AssetSource('beep_critical.mp3'), volume: 1.0)
              .catchError((_) {});
          Future.delayed(
              const Duration(milliseconds: 350), HapticFeedback.heavyImpact);
        } else if (_zone != _Zone.danger) {
          _alerted = false;
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dangerPulse.dispose();
    _glowPulse.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext ctx) {
    final c = _zone.color;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _appBar(),
      // ── Fixed bottom button — always visible ──────────────────────────────
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: _dismissButton()),
      body: SingleChildScrollView(
        // Extra bottom padding so content doesn't hide behind fixed button
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(children: [

          // ── ANIMATED DANGER BANNER ──────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _zone == _Zone.danger
                ? _dangerBanner()
                : const SizedBox.shrink()),
          if (_zone == _Zone.danger) const SizedBox(height: 10),

          // ── GAUGE (top) ───────────────────────────────────────────────
          _distanceMeter(),

          const SizedBox(height: 12),
          _circleCard(c),

          const SizedBox(height: 14),
          _deviceInfo(),
          const SizedBox(height: 10),
          _nearbyCounter(),
        ]),
      ),
    );
  }

  // ── App bar — NO calibration button ───────────────────────────────────────
  PreferredSizeWidget _appBar() => AppBar(
    backgroundColor: AppColors.surface,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_rounded,
          color: AppColors.textSecondary, size: 20),
      onPressed: () => Navigator.pop(context)),
    title: Row(children: [
      Text(_dev.typeIcon, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 8),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('كشف القرب',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 15, fontWeight: FontWeight.w600)),

          // Pulsing status text
          AnimatedBuilder(
            animation: _dangerPulse,
            builder: (_, __) {
              final scale   = 0.88 + _dangerPulse.value * 0.22;
              final opacity = 0.5  + _dangerPulse.value * 0.5;
              final txt = _zone == _Zone.danger ? '⚠ جهاز غش في نطاق الخطر!'
                  : _zone == _Zone.near   ? '⚡ جهاز قريب — تنبّه'
                  : _zone == _Zone.medium ? '📶 جهاز في المحيط'
                  : '📡 المسح نشط';
              return Transform.scale(
                scale: scale,
                alignment: Alignment.centerRight,
                child: Opacity(
                  opacity: opacity,
                  child: Text(txt,
                      style: TextStyle(color: _zone.color,
                          fontSize: 10, fontWeight: FontWeight.w700))));
            }),
        ])),
    ]),
  );

  // ── DANGER BANNER — animated pulsing ─────────────────────────────────────
  Widget _dangerBanner() => AnimatedBuilder(
    animation: _dangerPulse,
    builder: (_, __) {
      // Scale pulsing: 1.0 → 1.03 → 1.0
      final scale = 1.0 + _dangerPulse.value * 0.03;
      return Transform.scale(
        scale: scale,
        child: Container(
          key: const ValueKey('danger'),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0000),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.critical.withOpacity(0.5 + _dangerPulse.value * 0.5),
                width: 2.0)),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.critical.withOpacity(0.8 + _dangerPulse.value * 0.2)),
              child: const Icon(Icons.warning_rounded, color: Colors.white, size: 24)),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // THE PULSING WARNING TEXT
              Text('احذر جهاز غش بجانبك',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16 + _dangerPulse.value * 2, // grows 16→18
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Row(children: [
                _pill(_dev.typeLabel, Colors.white),
              ]),
            ])),
          ])));
    });

  // ── CIRCLE CARD ───────────────────────────────────────────────────────────
  Widget _circleCard(Color c) {
    final bars = _det.bars;
    final arrowC = _approaching ? AppColors.critical
        : _receding ? AppColors.safe : AppColors.textMuted;
    final arrowIcon = _approaching ? Icons.arrow_upward_rounded
        : _receding ? Icons.arrow_downward_rounded : Icons.remove_rounded;
    final arrowLabel = _approaching ? 'اقتراب'
        : _receding ? 'ابتعاد' : 'ثابت';

    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (_, __) {
        final glow = _zone == _Zone.danger
            ? c.withOpacity(0.12 + _glowPulse.value * 0.10)
            : Colors.transparent;

        return Center(
          child: SizedBox(
            width: 190, height: 190,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                    color: c.withOpacity(0.6 + _glowPulse.value * 0.3),
                    width: _zone == _Zone.danger ? 2.0 : 1.0),
                boxShadow: [
                  BoxShadow(color: glow, blurRadius: 18, spreadRadius: 2)
                ]),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [

                    // Zone label
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _zone.rangeLabel,
                        key: ValueKey(_zone),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: c,
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            height: 1.1))),

                    // Compact signal bars — LTR
                    ClipRect(
                      child: Directionality(
                        textDirection: TextDirection.ltr,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: List.generate(5, (i) {
                            final on = i < bars;
                            final bc = on ? _barColor(i) : AppColors.border;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              width: 14,
                              height: 8.0 + i * 5,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: bc,
                                borderRadius: BorderRadius.circular(3),
                                boxShadow: on
                                    ? [BoxShadow(
                                        color: bc.withOpacity(0.4),
                                        blurRadius: 4)]
                                    : []));
                          })))),

                    // Zone labels — LTR
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(children: [
                        _zl('بعيد',  const Color(0xFF00E676), _zone == _Zone.far),
                        _zl('متوسط', const Color(0xFFFFD600), _zone == _Zone.medium),
                        _zl('قريب',  const Color(0xFFFF6D00), _zone == _Zone.near),
                        _zl('خطر',   const Color(0xFFFF1744), _zone == _Zone.danger),
                      ])),

                    // Arrow
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(arrowIcon, color: arrowC, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          arrowLabel,
                          style: TextStyle(
                              color: arrowC,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                      ]),

                  ])))));
      });
  }


  Widget _zl(String t, Color c, bool active) => Expanded(
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 4),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: active ? c.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: active ? c.withOpacity(0.7) : Colors.transparent)),
      child: Text(t, textAlign: TextAlign.center,
          style: TextStyle(
              color: active ? c : c.withOpacity(0.2),
              fontSize: 10,
              fontWeight: active ? FontWeight.w800 : FontWeight.w400))));

  Color _barColor(int i) => const [
    Color(0xFF00E676), Color(0xFF8AE000),
    Color(0xFFFFD600), Color(0xFFFF6D00),
    Color(0xFFFF1744),
  ][i];

  // ── Device info ───────────────────────────────────────────────────────────
  Widget _deviceInfo() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 0.5)),
    child: Row(children: [
      Container(width: 46, height: 46,
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.accent.withOpacity(0.2))),
        child: Center(child: Text(_dev.typeIcon,
            style: const TextStyle(fontSize: 24)))),
      const SizedBox(width: 14),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Directionality(textDirection: TextDirection.ltr,
          child: Text(_dev.name.isNotEmpty ? _dev.name : 'جهاز غير معروف',
            style: const TextStyle(color: AppColors.textPrimary,
                fontWeight: FontWeight.w700, fontSize: 14),
            overflow: TextOverflow.ellipsis)),
        const SizedBox(height: 4),
        Row(children: [
          Text(_dev.typeLabel, style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(width: 6),
          _badge(_dev.protocolBadge, AppColors.accent),
          const SizedBox(width: 6),
          _badge('$_updates تحديث', AppColors.textMuted),
          const SizedBox(width: 6),
          _badge('${_det.latest} dBm', AppColors.textMuted),
        ]),
      ])),
    ]));

  // ── Other nearby devices (< 0.5m threshold) ──────────────────────────────
  Widget _nearbyCounter() {
    final others = widget.scanner.devices.values.where((d) =>
        d.address.replaceAll(':', '') !=
            widget.device.address.replaceAll(':', '') &&
        d.rssi > -60).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _glowPulse,
      builder: (_, __) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A0A00),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.critical.withOpacity(
                  0.4 + _glowPulse.value * 0.3), width: 1.5)),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.critical.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.critical.withOpacity(0.5))),
            child: Center(child: Text('${others.length}',
                style: const TextStyle(color: AppColors.critical,
                    fontSize: 18, fontWeight: FontWeight.w900)))),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              others.length == 1
                  ? 'جهاز غش إضافي في نطاق الخطر'
                  : '${others.length} أجهزة غش في نطاق الخطر',
              style: const TextStyle(color: AppColors.critical,
                  fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 3),
            Text(
              others.map((d) => d.name.isNotEmpty ? d.name : d.typeLabel).join(' • '),
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis),
          ])),
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.critical, size: 22),
        ])));
  }

  // ── Speedometer gauge ─────────────────────────────────────────────────────
  Widget _distanceMeter() {
    // Use EMA-smoothed RSSI for gauge — much more stable visually
    final rssi = _det.gaugeRssi;
    final pct  = ((rssi - (-90.0)) / ((-45.0) - (-90.0))).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: pct),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      builder: (_, v, __) => _SpeedometerGauge(value: v),
    );
  }

  // ── Dismiss button — remove device and go back ────────────────────────────
  Widget _dismissButton() => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: () {
        // Remove device from scanner's map
        final key = widget.device.address.replaceAll(':', '');
        widget.scanner.devices.remove(key);
        widget.scanner.notifyListeners();
        // Go back to main screen
        Navigator.pop(context);
      },
      icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
      label: const Text('تم كشفه — انتقل للجهاز التالي',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00803C),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14)),
        elevation: 4),
    ));

  Widget _pill(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(7),
      border: Border.all(color: c.withOpacity(0.5), width: 0.8)),
    child: Text(t, style: TextStyle(color: c,
        fontSize: 12, fontWeight: FontWeight.w700)));

  Widget _badge(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4),
      border: Border.all(color: c.withOpacity(0.25), width: 0.4)),
    child: Text(t, style: TextStyle(color: c,
        fontSize: 9, fontWeight: FontWeight.w600)));
}

// ── Speedometer Gauge Widget — car-style ─────────────────────────────────────
class _SpeedometerGauge extends StatelessWidget {
  final double value; // 0.0 to 1.0
  const _SpeedometerGauge({required this.value});

  @override
  Widget build(BuildContext context) {
    final Color needleC = value < 0.40
        ? const Color(0xFF00E676)
        : value < 0.72
            ? const Color(0xFFFF6D00)
            : const Color(0xFFFF1744);
    final int pct = (value * 100).round();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),   // deep dark background
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: needleC.withOpacity(0.45), width: 1.2),
        boxShadow: [BoxShadow(
            color: needleC.withOpacity(0.20), blurRadius: 24, spreadRadius: 2)]),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(children: [
        // Title
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('مقياس اقتراب جهاز الغش',
              style: TextStyle(color: Color(0xFF4A7A9B),
                  fontSize: 11, letterSpacing: 0.5)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: needleC.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: needleC.withOpacity(0.35))),
            child: Text('$pct %',
                style: TextStyle(color: needleC, fontSize: 11,
                    fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),

        // The gauge arc
        SizedBox(
          height: 210,
          child: CustomPaint(
            painter: _GaugePainter(value: value),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 80),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  // Very big percentage
                  Text('$pct',
                      style: TextStyle(
                          color: needleC,
                          fontSize: 68,
                          fontWeight: FontWeight.w900,
                          height: 1.0,
                          shadows: [Shadow(
                              color: needleC.withOpacity(0.5),
                              blurRadius: 20)])),
                  Text('%',
                      style: TextStyle(
                          color: needleC.withOpacity(0.7),
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                ])))),
        ),

        const SizedBox(height: 6),

        // Bottom labels: 0% ← → 100%
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _lbl('0%', const Color(0xFF00E676), 'بعيد'),
              _lbl('50%', const Color(0xFFFF6D00), 'قريب'),
              _lbl('100%', const Color(0xFFFF1744), 'خطر'),
            ])),
      ]));
  }

  Widget _lbl(String pct, Color c, String txt) => Column(
    mainAxisSize: MainAxisSize.min, children: [
    Text(pct,  style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    Text(txt, style: TextStyle(color: c.withOpacity(0.6), fontSize: 9)),
  ]);
}

// ── Gauge Painter — large semicircle with tick marks + glow ──────────────────
class _GaugePainter extends CustomPainter {
  final double value;
  const _GaugePainter({required this.value});

  static const double _start = math.pi * 0.75;  // 135°
  static const double _sweep = math.pi * 1.5;   // 270°

  @override
  void paint(Canvas canvas, Size sz) {
    final cx = sz.width  / 2;
    final cy = sz.height * 0.86;
    final r  = sz.width  * 0.44;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    // ── 1. Background track (dark) ────────────────────────────────────────
    canvas.drawArc(rect, _start, _sweep, false,
        Paint()
          ..color = const Color(0xFF1E3050)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..strokeCap = StrokeCap.round);

    // ── 2. Glow under coloured arc ────────────────────────────────────────
    final glowColor = value < 0.40 ? const Color(0xFF00E676)
        : value < 0.72 ? const Color(0xFFFF6D00)
        : const Color(0xFFFF1744);

    if (value > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: Offset(cx, cy), radius: r),
          _start, _sweep * value, false,
          Paint()
            ..color = glowColor.withOpacity(0.18)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 30
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }

    // ── 3. Coloured arc in 3 segments ─────────────────────────────────────
    const segs = [
      (end: 0.40, c: Color(0xFF00E676)),
      (end: 0.72, c: Color(0xFFFF6D00)),
      (end: 1.00, c: Color(0xFFFF1744)),
    ];
    double prev = 0.0;
    for (final s in segs) {
      final drawn = value.clamp(prev, s.end);
      if (drawn > prev) {
        canvas.drawArc(rect, _start + _sweep * prev, _sweep * (drawn - prev), false,
            Paint()
              ..color = s.c
              ..style = PaintingStyle.stroke
              ..strokeWidth = 22
              ..strokeCap = StrokeCap.round);
      }
      prev = s.end;
    }

    // ── 4. Tick marks (11 major + labels) ────────────────────────────────
    for (int i = 0; i <= 10; i++) {
      final a     = _start + _sweep * (i / 10);
      final isMaj = i % 2 == 0;
      final inner = r - (isMaj ? 34 : 28);
      final outer = r - 8;
      canvas.drawLine(
          Offset(cx + inner * math.cos(a), cy + inner * math.sin(a)),
          Offset(cx + outer * math.cos(a), cy + outer * math.sin(a)),
          Paint()
            ..color = (isMaj ? Colors.white : const Color(0xFF4A7A9B)).withOpacity(0.5)
            ..strokeWidth = isMaj ? 2.0 : 1.0);

      // Label every 2 ticks
      if (isMaj) {
        final lbl = '${i * 10}';
        final tp  = TextPainter(
          text: TextSpan(text: lbl,
              style: const TextStyle(color: Color(0xFF4A7A9B), fontSize: 9)),
          textDirection: TextDirection.ltr)..layout();
        final lx = cx + (inner - 14) * math.cos(a) - tp.width / 2;
        final ly = cy + (inner - 14) * math.sin(a) - tp.height / 2;
        tp.paint(canvas, Offset(lx, ly));
      }
    }

    // ── 5. Needle ─────────────────────────────────────────────────────────
    final na = _start + _sweep * value;
    final nColor = value < 0.40 ? const Color(0xFF00E676)
        : value < 0.72 ? const Color(0xFFFF6D00)
        : const Color(0xFFFF1744);
    final nx = cx + (r - 32) * math.cos(na);
    final ny = cy + (r - 32) * math.sin(na);

    // Glow
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()
          ..color = nColor.withOpacity(0.3)
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    // Body
    canvas.drawLine(Offset(cx, cy), Offset(nx, ny),
        Paint()
          ..color = nColor
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);

    // Centre cap — glowing dot
    canvas.drawCircle(Offset(cx, cy), 14,
        Paint()..color = nColor.withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(Offset(cx, cy), 10,
        Paint()..color = const Color(0xFF1E3050));
    canvas.drawCircle(Offset(cx, cy), 8,
        Paint()..color = nColor);
    canvas.drawCircle(Offset(cx, cy), 4,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.value != value;
}

// ── Zone enum ──────────────────────────────────────────────────────────────────
enum _Zone {
  far, medium, near, danger;
  Color get color => switch (this) {
    _Zone.far    => const Color(0xFF00E676),
    _Zone.medium => const Color(0xFFFFD600),
    _Zone.near   => const Color(0xFFFF6D00),
    _Zone.danger => const Color(0xFFFF1744),
  };
  String get rangeLabel => switch (this) {
    _Zone.far    => 'بعيد > 2م',
    _Zone.medium => '1 – 2 متر',
    _Zone.near   => '50سم – 1م',
    _Zone.danger => 'خطر مباشر',
  };
  String get shortDesc => switch (this) {
    _Zone.far    => 'خارج النطاق الحرج',
    _Zone.medium => 'في محيط القاعة',
    _Zone.near   => 'تدقيق فوري',
    _Zone.danger => 'خطر مباشر',
  };
}
