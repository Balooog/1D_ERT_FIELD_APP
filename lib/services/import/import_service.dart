import 'dart:math' as math;

import '../../models/direction_reading.dart';
import '../../models/site.dart';
import 'adapter_csv.dart';
import 'adapter_excel.dart';
import 'adapter_surfer_dat.dart';
import 'import_adapter.dart';
import 'import_models.dart';

class ImportService {
  ImportService({
    ImportAdapter? csvAdapter,
    ImportAdapter? excelAdapter,
    ImportAdapter? datAdapter,
  })  : _csvAdapter = csvAdapter ?? const CsvImportAdapter(),
        _excelAdapter = excelAdapter ?? const ExcelImportAdapter(),
        _datAdapter = datAdapter ?? const SurferDatImportAdapter();

  final ImportAdapter _csvAdapter;
  final ImportAdapter _excelAdapter;
  final ImportAdapter _datAdapter;
  static const int _syntheticUnitColumnIndex = -1;
  static const Set<ImportColumnTarget> _coreAutoTargets = {
    ImportColumnTarget.aSpacingFeet,
    ImportColumnTarget.pinsInsideFeet,
    ImportColumnTarget.pinsOutsideFeet,
    ImportColumnTarget.resistanceNsOhm,
    ImportColumnTarget.resistanceWeOhm,
  };

  Future<ImportSession> load(ImportSource source) async {
    final adapter = _selectAdapter(source.name);
    final table = await adapter.parse(source);
    final preview = _buildPreview(source.name, table);
    return ImportSession(source: source, table: table, preview: preview);
  }

  ImportValidationResult validate(
      ImportSession session, ImportMapping mapping) {
    final table = session.table;
    if (table.headers.isEmpty) {
      return ImportValidationResult(
        totalRows: 0,
        importedRows: 0,
        skippedRows: 0,
        issues: const [],
        spacings: const [],
      );
    }
    final assignments =
        mapping.assignments.map((key, value) => MapEntry(key, value));
    final spacingColumn =
        _columnFor(assignments, ImportColumnTarget.aSpacingFeet);
    if (spacingColumn == null) {
      return ImportValidationResult(
        totalRows: table.rows.length,
        importedRows: 0,
        skippedRows: table.rows.length,
        issues: [
          ImportValidationIssue(
              rowIndex: 0, message: 'Map an a-spacing column to import.'),
        ],
        spacings: const [],
      );
    }
    final unitColumn = _columnFor(assignments, ImportColumnTarget.units);
    final pinsInsideColumn =
        _columnFor(assignments, ImportColumnTarget.pinsInsideFeet);
    final pinsOutsideColumn =
        _columnFor(assignments, ImportColumnTarget.pinsOutsideFeet);
    final resNsColumn =
        _columnFor(assignments, ImportColumnTarget.resistanceNsOhm);
    final resWeColumn =
        _columnFor(assignments, ImportColumnTarget.resistanceWeOhm);
    final sdNsColumn = _columnFor(assignments, ImportColumnTarget.sdNsPercent);
    final sdWeColumn = _columnFor(assignments, ImportColumnTarget.sdWePercent);

    final issues = <ImportValidationIssue>[];
    final records = <SpacingRecord>[];
    final seenSpacings = <double>{};
    var imported = 0;
    var skipped = 0;

    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      final rowIndex = i + 2; // account for header
      final unit = _resolveUnit(row, unitColumn, mapping.distanceUnit);
      final spacingValue = _parseDouble(row, spacingColumn);
      if (spacingValue == null) {
        skipped++;
        issues.add(ImportValidationIssue(
            rowIndex: rowIndex, message: 'Missing a-spacing value.'));
        continue;
      }
      if (spacingValue <= 0) {
        skipped++;
        issues.add(ImportValidationIssue(
            rowIndex: rowIndex, message: 'Negative or zero a-spacing.'));
        continue;
      }
      final spacingFeet =
          double.parse(unit.toFeet(spacingValue).toStringAsFixed(5));
      if (!_checkPinsConsistency(
          row, pinsInsideColumn, pinsOutsideColumn, spacingFeet, unit)) {
        issues.add(ImportValidationIssue(
            rowIndex: rowIndex,
            message: 'Pins in/out do not match a-spacing.'));
      }
      final spacingKey = _roundSpacing(spacingFeet);
      if (seenSpacings.contains(spacingKey)) {
        skipped++;
        issues.add(ImportValidationIssue(
            rowIndex: rowIndex, message: 'Duplicate a-spacing encountered.'));
        continue;
      }
      final resistanceNs = _parseDouble(row, resNsColumn);
      final resistanceWe = _parseDouble(row, resWeColumn);
      final sdNs = _parseDouble(row, sdNsColumn);
      final sdWe = _parseDouble(row, sdWeColumn);

      if (resistanceNs == null && resistanceWe == null) {
        skipped++;
        issues.add(ImportValidationIssue(
            rowIndex: rowIndex,
            message: 'No resistivity columns mapped for this row.'));
        continue;
      }

      seenSpacings.add(spacingKey);
      imported++;
      records.add(
        buildSpacingRecord(
          spacingFeet: spacingFeet,
          resistanceNs: resistanceNs,
          sdNs: sdNs,
          resistanceWe: resistanceWe,
          sdWe: sdWe,
        ),
      );
    }

    records.sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
    return ImportValidationResult(
      totalRows: table.rows.length,
      importedRows: imported,
      skippedRows: skipped,
      issues: issues,
      spacings: records,
    );
  }

  ImportMergePreview previewMerge(
      SiteRecord? existing, ImportValidationResult validation,
      {bool overwrite = false}) {
    if (existing == null) {
      return ImportMergePreview(
        newRows: validation.importedRows,
        updatedRows: 0,
        skippedRows: 0,
        duplicateSpacings: const [],
      );
    }
    final duplicates = <double>[];
    var newRows = 0;
    var updatedRows = 0;
    var skipped = 0;

    final existingSpacings =
        existing.spacings.map((spacing) => spacing.spacingFeet).toSet();
    for (final spacing in validation.spacings) {
      if (!existingSpacings.contains(spacing.spacingFeet)) {
        newRows++;
        continue;
      }
      if (overwrite) {
        updatedRows++;
      } else {
        skipped++;
        duplicates.add(spacing.spacingFeet);
      }
    }
    return ImportMergePreview(
      newRows: newRows,
      updatedRows: updatedRows,
      skippedRows: skipped,
      duplicateSpacings: duplicates,
    );
  }

  SiteRecord mergeIntoSite({
    required SiteRecord base,
    required ImportValidationResult validation,
    bool overwrite = false,
  }) {
    var updated = base;
    for (final spacing in validation.spacings) {
      final existing = updated.spacing(spacing.spacingFeet);
      if (existing == null) {
        updated = updated.upsertSpacing(spacing);
        continue;
      }
      if (!overwrite) {
        continue;
      }
      updated = updated.upsertSpacing(_mergeSpacing(existing, spacing));
    }
    return updated;
  }

  SiteRecord createSite({
    required String siteId,
    required String displayName,
    required ImportValidationResult validation,
    double powerMilliAmps = 0.5,
    int stacks = 4,
    SoilType soil = SoilType.unknown,
    MoistureLevel moisture = MoistureLevel.normal,
  }) {
    return SiteRecord(
      siteId: siteId,
      displayName: displayName,
      powerMilliAmps: powerMilliAmps,
      stacks: stacks,
      soil: soil,
      moisture: moisture,
      spacings: validation.spacings,
    );
  }

  ImportMapping autoMap(ImportPreview preview) {
    final assignments = <int, ImportColumnTarget>{};
    final assignedTargets = <ImportColumnTarget>{};

    void tryAssign(int index, ImportColumnTarget target) {
      if (assignedTargets.contains(target)) {
        return;
      }
      assignments[index] = target;
      assignedTargets.add(target);
    }

    for (final column in preview.columns) {
      final target = column.suggestedTarget;
      if (target == ImportColumnTarget.units) {
        tryAssign(column.index, ImportColumnTarget.units);
      }
    }
    for (final column in preview.columns) {
      final target = column.suggestedTarget;
      if (target != null && _coreAutoTargets.contains(target)) {
        final resolved = target;
        tryAssign(column.index, resolved);
      }
    }

    final detectedUnit = preview.unitDetection.unit;
    if (!assignedTargets.contains(ImportColumnTarget.units) &&
        detectedUnit != null) {
      tryAssign(_syntheticUnitColumnIndex, ImportColumnTarget.units);
    }

    return ImportMapping(
      assignments: assignments,
      distanceUnit: preview.unitDetection.unit ?? ImportDistanceUnit.meters,
    );
  }

  ImportAdapter _selectAdapter(String fileName) {
    final normalized = fileName.toLowerCase();
    if (normalized.endsWith('.xlsx')) {
      return _excelAdapter;
    }
    if (normalized.endsWith('.dat')) {
      return _datAdapter;
    }
    return _csvAdapter;
  }

  ImportPreview _buildPreview(String fileName, ImportTable table) {
    final typeLabel = _typeLabelFor(fileName);
    final columns = <ImportColumnDescriptor>[];
    for (var i = 0; i < table.headers.length; i++) {
      final header = table.headers[i];
      final samples = <String>[];
      for (final row in table.rows.take(5)) {
        if (i < row.length) {
          samples.add(row[i]);
        }
      }
      final isNumeric = _isMostlyNumeric(samples);
      columns.add(
        ImportColumnDescriptor(
          index: i,
          header: header,
          samples: samples,
          isNumeric: isNumeric,
          suggestedTarget: _suggestTarget(header, samples, isNumeric),
        ),
      );
    }

    final previewRows = table.rows
        .take(20)
        .map((row) => row.take(table.headers.length).toList())
        .toList();
    final detection = _detectUnits(fileName, table, columns);
    return ImportPreview(
      typeLabel: typeLabel,
      columnCount: table.headers.length,
      rowCount: table.rows.length,
      previewRows: previewRows,
      columns: columns,
      issues: table.issues,
      unitDetection: detection,
    );
  }

  String _typeLabelFor(String fileName) {
    final normalized = fileName.toLowerCase();
    if (normalized.endsWith('.xlsx')) {
      return 'Excel (.xlsx)';
    }
    if (normalized.endsWith('.dat')) {
      return 'Surfer DAT (.dat)';
    }
    if (normalized.endsWith('.txt')) {
      return 'Text (.txt)';
    }
    if (normalized.endsWith('.csv')) {
      return 'CSV (.csv)';
    }
    return 'Delimited text';
  }

  ImportColumnTarget? _suggestTarget(
      String header, List<String> samples, bool isNumeric) {
    final normalized = header.toLowerCase();
    final sanitized = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    bool containsAny(List<String> tokens) =>
        tokens.any((token) => sanitized.contains(token));

    if (containsAny(['unit', 'units'])) {
      return ImportColumnTarget.units;
    }

    if (!isNumeric) {
      final joinedSamples = samples.join(' ').toLowerCase();
      if (joinedSamples.contains('ft') || joinedSamples.contains('feet')) {
        return ImportColumnTarget.units;
      }
      if (joinedSamples.contains('m ')) {
        return ImportColumnTarget.units;
      }
      return null;
    }

    if (_looksLikeSpacingHeader(sanitized)) {
      return ImportColumnTarget.aSpacingFeet;
    }
    if (containsAny(['inside', 'pins in', 'mn', 'inner'])) {
      return ImportColumnTarget.pinsInsideFeet;
    }
    if (containsAny(['outside', 'pins out', 'outer'])) {
      return ImportColumnTarget.pinsOutsideFeet;
    }
    if (containsAny(['sd', 'std', 'stdev', 'sigma'])) {
      if (containsAny(['ns', 'north south'])) {
        return ImportColumnTarget.sdNsPercent;
      }
      if (containsAny(['we', 'west east', 'east west'])) {
        return ImportColumnTarget.sdWePercent;
      }
      return null;
    }
    if (containsAny(['res', 'rho'])) {
      if (containsAny(['ns', 'north south'])) {
        return ImportColumnTarget.resistanceNsOhm;
      }
      if (containsAny(['we', 'west east', 'east west'])) {
        return ImportColumnTarget.resistanceWeOhm;
      }
      if (containsAny(['avg', 'mean'])) {
        return ImportColumnTarget.resistanceNsOhm;
      }
    }
    return null;
  }

  bool _looksLikeSpacingHeader(String sanitized) {
    if (sanitized.isEmpty) {
      return false;
    }
    if (sanitized.contains('spacing') ||
        sanitized.contains('electrode spacing') ||
        sanitized.contains('a spacing')) {
      return true;
    }
    final tokens = sanitized.split(' ');
    if (tokens.isNotEmpty &&
        (tokens.first == 'a' ||
            tokens.first.startsWith('ab') ||
            tokens.first == 'ab')) {
      return true;
    }
    final pattern = RegExp(r'(^|[\s_])(a|ab)([\s_]|$)');
    if (pattern.hasMatch(sanitized)) {
      return true;
    }
    return false;
  }

  int? _columnFor(
      Map<int, ImportColumnTarget> assignments, ImportColumnTarget target) {
    for (final entry in assignments.entries) {
      if (entry.value == target) {
        return entry.key;
      }
    }
    return null;
  }

  ImportDistanceUnit _resolveUnit(
      List<String> row, int? unitColumn, ImportDistanceUnit fallback) {
    if (unitColumn == null || unitColumn < 0 || unitColumn >= row.length) {
      return fallback;
    }
    final text = row[unitColumn].toLowerCase();
    if (text.contains('m')) {
      return ImportDistanceUnit.meters;
    }
    if (text.contains('f')) {
      return ImportDistanceUnit.feet;
    }
    return fallback;
  }

  double? _parseDouble(List<String> row, int? column) {
    if (column == null || column >= row.length) {
      return null;
    }
    final text = row[column].trim();
    if (text.isEmpty) {
      return null;
    }
    return double.tryParse(_normalizeNumeric(text));
  }

  bool _isMostlyNumeric(List<String> samples) {
    if (samples.isEmpty) {
      return false;
    }
    var numeric = 0;
    for (final sample in samples) {
      if (double.tryParse(sample.replaceAll(RegExp(r'[^0-9eE+\-.]'), '')) !=
          null) {
        numeric++;
      }
    }
    return numeric >= math.max(1, samples.length ~/ 2);
  }

  String _normalizeNumeric(String text) {
    return text.replaceAll(RegExp(r'[^0-9eE+\-.]'), '');
  }

  bool _checkPinsConsistency(
    List<String> row,
    int? insideColumn,
    int? outsideColumn,
    double spacingFeet,
    ImportDistanceUnit unit,
  ) {
    if (insideColumn == null || outsideColumn == null) {
      return true;
    }
    final inside = _parseDouble(row, insideColumn);
    final outside = _parseDouble(row, outsideColumn);
    if (inside == null || outside == null) {
      return true;
    }
    final insideFeet = unit.toFeet(inside);
    final outsideFeet = unit.toFeet(outside);
    final expectedSpacing = (insideFeet + outsideFeet) / 2;
    return (expectedSpacing - spacingFeet).abs() <= 0.5;
  }

  double _roundSpacing(double spacingFeet) {
    return double.parse(spacingFeet.toStringAsFixed(5));
  }

  SpacingRecord _mergeSpacing(SpacingRecord existing, SpacingRecord incoming) {
    DirectionReadingHistory mergeHistory(
      DirectionReadingHistory current,
      DirectionReadingHistory next,
    ) {
      if (next.samples.isEmpty) {
        return current;
      }
      return current.copyWith(samples: next.samples);
    }

    return existing.copyWith(
      orientationA: mergeHistory(existing.orientationA, incoming.orientationA)
          .copyWith(label: existing.orientationA.label),
      orientationB: mergeHistory(existing.orientationB, incoming.orientationB)
          .copyWith(label: existing.orientationB.label),
    );
  }

  ImportUnitDetection _detectUnits(
    String fileName,
    ImportTable table,
    List<ImportColumnDescriptor> columns,
  ) {
    final signals = <_UnitSignal>[];
    final evidence = <String>{};

    void addSignal(
      ImportDistanceUnit unit,
      double confidence,
      String reason, {
      int priority = 3,
    }) {
      signals.add(
        _UnitSignal(
          unit: unit,
          confidence: confidence,
          reason: reason,
          priority: priority,
        ),
      );
      evidence.add(reason);
    }

    for (final column in columns) {
      final suffixUnit = _unitFromHeaderSuffix(column.header);
      if (suffixUnit != null) {
        final suffix = suffixUnit == ImportDistanceUnit.meters ? '_m' : '_ft';
        final qualifier = suffixUnit == ImportDistanceUnit.feet
            ? ' (filename or directive)'
            : '';
        addSignal(
          suffixUnit,
          0.95,
          'Header "${column.header}" ends with $suffix$qualifier',
          priority: 0,
        );
      }
    }

    final directive = table.unitDirective?.trim();
    if (directive != null && directive.isNotEmpty) {
      final unit = _unitFromText(directive);
      if (unit != null) {
        addSignal(
          unit,
          0.9,
          'Unit directive "$directive"',
          priority: 1,
        );
      }
    }

    final nameUnit = _unitFromFilename(fileName);
    if (nameUnit != null) {
      addSignal(
        nameUnit,
        0.75,
        'Filename suffix indicates ${nameUnit == ImportDistanceUnit.meters ? 'meters' : 'feet'}',
        priority: 2,
      );
    }

    for (final column in columns.where((c) => !c.isNumeric)) {
      for (final sample in column.samples) {
        final unit = _unitFromText(sample);
        if (unit != null) {
          addSignal(
            unit,
            0.65,
            'Sample "${sample.trim()}" hints at ${unit == ImportDistanceUnit.meters ? 'meters' : 'feet'}',
          );
          break;
        }
      }
    }

    ImportColumnDescriptor? spacingColumn =
        columns.byTarget(ImportColumnTarget.aSpacingFeet);
    if (spacingColumn == null) {
      for (final column in columns) {
        if (column.isNumeric) {
          spacingColumn = column;
          break;
        }
      }
    }
    spacingColumn ??= columns.isEmpty ? null : columns.first;
    if (spacingColumn != null) {
      final values = <double>[];
      for (final row in table.rows.take(80)) {
        if (spacingColumn.index < row.length) {
          final value =
              double.tryParse(_normalizeNumeric(row[spacingColumn.index]));
          if (value != null && value.isFinite) {
            values.add(value.abs());
          }
        }
      }
      if (values.isNotEmpty) {
        values.sort();
        final median = values[values.length ~/ 2];
        final max = values.last;
        if (median >= 0.1 && median <= 150 && max <= 200) {
          addSignal(
            ImportDistanceUnit.meters,
            0.55,
            'Spacing median ${median.toStringAsFixed(1)} within meter range',
          );
        }
        bool nearMultiple(double value, double step, double tolerance) {
          final remainder = value % step;
          return remainder <= tolerance || (step - remainder) <= tolerance;
        }

        final multiplesOfFive = values.where((value) {
          if (value < 5) {
            return false;
          }
          return nearMultiple(value, 5, 0.01);
        }).length;
        if (values.length >= 3 &&
            multiplesOfFive >= (values.length * 0.6) &&
            max >= 20) {
          addSignal(
            ImportDistanceUnit.feet,
            0.5,
            'Spacing increments align with 5 ft multiples',
          );
        }
      }
    }

    if (signals.isEmpty) {
      return const ImportUnitDetection(ambiguous: true);
    }

    signals.sort((a, b) {
      final priorityCompare = a.priority.compareTo(b.priority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return b.confidence.compareTo(a.confidence);
    });

    final top = signals.first;
    _UnitSignal? competitor;
    for (final signal in signals.skip(1)) {
      if (signal.priority != top.priority) {
        break;
      }
      if (signal.unit != top.unit) {
        competitor = signal;
        break;
      }
    }
    final ambiguous = top.confidence < 0.6 ||
        (competitor != null &&
            (top.confidence - competitor.confidence).abs() <= 0.15);
    return ImportUnitDetection(
      unit: top.unit,
      reason: top.reason,
      evidence: evidence.toList(growable: false),
      confidence: top.confidence,
      ambiguous: ambiguous,
    );
  }

  ImportDistanceUnit? _unitFromFilename(String fileName) {
    final normalized = fileName.toLowerCase();
    final stem = normalized.replaceFirst(RegExp(r'\.[^.]+$'), '');
    if (RegExp(r'(?:_|-)(m|meter|meters)$').hasMatch(stem)) {
      return ImportDistanceUnit.meters;
    }
    if (RegExp(r'(?:_|-)(ft|feet|foot)$').hasMatch(stem)) {
      return ImportDistanceUnit.feet;
    }
    return null;
  }

  ImportDistanceUnit? _unitFromHeaderSuffix(String header) {
    final normalized = header.toLowerCase();
    if (normalized.endsWith('_m') ||
        normalized.endsWith('_meter') ||
        normalized.endsWith('_meters')) {
      return ImportDistanceUnit.meters;
    }
    if (normalized.endsWith('_ft') ||
        normalized.endsWith('_foot') ||
        normalized.endsWith('_feet')) {
      return ImportDistanceUnit.feet;
    }
    return null;
  }

  ImportDistanceUnit? _unitFromText(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized.contains('meter') || normalized == 'm') {
      return ImportDistanceUnit.meters;
    }
    if (normalized.contains('foot') ||
        normalized.contains('feet') ||
        normalized.contains('ft')) {
      return ImportDistanceUnit.feet;
    }
    return null;
  }
}

class _UnitSignal {
  _UnitSignal({
    required this.unit,
    required this.confidence,
    required this.reason,
    required this.priority,
  });

  final ImportDistanceUnit unit;
  final double confidence;
  final String reason;
  final int priority;
}
