import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants.dart';
import '../services/classic_bt_service.dart';
import '../providers/ble_scanner.dart';
import '../services/alert_service.dart';
import '../widgets/radar_widget.dart';
import '../widgets/device_card.dart';
import 'history_screen.dart';
import 'settings_screen.dart';
import 'identified_devices_screen.dart';
import 'find_distance_screen.dart';
import 'magnetic_detector_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final _scanner = BleScanner();
  late TabController _tabs;
  String _session = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _session = _sid();
    AlertService.instance.start();
    _scanner.addListener(_syncAlerts);
  }

  void _syncAlerts() {
    if (!_scanner.isScanning) { AlertService.instance.setLevel(null); return; }
    final suspects = _scanner.criticalList;
    if (suspects.isEmpty) { AlertService.instance.setLevel(null); return; }
    AlertService.instance.setLevel(ThreatLevel.high);
  }

  String _sid() {
    final n = DateTime.now();
    p(int v) => v.toString().padLeft(2, '0');
    return '${n.year}${p(n.month)}${p(n.day)}-${p(n.hour)}${p(n.minute)}';
  }

  Future<bool> _requestPermissions() async {
    int sdk = 31;
    try {
      final r = await Process.run('getprop', ['ro.build.version.sdk']);
      sdk = int.tryParse(r.stdout.toString().trim()) ?? 31;
    } catch (_) {}

    final perms = <Permission>[Permission.location];
    if (sdk >= 31) {
      perms.addAll([Permission.bluetoothScan, Permission.bluetoothConnect]);
    } else {
      perms.add(Permission.bluetooth);
    }
    if (sdk >= 33) perms.add(Permission.notification);

    final res   = await perms.request();
    final loc   = res[Permission.location] ?? PermissionStatus.denied;
    if (loc.isDenied || loc.isPermanentlyDenied) {
      if (mounted) _showPermDialog(loc.isPermanentlyDenied);
      return false;
    }
    return true;
  }

  void _showPermDialog(bool perm) => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.bluetooth_disabled, color: AppColors.medium, size: 22),
        SizedBox(width: 10),
        Text('صلاحيات مطلوبة',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
      ]),
      content: Text(
        perm
          ? 'افتح إعدادات التطبيق وفعّل:\n• الموقع الدقيق\n• Bluetooth'
          : 'يجب منح الإذن لـ:\n• الموقع الدقيق (للمسح)\n• Bluetooth Scan & Connect',
        style: const TextStyle(color: AppColors.textSecondary,
            height: 1.7, fontSize: 13)),
      actions: [
        if (perm) TextButton(
          onPressed: () { Navigator.pop(context); openAppSettings(); },
          child: const Text('فتح الإعدادات',
              style: TextStyle(color: AppColors.accent))),
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق',
                style: TextStyle(color: AppColors.textMuted))),
      ],
    ),
  );

  Future<void> _toggleScan() async {
    if (_scanner.isScanning) { _scanner.stop(); return; }

    // Check 1: Bluetooth ON
    final btState = await FlutterBluePlus.adapterState.first
        .timeout(const Duration(seconds: 3),
            onTimeout: () => BluetoothAdapterState.unknown);
    if (btState == BluetoothAdapterState.off) {
      if (mounted) _showServiceDialog(
        icon: Icons.bluetooth_disabled_rounded,
        color: AppColors.accent,
        title: 'البلوتوث غير مفعّل',
        message: 'يجب تفعيل البلوتوث قبل بدء المسح ثم فعّل البلوتوث.',
        actionLabel: 'تفعيل البلوتوث',
        onAction: () async {
          Navigator.pop(context);
          try { await FlutterBluePlus.turnOn(); } catch (_) {}
        },
      );
      return;
    }

    // Check 2: Location permission
    var locPerm = await Permission.location.status;
    if (locPerm.isDenied) {
      locPerm = await Permission.location.request();
    }
    if (locPerm.isPermanentlyDenied) {
      if (mounted) _showServiceDialog(
        icon: Icons.location_off_rounded,
        color: AppColors.medium,
        title: 'صلاحية الموقع مرفوضة',
        message: 'يرجى فتح الإعدادات ومنح صلاحية الموقع للتطبيق.',
        actionLabel: 'فتح الإعدادات',
        onAction: () { Navigator.pop(context); openAppSettings(); },
      );
      return;
    }
    if (!locPerm.isGranted) return;

    // Check 3: GPS service enabled (Android only)
    final locServiceEnabled = await Permission.locationWhenInUse.serviceStatus;
    if (locServiceEnabled != ServiceStatus.enabled) {
      if (mounted) _showServiceDialog(
        icon: Icons.gps_off_rounded,
        color: AppColors.medium,
        title: 'خدمة GPS غير مفعّلة',
        message: 'يجب تفعيل خدمة الموقع (GPS) في إعدادات الهاتف.',
        actionLabel: 'فتح إعدادات الموقع',
        onAction: () async {
          Navigator.pop(context);
          await openAppSettings();
        },
      );
      return;
    }

    final ok = await _requestPermissions();
    if (!ok) return;
    final err = await _scanner.start();
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err),
          backgroundColor: AppColors.critical.withOpacity(0.9)));
    }
  }

  void _showServiceDialog({
    required IconData icon, required Color color,
    required String title, required String message,
    required String actionLabel, required VoidCallback onAction,
  }) => showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: color.withOpacity(0.12)),
          child: Icon(icon, color: color, size: 24)),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: const TextStyle(
            color: AppColors.textPrimary, fontSize: 15,
            fontWeight: FontWeight.w700))),
      ]),
      content: Text(message, style: const TextStyle(
          color: AppColors.textSecondary, height: 1.6, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('لاحقاً',
                style: TextStyle(color: AppColors.textMuted))),
        ElevatedButton(
          onPressed: onAction,
          style: ElevatedButton.styleFrom(
            backgroundColor: color, foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10))),
          child: Text(actionLabel)),
      ]));

  @override
  void dispose() {
    _scanner.removeListener(_syncAlerts);
    _scanner.dispose();
    _tabs.dispose();
    AlertService.instance.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _scanner,
      builder: (context, _) {
        final scanning = _scanner.isScanning;
        final tracked  = _scanner.trackedDevice;
        final all      = _scanner.allDevices;
        final phones   = _scanner.phoneList;
        final audio    = _scanner.audioList;
        final critical = _scanner.criticalList;

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(child: Column(children: [
            _appBar(scanning),
            if (tracked != null)                  _trackBanner(tracked),
            if (_scanner.state == ScanState.error) _errBanner(),
            _radar(scanning),
            if (scanning) _stats(),
            // ── Quick action buttons ────────────────────────────────────────
            // Magnetic scanner — always visible
            _magneticButton(),
            if (scanning) _actionButtons(),

            _tabBar(),
            Expanded(child: TabBarView(
              controller: _tabs,
              children: [
                _list(all,      'لا توجد أجهزة',     Icons.bluetooth_searching),
                _list(phones,   'لم يُرصد أي هاتف',  Icons.phone_android),
                _list(audio,    'لا توجد سماعات',    Icons.headphones),
                _list(critical, 'لا توجد تهديدات قريبة', Icons.security),
              ],
            )),
          ])),
          floatingActionButton: _fab(scanning),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        );
      },
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────
  Widget _appBar(bool sc) => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
    child: Row(children: [
      // ── Ministry logo ────────────────────────────────────────────────
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [BoxShadow(
            color: const Color(0xFFB8960C).withOpacity(0.35), blurRadius: 10)]),
        child: ClipOval(child: Padding(
          padding: const EdgeInsets.all(3),
          child: Image.asset('assets/ministry_logo.png', fit: BoxFit.contain)))),
      const SizedBox(width: 9),

      // ── App title (Arabic) ───────────────────────────────────────────
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('رصد أجهزة الغش الإلكتروني',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 13, fontWeight: FontWeight.w800, height: 1.2)),
          Text('جلسة: \$_session', style: const TextStyle(
              color: AppColors.textMuted, fontSize: 9)),
        ])),

      // ── History ──────────────────────────────────────────────────────
      IconButton(
        icon: const Icon(Icons.history_rounded,
            color: AppColors.textSecondary, size: 20),
        padding: const EdgeInsets.all(6),
        onPressed: () => _go(HistoryScreen(session: _session))),

      // ── Support button ───────────────────────────────────────────────
      _appBarBtn(
        label: 'دعم',
        icon: Icons.support_agent_rounded,
        color: const Color(0xFF00D68F),
        onTap: _showSupportDialog,
      ),

      // ── Settings button ──────────────────────────────────────────────
      _appBarBtn(
        label: 'الإعدادات',
        icon: Icons.tune_rounded,
        color: AppColors.accent,
        onTap: () => _go(const SettingsScreen()),
      ),

      // ── Exit button ───────────────────────────────────────────────────
      _appBarBtn(
        label: 'خروج',
        icon: Icons.exit_to_app_rounded,
        color: AppColors.critical,
        onTap: _confirmExit,
      ),
    ]),
  );

  // Small labeled app-bar button
  Widget _appBarBtn({
    required String label, required IconData icon,
    required Color color,  required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withOpacity(0.25), width: 0.5)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: 8,
                fontWeight: FontWeight.w600, height: 1.1)),
      ])));

  Widget _radar(bool sc) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: SizedBox(
      height: 180,   // compact height — device list gets the rest
      child: Center(
        child: AspectRatio(aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: AppColors.surface,
              border: Border.all(color: AppColors.border, width: 0.8),
              boxShadow: [BoxShadow(
                  color: AppColors.accent.withOpacity(0.05), blurRadius: 24)]),
            padding: const EdgeInsets.all(4),
            child: _RadarSimple(devices: _scanner.allDevices, scanning: sc,
                trackedId: _scanner.trackedId),
          ),
        ),
      ),
    ),
  );

  Widget _stats() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
    child: Row(children: [
      _chip('${_scanner.totalDetected}', 'جهاز',   AppColors.accent),
      const SizedBox(width: 6),
      _chip('${_scanner.phoneCount}',    '📱',      AppColors.critical),
      const SizedBox(width: 6),
      _chip('${_scanner.audioCount}',    '🎧',      AppColors.medium),
      const Spacer(),
      StreamBuilder(
        stream: Stream.periodic(const Duration(seconds: 1)),
        builder: (_, __) {
          final e = _scanner.scanStartTime != null
              ? DateTime.now().difference(_scanner.scanStartTime!)
              : Duration.zero;
          final mm = e.inMinutes.toString().padLeft(2,'0');
          final ss = (e.inSeconds%60).toString().padLeft(2,'0');
          return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('⏱ $mm:$ss', style: const TextStyle(
                color: AppColors.textMuted, fontSize: 11, fontFamily: 'monospace')),
            Text('${_scanner.eventCount} حدث | ${_scanner.debugLine}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 9)),
          ]);
        }),
    ]),
  );

  Widget _chip(String v, String l, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: c.withOpacity(0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: c.withOpacity(0.25), width: 0.5)),
    child: RichText(text: TextSpan(children: [
      TextSpan(text: '$v ', style: TextStyle(
          color: c, fontSize: 13, fontWeight: FontWeight.w800)),
      TextSpan(text: l, style: const TextStyle(
          color: AppColors.textMuted, fontSize: 10)),
    ])));

  Widget _tabBar() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    height: 36,
    decoration: BoxDecoration(color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: TabBar(
      controller: _tabs,
      indicator: BoxDecoration(color: AppColors.accent.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withOpacity(0.4), width: 0.5)),
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      labelColor: AppColors.accent,
      unselectedLabelColor: AppColors.textMuted,
      tabs: const [
        Tab(text: 'الكل'),
        Tab(text: '📱 هواتف'),
        Tab(text: '🎧 سماعات'),
        Tab(text: '⚠ قريب'),
      ],
    ),
  );

  Widget _list(List<NativeDevice> devs, String empty, IconData icon) {
    if (devs.isEmpty) return Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.textMuted.withOpacity(0.25), size: 48),
        const SizedBox(height: 12),
        Text(empty, style: const TextStyle(
            color: AppColors.textMuted, fontSize: 13)),
      ]));
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: devs.length,
      itemBuilder: (_, i) {
        final d = devs[i];
        return DeviceCard(
          key: ValueKey(d.address),
          device: d, scanner: _scanner, session: _session,
          isTracked: d.address.replaceAll(':', '') == _scanner.trackedId,
          onTap: () {
            final k = d.address.replaceAll(':', '');
            if (k == _scanner.trackedId) _scanner.untrack();
            else _scanner.track(k);
          },
        );
      },
    );
  }

  Widget _trackBanner(NativeDevice d) {
    // All devices shown are ≤ 2m — use fine-grained thresholds
    final c = d.distanceMeters <= 0.5 ? AppColors.critical
        : d.distanceMeters <= 1.0 ? AppColors.high
        : d.distanceMeters <= 1.5 ? AppColors.medium : AppColors.low;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.4), width: 0.8)),
      child: Row(children: [
        Icon(Icons.my_location_rounded, color: c, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(d.typeIcon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 5),
              Expanded(child: Directionality(textDirection: TextDirection.ltr,
                child: Text(d.name, style: TextStyle(color: c, fontSize: 12,
                    fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))),
            ]),
            Text('${d.rssiLabel}  •  ${d.typeLabel}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          ],
        )),
        Text(d.distanceLabel, style: TextStyle(
            color: c, fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(width: 10),
        GestureDetector(onTap: _scanner.untrack,
            child: const Icon(Icons.close_rounded,
                color: AppColors.textMuted, size: 18)),
      ]),
    );
  }

  Widget _errBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: AppColors.critical.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.critical.withOpacity(0.3), width: 0.5)),
    child: Row(children: [
      const Icon(Icons.error_outline, color: AppColors.critical, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(_scanner.errorMessage ?? 'خطأ',
          style: const TextStyle(color: AppColors.critical, fontSize: 12))),
      TextButton(onPressed: _toggleScan,
          style: TextButton.styleFrom(
              foregroundColor: AppColors.accent, padding: EdgeInsets.zero),
          child: const Text('إعادة المحاولة', style: TextStyle(fontSize: 12))),
    ]),
  );

  Widget _fab(bool sc) => GestureDetector(
    onTap: _toggleScan,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: sc
            ? [AppColors.critical, AppColors.critical.withOpacity(0.7)]
            : [AppColors.accent, AppColors.accentDim]),
        boxShadow: [BoxShadow(
          color: (sc ? AppColors.critical : AppColors.accent).withOpacity(0.4),
          blurRadius: 16, offset: const Offset(0, 4))]),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(sc ? Icons.stop_rounded : Icons.radar_rounded,
            color: Colors.white, size: 22),
        const SizedBox(width: 8),
        Text(sc ? 'إيقاف المسح' : 'بدء مسح الغش',
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 15)),
      ]),
    ),
  );

  void _showSupportDialog() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.support_agent_rounded,
            color: Color(0xFF00D68F), size: 22),
        SizedBox(width: 10),
        Text('الاتصال بالدعم',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('شكيب الوسلاتي',
              style: TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('ديوان وزير التربية',
              style: TextStyle(color: Color(0xFFB8960C), fontSize: 12)),
          const SizedBox(height: 16),
          // Phone
          // Email
          _supportRow(Icons.email_rounded, 'البريد الإلكتروني',
              'chekib318@gmail.com',
              onTap: () async {
                Navigator.pop(context);
                final uri = Uri.parse(
                    'mailto:chekib318@gmail.com?subject=ExamGuard - طلب دعم');
                if (await canLaunchUrl(uri)) await launchUrl(uri);
              }),
        ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق',
                style: TextStyle(color: AppColors.textMuted))),
      ]));

  Widget _supportRow(IconData icon, String label, String value,
      {required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.5)),
        child: Row(children: [
          Icon(icon, color: AppColors.accent, size: 18),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(
                color: AppColors.textMuted, fontSize: 10)),
            Text(value, style: const TextStyle(
                color: AppColors.textPrimary, fontSize: 12,
                fontWeight: FontWeight.w600),
                textDirection: TextDirection.ltr),
          ]),
          const Spacer(),
          const Icon(Icons.open_in_new_rounded,
              color: AppColors.accent, size: 14),
        ])));

  void _confirmExit() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.exit_to_app_rounded, color: AppColors.critical, size: 22),
        SizedBox(width: 10),
        Text('تأكيد الخروج',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      ]),
      content: const Text('هل تريد الخروج؟',
          style: TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
          onPressed: () { Navigator.pop(context); SystemNavigator.pop(); },
          child: const Text('خروج', style: TextStyle(
              color: AppColors.critical, fontWeight: FontWeight.w700))),
      ]));

  Widget _magneticButton() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
    child: GestureDetector(
      onTap: () => _go(const MagneticDetectorScreen()),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF4A0080).withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: const Color(0xFFB044FF).withOpacity(0.45), width: 1.0)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.hearing_rounded,
              color: Color(0xFFB044FF), size: 20),
          const SizedBox(width: 10),
          const Text('مسح سماعات مغناطيسية',
              style: TextStyle(color: Color(0xFFB044FF),
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ]))));

  Widget _actionButtons() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
    child: Row(children: [

      // ── Identified Devices ─────────────────────────────────────────
      Expanded(child: _actionBtn(
        icon: Icons.list_alt_rounded,
        label: 'الأجهزة المُعرَّفة',
        count: _scanner.totalDetected,
        color: AppColors.accent,
        onTap: () => _go(IdentifiedDevicesScreen(scanner: _scanner)),
      )),

      const SizedBox(width: 10),

      // ── Find Distance ──────────────────────────────────────────────
      Expanded(child: _actionBtn(
        icon: Icons.social_distance_rounded,
        label: 'قياس المسافة',
        count: _scanner.criticalList.length,
        color: AppColors.critical,
        onTap: () {
          final devs = _scanner.allDevices;
          if (devs.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('لا توجد أجهزة مرصودة بعد')));
            return;
          }
          // Open with closest device
          _go(FindDistanceScreen(device: devs.first, scanner: _scanner));
        },
      )),
    ]),
  );

  Widget _actionBtn({
    required IconData icon, required String label,
    required int count,    required Color color,
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3), width: 0.5)),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(label,
            style: TextStyle(color: color, fontSize: 12,
                fontWeight: FontWeight.w600))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(6)),
          child: Text('$count', style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w800))),
      ]),
    ),
  );

  void _go(Widget w) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => w));
}

// ── Simple Radar (works with NativeDevice) ────────────────────────────────
class _RadarSimple extends StatefulWidget {
  final List<NativeDevice> devices;
  final bool scanning;
  final String? trackedId;
  const _RadarSimple({required this.devices, required this.scanning, this.trackedId});
  @override
  State<_RadarSimple> createState() => _RadarSimpleState();
}
class _RadarSimpleState extends State<_RadarSimple>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 4))..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) {
      return CustomPaint(
        painter: _SimpleRadarPainter(
          devices: widget.devices,
          sweep: _ctrl.value * 2 * 3.14159,
          scanning: widget.scanning,
          trackedId: widget.trackedId),
        size: Size.infinite);
    });
  }
}
class _SimpleRadarPainter extends CustomPainter {
  final List<NativeDevice> devices;
  final double sweep;
  final bool scanning;
  final String? trackedId;
  const _SimpleRadarPainter({required this.devices, required this.sweep,
      required this.scanning, this.trackedId});
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width/2, cy = size.height/2, R = cx < cy ? cx : cy;
    // Grid
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 0.6;
    for (int i = 1; i <= 4; i++) {
      p.color = const Color(0xFF1E4060).withOpacity(0.4 + i*0.1);
      canvas.drawCircle(Offset(cx,cy), R*i/4, p);
    }
    // Sweep
    if (scanning) {
      final r = Rect.fromCircle(center: Offset(cx,cy), radius: R);
      canvas.drawArc(r, sweep-1.0, 1.0, true,
          Paint()..shader = SweepGradient(startAngle: sweep-1.0, endAngle: sweep,
            colors: [Colors.transparent, const Color(0xFF00FF88).withOpacity(0.3)])
            .createShader(r));
      canvas.drawLine(Offset(cx,cy),
          Offset(cx + R * (sweep > 0 ? (sweep.cos) : 1),
                 cy + R * (sweep > 0 ? (sweep.sin) : 0)),
          Paint()..color = const Color(0xFF00FF88).withOpacity(0.8)..strokeWidth=1.2);
    }
    // Devices
    for (int i = 0; i < devices.length; i++) {
      final d = devices[i];
      final angle = (d.address.hashCode.abs() % 1000) / 1000.0 * 6.28318;
      final radius = (d.distanceMeters / 12.0).clamp(0.06, 0.92);
      final pos = Offset(cx + angle.cos * radius * R, cy + angle.sin * radius * R);
      final dist = d.distanceMeters;
      final c = dist<=2 ? const Color(0xFFFF1744) : dist<=5 ? const Color(0xFFFF6D00)
          : dist<=10 ? const Color(0xFFFFD600) : const Color(0xFF00E676);
      canvas.drawCircle(pos, 8, Paint()..color = c.withOpacity(0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(pos, 5, Paint()..color = c);
    }
    // Center
    canvas.drawCircle(Offset(cx,cy), 7, Paint()..color = const Color(0xFF00AAFF));
    canvas.drawCircle(Offset(cx,cy), 3, Paint()..color = Colors.white);
  }
  @override bool shouldRepaint(_) => true;
}
extension on double {
  double get cos => _cos(this);
  double get sin => _sin(this);
  static double _cos(double x) {
    x = x % 6.28318;
    double r=1,t=1;
    for(int i=1;i<12;i++){t*=-x*x/(2*i*(2*i-1));r+=t;}
    return r;
  }
  static double _sin(double x) {
    x = x % 6.28318;
    double r=x,t=x;
    for(int i=1;i<12;i++){t*=-x*x/((2*i+1)*2*i);r+=t;}
    return r;
  }
}
