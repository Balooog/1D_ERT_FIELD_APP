import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../../models/direction_reading.dart';
import '../../models/site.dart';

enum ImportColumnTarget {
  aSpacingFeet,
  pinsInsideFeet,
  pinsOutsideFeet,
  resistanceNsOhm,
  resistanceWeOhm,
  sdNsPercent,
  sdWePercent,
  units,
}

enum ImportDistanceUnit {
  feet,
  meters,
}

extension ImportDistanceUnitX on ImportDistanceUnit {
  String get label {
    switch (this) {
      case ImportDistanceUnit.feet:
        return 'Feet (ft)';
      case ImportDistanceUnit.meters:
        return 'Meters (m)';
    }
  }

  double toFeet(double value) {
    switch (this) {
      case ImportDistanceUnit.feet:
        return value;
      case ImportDistanceUnit.meters:
        return value * 3.28084;
    }
  }
}

class ImportSource {
  const ImportSource({
    required this.name,
    required this.bytes,
    this.explicitSheet,
  });

  final String name;
  final Uint8List bytes;
  final String? explicitSheet;
}

class ImportRowIssue {
  ImportRowIssue({
    required this.index,
    required this.message,
  });

  final int index;
  final String message;
}

class ImportTable {
  ImportTable({
    required this.headers,
    required this.rows,
    List<ImportRowIssue>? issues,
  }) : issues = List.unmodifiable(issues ?? const []);

  final List<String> headers;
  final List<List<String>> rows;
  final List<ImportRowIssue> issues;
}

class ImportColumnDescriptor {
  ImportColumnDescriptor({
    required this.index,
    required this.header,
    required this.samples,
    required this.isNumeric,
    this.suggestedTarget,
  });

  final int index;
  final String header;
  final List<String> samples;
  final bool isNumeric;
  final ImportColumnTarget? suggestedTarget;
}

class ImportPreview {
  ImportPreview({
    required this.typeLabel,
    required this.columnCount,
    required this.rowCount,
    required this.previewRows,
    required this.columns,
    required this.issues,
  });

  final String typeLabel;
  final int columnCount;
  final int rowCount;
  final List<List<String>> previewRows;
  final List<ImportColumnDescriptor> columns;
  final List<ImportRowIssue> issues;
}

class ImportSession {
  ImportSession({
    required this.source,
    required this.table,
    required this.preview,
  });

  final ImportSource source;
  final ImportTable table;
  final ImportPreview preview;
}

class ImportMapping {
  ImportMapping({
    required this.assignments,
    required this.distanceUnit,
  });

  final Map<int, ImportColumnTarget> assignments;
  final ImportDistanceUnit distanceUnit;

  ImportColumnTarget? targetForColumn(int index) => assignments[index];
}

class ImportValidationIssue {
  ImportValidationIssue({
    required this.rowIndex,
    required this.message,
  });

  final int rowIndex;
  final String message;
}

class ImportValidationResult {
  ImportValidationResult({
    required this.totalRows,
    required this.importedRows,
    required this.skippedRows,
    required this.issues,
    required this.spacings,
  });

  final int totalRows;
  final int importedRows;
  final int skippedRows;
  final List<ImportValidationIssue> issues;
  final List<SpacingRecord> spacings;

  bool get isValid => importedRows > 0 && issues.length < importedRows;
}

class ImportMergePreview {
  ImportMergePreview({
    required this.newRows,
    required this.updatedRows,
    required this.skippedRows,
    required this.duplicateSpacings,
  });

  final int newRows;
  final int updatedRows;
  final int skippedRows;
  final List<double> duplicateSpacings;
}

class ImportSummary {
  ImportSummary({
    required this.validation,
    required this.merge,
  });

  final ImportValidationResult validation;
  final ImportMergePreview? merge;
}

SpacingRecord buildSpacingRecord({
  required double spacingFeet,
  double? resistanceNs,
  double? sdNs,
  double? resistanceWe,
  double? sdWe,
}) {
  DirectionReadingHistory buildHistory({
    required OrientationKind orientation,
    required String label,
    double? resistance,
    double? sd,
  }) {
    final sample = resistance == null && sd == null
        ? null
        : DirectionReadingSample(
            timestamp: DateTime.now(),
            resistanceOhm: resistance,
            standardDeviationPercent: sd,
          );
    return DirectionReadingHistory(
      orientation: orientation,
      label: label,
      samples: sample == null ? const [] : [sample],
    );
  }

  return SpacingRecord(
    spacingFeet: spacingFeet,
    orientationA: buildHistory(
      orientation: OrientationKind.a,
      label: 'N–S',
      resistance: resistanceNs,
      sd: sdNs,
    ),
    orientationB: buildHistory(
      orientation: OrientationKind.b,
      label: 'W–E',
      resistance: resistanceWe,
      sd: sdWe,
    ),
  );
}

extension ImportValidationResultX on ImportValidationResult {
  Map<double, SpacingRecord> toSpacingMap() {
    final map = <double, SpacingRecord>{};
    for (final spacing in spacings) {
      map[spacing.spacingFeet] = spacing;
    }
    return map;
  }
}

extension ImportColumnTargetLabel on ImportColumnTarget {
  String get label {
    switch (this) {
      case ImportColumnTarget.aSpacingFeet:
        return 'a-spacing';
      case ImportColumnTarget.pinsInsideFeet:
        return 'Pins in';
      case ImportColumnTarget.pinsOutsideFeet:
        return 'Pins out';
      case ImportColumnTarget.resistanceNsOhm:
        return 'Res N–S';
      case ImportColumnTarget.resistanceWeOhm:
        return 'Res W–E';
      case ImportColumnTarget.sdNsPercent:
        return 'SD N–S';
      case ImportColumnTarget.sdWePercent:
        return 'SD W–E';
      case ImportColumnTarget.units:
        return 'Units';
    }
  }
}

extension ImportColumnDescriptorLookup on Iterable<ImportColumnDescriptor> {
  ImportColumnDescriptor? byTarget(ImportColumnTarget target) {
    return firstWhereOrNull((descriptor) => descriptor.suggestedTarget == target);
  }
}
