import 'package:flutter/services.dart';

class ForegroundService {
  static const _ch = MethodChannel('tn.gov.education.examguard/service');

  static Future<void> start() async {
    try { await _ch.invokeMethod('startService'); } catch (_) {}
  }
  static Future<void> stop() async {
    try { await _ch.invokeMethod('stopService'); } catch (_) {}
  }
  static Future<void> startClassicDiscovery() async {
    try { await _ch.invokeMethod('startClassicDiscovery'); } catch (_) {}
  }
  static Future<void> stopClassicDiscovery() async {
    try { await _ch.invokeMethod('stopClassicDiscovery'); } catch (_) {}
  }
}
