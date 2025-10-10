import 'dart:convert';

import 'import_adapter.dart';
import 'import_models.dart';

class SurferDatImportAdapter implements ImportAdapter {
  const SurferDatImportAdapter();

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');

  @override
  Future<ImportTable> parse(ImportSource source) async {
    final decoded = utf8.decode(source.bytes, allowMalformed: true);
    final lines = decoded.split(RegExp(r'\r?\n'));
    final issues = <ImportRowIssue>[];
    final rows = <List<String>>[];
    List<String>? header;

    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('#') || line.startsWith('//')) {
        continue;
      }
      final parts = line.split(_whitespace).where((part) => part.isNotEmpty).toList();
      if (parts.isEmpty) {
        continue;
      }
      if (header == null && parts.any((part) => _hasLetter.hasMatch(part))) {
        header = parts;
        continue;
      }
      if (parts.length < 3) {
        issues.add(ImportRowIssue(index: i + 1, message: 'Expected 3 numeric values.'));
        continue;
      }
      final values = parts.take(3).map((value) => value.trim()).toList(growable: false);
      if (!_isNumeric(values[0]) || !_isNumeric(values[1]) || !_isNumeric(values[2])) {
        issues.add(ImportRowIssue(index: i + 1, message: 'Non-numeric value encountered.'));
        continue;
      }
      rows.add(values);
    }

    header ??= const ['X', 'Y', 'Z'];
    if (header.length > 3) {
      header = header.take(3).toList(growable: false);
    } else if (header.length < 3) {
      header = [...header, for (var i = header.length; i < 3; i++) 'Value ${i + 1}'];
    }

    return ImportTable(
      headers: header!,
      rows: rows,
      issues: issues,
    );
  }

  bool _isNumeric(String value) {
    return double.tryParse(value.replaceAll(',', '')) != null;
  }
}
