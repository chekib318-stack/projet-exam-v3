import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/classic_bt_service.dart';
import '../services/foreground_service.dart';

enum ScanState { idle, starting, scanning, error }

class BleScanner extends ChangeNotifier {
  final Map<String, NativeDevice> devices = {}; // ALL devices (BLE + Classic)

  ScanState state = ScanState.idle;
  String?   errorMessage;
  String?   trackedId;
  DateTime? scanStartTime;
  int       eventCount = 0;
  String    debugLine  = '';

  bool get isScanning    => state == ScanState.scanning;
  int  get totalDetected => devices.values.where((d) => d.distanceMeters <= 10.0).length;
  int  get phoneCount    => devices.values.where((d) => (d.type == 'phone' || d.type == 'computer') && d.distanceMeters <= 10.0).length;
  int  get audioCount    => devices.values.where((d) => d.type == 'earbuds' && d.distanceMeters <= 10.0).length;
  int  get suspectCount  => devices.values.where((d) =>
      d.type == 'phone' || d.type == 'earbuds' || d.type == 'computer').length;

  NativeDevice? get trackedDevice =>
      trackedId != null ? devices[trackedId] : null;

  StreamSubscription? _nativeSub;
  Timer? _refreshTimer;
  Timer? _purgeTimer;

  final _native = NativeScanner.instance;

  Future<String?> start() async {
    if (state == ScanState.scanning) return null;

    // Verify BT is on
    try {
      final s = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      if (s == BluetoothAdapterState.off) {
        errorMessage = 'يرجى تفعيل البلوتوث';
        state = ScanState.error;
        notifyListeners();
        return errorMessage;
      }
    } catch (_) {}

    state = ScanState.starting;
    devices.clear();
    trackedId  = null;
    eventCount = 0;
    debugLine  = 'جارٍ الاتصال...';
    scanStartTime = DateTime.now();
    notifyListeners();

    await ForegroundService.start();

    // Subscribe to native events BEFORE starting scan
    _nativeSub?.cancel();
    _nativeSub = _native.stream.listen((dev) {
      if (dev.address.isEmpty) return;

      final key = dev.address.replaceAll(':', '');

      // "gone" = device disconnected from GATT → remove it
      if (dev.isGone) {
        if (devices.containsKey(key)) {
          devices.remove(key);
          if (trackedId == key) trackedId = null;
          debugLine = 'غادر: ${dev.address.substring(dev.address.length > 5 ? dev.address.length - 5 : 0)}';
          notifyListeners();
        }
        return;
      }

      eventCount++;

      if (devices.containsKey(key)) {
        // Always update RSSI — never remove based on distance
        // (distance filter is only applied in allDevices getter for home screen)
        devices[key]!.update(dev.rssi);
      } else {
        // Add all devices — home screen filters by distance in getter
        devices[key] = dev;
        debugLine = '${devices.length} جهاز';
      }
      notifyListeners();
    });

    // Start the native scanner
    await _native.start();

    state = ScanState.scanning;
    debugLine = 'المسح نشط...';

    // 1Hz UI refresh
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (isScanning) notifyListeners();
    });

    // Purge stale devices
    _purgeTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      final before = devices.length;
      devices.removeWhere((_, d) => d.isStale);
      if (devices.length != before) notifyListeners();
    });

    notifyListeners();
    return null;
  }

  void stop() {
    _refreshTimer?.cancel();
    _purgeTimer?.cancel();
    _nativeSub?.cancel();
    _native.stop();
    ForegroundService.stop();
    state     = ScanState.idle;
    trackedId = null;
    devices.clear();
    scanStartTime = null;
    errorMessage  = null;
    eventCount    = 0;
    debugLine     = '';
    notifyListeners();
  }

  void track(String id)  { trackedId = id;   notifyListeners(); }
  void untrack()         { trackedId = null;  notifyListeners(); }

  void setWhitelist(String id, bool v) { notifyListeners(); }
  void setFlag(String id, bool v)      { notifyListeners(); }

  // Sorted lists
  List<NativeDevice> get allDevices  => devices.values
      .where((d) => d.distanceMeters <= 10.0)  // show only devices within 10m
      .toList()
    ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  List<NativeDevice> get phoneList   => devices.values
      .where((d) => (d.type == 'phone' || d.type == 'computer')
          && d.distanceMeters <= 10.0)
      .toList()
    ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  List<NativeDevice> get audioList   => devices.values
      .where((d) => d.type == 'earbuds' && d.distanceMeters <= 10.0)
      .toList()
    ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
  List<NativeDevice> get criticalList => devices.values
      .where((d) => d.distanceMeters <= 2.0)  // critical = < 2m only
      .toList()
    ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

  @override
  void dispose() { stop(); super.dispose(); }
}
