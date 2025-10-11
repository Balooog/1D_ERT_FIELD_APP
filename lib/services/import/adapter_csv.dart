import 'dart:convert';

import 'package:csv/csv.dart';

import 'import_adapter.dart';
import 'import_models.dart';

class CsvImportAdapter implements ImportAdapter {
  const CsvImportAdapter();

  static const List<String> _candidateDelimiters = [',', ';', '\t', '|'];

  @override
  Future<ImportTable> parse(ImportSource source) async {
    var decoded = utf8.decode(source.bytes, allowMalformed: true);
    if (decoded.isEmpty) {
      return ImportTable(headers: const [], rows: const []);
    }
    if (decoded.codeUnitAt(0) == 0xFEFF) {
      decoded = decoded.substring(1);
    }

    final splitter = const LineSplitter();
    final lines = splitter.convert(decoded);
    final filteredLines = <String>[];
    String? unitDirective;
    var headerFound = false;
    for (final raw in lines) {
      var sanitized = raw.replaceAll('\r', '');
      if (sanitized.isEmpty) {
        continue;
      }
      final trimmed = sanitized.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final lower = trimmed.toLowerCase();
      if (!headerFound) {
        if (lower.startsWith('unit=')) {
          final equalsIndex = trimmed.indexOf('=');
          unitDirective = equalsIndex >= 0 ? trimmed.substring(equalsIndex + 1).trim() : null;
          continue;
        }
        if (trimmed.startsWith('#') || trimmed.startsWith('//') || trimmed.startsWith(';')) {
          continue;
        }
        if (sanitized.codeUnitAt(0) == 0xFEFF) {
          sanitized = sanitized.substring(1);
        }
        filteredLines.add(sanitized);
        headerFound = true;
        continue;
      }
      if (trimmed.startsWith('#') || trimmed.startsWith('//') || trimmed.startsWith(';')) {
        continue;
      }
      filteredLines.add(sanitized);
    }

    if (filteredLines.isEmpty) {
      return ImportTable(headers: const [], rows: const [], unitDirective: unitDirective);
    }

    final delimiter = _detectDelimiter(filteredLines);
    final converter = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    );
    final rawRows = converter.convert(filteredLines.join('\n'));
    if (rawRows.isEmpty) {
      return ImportTable(headers: const [], rows: const [], unitDirective: unitDirective);
    }

    final normalized = rawRows
        .map(
          (row) => row
              .map((value) => value?.toString().trim() ?? '')
              .toList(growable: false),
        )
        .toList(growable: false);

    final header = normalized.first;
    final rows = normalized.skip(1).where((row) {
      return row.any((cell) => cell.isNotEmpty);
    }).toList(growable: false);

    return ImportTable(headers: header, rows: rows, unitDirective: unitDirective);
  }

  String _detectDelimiter(List<String> lines) {
    if (lines.isEmpty) {
      return ',';
    }
    final sample = lines.where((line) => line.trim().isNotEmpty).take(10).toList();
    if (sample.isEmpty) {
      return ',';
    }
    final scores = <String, _DelimiterScore>{};
    for (final delimiter in _candidateDelimiters) {
      final counts = sample
          .map((line) => line.split(delimiter).length)
          .where((count) => count > 1)
          .toList();
      if (counts.isEmpty) {
        continue;
      }
      final mean = _mean(counts);
      final variance = _meanDouble(
        counts.map((count) => (count - mean) * (count - mean)).toList(),
      );
      scores[delimiter] = _DelimiterScore(mean: mean, variance: variance);
    }
    if (scores.isEmpty) {
      return ',';
    }
    final sorted = scores.entries.toList()
      ..sort((a, b) {
        final meanCompare = b.value.mean.compareTo(a.value.mean);
        if (meanCompare != 0) {
          return meanCompare;
        }
        return a.value.variance.compareTo(b.value.variance);
      });
    return sorted.first.key;
  }
}

class _DelimiterScore {
  const _DelimiterScore({required this.mean, required this.variance});

  final double mean;
  final double variance;
}

double _mean(List<int> values) {
  if (values.isEmpty) {
    return 0;
  }
  var sum = 0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}

double _meanDouble(List<double> values) {
  if (values.isEmpty) {
    return 0;
  }
  var sum = 0.0;
  for (final value in values) {
    sum += value;
  }
  return sum / values.length;
}
