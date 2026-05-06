import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../services/classic_bt_service.dart';
import '../providers/ble_scanner.dart';
import 'find_distance_screen.dart';

class IdentifiedDevicesScreen extends StatelessWidget {
  final BleScanner scanner;

  const IdentifiedDevicesScreen({super.key, required this.scanner});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: scanner,
      builder: (context, _) {
        final devices = scanner.allDevices;

        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded,
                  color: AppColors.textSecondary, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الأجهزة المُعرَّفة',
                    style: TextStyle(color: AppColors.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text('${devices.length} جهاز',
                    style: const TextStyle(
                        color: AppColors.textMuted, fontSize: 11)),
              ]),
            actions: [
              // Filter chips
              _FilterChip(count: scanner.phoneCount, icon: '📱'),
              _FilterChip(count: scanner.audioCount, icon: '🎧'),
              const SizedBox(width: 8),
            ],
          ),

          body: devices.isEmpty
              ? _emptyState(scanner.isScanning)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: devices.length,
                  itemBuilder: (ctx, i) {
                    final d = devices[i];
                    return _DeviceRow(
                      device: d,
                      isHighlighted: i == 0, // closest device highlighted
                      onTap: () => Navigator.push(ctx,
                        MaterialPageRoute(builder: (_) =>
                          FindDistanceScreen(device: d, scanner: scanner))),
                    );
                  },
                ),
        );
      },
    );
  }

  Widget _emptyState(bool scanning) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bluetooth_searching,
          color: AppColors.textMuted.withOpacity(0.25), size: 64),
      const SizedBox(height: 16),
      Text(
        scanning
            ? 'جارٍ البحث عن الأجهزة...'
            : 'لم يُرصد أي جهاز\nابدأ المسح أولاً',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted,
            fontSize: 14, height: 1.6)),
    ]));
}

// ── Single device row ─────────────────────────────────────────────────────────
class _DeviceRow extends StatelessWidget {
  final NativeDevice device;
  final bool         isHighlighted;
  final VoidCallback onTap;

  const _DeviceRow({
    required this.device,
    required this.isHighlighted,
    required this.onTap,
  });

  Color get _distColor {
    final d = device.distanceMeters;
    if (d <= 0.5) return AppColors.critical;
    if (d <= 1.0) return AppColors.high;
    if (d <= 1.5) return AppColors.medium;
    return AppColors.low;
  }

  @override
  Widget build(BuildContext context) {
    final c = _distColor;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: isHighlighted ? c.withOpacity(0.07) : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isHighlighted ? c.withOpacity(0.5) : AppColors.border,
          width: isHighlighted ? 1.0 : 0.5)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [

            // ── Device type icon ──────────────────────────────────────
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.accent.withOpacity(0.2), width: 0.5)),
              child: Center(child: Text(
                _svgIcon(device.type),
                style: const TextStyle(fontSize: 22)))),

            const SizedBox(width: 12),

            // ── Name + address ────────────────────────────────────────
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    device.name.isNotEmpty ? device.name : 'Unknown Device',
                    style: TextStyle(
                      color: isHighlighted
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                      fontWeight: isHighlighted
                          ? FontWeight.w700
                          : FontWeight.w500,
                      fontSize: 14),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(height: 3),
                Row(children: [
                  Text(device.address,
                      style: const TextStyle(
                          color: AppColors.textMuted, fontSize: 10,
                          fontFamily: 'monospace'),
                      textDirection: TextDirection.ltr),
                  const SizedBox(width: 8),
                  _protocolBadge(device.protocolBadge),
                ]),
              ])),

            // ── Distance + BT icon ────────────────────────────────────
            Column(children: [
              Text(device.distanceLabel,
                  style: TextStyle(color: c, fontSize: 14,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Icon(Icons.bluetooth_rounded,
                  color: isHighlighted ? c : AppColors.accent,
                  size: 20),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _protocolBadge(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: AppColors.accent.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(
          color: AppColors.accent.withOpacity(0.25), width: 0.4)),
    child: Text(text, style: const TextStyle(
        color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w600)));

  // Map device type to emoji icon matching the screenshots
  String _svgIcon(String type) => switch (type) {
    'phone'    => '📱',
    'earbuds'  => '🎧',
    'computer' => '🖥️',
    'watch'    => '⌚',
    'glasses'  => '🥽',
    _          => '📡',
  };
}

// ── Filter chip widget ─────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final int    count;
  final String icon;
  const _FilterChip({required this.count, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: Text('$icon $count',
        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)));
}
