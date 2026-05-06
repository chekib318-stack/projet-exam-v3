import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

enum ThreatLevel { low, medium, high, critical }
enum AlertMode   { soundAndVibration, vibrationOnly, silent }

class AlertService {
  static final AlertService instance = AlertService._();
  AlertService._();

  final AudioPlayer _player = AudioPlayer();
  AlertMode mode = AlertMode.soundAndVibration;
  ThreatLevel? _cur;
  Timer? _timer;
  bool _active = false;

  void start() => _active = true;

  void stop() {
    _active = false;
    _timer?.cancel();
    _cur = null;
    _player.stop();
    Vibration.cancel();
  }

  Future<void> setLevel(ThreatLevel? l) async {
    if (!_active || mode == AlertMode.silent) return;
    if (l == _cur) return;
    _cur = l;
    _timer?.cancel();
    _player.stop();
    if (l == null) { Vibration.cancel(); return; }

    if (l == ThreatLevel.critical) { _playCritical(); return; }

    final ms = switch (l) {
      ThreatLevel.low    => 3000, ThreatLevel.medium => 1200,
      ThreatLevel.high   => 500,  _ => 500,
    };
    _beep(l);
    _timer = Timer.periodic(Duration(milliseconds: ms), (_) {
      if (_active && _cur == l) _beep(l);
    });
  }

  Future<void> _beep(ThreatLevel l) async {
    if (mode != AlertMode.silent) {
      final pat = switch (l) {
        ThreatLevel.low    => [0,80],   ThreatLevel.medium => [0,150,120,150],
        ThreatLevel.high   => [0,200,80,200,80,200], _ => [0,100],
      };
      final v = await Vibration.hasVibrator() ?? false;
      if (v) Vibration.vibrate(pattern: pat);
    }
    if (mode == AlertMode.soundAndVibration) {
      final a = switch (l) {
        ThreatLevel.low    => 'beep_low.mp3', ThreatLevel.medium => 'beep_mid.mp3',
        ThreatLevel.high   => 'beep_high.mp3', _ => 'beep_mid.mp3',
      };
      final vol = switch (l) {
        ThreatLevel.low => 0.35, ThreatLevel.medium => 0.65,
        ThreatLevel.high => 0.9, _ => 1.0,
      };
      await _player.play(AssetSource(a), volume: vol);
    }
  }

  Future<void> _playCritical() async {
    if (mode == AlertMode.soundAndVibration) {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('beep_critical.mp3'), volume: 1.0);
    }
    final v = await Vibration.hasVibrator() ?? false;
    if (v) Vibration.vibrate(pattern: [0,400,100,400,100,400], repeat: 0);
  }

  void dispose() { stop(); _player.dispose(); }
}
