import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ══════════════════════════════════════════════════════════════════════════════
/// LicenseService — حماية بكود رباعي (كل كود صالح 4 أشهر)
///
/// الفترات الثلاث في السنة:
///   الفترة 1: جانفي — أفريل    (P1-YYYY)
///   الفترة 2: ماي   — أوت      (P2-YYYY)
///   الفترة 3: سبتمبر — ديسمبر  (P3-YYYY)
///
/// أنت تولّد كوداً واحداً كل 4 أشهر وترسله للمراقبين.
/// ══════════════════════════════════════════════════════════════════════════════
class LicenseService {

  // ─── المفتاح السري — غيّره قبل البناء ───────────────────────────────────
  static const String _secretKey = 'MoE@Tunisia#ExamGuard@2026!';

  // ─── تاريخ انتهاء التطبيق كلياً ─────────────────────────────────────────
  static final DateTime _hardExpiry = DateTime(2028, 1, 1);

  // ─── مفاتيح التخزين ──────────────────────────────────────────────────────
  static const _kActivatedPeriod = 'license_period';   // e.g. "P2-2026"
  static const _kInstallDate     = 'license_install';

  // ══════════════════════════════════════════════════════════════════════════
  // حساب الفترة الحالية
  // ══════════════════════════════════════════════════════════════════════════
  static String _periodKey({DateTime? date}) {
    final d   = date ?? DateTime.now();
    final num = d.month <= 4 ? 1 : d.month <= 8 ? 2 : 3;
    return 'P$num-${d.year}';
  }

  static String periodLabel({DateTime? date}) {
    final d   = date ?? DateTime.now();
    final num = d.month <= 4 ? 1 : d.month <= 8 ? 2 : 3;
    return switch (num) {
      1 => 'جانفي – أفريل ${d.year}',
      2 => 'ماي – أوت ${d.year}',
      _ => 'سبتمبر – ديسمبر ${d.year}',
    };
  }

  // ══════════════════════════════════════════════════════════════════════════
  // توليد الكود الرباعي — تستخدمه أنت كمدير
  // استدعاء: LicenseService.generateCode()
  // ══════════════════════════════════════════════════════════════════════════
  static String generateCode({DateTime? forDate}) {
    final period = _periodKey(date: forDate);
    final key    = utf8.encode(_secretKey);
    final msg    = utf8.encode(period);
    final digest = Hmac(sha256, key).convert(msg).toString();
    // 6 أرقام من الهاش
    final digits = digest.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.substring(0, 6).padLeft(6, '0');
  }

  // ══════════════════════════════════════════════════════════════════════════
  // التحقق من الكود
  // ══════════════════════════════════════════════════════════════════════════
  static bool verifyCode(String input) =>
      input.trim() == generateCode();

  // ══════════════════════════════════════════════════════════════════════════
  // تفعيل الترخيص
  // ══════════════════════════════════════════════════════════════════════════
  static Future<void> activate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActivatedPeriod, _periodKey());
    if (!prefs.containsKey(_kInstallDate)) {
      await prefs.setString(_kInstallDate, DateTime.now().toIso8601String());
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // فحص حالة الترخيص عند كل فتح
  // ══════════════════════════════════════════════════════════════════════════
  static Future<LicenseStatus> checkStatus() async {
    if (DateTime.now().isAfter(_hardExpiry))
      return LicenseStatus.expired;

    final prefs  = await SharedPreferences.getInstance();
    final saved  = prefs.getString(_kActivatedPeriod) ?? '';
    final current = _periodKey();

    return saved == current
        ? LicenseStatus.active
        : LicenseStatus.requiresCode;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // معلومات عرض
  // ══════════════════════════════════════════════════════════════════════════
  static String get currentPeriodLabel  => periodLabel();
  static String get expiryDateLabel =>
      '${_hardExpiry.day}/${_hardExpiry.month}/${_hardExpiry.year}';

  static Future<void> deactivate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kActivatedPeriod);
  }
}

enum LicenseStatus { active, requiresCode, expired }
