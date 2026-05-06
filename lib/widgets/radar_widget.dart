// radar_widget.dart — compatible with NativeDevice (unified model)
// BleDevice and ThreatLevel are no longer used — all detection goes through NativeDevice.

import 'dart:math';
import 'package:flutter/material.dart';
import '../services/classic_bt_service.dart'; // NativeDevice

class RadarWidget extends StatefulWidget {
  final List<NativeDevice> devices;
  final bool scanning;
  final String? trackedId;

  const RadarWidget({
    super.key,
    required this.devices,
    required this.scanning,
    this.trackedId,
  });

  @override
  State<RadarWidget> createState() => _RadarWidgetState();
}

class _RadarWidgetState extends State<RadarWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _RadarPainter(
          devices:   widget.devices,
          sweep:     _ctrl.value * 2 * pi,
          scanning:  widget.scanning,
          trackedId: widget.trackedId,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<NativeDevice> devices;
  final double sweep;
  final bool   scanning;
  final String? trackedId;

  const _RadarPainter({
    required this.devices,
    required this.sweep,
    required this.scanning,
    this.trackedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final R  = min(cx, cy) - 2;

    _drawGrid(canvas, cx, cy, R);
    if (scanning) _drawSweep(canvas, cx, cy, R);
    _drawDevices(canvas, cx, cy, R);
    _drawCenter(canvas, cx, cy);
  }

  void _drawGrid(Canvas canvas, double cx, double cy, double R) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (int i = 1; i <= 4; i++) {
      p.color = const Color(0xFF1E4060).withOpacity(0.3 + i * 0.1);
      canvas.drawCircle(Offset(cx, cy), R * i / 4, p);
    }
    final lp = Paint()
      ..color = const Color(0xFF1E4060).withOpacity(0.3)
      ..strokeWidth = 0.4;
    for (int i = 0; i < 8; i++) {
      final a = i * pi / 4;
      canvas.drawLine(Offset(cx, cy),
          Offset(cx + cos(a) * R, cy + sin(a) * R), lp);
    }
    // Distance labels
    const labels = ['0.5م', '1م', '1.5م', '2م'];
    for (int i = 0; i < 4; i++) {
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
              color: const Color(0xFF4A8AB5).withOpacity(0.55), fontSize: 9)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx + R * (i + 1) / 4 + 3, cy - 12));
    }
  }

  void _drawSweep(Canvas canvas, double cx, double cy, double R) {
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: R);
    canvas.drawArc(rect, sweep - 1.0, 1.0, true,
        Paint()
          ..shader = SweepGradient(
            startAngle: sweep - 1.0, endAngle: sweep,
            colors: [Colors.transparent, const Color(0xFF00FF88).withOpacity(0.28)],
          ).createShader(rect));
    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + cos(sweep) * R, cy + sin(sweep) * R),
      Paint()
        ..color = const Color(0xFF00FF88).withOpacity(0.75)
        ..strokeWidth = 1.1,
    );
  }

  void _drawDevices(Canvas canvas, double cx, double cy, double R) {
    for (final d in devices) {
      final isTracked = d.address.replaceAll(':', '') == trackedId;

      // Stable angle from address hash
      final angle  = (d.address.hashCode.abs() % 10000) / 10000.0 * 2 * pi;
      final radius = (d.distanceMeters / 2.0).clamp(0.10, 0.92);  // 2m = full radar
      final pos    = Offset(
          cx + cos(angle) * radius * R,
          cy + sin(angle) * radius * R);

      // Fine-grained colour thresholds within 2m detection zone
      final dist = d.distanceMeters;
      final c = dist <= 0.5 ? const Color(0xFFFF1744)   // < 50cm  CRITICAL
          :     dist <= 1.0 ? const Color(0xFFFF6D00)   // < 1.0m  HIGH
          :     dist <= 1.5 ? const Color(0xFFFFD600)   // < 1.5m  MEDIUM
          :                   const Color(0xFF00E676);   // < 2.0m  LOW

      final r = isTracked ? 12.0 : _dotRadius(d);

      // Glow
      canvas.drawCircle(pos, r + 8,
          Paint()
            ..color = c.withOpacity(0.18)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));

      // Tracking ring
      if (isTracked) {
        canvas.drawCircle(pos, r + 6,
            Paint()
              ..color = c.withOpacity(0.8)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5);
      }

      // Main dot
      canvas.drawCircle(pos, r, Paint()..color = c);

      // Highlight
      canvas.drawCircle(Offset(pos.dx - r * 0.25, pos.dy - r * 0.3),
          r * 0.28, Paint()..color = Colors.white.withOpacity(0.35));

      // Distance label
      final tp = TextPainter(
        text: TextSpan(
          text: d.distanceLabel,
          style: TextStyle(
              color: c, fontSize: 9, fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(pos.dx + r + 3, pos.dy - 5));
    }
  }

  void _drawCenter(Canvas canvas, double cx, double cy) {
    canvas.drawCircle(Offset(cx, cy), 8,
        Paint()
          ..color = const Color(0xFF00AAFF)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawCircle(Offset(cx, cy), 5,
        Paint()..color = const Color(0xFF00AAFF));
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = Colors.white);
  }

  double _dotRadius(NativeDevice d) {
    final dist = d.distanceMeters;
    if (dist <= 0.5) return 11;  // < 50cm
    if (dist <= 1.0) return 9;   // < 1m
    if (dist <= 1.5) return 7;   // < 1.5m
    return 5;                     // < 2m
  }

  @override
  bool shouldRepaint(_RadarPainter old) => true;
}
