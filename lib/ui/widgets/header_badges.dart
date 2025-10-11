import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/qc_rules.dart';

class HeaderBadges extends StatelessWidget {
  const HeaderBadges({super.key, required this.summary});

  final QaSummary summary;

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('0.0');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _badge('RMS%', numberFormat.format(summary.rms)),
          _badge('χ²', numberFormat.format(summary.chiSq)),
          _badge('Green', summary.green.toString(), color: Colors.green),
          _badge('Yellow', summary.yellow.toString(), color: Colors.orange),
          _badge('Red', summary.red.toString(), color: Colors.red),
          _badge(
              'SP drift',
              summary.lastSpDrift == null
                  ? '—'
                  : '${summary.lastSpDrift!.toStringAsFixed(2)} mV'),
          _badge(
              'Contact Ω',
              summary.worstContact == null
                  ? '—'
                  : summary.worstContact!.toStringAsFixed(0)),
        ],
      ),
    );
  }

  Widget _badge(String label, String value, {Color? color}) {
    return Chip(
      avatar: color != null
          ? CircleAvatar(backgroundColor: color, radius: 6)
          : null,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
