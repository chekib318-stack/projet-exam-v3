import 'package:flutter/material.dart';
import '../core/constants.dart';
import 'home_screen.dart';
import '../screens/activation_screen.dart';
import '../services/license_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _fade;
  late Animation<double>   _scale;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1200));

    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _scale = Tween(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));

    _ctrl.forward();

    // Auto-navigate after 10 seconds — check license
    Future.delayed(const Duration(seconds: 10), () async {
      if (!mounted) return;
      final status = await LicenseService.checkStatus();
      if (!mounted) return;
      final dest = switch (status) {
        LicenseStatus.active       => const HomeScreen(),
        LicenseStatus.requiresCode => const ActivationScreen(),
        LicenseStatus.expired      => const ActivationScreen(),
      };
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => dest,
          transitionDuration: const Duration(milliseconds: 700),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E18),
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: ScaleTransition(
            scale: _scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // ── Ministry Logo ──────────────────────────────────────
                Container(
                  width: 180, height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFB8960C).withOpacity(0.45),
                        blurRadius: 40, spreadRadius: 6),
                    ]),
                  child: ClipOval(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Image.asset(
                        'assets/ministry_logo.png',
                        fit: BoxFit.contain),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // ── Gold divider ───────────────────────────────────────
                Container(
                  width: 80, height: 2,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [
                      Colors.transparent,
                      Color(0xFFB8960C),
                      Colors.transparent,
                    ]),
                    borderRadius: BorderRadius.circular(1)),
                ),

                const SizedBox(height: 28),

                // ── App title ─────────────────────────────────────────
                const Text(
                  'رصد أجهزة الغش الإلكتروني',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 10),

                // ── English subtitle ──────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.35),
                        width: 0.8)),
                  child: const Text(
                    'ExamGuard',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.5),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Ministry text ─────────────────────────────────────
                const Text(
                  'وزارة التربية — الجمهورية التونسية',
                  style: TextStyle(
                    color: Color(0xFFB8960C),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5),
                ),

                const SizedBox(height: 60),

                // ── Animated dots ─────────────────────────────────────
                _AnimatedDots(),

                const SizedBox(height: 14),

                Text('الإصدار 1.0',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.25),
                        fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Animated loading dots ──────────────────────────────────────────────────
class _AnimatedDots extends StatefulWidget {
  @override
  State<_AnimatedDots> createState() => _AnimatedDotsState();
}

class _AnimatedDotsState extends State<_AnimatedDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final delay = i / 3.0;
          final t = ((_ctrl.value - delay) % 1.0 + 1.0) % 1.0;
          final opacity = (0.25 + 0.75 * (t < 0.5 ? t * 2 : 2 - t * 2));
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accent.withOpacity(opacity)));
        }),
      ),
    );
  }
}
