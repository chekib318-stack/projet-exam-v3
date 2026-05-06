import 'package:flutter/material.dart';
import '../screens/find_distance_screen.dart';
import '../core/constants.dart';
import '../services/classic_bt_service.dart';
import '../providers/ble_scanner.dart';

class DeviceCard extends StatelessWidget {
  final NativeDevice device;
  final BleScanner   scanner;
  final String       session;
  final bool         isTracked;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.device,
    required this.scanner,
    required this.session,
    this.isTracked = false,
    this.onTap,
  });

  // Fine-grained thresholds within the 2m detection zone
  Color get _c {
    final d = device.distanceMeters;
    if (d <= 0.5) return AppColors.critical;  // < 50cm  ← très proche
    if (d <= 1.0) return AppColors.high;      // < 1m
    if (d <= 1.5) return AppColors.medium;    // < 1.5m
    return AppColors.low;                      // < 2m
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: isTracked ? c.withOpacity(0.08) : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isTracked ? c.withOpacity(0.6) : c.withOpacity(0.25),
            width: isTracked ? 1.2 : 0.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(children: [
            // ── Header ──────────────────────────────────────────────────
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.withOpacity(0.12),
                  border: Border.all(color: c.withOpacity(0.3), width: 0.5)),
                child: Center(child: Text(device.typeIcon,
                    style: const TextStyle(fontSize: 20)))),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(
                        device.name.isNotEmpty ? device.name : 'جهاز مجهول',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 14),
                        overflow: TextOverflow.ellipsis))),
                    _badge(device.protocolBadge, AppColors.accent),
                    if (device.isLive) ...[
                      const SizedBox(width: 4),
                      _liveDot(),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(device.typeLabel, style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
                ],
              )),
            ]),
            const SizedBox(height: 12),

            // ── Stats ────────────────────────────────────────────────────
            Row(children: [
              _bigStat(device.distanceLabel, c, 'المسافة'),
              const SizedBox(width: 16),
              _smStat(device.rssiLabel, 'RSSI'),
              const SizedBox(width: 12),
              _smStat('${device.updateCount}x', 'تحديث'),
              const Spacer(),
              _rssiBar(device.rssi, c),
            ]),
            const SizedBox(height: 10),

            // ── Proximity bar ─────────────────────────────────────────────
            _proximityBar(c),
            const SizedBox(height: 4),
            // ── Find Distance button ───────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => FindDistanceScreen(
                      device: device, scanner: scanner))),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFF00D68F).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(8)),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.social_distance_rounded,
                        color: Color(0xFF00D68F), size: 14),
                    SizedBox(width: 6),
                    Text('قياس المسافة', style: TextStyle(
                        color: Color(0xFF00D68F), fontSize: 11,
                        fontWeight: FontWeight.w600)),
                  ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _liveDot() => Container(
    width: 7, height: 7,
    decoration: const BoxDecoration(
      shape: BoxShape.circle, color: AppColors.safe));

  Widget _badge(String t, Color c) => Container(
    margin: const EdgeInsets.only(left: 5),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(4),
      border: Border.all(color: c.withOpacity(0.3), width: 0.4)),
    child: Text(t, style: TextStyle(color: c, fontSize: 9,
        fontWeight: FontWeight.w600)));

  Widget _bigStat(String v, Color c, String l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
      const SizedBox(height: 2),
      Text(v, style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.w800)),
    ]);

  Widget _smStat(String v, String l) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(l, style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
      const SizedBox(height: 2),
      Text(v, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
    ]);

  Widget _rssiBar(int rssi, Color c) {
    final bars = rssi > -50 ? 4 : rssi > -65 ? 3 : rssi > -75 ? 2 : 1;
    return Row(children: List.generate(4, (i) => Container(
      width: 5, height: 8.0 + i * 4, margin: const EdgeInsets.only(left: 2),
      decoration: BoxDecoration(
        color: i < bars ? c : AppColors.border,
        borderRadius: BorderRadius.circular(2)),
    )).reversed.toList());
  }


  Widget _proximityBar(Color c) {
    final ratio = 1.0 - (device.distanceMeters / 2.0).clamp(0.0, 1.0);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('2م', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
        Text(device.distanceLabel, style: TextStyle(
            color: c, fontSize: 11, fontWeight: FontWeight.w700)),
        const Text('0م', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
      ]),
      const SizedBox(height: 4),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ratio),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        builder: (_, v, __) => ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v, minHeight: 5,
            backgroundColor: AppColors.border,
            valueColor: AlwaysStoppedAnimation(c)),
        ),
      ),
    ]);
  }
}
