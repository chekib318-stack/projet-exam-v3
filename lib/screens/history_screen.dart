import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import '../core/constants.dart';
import '../services/database_service.dart';

class HistoryScreen extends StatefulWidget {
  final String session;
  const HistoryScreen({super.key, required this.session});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<IncidentRecord> _records = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await DbService.instance.getIncidents(session: widget.session);
    setState(() { _records = r; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: const Text('سجل الحوادث',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded,
                  color: AppColors.critical, size: 22),
              onPressed: _confirmDelete),
        ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(
              color: AppColors.accent))
          : _records.isEmpty
              ? const Center(child: Text('لا توجد حوادث مسجلة',
                  style: TextStyle(color: AppColors.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _records.length,
                  itemBuilder: (_, i) => _IncidentCard(record: _records[i])),
    );
  }

  void _confirmDelete() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      title: const Text('حذف السجل',
          style: TextStyle(color: AppColors.textPrimary)),
      content: const Text('هل تريد حذف جميع حوادث هذه الجلسة؟',
          style: TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(color: AppColors.textMuted))),
        TextButton(
          onPressed: () async {
            await DbService.instance.clearIncidents(widget.session);
            if (mounted) Navigator.pop(context);
            _load();
          },
          child: const Text('حذف',
              style: TextStyle(color: AppColors.critical))),
      ]));
}

class _IncidentCard extends StatelessWidget {
  final IncidentRecord record;
  const _IncidentCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('HH:mm:ss  dd/MM/yyyy');
    final Color c = switch (record.threatLevel) {
      'حرج'   => AppColors.critical,
      'عالٍ'  => AppColors.high,
      'متوسط' => AppColors.medium,
      _        => AppColors.low,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withOpacity(0.25), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(record.deviceType,
              style: const TextStyle(color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(5)),
            child: Text(record.threatLevel,
                style: TextStyle(color: c, fontSize: 11,
                    fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        // Use Directionality widget for LTR device names instead of TextDirection.ltr
        Directionality(
          textDirection: TextDirection.ltr,
          child: Text(record.deviceName,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12))),
        const SizedBox(height: 8),
        Row(children: [
          _stat('المسافة', '${record.distance.toStringAsFixed(1)} م'),
          const SizedBox(width: 18),
          _stat('RSSI', '${record.rssi.toStringAsFixed(0)} dBm'),
          const Spacer(),
          Text(fmt.format(record.timestamp),
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 10)),
        ]),
      ]));
  }

  Widget _stat(String label, String val) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(
          color: AppColors.textMuted, fontSize: 9)),
      Text(val, style: const TextStyle(
          color: AppColors.textSecondary, fontSize: 12,
          fontWeight: FontWeight.w500)),
    ]);
}
