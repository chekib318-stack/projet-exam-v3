import 'package:flutter/material.dart';
import '../core/constants.dart';

class WhitelistScreen extends StatelessWidget {
  const WhitelistScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('القائمة البيضاء',
            style: TextStyle(color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textSecondary)),
      body: const Center(
        child: Text('ميزة القائمة البيضاء قادمة قريباً',
            style: TextStyle(color: AppColors.textMuted))),
    );
  }
}
