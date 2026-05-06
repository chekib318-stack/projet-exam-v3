import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/license_service.dart';
import '../core/constants.dart';
import 'home_screen.dart';

class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});
  @override State<ActivationScreen> createState() => _ActivState();
}

class _ActivState extends State<ActivationScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _shake;
  final _ctrl     = TextEditingController();
  bool  _loading  = false;
  bool  _error    = false;
  bool  _blocked  = false;
  int   _attempts = 0;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
  }

  @override
  void dispose() { _shake.dispose(); _ctrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_blocked || _loading) return;
    final code = _ctrl.text.trim();
    if (code.length != 6) return;

    setState(() { _loading = true; _error = false; });
    await Future.delayed(const Duration(milliseconds: 700));

    if (LicenseService.verifyCode(code)) {
      await LicenseService.activate();
      if (mounted) {
        Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    } else {
      _attempts++;
      setState(() { _loading = false; _error = true; });
      _shake.forward(from: 0).then((_) => _shake.reverse());
      if (_attempts >= 5) {
        setState(() => _blocked = true);
        await Future.delayed(const Duration(seconds: 60));
        if (mounted) setState(() { _blocked = false; _attempts = 0; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [

                // Ministry logo
                Container(
                  width: 88, height: 88,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Colors.white,
                    boxShadow: [BoxShadow(
                        color: Color(0x40B8960C), blurRadius: 20)]),
                  child: ClipOval(child: Padding(
                    padding: const EdgeInsets.all(7),
                    child: Image.asset('assets/ministry_logo.png',
                        fit: BoxFit.contain)))),
                const SizedBox(height: 16),

                const Text('رصد أجهزة الغش الإلكتروني',
                    style: TextStyle(color: Colors.white, fontSize: 17,
                        fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                const Text('وزارة التربية — الجمهورية التونسية',
                    style: TextStyle(color: Color(0xFF4A7A9B), fontSize: 11)),

                const SizedBox(height: 36),

                // Activation card
                AnimatedBuilder(
                  animation: _shake,
                  builder: (_, child) => Transform.translate(
                    offset: Offset(
                        _shake.isAnimating
                            ? (_shake.value < 0.5
                                ? _shake.value * 14
                                : (1 - _shake.value) * 14)
                            : 0.0,
                        0),
                    child: child),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _error
                            ? const Color(0xFFFF1744).withOpacity(0.5)
                            : const Color(0xFF0E7C7B).withOpacity(0.35),
                        width: 1.2)),
                    child: Column(children: [

                      // Icon
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF0E7C7B).withOpacity(0.10),
                          border: Border.all(
                              color: const Color(0xFF0E7C7B).withOpacity(0.35))),
                        child: const Icon(Icons.shield_outlined,
                            color: Color(0xFF0E7C7B), size: 30)),
                      const SizedBox(height: 14),

                      // Title — simple
                      const Text('أدخل كود التفعيل',
                          style: TextStyle(color: Colors.white,
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),

                      // Description
                      const Text(
                        'يُرسَل إليك من المهندس المسؤول\n'
                        'شكيب الوسلاتي — ديوان وزير التربية',
                        style: TextStyle(color: Color(0xFF4A7A9B),
                            fontSize: 12, height: 1.5),
                        textAlign: TextAlign.center),
                      const SizedBox(height: 22),

                      // 6-digit input
                      Directionality(
                        textDirection: TextDirection.ltr,
                        child: TextField(
                          controller: _ctrl,
                          enabled: !_blocked && !_loading,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 28,
                              fontWeight: FontWeight.w900, letterSpacing: 10),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '○ ○ ○ ○ ○ ○',
                            hintStyle: const TextStyle(
                                color: Color(0xFF2A3A50),
                                fontSize: 22, letterSpacing: 8),
                            filled: true,
                            fillColor: const Color(0xFF0A0E1A),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: _error
                                        ? const Color(0xFFFF1744).withOpacity(0.5)
                                        : const Color(0xFF1E3050))),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: Color(0xFF0E7C7B), width: 1.5)),
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 12)))),

                      // Error message
                      if (_error) ...[
                        const SizedBox(height: 10),
                        Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          const Icon(Icons.cancel_outlined,
                              color: Color(0xFFFF1744), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            _blocked
                                ? 'تجاوزت عدد المحاولات — انتظر دقيقة'
                                : 'الكود غير صحيح (المحاولة $_attempts)',
                            style: const TextStyle(
                                color: Color(0xFFFF1744), fontSize: 12)),
                        ]),
                      ],

                      const SizedBox(height: 20),

                      // Submit button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loading || _blocked ? null : _submit,
                          icon: _loading
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.check_circle_outline_rounded,
                                  size: 18),
                          label: Text(_blocked
                              ? 'محظور مؤقتاً...'
                              : _loading ? '' : 'تفعيل التطبيق'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E7C7B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            disabledBackgroundColor:
                                const Color(0xFF0E7C7B).withOpacity(0.3)))),
                    ])),
                ),

                const SizedBox(height: 24),

                // Footer
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF1E3050), width: 0.5)),
                  child: Row(children: [
                    const Icon(Icons.info_outline_rounded,
                        color: Color(0xFF4A7A9B), size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(
                      'صالح حتى: ${LicenseService.expiryDateLabel}  •  الإصدار 1.0',
                      style: const TextStyle(
                          color: Color(0xFF4A7A9B), fontSize: 10))),
                  ])),
              ]),
          )),
      ));
  }
}
