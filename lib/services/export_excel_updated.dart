import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:collection/collection.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/direction_reading.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../utils/units.dart' as units;

class UpdatedExcelWriter {
  UpdatedExcelWriter({
    required this.project,
    required Iterable<SiteRecord> sites,
    DateTime? generatedAt,
    this.operatorName,
    this.includeGps = false,
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
  final bool includeGps;

  Uint8List build() {
    final workbook = Excel.createExcel();
    const defaultSheet = 'Sheet1';
    final summary = workbook[defaultSheet];
    final data = workbook[_dataSheetName];
    final notes = workbook[_notesSheetName];

    _clearSheet(summary);
    _clearSheet(data);
    _clearSheet(notes);

    final dataRowCount = _buildDataSheet(data);
    _buildSummarySheet(summary);
    _buildNotesSheet(notes, dataRowCount);

    final encoded = workbook.encode() ?? const <int>[];
    final bytes = Uint8List.fromList(encoded);
    return _applySheetDecorations(bytes);
  }

  void _buildSummarySheet(Sheet summary) {
    summary.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
    );

    final banner =
        summary.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0));
    banner.value =
        TextCellValue('THG Geophysics — Apparent Resistivity Summary');
    banner.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    const labels = [
      'Project',
      'Site',
      'Date',
      'Operator',
      'Array Type',
      'Units',
      'Latitude',
      'Longitude',
    ];

    for (var i = 0; i < labels.length; i++) {
      final rowIndex = 2 + i;
      final labelCell = summary
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
      labelCell.value = TextCellValue(labels[i]);
      labelCell.cellStyle = _labelStyle;
    }

    final siteLabel = sites.length == 1 ? sites.first.displayName : 'All Sites';
    _setText(summary, 1, 2, project.projectName, style: _valueStyle);
    _setText(summary, 1, 3, siteLabel, style: _valueStyle);
    _setText(summary, 1, 4, DateFormat('yyyy-MM-dd').format(generatedAt),
        style: _valueStyle);
    _setText(summary, 1, 5, (operatorName ?? '').trim(), style: _valueStyle);
    _setText(summary, 1, 6, _arrayTypeLabel(project.arrayType),
        style: _valueStyle);
    _setText(summary, 1, 7, _unitLabel, style: _valueStyle);

    if (includeGps) {
      final primaryLocation = sites.length == 1 ? sites.first.location : null;
      if (primaryLocation?.latitude != null) {
        _setNumber(summary, 1, 8, primaryLocation!.latitude);
      }
      if (primaryLocation?.longitude != null) {
        _setNumber(summary, 1, 9, primaryLocation!.longitude);
      }
    }

    _setText(summary, 0, 11, 'σρ good ≤', style: _labelStyle);
    _setNumber(summary, 1, 11, _sigmaGreenThreshold);
    _setText(summary, 0, 12, 'σρ caution <', style: _labelStyle);
    _setNumber(summary, 1, 12, _sigmaAmberThreshold);

    summary.setColumnWidth(0, 18);
    summary.setColumnWidth(1, 36);
  }

  int _buildDataSheet(Sheet data) {
    for (var column = 0; column < _dataHeaders.length; column++) {
      final cell = data
          .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0));
      cell.value = TextCellValue(_dataHeaders[column]);
      cell.cellStyle = _headerStyle;
      data.setColumnWidth(column, _dataColumnWidths[column]);
    }

    final rows = _buildRows();
    var rowIndex = 1;
    var sequence = 1;

    for (final row in rows) {
      final sequenceCell = data
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
      sequenceCell.value = IntCellValue(sequence);
      sequenceCell.cellStyle = _numberStyle;

      if (row.aMeters != null) {
        final cell = data.cell(
          CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex),
        );
        cell.value = DoubleCellValue(row.aMeters!);
        cell.cellStyle = _numberStyle;
      }
      if (row.aFeet != null) {
        final cell = data.cell(
          CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex),
        );
        cell.value = DoubleCellValue(row.aFeet!);
        cell.cellStyle = _numberStyle;
      }
      if (row.lMeters != null) {
        final cell = data.cell(
          CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex),
        );
        cell.value = DoubleCellValue(row.lMeters!);
        cell.cellStyle = _numberStyle;
      }
      if (row.resistanceOhm != null) {
        final cell = data.cell(
          CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex),
        );
        cell.value = DoubleCellValue(row.resistanceOhm!);
        cell.cellStyle = _numberStyle;
      }

      final rhoCell = data
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex));
      rhoCell.setFormula(_rhoFormula(rowIndex + 1));
      rhoCell.cellStyle = _numberStyle;

      final sigmaFormula = _sigmaFormula(rowIndex + 1, row.sdPercent);
      final sigmaCell = data
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex));
      if (sigmaFormula != null) {
        sigmaCell.setFormula(sigmaFormula);
        sigmaCell.cellStyle = _numberStyle.copyWith(
          backgroundColorHexVal:
              ExcelColor.fromHexString(_sigmaColor(row.sdPercent ?? 0)),
        );
      } else {
        sigmaCell.value = null;
        sigmaCell.cellStyle = _numberStyle;
      }

      _setText(data, 9, rowIndex, row.directionCode, style: _textCenterStyle);
      _setText(data, 10, rowIndex, row.timestampIso ?? '', style: _textStyle);
      _setText(data, 11, rowIndex, row.note ?? '', style: _wrappedTextStyle);
      _setText(data, 12, rowIndex, row.warning, style: _wrappedTextStyle);

      rowIndex += 1;
      sequence += 1;
    }

    return rows.length;
  }

  void _buildNotesSheet(Sheet notes, int dataRowCount) {
    _setText(notes, 0, 0, 'Notes',
        style: _headerStyle.copyWith(fontSizeVal: 14));
    _setText(
      notes,
      0,
      1,
      '• Summary rows 3–10 store metadata and QA thresholds (σρ <= ${_sigmaGreenThreshold.toStringAsFixed(2)} green, < ${_sigmaAmberThreshold.toStringAsFixed(2)} amber).\n'
      '• Data sheet headers remain in row 1; long notes and warnings wrap automatically.\n'
      '• Direction codes use ns / we / other.\n'
      '• ρₐ and σρ formulas remain visible for transparency.\n'
      '• Export generated ${DateFormat('yyyy-MM-dd').format(generatedAt)} with $dataRowCount data rows.',
      style: _wrappedTextStyle,
    );
    notes.setColumnWidth(0, 80);
  }

  List<_ExcelDataRow> _buildRows() {
    final entries = <_ExcelDataRow>[];
    for (final site in sites) {
      for (final spacing in site.spacings) {
        entries.add(
          _ExcelDataRow.from(
            site: site,
            spacing: spacing,
            history: spacing.orientationA,
            arrayType: project.arrayType,
          ),
        );
        entries.add(
          _ExcelDataRow.from(
            site: site,
            spacing: spacing,
            history: spacing.orientationB,
            arrayType: project.arrayType,
          ),
        );
      }
    }
    return entries.where((row) => row.isRenderable).toList();
  }

  Uint8List _applySheetDecorations(Uint8List input) {
    final archive = ZipDecoder().decodeBytes(input);
    final updated = Archive();
    for (final file in archive) {
      if (file.name == 'xl/worksheets/$_dataSheetXml') {
        final content = utf8.decode(file.content);
        final modified = _decorateDataSheetXml(content);
        updated.addFile(
            ArchiveFile(file.name, modified.length, utf8.encode(modified))
              ..isFile = true);
      } else if (file.name == 'xl/workbook.xml') {
        final content = utf8.decode(file.content);
        var workbookXml =
            content.replaceFirst('name="Sheet1"', 'name="$_summarySheetName"');
        if (!workbookXml.contains('_xlnm.Print_Titles')) {
          if (workbookXml.contains('<definedNames>')) {
            workbookXml = workbookXml.replaceFirst(
              '<definedNames>',
              '<definedNames>$_printTitlesDefinedNameFragment',
            );
          } else {
            workbookXml = workbookXml.replaceFirst(
              '</workbook>',
              '<definedNames>$_printTitlesDefinedNameFragment</definedNames></workbook>',
            );
          }
        }
        updated.addFile(
            ArchiveFile(file.name, workbookXml.length, utf8.encode(workbookXml))
              ..isFile = true);
      } else {
        updated.addFile(file);
      }
    }
    final output = ZipEncoder().encode(updated) ?? const <int>[];
    return Uint8List.fromList(output);
  }

  String _decorateDataSheetXml(String xml) {
    var processed = xml;
    processed = processed.replaceFirst(
      '<sheetView workbookViewId="0"/>',
      '<sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView>',
    );

    if (!processed.contains('<headerFooter')) {
      processed = processed.replaceFirst(
        '</worksheet>',
        '<headerFooter><oddHeader>&amp;LTHG Geophysics&amp;CResiCheck Field Export</oddHeader><oddFooter>&amp;RPage &amp;P of &amp;N</oddFooter></headerFooter></worksheet>',
      );
    }

    if (!processed.contains('<pageSetup')) {
      if (!processed.contains('</pageMargins>')) {
        processed = processed.replaceFirst(
          '<sheetData>',
          '<sheetData>',
        );
      }
      processed = processed.replaceFirst(
        '</pageMargins>',
        '</pageMargins><pageSetup orientation="portrait" fitToWidth="1" fitToHeight="0" usePrinterDefaults="0" paperSize="9"/>',
      );
    }

    return processed;
  }

  void _setText(
    Sheet sheet,
    int column,
    int row,
    String value, {
    CellStyle? style,
  }) {
    final cell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row));
    cell.value = TextCellValue(value);
    if (style != null) {
      cell.cellStyle = style;
    }
  }

  void _setNumber(Sheet sheet, int column, int row, num value) {
    final cell = sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: row));
    final cellValue =
        value is int ? IntCellValue(value) : DoubleCellValue(value.toDouble());
    cell.value = cellValue;
    cell.cellStyle = _numberStyle;
  }

  void _clearSheet(Sheet sheet) {
    for (var row = sheet.maxRows - 1; row >= 0; row--) {
      sheet.removeRow(row);
    }
  }

  String _rhoFormula(int excelRow) {
    return '=IF(LOWER(Summary!B7)="wenner",'
        'IF(OR(B$excelRow="",E$excelRow=""),"",2*PI()*B$excelRow*E$excelRow),'
        'IF(LOWER(Summary!B7)="schlumberger",'
        'IF(OR(D$excelRow="",B$excelRow="",E$excelRow=""),"",PI()*(((D$excelRow^2)-(B$excelRow^2))/(2*B$excelRow))*E$excelRow),'
        '""))';
  }

  String? _sigmaFormula(int excelRow, double? sdPercent) {
    if (sdPercent == null) {
      return null;
    }
    final percent = sdPercent.toStringAsFixed(3);
    return '=IF(H$excelRow="","",H$excelRow*$percent/100)';
  }

  String _sigmaColor(double sigmaPercent) {
    if (sigmaPercent <= _sigmaGreenThreshold * 100) {
      return _sigmaGreenHex;
    }
    if (sigmaPercent <= _sigmaAmberThreshold * 100) {
      return _sigmaAmberHex;
    }
    return _sigmaRedHex;
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
  static const _sigmaGreenThreshold = 0.03;
  static const _sigmaAmberThreshold = 0.10;
  static const _sigmaGreenHex = 'FFC6EFCE';
  static const _sigmaAmberHex = 'FFFFEB9C';
  static const _sigmaRedHex = 'FFF4C7C3';
  static const _unitLabel = 'ft / Ω·m';
  static const _dataSheetXml = 'sheet2.xml';
  static const _printTitlesDefinedNameFragment =
      '<definedName name="_xlnm.Print_Titles" localSheetId="1">Data!\$1:\$1</definedName>';

  static const _dataHeaders = <String>[
    'Row',
    'a_m',
    'a_ft',
    'L_m (Schlumb)',
    'R_ohm',
    'V_V',
    'I_A',
    'rho_app_ohm_m',
    'sigma_rhoa_ohm_m',
    'direction',
    'timestamp_iso',
    'notes',
    'warnings',
  ];

  static const _dataColumnWidths = <double>[
    6,
    10,
    10,
    18,
    12,
    10,
    10,
    18,
    20,
    12,
    26,
    40,
    28,
  ];

  static final _headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('FFFFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('FF1F4E78'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  static final _labelStyle = CellStyle(
    bold: true,
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
  );

  static final _valueStyle = CellStyle(
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
  );

  static final _numberStyle = CellStyle(
    horizontalAlign: HorizontalAlign.Right,
    verticalAlign: VerticalAlign.Center,
  );

  static final _textCenterStyle = CellStyle(
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  static final _textStyle = CellStyle(
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
  );

  static final _wrappedTextStyle = CellStyle(
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
    textWrapping: TextWrapping.WrapText,
  );
}

class _ExcelDataRow {
  _ExcelDataRow({
    required this.directionLabel,
    required this.aFeet,
    required this.aMeters,
    required this.lMeters,
    required this.resistanceOhm,
    required this.sdPercent,
    required this.timestampIso,
    required this.note,
    required this.isBad,
  });

  factory _ExcelDataRow.from({
    required SiteRecord site,
    required SpacingRecord spacing,
    required DirectionReadingHistory history,
    required ArrayType arrayType,
  }) {
    final sample = history.latest;
    final spacingFeet = spacing.spacingFeet;
    final spacingMeters = units.feetToMeters(spacingFeet);
    double? lMeters;
    double aMetersValue;
    if (arrayType == ArrayType.schlumberger) {
      aMetersValue = spacingMeters / 6;
      lMeters = spacingMeters;
    } else {
      aMetersValue = spacingMeters;
    }

    return _ExcelDataRow(
      directionLabel: history.label,
      aFeet: arrayType == ArrayType.schlumberger
          ? units.metersToFeet(aMetersValue)
          : spacingFeet,
      aMeters: aMetersValue,
      lMeters: lMeters,
      resistanceOhm: sample?.resistanceOhm,
      sdPercent: sample?.standardDeviationPercent,
      timestampIso: sample?.timestamp.toUtc().toIso8601String(),
      note: sample?.note.isEmpty ?? true ? null : sample?.note,
      isBad: sample?.isBad ?? false,
    );
  }

  final String directionLabel;
  final double? aFeet;
  final double? aMeters;
  final double? lMeters;
  final double? resistanceOhm;
  final double? sdPercent;
  final String? timestampIso;
  final String? note;
  final bool isBad;

  bool get isRenderable => resistanceOhm != null || sdPercent != null;

  String get directionCode {
    final normalized = directionLabel.toLowerCase();
    if (normalized.contains('n') && normalized.contains('s')) {
      return 'ns';
    }
    if (normalized.contains('w') && normalized.contains('e')) {
      return 'we';
    }
    return 'other';
  }

  String get warning => isBad ? 'bad_reading' : '';
}

Future<File> writeUpdatedTable({
  required ProjectRecord project,
  required List<SiteRecord> sites,
  required Directory outDir,
  required String fileName,
  bool includeGps = false,
  String? operatorName,
  DateTime? generatedAt,
}) async {
  final writer = UpdatedExcelWriter(
    project: project,
    sites: sites,
    generatedAt: generatedAt,
    operatorName: operatorName,
    includeGps: includeGps,
  );
  final bytes = writer.build();
  final target = File(p.join(outDir.path, fileName));
  await target.writeAsBytes(bytes, flush: true);
  return target;
}
