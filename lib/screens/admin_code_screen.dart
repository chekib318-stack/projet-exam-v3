import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/license_service.dart';

// ── Top-level classes — MUST be outside any class in Dart ────────────────────
class _Period {
  final DateTime start, end;
  final int num, year;
  const _Period(this.start, this.end, this.num, this.year);
}

String _fmt(DateTime d) =>
    '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';

// ── Screen ────────────────────────────────────────────────────────────────────
class AdminCodeScreen extends StatefulWidget {
  const AdminCodeScreen({super.key});
  @override State<AdminCodeScreen> createState() => _AdminState();
}

class _AdminState extends State<AdminCodeScreen> {

  List<_Period> _periods() {
    final now = DateTime.now();
    final List<_Period> list = [];
    for (int y = now.year; y <= now.year + 1; y++) {
      list.add(_Period(DateTime(y,  1, 1), DateTime(y,  4, 30), 1, y));
      list.add(_Period(DateTime(y,  5, 1), DateTime(y,  8, 31), 2, y));
      list.add(_Period(DateTime(y,  9, 1), DateTime(y, 12, 31), 3, y));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final periods = _periods();
    final now     = DateTime.now();
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white54, size: 20),
          onPressed: () => Navigator.pop(context)),
        title: const Text('لوحة المدير — توليد الأكواد',
            style: TextStyle(color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w700)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.4))),
            child: const Text('سري — للمدير فقط',
                style: TextStyle(color: Colors.red,
                    fontSize: 10, fontWeight: FontWeight.w700))),
        ]),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: periods.length + 1,
        itemBuilder: (ctx, i) {
          if (i == 0) return _header();
          final p         = periods[i - 1];
          final isCurrent = p.start.isBefore(now) && p.end.isAfter(now);
          return _periodCard(context, p, isCurrent);
        }),
    );
  }

  Widget _header() => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF0E7C7B).withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF0E7C7B).withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Icon(Icons.info_outline_rounded, color: Color(0xFF0E7C7B), size: 18),
        SizedBox(width: 8),
        Text('كيفية استخدام هذه الأكواد',
            style: TextStyle(color: Color(0xFF0E7C7B),
                fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
      const SizedBox(height: 10),
      _step('①', 'اختر الكود الخاص بالفترة الحالية (المحاطة بإطار أخضر)'),
      _step('②', 'اضغط «نسخ» ثم أرسله للمراقبين عبر WhatsApp أو SMS'),
      _step('③', 'يُدخله المراقب مرة واحدة ويظل صالحاً 4 أشهر كاملة'),
      _step('④', 'في بداية كل فترة جديدة، أرسل الكود الجديد'),
    ]));

  Widget _step(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$num  ', style: const TextStyle(
          color: Color(0xFF0E7C7B),
          fontWeight: FontWeight.w800, fontSize: 12)),
      Expanded(child: Text(text,
          style: const TextStyle(
              color: Color(0xFF4A7A9B), fontSize: 11))),
    ]));

  Widget _periodCard(BuildContext ctx, _Period p, bool isCurrent) {
    final code = LicenseService.generateCode(forDate: p.start);
    final c    = isCurrent
        ? const Color(0xFF00E676)
        : const Color(0xFF4A7A9B);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? const Color(0xFF00E676).withOpacity(0.6)
              : const Color(0xFF1E3050),
          width: isCurrent ? 1.5 : 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Header row
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.withOpacity(0.5))),
            child: Text('P${p.num} — ${p.year}',
                style: TextStyle(color: c, fontSize: 11,
                    fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          if (isCurrent) Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF00E676).withOpacity(0.15),
              borderRadius: BorderRadius.circular(6)),
            child: const Text('الفترة الحالية',
                style: TextStyle(color: Color(0xFF00E676),
                    fontSize: 10, fontWeight: FontWeight.w700))),
          const Spacer(),
          Text('${_fmt(p.start)} ← ${_fmt(p.end)}',
              style: const TextStyle(color: Color(0xFF4A7A9B), fontSize: 10),
              textDirection: TextDirection.ltr),
        ]),

        const SizedBox(height: 14),

        // Code + copy button
        Row(children: [
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E1A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E3050))),
            child: Text(code,
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: c, fontSize: 32,
                    fontWeight: FontWeight.w900, letterSpacing: 12)))),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text('تم نسخ الكود: $code — أرسله للمراقبين',
                    textDirection: TextDirection.rtl),
                backgroundColor: const Color(0xFF0E7C7B),
                duration: const Duration(seconds: 3)));
            },
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF0E7C7B).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF0E7C7B).withOpacity(0.4))),
              child: const Icon(Icons.copy_rounded,
                  color: Color(0xFF0E7C7B), size: 22))),
        ]),

        const SizedBox(height: 8),
        Text('صالح من ${_fmt(p.start)} إلى ${_fmt(p.end)}',
            style: const TextStyle(color: Color(0xFF2A3A50), fontSize: 10),
            textDirection: TextDirection.rtl),
      ]));
  }
}
