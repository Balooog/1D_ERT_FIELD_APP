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
      final isComment =
          trimmed.startsWith('#') || trimmed.startsWith('//') || trimmed.startsWith(';');
      if (!headerFound) {
        if (lower.startsWith('unit=')) {
          final equalsIndex = trimmed.indexOf('=');
          unitDirective =
              equalsIndex >= 0 ? trimmed.substring(equalsIndex + 1).trim() : null;
          continue;
        }
        if (isComment) {
          continue;
        }
        if (sanitized.codeUnitAt(0) == 0xFEFF) {
          sanitized = sanitized.substring(1);
        }
        filteredLines.add(sanitized);
        headerFound = true;
        continue;
      }
      if (isComment || lower.startsWith('unit=')) {
        if (lower.startsWith('unit=') && unitDirective == null) {
          final equalsIndex = trimmed.indexOf('=');
          unitDirective =
              equalsIndex >= 0 ? trimmed.substring(equalsIndex + 1).trim() : null;
        }
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
        .where((row) => row.any((cell) => cell.isNotEmpty))
        .toList(growable: false);

    if (normalized.isEmpty) {
      return ImportTable(headers: const [], rows: const [], unitDirective: unitDirective);
    }

    final headerResult = _normalizeHeaderRow(normalized.first);
    if (headerResult.isLikelyDataRow) {
      final inferredHeaders = List<String>.generate(
        normalized.first.length,
        (index) => 'column_${index + 1}',
      );
      final rows = normalized
          .map((row) => row.take(inferredHeaders.length).toList(growable: false))
          .toList(growable: false);
      return ImportTable(headers: inferredHeaders, rows: rows, unitDirective: unitDirective);
    }

    final dataRows = <List<String>>[];
    for (final row in normalized.skip(1)) {
      if (headerResult.activeIndices.isEmpty) {
        continue;
      }
      final projected = <String>[];
      for (final index in headerResult.activeIndices) {
        projected.add(index < row.length ? row[index] : '');
      }
      if (projected.any((cell) => cell.isNotEmpty)) {
        dataRows.add(projected);
      }
    }

    return ImportTable(
      headers: headerResult.headers,
      rows: dataRows,
      unitDirective: unitDirective,
    );
  }

  _HeaderNormalizationResult _normalizeHeaderRow(List<String> headerRow) {
    final tokens = _normalizeHeaderTokens(headerRow);
    final activeIndices = <int>[];
    final normalizedHeaders = <String>[];
    var numericCount = 0;
    for (final token in tokens) {
      activeIndices.add(token.index);
      normalizedHeaders.add(token.normalized);
      if (_looksNumeric(token.raw)) {
        numericCount++;
      }
    }

    final isLikelyDataRow =
        activeIndices.isEmpty || numericCount >= activeIndices.length;
    return _HeaderNormalizationResult(
      headers: normalizedHeaders,
      activeIndices: activeIndices,
      isLikelyDataRow: isLikelyDataRow,
    );
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

class _HeaderNormalizationResult {
  _HeaderNormalizationResult({
    required this.headers,
    required this.activeIndices,
    required this.isLikelyDataRow,
  });

  final List<String> headers;
  final List<int> activeIndices;
  final bool isLikelyDataRow;
}

class _NormalizedHeaderToken {
  _NormalizedHeaderToken({
    required this.index,
    required this.normalized,
    required this.raw,
  });

  final int index;
  final String normalized;
  final String raw;
}

String _norm(String value) {
  if (value.isEmpty) {
    return '';
  }
  return value
      .trim()
      .replaceAll(RegExp(r'[\s\-]+'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '')
      .replaceAll(RegExp(r'_+'), '_')
      .toLowerCase();
}

List<_NormalizedHeaderToken> _normalizeHeaderTokens(List<String> raw) {
  final seen = <String>{};
  final tokens = <_NormalizedHeaderToken>[];
  for (var i = 0; i < raw.length; i++) {
    final original = raw[i];
    final trimmed = original.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final normalized = _norm(trimmed);
    if (normalized.isEmpty) {
      continue;
    }
    if (!seen.add(normalized)) {
      continue;
    }
    tokens.add(
      _NormalizedHeaderToken(
        index: i,
        normalized: normalized,
        raw: trimmed,
      ),
    );
  }
  return tokens;
}

bool _looksNumeric(String value) {
  if (value.isEmpty) {
    return false;
  }
  final normalized = value.replaceAll(RegExp(r'[^0-9eE+\-.]'), '');
  if (normalized.isEmpty) {
    return false;
  }
  return double.tryParse(normalized) != null;
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
