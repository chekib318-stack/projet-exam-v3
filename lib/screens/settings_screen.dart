import 'package:flutter/material.dart';
import 'admin_code_screen.dart';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../services/alert_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AlertMode _mode = AlertMode.soundAndVibration;
  int _secretTaps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: AppColors.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: const Row(children: [
          Icon(Icons.tune_rounded, color: AppColors.accent, size: 18),
          SizedBox(width: 8),
          Text('الإعدادات',
              style: TextStyle(color: AppColors.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w600)),
        ])),
      body: ListView(padding: const EdgeInsets.all(16), children: [

        // ── Alert mode ────────────────────────────────────────────────────
        _section('وضع التنبيه'),
        _card(Column(children: [
          _radio(AlertMode.soundAndVibration,
              Icons.volume_up_rounded, 'صوت + اهتزاز'),
          _div(),
          _radio(AlertMode.vibrationOnly,
              Icons.vibration_rounded, 'اهتزاز فقط'),
          _div(),
          _radio(AlertMode.silent,
              Icons.notifications_off_rounded, 'صامت — بصري فقط'),
        ])),

        const SizedBox(height: 20),

        // ── App info ──────────────────────────────────────────────────────
        _section('معلومات التطبيق'),
        _card(Column(children: [
          _row('اسم التطبيق',  'رصد أجهزة الغش الإلكتروني'),
          _div(),
          GestureDetector(
            onTap: () {
              _secretTaps++;
              if (_secretTaps >= 7) {
                _secretTaps = 0;
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const AdminCodeScreen()));
              }
            },
            child: _row('الإصدار', '1.0.0 — 2026')),
          _div(), _row('تقنية الكشف', 'BLE 5.0 + Bluetooth Classic'),
          _div(), _row('نطاق الرصد', 'أقل من 2 متر'),
          _div(), _row('التخزين', 'محلي — بدون إرسال بيانات'),
        ])),

        const SizedBox(height: 20),

        // ── Developer ─────────────────────────────────────────────────────
        _section('المطوّر'),
        _card(Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 58, height: 58,
                decoration: BoxDecoration(shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [BoxShadow(
                      color: const Color(0xFFB8960C).withOpacity(0.4),
                      blurRadius: 14)]),
                child: ClipOval(child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.asset('assets/ministry_logo.png',
                      fit: BoxFit.contain)))),
              const SizedBox(width: 14),
              const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('شكيب الوسلاتي',
                      style: TextStyle(color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700, fontSize: 16)),
                  SizedBox(height: 4),
                  Text('ديوان وزير التربية',
                      style: TextStyle(
                          color: Color(0xFFB8960C), fontSize: 12)),
                ])),
            ])),
          _div(),
          _row('الوحدة',  'وزارة التربية — الجمهورية التونسية'),
          _div(), _row('الإصدار', '1.0 — 2026'),
        ])),

        const SizedBox(height: 24),

        // ── Exit button ───────────────────────────────────────────────────
        GestureDetector(
          onTap: _confirmExit,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 15),
            decoration: BoxDecoration(
              color: AppColors.critical.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: AppColors.critical.withOpacity(0.45), width: 0.8)),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.exit_to_app_rounded,
                    color: AppColors.critical, size: 20),
                SizedBox(width: 10),
                Text('الخروج من التطبيق',
                    style: TextStyle(color: AppColors.critical,
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ]))),

        const SizedBox(height: 40),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _section(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t.toUpperCase(), style: const TextStyle(
        color: AppColors.textMuted, fontSize: 10, letterSpacing: 1.2)));

  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(color: AppColors.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.border, width: 0.5)),
    child: child);

  Widget _div() => Divider(height: 0.5,
      color: AppColors.border.withOpacity(0.6), indent: 16);

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Row(children: [
      Text(k, style: const TextStyle(
          color: AppColors.textMuted, fontSize: 12)),
      const SizedBox(width: 12),
      Expanded(child: Text(v, textAlign: TextAlign.end,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 12))),
    ]));

  Widget _radio(AlertMode m, IconData ic, String label) =>
    RadioListTile<AlertMode>(
      value: m, groupValue: _mode, activeColor: AppColors.accent,
      title: Text(label, style: const TextStyle(
          color: AppColors.textPrimary, fontSize: 13)),
      secondary: Icon(ic, color: AppColors.textSecondary, size: 20),
      onChanged: (v) {
        setState(() => _mode = v!);
        AlertService.instance.mode = v!;
      });

  void _confirmExit() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Row(children: [
        Icon(Icons.exit_to_app_rounded, color: AppColors.critical, size: 22),
        SizedBox(width: 10),
        Text('تأكيد الخروج', style: TextStyle(
            color: AppColors.textPrimary, fontSize: 15)),
      ]),
      content: const Text('هل تريد الخروج من التطبيق؟',
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
}
