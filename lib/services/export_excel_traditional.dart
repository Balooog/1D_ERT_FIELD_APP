import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/calc.dart' as calc;
import '../models/enums.dart';
import '../models/project.dart';
import '../models/site.dart';

Future<File> writeTraditionalTable({
  required ProjectRecord project,
  required SiteRecord site,
  required Directory outDir,
  bool includeGps = false,
  DateTime? generatedAt,
}) async {
  final workbook = Workbook();
  final worksheet = workbook.worksheets[0]..name = 'TABLE 1';
  final timestamp = generatedAt ?? DateTime.now();
  final sortedSpacings = [...site.spacings]
    ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
  final columnCount = 1 + (sortedSpacings.length * 2);

  _buildBanner(worksheet, columnCount);
  _buildMetadata(
    worksheet: worksheet,
    project: project,
    site: site,
    timestamp: timestamp,
    includeGps: includeGps,
  );
  _buildDataTable(
    worksheet: worksheet,
    spacings: sortedSpacings,
    arrayType: project.arrayType,
  );

  worksheet.pageSetup
    ..fitToPagesWide = 1
    ..fitToPagesTall = 0
    ..printTitleRows = '\$9:\$10';

  final bytes = workbook.saveAsStream();
  workbook.dispose();

  final fileName = _buildFileName(project, site);
  final file = File(p.join(outDir.path, fileName));
  final processed = _applyHeaderFooter(Uint8List.fromList(bytes));
  await file.writeAsBytes(processed, flush: true);
  return file;
}

void _buildBanner(Worksheet sheet, int lastColumn) {
  final banner = sheet.getRangeByIndex(1, 1, 1, lastColumn);
  banner.merge();
  banner.setText('TABLE 1 — Apparent Resistivity Data');
  banner.cellStyle
    ..fontSize = 16
    ..bold = true
    ..hAlign = HAlignType.center
    ..vAlign = VAlignType.center;
}

void _buildMetadata({
  required Worksheet worksheet,
  required ProjectRecord project,
  required SiteRecord site,
  required DateTime timestamp,
  required bool includeGps,
}) {
  final leftLabels = [
    'Client',
    'Project Name/No.',
    'Location',
    'Equipment',
    'Test Method',
  ];
  final leftValues = [
    project.projectId,
    project.projectName,
    site.displayName,
    'ResiCheck Field Kit',
    _arrayTypeLabel(project.arrayType),
  ];

  for (var i = 0; i < leftLabels.length; i++) {
    final row = 3 + i;
    final labelRange = worksheet.getRangeByIndex(row, 1);
    labelRange.setText(leftLabels[i]);
    _applyMetaLabelStyle(labelRange);
    final valueRange = worksheet.getRangeByIndex(row, 2, row, 4);
    valueRange.merge();
    valueRange.setText(leftValues[i]);
    _applyMetaValueStyle(valueRange);
  }

  final rightLabels = ['Date', 'Weather', 'Temperature'];
  final rightValues = [
    DateFormat('yyyy-MM-dd').format(timestamp),
    _titleCase(site.moisture.name),
    site.groundTemperatureF.isFinite
        ? '${site.groundTemperatureF.toStringAsFixed(1)} °F'
        : '—',
  ];

  for (var i = 0; i < rightLabels.length; i++) {
    final row = 3 + i;
    final labelRange = worksheet.getRangeByIndex(row, 6);
    labelRange.setText(rightLabels[i]);
    _applyMetaLabelStyle(labelRange);
    final valueRange = worksheet.getRangeByIndex(row, 7, row, 8);
    valueRange.merge();
    valueRange.setText(rightValues[i]);
    _applyMetaValueStyle(valueRange);
  }

  if (includeGps && site.location != null) {
    final latitude = site.location?.latitude;
    final longitude = site.location?.longitude;
    if (latitude != null) {
      final range = worksheet.getRangeByIndex(7, 6);
      range.setText('Latitude');
      _applyMetaLabelStyle(range);
      final value = worksheet.getRangeByIndex(7, 7, 7, 8);
      value.merge();
      value.setNumber(latitude);
      value.numberFormat = '0.0000';
      _applyMetaValueStyle(value);
    }
    if (longitude != null) {
      final range = worksheet.getRangeByIndex(8, 6);
      range.setText('Longitude');
      _applyMetaLabelStyle(range);
      final value = worksheet.getRangeByIndex(8, 7, 8, 8);
      value.merge();
      value.setNumber(longitude);
      value.numberFormat = '0.0000';
      _applyMetaValueStyle(value);
    }
  }

  worksheet.setColumnWidthInPixels(1, 120);
  worksheet.setColumnWidthInPixels(2, 140);
  worksheet.setColumnWidthInPixels(3, 36);
  worksheet.setColumnWidthInPixels(4, 36);
  worksheet.setColumnWidthInPixels(6, 110);
  worksheet.setColumnWidthInPixels(7, 140);
  worksheet.setColumnWidthInPixels(8, 60);
}

void _buildDataTable({
  required Worksheet worksheet,
  required List<SpacingRecord> spacings,
  required ArrayType arrayType,
}) {
  const tableStartRow = 9;
  var column = 2;
  final directionHeader = worksheet.getRangeByIndex(tableStartRow, 1);
  directionHeader.setText('Direction');
  _applyHeaderStyle(directionHeader);
  final emptyHeader = worksheet.getRangeByIndex(tableStartRow + 1, 1);
  emptyHeader.setText('');
  _applyHeaderStyle(emptyHeader);
  final arrayLabel = worksheet.getRangeByIndex(tableStartRow + 2, 1);
  arrayLabel.setText('Array');
  _applyRowLabelStyle(arrayLabel);
  final dir1Label = worksheet.getRangeByIndex(tableStartRow + 3, 1);
  dir1Label.setText('Dir. 1');
  _applyRowLabelStyle(dir1Label);
  final dir2Label = worksheet.getRangeByIndex(tableStartRow + 4, 1);
  dir2Label.setText('Dir. 2');
  _applyRowLabelStyle(dir2Label);
  final avgLabel = worksheet.getRangeByIndex(tableStartRow + 5, 1);
  avgLabel.setText('SITE AVG');
  _applyRowLabelStyle(avgLabel, bold: true);

  final spacingSnapshots = <_SpacingSnapshot>[];

  for (final spacing in spacings) {
    final header = worksheet.getRangeByIndex(
      tableStartRow,
      column,
      tableStartRow,
      column + 1,
    );
    header.merge();
    header.setText(
      '${spacing.spacingFeet.toStringAsFixed(spacing.spacingFeet % 1 == 0 ? 0 : 1)} ft',
    );
    _applyHeaderStyle(header);

    final resistanceHeader =
        worksheet.getRangeByIndex(tableStartRow + 1, column);
    resistanceHeader.setText('Resistance (Ω)');
    _applySubHeaderStyle(resistanceHeader);
    final rhoHeader = worksheet.getRangeByIndex(tableStartRow + 1, column + 1);
    rhoHeader.setText('Apparent Resistivity (Ω·m)');
    _applySubHeaderStyle(rhoHeader);

    worksheet.setColumnWidthInPixels(column, 110);
    worksheet.setColumnWidthInPixels(column + 1, 135);

    final arrayValueRange =
        worksheet.getRangeByIndex(tableStartRow + 2, column);
    arrayValueRange.setNumber(spacing.spacingFeet);
    arrayValueRange.numberFormat = '0.0';
    _applyRowValueStyle(arrayValueRange);
    final arrayEmpty = worksheet.getRangeByIndex(tableStartRow + 2, column + 1);
    arrayEmpty.setText('');
    _applyRowValueStyle(arrayEmpty);

    final latestA = spacing.orientationA.latest;
    final latestB = spacing.orientationB.latest;
    final rhoA = _computeResistivity(
      arrayType,
      spacing.spacingFeet,
      latestA?.resistanceOhm,
    );
    final rhoB = _computeResistivity(
      arrayType,
      spacing.spacingFeet,
      latestB?.resistanceOhm,
    );
    spacingSnapshots.add(
      _SpacingSnapshot(
        resistanceA: latestA?.resistanceOhm,
        resistanceB: latestB?.resistanceOhm,
        rhoA: rhoA,
        rhoB: rhoB,
      ),
    );

    _setNumeric(
      worksheet,
      row: tableStartRow + 3,
      column: column,
      value: latestA?.resistanceOhm,
    );
    _setNumeric(
      worksheet,
      row: tableStartRow + 3,
      column: column + 1,
      value: rhoA,
    );
    _setNumeric(
      worksheet,
      row: tableStartRow + 4,
      column: column,
      value: latestB?.resistanceOhm,
    );
    _setNumeric(
      worksheet,
      row: tableStartRow + 4,
      column: column + 1,
      value: rhoB,
    );

    column += 2;
  }

  if (spacingSnapshots.isEmpty) {
    return;
  }

  column -= 2;
  final directionValues = worksheet.getRangeByIndex(
      tableStartRow + 3, 2, tableStartRow + 4, column + 1);
  _applyRowValueStyle(directionValues);
  final averageValues = worksheet.getRangeByIndex(
      tableStartRow + 5, 2, tableStartRow + 5, column + 1);
  _applyRowValueStyle(averageValues, bold: true);

  column = 2;
  for (final snapshot in spacingSnapshots) {
    final avgResistance =
        _average([snapshot.resistanceA, snapshot.resistanceB]);
    final avgRho = _average([snapshot.rhoA, snapshot.rhoB]);
    _setNumeric(
      worksheet,
      row: tableStartRow + 5,
      column: column,
      value: avgResistance,
    );
    _setNumeric(
      worksheet,
      row: tableStartRow + 5,
      column: column + 1,
      value: avgRho,
    );
    column += 2;
  }

  final tableRange = worksheet.getRangeByIndex(
    tableStartRow,
    1,
    tableStartRow + 5,
    column - 1,
  );
  tableRange.cellStyle.borders.all
    ..lineStyle = LineStyle.thin
    ..color = '#B7C9E2';

  worksheet
      .getRangeByIndex(tableStartRow + 3, 1, tableStartRow + 3, column - 1)
      .cellStyle
      .backColor = '#F4F8FF';
  worksheet
      .getRangeByIndex(tableStartRow + 5, 1, tableStartRow + 5, column - 1)
      .cellStyle
      .backColor = '#E9F1FD';

  worksheet.getRangeByIndex(tableStartRow + 3, 2).freezePanes();

  worksheet
      .getRangeByIndex(tableStartRow + 3, 2, tableStartRow + 5, column - 1)
      .numberFormat = '0.00';
  worksheet
      .getRangeByIndex(tableStartRow + 3, 2, tableStartRow + 5, column - 1)
      .cellStyle
      .hAlign = HAlignType.right;
}

void _setNumeric(
  Worksheet worksheet, {
  required int row,
  required int column,
  double? value,
}) {
  final range = worksheet.getRangeByIndex(row, column);
  if (value == null || value.isNaN || !value.isFinite) {
    range.setText('');
  } else {
    range
      ..setNumber(value)
      ..numberFormat = value.abs() >= 1000 ? '0' : '0.00';
  }
}

String _buildFileName(ProjectRecord project, SiteRecord site) {
  final projectSlug = _slug(project.projectName);
  final siteSlug =
      _slug(site.displayName.isNotEmpty ? site.displayName : site.siteId);
  return '${projectSlug}_${siteSlug}_ER_Table.xlsx';
}

String _slug(String input) {
  final sanitized = input.trim().replaceAll(RegExp(r'[^A-Za-z0-9-_]'), '_');
  return sanitized.isEmpty ? 'project' : sanitized;
}

String _arrayTypeLabel(ArrayType type) {
  switch (type) {
    case ArrayType.wenner:
      return 'Wenner';
    case ArrayType.schlumberger:
      return 'Schlumberger';
    case ArrayType.dipoleDipole:
      return 'Dipole-Dipole';
    case ArrayType.poleDipole:
      return 'Pole-Dipole';
    case ArrayType.custom:
      return 'Custom';
  }
}

double? _average(List<double?> values) {
  final filtered =
      values.whereType<double>().where((value) => value.isFinite).toList();
  if (filtered.isEmpty) {
    return null;
  }
  final sum = filtered.reduce((a, b) => a + b);
  return sum / filtered.length;
}

double? _computeResistivity(
  ArrayType arrayType,
  double spacingFeet,
  double? resistance,
) {
  if (resistance == null) {
    return null;
  }
  switch (arrayType) {
    case ArrayType.wenner:
      return calc.rhoAWenner(spacingFeet, resistance);
    case ArrayType.schlumberger:
      final spacingMeters = calc.feetToMeters(spacingFeet);
      if (spacingMeters == 0) {
        return null;
      }
      final aMeters = spacingMeters / 6;
      if (aMeters == 0) {
        return null;
      }
      final lMeters = spacingMeters;
      final factor = math.pi *
          (((lMeters * lMeters) - (aMeters * aMeters)) / (2 * aMeters));
      return factor * resistance;
    default:
      return calc.rhoAWenner(spacingFeet, resistance);
  }
}

String _titleCase(String input) {
  if (input.isEmpty) return input;
  final sanitized = input.replaceAll('_', ' ');
  return sanitized.split(' ').map((word) {
    if (word.isEmpty) return word;
    return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
  }).join(' ');
}

void _applyHeaderStyle(Range range) {
  final style = range.cellStyle;
  style.backColor = '#1F4E78';
  style.fontColor = '#FFFFFF';
  style.bold = true;
  style.hAlign = HAlignType.center;
  style.vAlign = VAlignType.center;
}

void _applySubHeaderStyle(Range range) {
  final style = range.cellStyle;
  style.backColor = '#E1EAF7';
  style.bold = true;
  style.hAlign = HAlignType.center;
  style.vAlign = VAlignType.center;
  style.wrapText = true;
}

void _applyRowLabelStyle(Range range, {bool bold = false}) {
  final style = range.cellStyle;
  style.bold = bold;
  style.hAlign = HAlignType.left;
  style.vAlign = VAlignType.center;
}

void _applyRowValueStyle(Range range, {bool bold = false}) {
  final style = range.cellStyle;
  style.bold = bold;
  style.hAlign = HAlignType.right;
  style.vAlign = VAlignType.center;
}

void _applyMetaLabelStyle(Range range) {
  final style = range.cellStyle;
  style.bold = true;
  style.hAlign = HAlignType.left;
  style.vAlign = VAlignType.center;
}

void _applyMetaValueStyle(Range range) {
  final style = range.cellStyle;
  style.hAlign = HAlignType.left;
  style.vAlign = VAlignType.center;
}

Uint8List _applyHeaderFooter(Uint8List input) {
  final archive = ZipDecoder().decodeBytes(input);
  final updated = Archive();
  for (final file in archive) {
    if (file.isFile && file.name == 'xl/worksheets/sheet1.xml') {
      final xml = utf8.decode(file.content);
      if (xml.contains('<headerFooter')) {
        updated.addFile(file);
      } else {
        const headerFooter =
            '<headerFooter><oddHeader>&amp;LTHG Geophysics&amp;CResiCheck Field Export</oddHeader><oddFooter>&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter>';
        final modified =
            xml.replaceFirst('</worksheet>', '$headerFooter</worksheet>');
        updated.addFile(
          ArchiveFile.noCompress(
            file.name,
            utf8.encode(modified).length,
            utf8.encode(modified),
          ),
        );
      }
    } else {
      updated.addFile(file);
    }
  }
  final output = ZipEncoder().encode(updated) ?? const <int>[];
  return Uint8List.fromList(output);
}

class _SpacingSnapshot {
  _SpacingSnapshot({
    this.resistanceA,
    this.resistanceB,
    this.rhoA,
    this.rhoB,
  });

  final double? resistanceA;
  final double? resistanceB;
  final double? rhoA;
  final double? rhoB;
}
