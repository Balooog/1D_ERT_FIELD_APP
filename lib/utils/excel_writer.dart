import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/direction_reading.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../utils/units.dart' as units;

class ThgExcelWriter {
  ThgExcelWriter({
    required this.project,
    required Iterable<SiteRecord> sites,
    DateTime? generatedAt,
    this.operatorName,
  })  : generatedAt = generatedAt ?? DateTime.now(),
        sites = List<SiteRecord>.unmodifiable(
          (sites.toList()
                ..sort((a, b) => _compareStrings(
                      a.displayName,
                      b.displayName,
                      fallbackA: a.siteId,
                      fallbackB: b.siteId,
                    )))
              .toList(),
        );

  final ProjectRecord project;
  final List<SiteRecord> sites;
  final DateTime generatedAt;
  final String? operatorName;

  Uint8List build() {
    final workbook = Excel.createExcel();
    final summary = workbook[_summarySheetName];
    final data = workbook[_dataSheetName];
    final notes = workbook[_notesSheetName];

    _buildSummarySheet(summary);
    _buildDataSheet(data);
    _buildNotesSheet(notes);

    final encoded = workbook.save() ?? const <int>[];
    return Uint8List.fromList(encoded);
  }

  void _buildSummarySheet(Sheet sheet) {
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: _headerFillColor,
      horizontalAlign: HorizontalAlign.Center,
    );
    const header = [
      'Project',
      'Site',
      'Date',
      'Operator',
      'Array Type',
      'Units',
      'Latitude',
      'Longitude',
    ];
    _writeRow(sheet, 0, header, style: headerStyle);

    final dateLabel = DateFormat('yyyy-MM-dd').format(generatedAt.toLocal());
    final arrayLabel = _arrayTypeLabel(project.arrayType);
    const unitLabel = 'ft / Ω·m';

    for (var index = 0; index < sites.length; index++) {
      final site = sites[index];
      final rowIndex = index + 1;
      final row = [
        project.projectName,
        site.displayName,
        dateLabel,
        (operatorName ?? '').trim(),
        arrayLabel,
        unitLabel,
        if (site.location?.latitude != null) site.location!.latitude else null,
        if (site.location?.longitude != null)
          site.location!.longitude
        else
          null,
      ];
      _writeRow(sheet, rowIndex, row);
    }

    sheet.setColWidth(0, 26);
    sheet.setColWidth(1, 20);
    sheet.setColWidth(2, 14);
    sheet.setColWidth(3, 18);
    sheet.setColWidth(4, 14);
    sheet.setColWidth(5, 14);
    sheet.setColWidth(6, 14);
    sheet.setColWidth(7, 14);
  }

  void _buildDataSheet(Sheet sheet) {
    final headerStyle = CellStyle(
      bold: true,
      backgroundColorHex: _headerFillColor,
    );
    const headers = [
      'Project',
      'Site',
      'Direction',
      'a_ft',
      'a_m',
      'MN/2_ft',
      'MN/2_m',
      'R_ohm',
      'sd_pct',
      'ρa_Ω·m',
      'σρ',
      'σρ_pct',
      'Note',
      'Is Bad',
    ];
    _writeRow(sheet, 0, headers, style: headerStyle);

    final rows = _buildDataRows();
    for (var i = 0; i < rows.length; i++) {
      final rowIndex = i + 1;
      final row = rows[i];
      _writeCell(sheet, rowIndex, _colProject, project.projectName);
      _writeCell(sheet, rowIndex, _colSite, row.siteName);
      _writeCell(sheet, rowIndex, _colDirection, row.directionLabel);
      _writeCell(sheet, rowIndex, _colSpacingFt, row.spacingFeet);
      _writeCell(sheet, rowIndex, _colSpacingM, row.spacingMeters);
      if (row.mnOver2Feet != null) {
        _writeCell(sheet, rowIndex, _colMnFt, row.mnOver2Feet);
      }
      if (row.mnOver2Meters != null) {
        _writeCell(sheet, rowIndex, _colMnM, row.mnOver2Meters);
      }
      if (row.resistanceOhm != null) {
        _writeCell(sheet, rowIndex, _colResistance, row.resistanceOhm);
      }
      if (row.sdPercent != null) {
        _writeCell(sheet, rowIndex, _colSdPct, row.sdPercent);
      }
      if (row.note != null && row.note!.isNotEmpty) {
        _writeCell(sheet, rowIndex, _colNote, row.note);
      }
      _writeCell(sheet, rowIndex, _colIsBad, row.isBad);

      final rhoFormula = _rhoFormula(rowIndex);
      sheet
          .cell(CellIndex.indexByColumnRow(
            columnIndex: _colRho,
            rowIndex: rowIndex,
          ))
          .setFormula(rhoFormula);

      final sigmaFormula = _sigmaFormula(rowIndex);
      sheet
          .cell(CellIndex.indexByColumnRow(
            columnIndex: _colSigma,
            rowIndex: rowIndex,
          ))
          .setFormula(sigmaFormula);

      sheet
          .cell(CellIndex.indexByColumnRow(
            columnIndex: _colSigmaPct,
            rowIndex: rowIndex,
          ))
          .setFormula(_sigmaPercentFormula(rowIndex));
    }

    sheet.setColWidth(_colProject, 22);
    sheet.setColWidth(_colSite, 18);
    sheet.setColWidth(_colDirection, 16);
    sheet.setColWidth(_colSpacingFt, 12);
    sheet.setColWidth(_colSpacingM, 12);
    sheet.setColWidth(_colMnFt, 12);
    sheet.setColWidth(_colMnM, 12);
    sheet.setColWidth(_colResistance, 12);
    sheet.setColWidth(_colSdPct, 10);
    sheet.setColWidth(_colRho, 14);
    sheet.setColWidth(_colSigma, 12);
    sheet.setColWidth(_colSigmaPct, 12);
    sheet.setColWidth(_colNote, 32);
    sheet.setColWidth(_colIsBad, 10);
  }

  void _buildNotesSheet(Sheet sheet) {
    const notes = [
      'ResiCheck Excel Export — THG baseline layout',
      'Summary tab lists project metadata per site for quick review.',
      'Data tab contains measurement values. Edit spacing or resistance and formulas recalculate ρa and σρ.',
      'Feel free to adjust column widths, fonts, or colors—formulas reference headers so layout tweaks are safe.',
    ];
    for (var i = 0; i < notes.length; i++) {
      _writeCell(sheet, i, 0, notes[i]);
    }
    sheet.setColWidth(0, 72);
  }

  List<_ExcelDataRow> _buildDataRows() {
    final rows = <_ExcelDataRow>[];
    for (final site in sites) {
      final sortedSpacings = [...site.spacings]
        ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
      for (final spacing in sortedSpacings) {
        rows.add(_ExcelDataRow.from(
          siteName: site.displayName,
          spacing: spacing,
          history: spacing.orientationA,
          arrayType: project.arrayType,
        ));
        rows.add(_ExcelDataRow.from(
          siteName: site.displayName,
          spacing: spacing,
          history: spacing.orientationB,
          arrayType: project.arrayType,
        ));
      }
    }
    return rows;
  }

  void _writeRow(
    Sheet sheet,
    int rowIndex,
    List<dynamic> values, {
    CellStyle? style,
  }) {
    for (var col = 0; col < values.length; col++) {
      _writeCell(sheet, rowIndex, col, values[col], style: style);
    }
  }

  void _writeCell(
    Sheet sheet,
    int rowIndex,
    int columnIndex,
    dynamic value, {
    CellStyle? style,
  }) {
    if (value == null) {
      return;
    }
    dynamic resolved = value;
    if (value is bool) {
      resolved = value ? 'TRUE' : 'FALSE';
    }
    final cell = sheet.cell(
      CellIndex.indexByColumnRow(
        columnIndex: columnIndex,
        rowIndex: rowIndex,
      ),
    );
    cell.value = resolved;
    if (style != null) {
      cell.cellStyle = style;
    }
  }

  String _rhoFormula(int rowIndex) {
    final resistanceRef = _cellRef(_colResistance, rowIndex);
    final spacingMetersRef = _cellRef(_colSpacingM, rowIndex);
    switch (project.arrayType) {
      case ArrayType.wenner:
        return '=IF($resistanceRef="","",2*PI()*$spacingMetersRef*$resistanceRef)';
      case ArrayType.schlumberger:
        final mnMetersRef = _cellRef(_colMnM, rowIndex);
        return '=IF(OR($resistanceRef="", $mnMetersRef=""),"",PI()*((($spacingMetersRef)^2)-(($mnMetersRef)^2))/($mnMetersRef*2)*$resistanceRef)';
      default:
        return '=IF($resistanceRef="","",2*PI()*$spacingMetersRef*$resistanceRef)';
    }
  }

  String _sigmaFormula(int rowIndex) {
    final rhoRef = _cellRef(_colRho, rowIndex);
    final sdRef = _cellRef(_colSdPct, rowIndex);
    return '=IF(OR($rhoRef="", $sdRef=""),"", $rhoRef*$sdRef/100)';
  }

  String _sigmaPercentFormula(int rowIndex) {
    final rhoRef = _cellRef(_colRho, rowIndex);
    final sdRef = _cellRef(_colSdPct, rowIndex);
    return '=IF($rhoRef="", "", $sdRef)';
  }

  String _cellRef(int columnIndex, int rowIndex) {
    final columnLabel = _columnLetter(columnIndex);
    return '$columnLabel${rowIndex + 1}';
  }

  static String _columnLetter(int index) {
    var current = index;
    final buffer = StringBuffer();
    while (current >= 0) {
      final remainder = current % 26;
      buffer.writeCharCode('A'.codeUnitAt(0) + remainder);
      current = (current ~/ 26) - 1;
    }
    return buffer.toString().split('').reversed.join();
  }

  static int _compareStrings(
    String a,
    String b, {
    required String fallbackA,
    required String fallbackB,
  }) {
    final primary = compareAsciiLowerCase(a, b);
    if (primary != 0) {
      return primary;
    }
    return compareAsciiLowerCase(fallbackA, fallbackB);
  }

  static String _arrayTypeLabel(ArrayType type) {
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

  static const _summarySheetName = 'Summary';
  static const _dataSheetName = 'Data';
  static const _notesSheetName = 'Notes';
  static const _headerFillColor = 'FFE9F1FF';

  static const _colProject = 0;
  static const _colSite = 1;
  static const _colDirection = 2;
  static const _colSpacingFt = 3;
  static const _colSpacingM = 4;
  static const _colMnFt = 5;
  static const _colMnM = 6;
  static const _colResistance = 7;
  static const _colSdPct = 8;
  static const _colRho = 9;
  static const _colSigma = 10;
  static const _colSigmaPct = 11;
  static const _colNote = 12;
  static const _colIsBad = 13;
}

class _ExcelDataRow {
  _ExcelDataRow({
    required this.siteName,
    required this.directionLabel,
    required this.spacingFeet,
    required this.spacingMeters,
    required this.mnOver2Feet,
    required this.mnOver2Meters,
    required this.resistanceOhm,
    required this.sdPercent,
    required this.note,
    required this.isBad,
  });

  factory _ExcelDataRow.from({
    required String siteName,
    required SpacingRecord spacing,
    required DirectionReadingHistory history,
    required ArrayType arrayType,
  }) {
    final sample = history.latest;
    final spacingFeet = spacing.spacingFeet;
    final spacingMeters = units.feetToMeters(spacingFeet);
    double? mnOver2Meters;
    double? mnOver2Feet;
    if (arrayType == ArrayType.schlumberger) {
      mnOver2Meters = spacingMeters / 6;
      mnOver2Feet = units.metersToFeet(mnOver2Meters);
    }
    return _ExcelDataRow(
      siteName: siteName,
      directionLabel: history.label,
      spacingFeet: spacingFeet,
      spacingMeters: spacingMeters,
      mnOver2Feet: mnOver2Feet,
      mnOver2Meters: mnOver2Meters,
      resistanceOhm: sample?.resistanceOhm,
      sdPercent: sample?.standardDeviationPercent,
      note: sample?.note,
      isBad: sample?.isBad ?? false,
    );
  }

  final String siteName;
  final String directionLabel;
  final double spacingFeet;
  final double spacingMeters;
  final double? mnOver2Feet;
  final double? mnOver2Meters;
  final double? resistanceOhm;
  final double? sdPercent;
  final String? note;
  final bool isBad;
}
