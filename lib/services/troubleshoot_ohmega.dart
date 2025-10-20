class OhmegaIssue {
  const OhmegaIssue({
    required this.code,
    required this.title,
    required this.likely,
    required this.actions,
    required this.source,
  });

  final String code;
  final String title;
  final String likely;
  final List<String> actions;
  final String source;
}

class TroubleshootOhmega {
  static const Map<String, OhmegaIssue> _issues = {
    'CURRENT ERROR': OhmegaIssue(
      code: 'CURRENT ERROR',
      title: 'Check Electrodes',
      likely:
          'Outer current electrodes (C1/C2) have poor contact or an open circuit.',
      actions: [
        'Re-seat and water C1/C2 electrodes.',
        'Lower current setting and retry.',
        'Check cable continuity and connectors.',
      ],
      source: 'Ohmega manual p.10 + THG field notes',
    ),
    'GAIN ERROR': OhmegaIssue(
      code: 'GAIN ERROR',
      title: 'Change Current',
      likely:
          'Inner potential electrodes (P1/P2) noisy or inconsistent contact.',
      actions: [
        'Inspect and reinsert P1/P2 stakes.',
        'Re-wet soil; ensure no shorts.',
        'Reduce current or increase sample time/cycles.',
      ],
      source: 'Ohmega manual p.10 + THG field notes',
    ),
    'ERRATIC': OhmegaIssue(
      code: 'ERRATIC READINGS',
      title: 'Readings Erratic',
      likely: 'Loose electrode(s), damaged cable, or interference.',
      actions: [
        'Check all four electrodes for firm contact.',
        'Verify cables are intact and away from power lines.',
        'Repeat with longer averaging cycle.',
      ],
      source: 'Ohmega manual p.14',
    ),
    'BATTERY LOW': OhmegaIssue(
      code: 'BATTERY LOW',
      title: 'Battery Low',
      likely: 'Low 12 V battery or alternator transient.',
      actions: [
        'Recharge or use an external 12 V supply.',
        'Do not run vehicle engine while the meter is connected.',
      ],
      source: 'Ohmega manual p.12',
    ),
    'CHECK ELECTRODES': OhmegaIssue(
      code: 'CHECK ELECTRODES',
      title: 'Check Electrodes',
      likely: 'Equivalent to CURRENT ERROR: C1/C2 contact is suspect.',
      actions: [
        'Re-seat and water C1/C2.',
        'Lower current and retry.',
        'Continuity test current lead.',
      ],
      source: 'Ohmega manual p.10 + THG field notes',
    ),
  };

  static OhmegaIssue? detect(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final text = raw.toUpperCase();
    for (final entry in _issues.entries) {
      if (text.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static Iterable<OhmegaIssue> get allIssues => _issues.values;
}
