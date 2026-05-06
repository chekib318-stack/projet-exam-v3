import 'dart:async';
import 'package:flutter/services.dart';

class NativeScanner {
  static final NativeScanner instance = NativeScanner._();
  NativeScanner._();

  static const _event  = EventChannel('tn.gov.education.examguard/classic_bt');
  static const _method = MethodChannel('tn.gov.education.examguard/service');

  StreamSubscription? _sub;
  final _ctrl = StreamController<NativeDevice>.broadcast();
  Stream<NativeDevice> get stream => _ctrl.stream;

  Future<void> start() async {
    _sub?.cancel();
    _sub = _event.receiveBroadcastStream().listen((data) {
      if (data is Map) {
        try {
          final dev = NativeDevice.fromMap(Map<String, dynamic>.from(data));
          _ctrl.add(dev); // includes "gone" protocol events
        } catch (_) {}
      }
    }, onError: (_) {});
    await Future.delayed(const Duration(milliseconds: 150));
    try { await _method.invokeMethod('startScan'); } catch (_) {}
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _method.invokeMethod('stopScan').catchError((_) {});
  }

  void dispose() { stop(); _ctrl.close(); }
}

class NativeDevice {
  final String address;
  final String name;
  int    rssi;
  final String type;
  final int    major;
  final String protocol;
  DateTime lastSeen;
  int updateCount;

  double _rssiEma = -70.0;   // EMA-smoothed RSSI for distance calculation
  bool   _emaInit = false;

  NativeDevice({
    required this.address, required this.name,
    required this.rssi,    required this.type,
    required this.major,   required this.protocol,
    required this.lastSeen, this.updateCount = 1,
  }) {
    _rssiEma = rssi.toDouble();
    _emaInit = true;
  }

  factory NativeDevice.fromMap(Map<String, dynamic> m) => NativeDevice(
    address:  m['address']  as String? ?? '',
    name:     m['name']     as String? ?? '',
    rssi:     m['rssi']     as int?    ?? -80,
    type:     m['type']     as String? ?? 'unknown',
    major:    m['major']    as int?    ?? 0,
    protocol: m['protocol'] as String? ?? 'unknown',
    lastSeen: DateTime.now(),
  );

  bool get isGone  => protocol == 'gone';
  bool get isLive  => protocol == 'gatt_rssi';
  bool get isStale => DateTime.now().difference(lastSeen).inSeconds > 300;

  void update(int newRssi) {
    rssi = newRssi;
    lastSeen = DateTime.now();
    updateCount++;
    // EMA on RSSI: far devices get more smoothing (alpha=0.25)
    // near devices less (alpha=0.4) — adapts to distance
    if (!_emaInit) { _rssiEma = newRssi.toDouble(); _emaInit = true; }
    final alpha = newRssi > -60 ? 0.4 : 0.2;
    _rssiEma = alpha * newRssi + (1 - alpha) * _rssiEma;
  }

  double get distanceMeters {
    final r = _emaInit ? _rssiEma : rssi.toDouble();
    if (r >= 0) return 0.1;
    const tx = -59.0, n = 2.7;
    double e = (tx - r) / (10.0 * n) * 2.302585093;
    double res = 1, t = 1;
    for (int i = 1; i < 20; i++) { t *= e / i; res += t; }
    return res.clamp(0.1, 30.0);
  }

  String get distanceLabel => '${distanceMeters.toStringAsFixed(1)} م';
  String get rssiLabel     => '$rssi dBm';

  String get typeIcon => switch (type) {
    'phone'    => '📱', 'earbuds'  => '🎧',
    'computer' => '💻', 'watch'    => '⌚',
    'glasses'  => '🥽', _          => '📡',
  };

  String get typeLabel => switch (type) {
    'phone'    => 'هاتف',     'earbuds'  => 'سماعة',
    'computer' => 'حاسوب',   'watch'    => 'ساعة ذكية',
    'glasses'  => 'نظارة',   _          => 'جهاز Bluetooth',
  };

  String get protocolBadge => switch (protocol) {
    'ble'       => 'BLE',   'gatt_rssi' => 'LIVE',
    'bonded'    => 'مقترن', 'discovery' => 'BR/EDR',
    _           => protocol,
  };
}

typedef ClassicBtDevice = NativeDevice;
