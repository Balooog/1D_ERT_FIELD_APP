import 'dart:convert';

import 'import_adapter.dart';
import 'import_models.dart';

class SurferDatImportAdapter implements ImportAdapter {
  const SurferDatImportAdapter();

  static final RegExp _whitespace = RegExp(r'\s+');
  static final RegExp _hasLetter = RegExp(r'[A-Za-z]');

  @override
  Future<ImportTable> parse(ImportSource source) async {
    var decoded = utf8.decode(source.bytes, allowMalformed: true);
    if (decoded.isNotEmpty && decoded.codeUnitAt(0) == 0xFEFF) {
      decoded = decoded.substring(1);
    }
    final lines = decoded.split(RegExp(r'\r?\n'));
    final issues = <ImportRowIssue>[];
    final rows = <List<String>>[];
    List<String>? header;
    String? unitDirective;

    for (var i = 0; i < lines.length; i++) {
      final rawLine = lines[i];
      final line = rawLine.trim();
      if (line.isEmpty) {
        continue;
      }
      if (line.startsWith('#') ||
          line.startsWith('//') ||
          line.startsWith(';')) {
        continue;
      }
      final lower = line.toLowerCase();
      if (lower.startsWith('unit=')) {
        final equalsIndex = line.indexOf('=');
        unitDirective =
            equalsIndex >= 0 ? line.substring(equalsIndex + 1).trim() : null;
        continue;
      }
      final parts =
          line.split(_whitespace).where((part) => part.isNotEmpty).toList();
      if (parts.isEmpty) {
        continue;
      }
      if (header == null && parts.any((part) => _hasLetter.hasMatch(part))) {
        header = parts;
        continue;
      }
      if (parts.length < 3) {
        issues.add(ImportRowIssue(
            index: i + 1, message: 'Expected 3 numeric values.'));
        continue;
      }
      final values =
          parts.take(3).map((value) => value.trim()).toList(growable: false);
      if (!_isNumeric(values[0]) ||
          !_isNumeric(values[1]) ||
          !_isNumeric(values[2])) {
        issues.add(ImportRowIssue(
            index: i + 1, message: 'Non-numeric value encountered.'));
        continue;
      }
      rows.add(values);
    }

    var headers = header ?? const ['X', 'Y', 'Z'];
    if (headers.length > 3) {
      headers = headers.take(3).toList(growable: false);
    } else if (headers.length < 3) {
      headers = [
        ...headers,
        for (var i = headers.length; i < 3; i++) 'Value ${i + 1}'
      ];
    }

    return ImportTable(
      headers: headers,
      rows: rows,
      issues: issues,
      unitDirective: unitDirective,
    );
  }

  bool _isNumeric(String value) {
    return double.tryParse(value.replaceAll(',', '')) != null;
  }
}
