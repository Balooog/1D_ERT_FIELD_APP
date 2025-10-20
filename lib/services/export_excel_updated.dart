import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_xlsio/xlsio.dart';

import '../models/direction_reading.dart';
import '../models/enums.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../models/calc.dart' as calc;
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
    final workbook = Workbook();
    while (workbook.worksheets.count < 3) {
      workbook.worksheets.add();
    }
    final siteTables = _buildSiteTables();
    final summary = workbook.worksheets[0]..name = _summarySheetName;
    final data = workbook.worksheets[1]..name = _dataSheetName;
    final notes = workbook.worksheets[2]..name = _notesSheetName;

    _buildSummarySheet(summary);
    final dataRowCount = _buildDataSheet(data, siteTables);
    _buildNotesSheet(notes, dataRowCount, siteTables.length);
    _configureDataSheetLayout(data);

    Worksheet? spacingSummarySheet;
    if (sites.isNotEmpty) {
      spacingSummarySheet = _buildSpacingSummarySheet(workbook);
    }
    if (siteTables.isNotEmpty && sites.length == 1) {
      final startTableIndex = spacingSummarySheet == null ? 1 : 2;
      _buildTableSheets(
        workbook,
        siteTables,
        startTableIndex: startTableIndex,
      );
    }

    final bytes = workbook.saveAsStream();
    workbook.dispose();
    return Uint8List.fromList(bytes);
  }

  void _buildSummarySheet(Worksheet summary) {
    final banner = summary.getRangeByIndex(1, 1, 1, 8);
    banner.merge();
    banner.setText('THG Geophysics — Apparent Resistivity Summary');
    final bannerStyle = banner.cellStyle;
    bannerStyle.bold = true;
    bannerStyle.fontSize = 16;
    bannerStyle.hAlign = HAlignType.center;
    bannerStyle.vAlign = VAlignType.center;

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
      final rowIndex = 3 + i;
      final labelCell = summary.getRangeByIndex(rowIndex, 1);
      labelCell.setText(labels[i]);
      _applyLabelStyle(labelCell);
    }

    final siteLabel = sites.length == 1 ? sites.first.displayName : 'All Sites';
    _setText(summary, 3, 2, project.projectName);
    _setText(summary, 4, 2, siteLabel);
    _setText(summary, 5, 2, DateFormat('yyyy-MM-dd').format(generatedAt));
    _setText(summary, 6, 2, (operatorName ?? '').trim());
    _setText(summary, 7, 2, _arrayTypeLabel(project.arrayType));
    _setText(summary, 8, 2, _unitLabel);

    if (includeGps) {
      final primaryLocation = sites.length == 1 ? sites.first.location : null;
      if (primaryLocation?.latitude != null) {
        _setNumber(summary, 9, 2, primaryLocation!.latitude);
      }
      if (primaryLocation?.longitude != null) {
        _setNumber(summary, 10, 2, primaryLocation!.longitude);
      }
    }

    _setText(summary, 12, 1, 'σρ good ≤');
    _setNumber(summary, 12, 2, _sigmaGreenThreshold);
    _setText(summary, 13, 1, 'σρ caution <');
    _setNumber(summary, 13, 2, _sigmaAmberThreshold);

    summary.setColumnWidthInPixels(1, 150);
    summary.setColumnWidthInPixels(2, 240);
    summary.setRowHeightInPixels(1, 32);
  }

  int _buildDataSheet(Worksheet data, List<_SiteTableData> siteTables) {
    for (var column = 0; column < _dataHeaders.length; column++) {
      final header = data.getRangeByIndex(1, column + 1);
      header.setText(_dataHeaders[column]);
      _applyHeaderStyle(header);
      data.setColumnWidthInPixels(column + 1, _dataColumnWidths[column]);
    }

    final rows = <_DirectionTableData>[
      for (final siteEntry in siteTables)
        for (final spacingEntry in siteEntry.spacings)
          ...spacingEntry.directions,
    ];
    var rowIndex = 2;
    var sequence = 1;

    for (final direction in rows) {
      final row = direction.row;
      direction.dataSheetRow = rowIndex;
      final sequenceCell = data.getRangeByIndex(rowIndex, 1);
      sequenceCell.setNumber(sequence.toDouble());
      sequenceCell.numberFormat = '0';
      _applyNumberStyle(sequenceCell);

      _setOptionalNumber(data, rowIndex, 2, row.aMeters);
      _setOptionalNumber(data, rowIndex, 3, row.aFeet);
      _setOptionalNumber(data, rowIndex, 4, row.lMeters);
      _setOptionalNumber(data, rowIndex, 5, row.resistanceOhm);

      final rhoCell = data.getRangeByIndex(rowIndex, 8);
      rhoCell.setFormula(_rhoFormula(rowIndex));
      _applyNumberStyle(rhoCell);

      final sigmaCell = data.getRangeByIndex(rowIndex, 9);
      final sigmaFormula = _sigmaFormula(rowIndex, row.sdPercent);
      if (sigmaFormula != null) {
        sigmaCell.setFormula(sigmaFormula);
        _applyNumberStyle(sigmaCell);
        sigmaCell.cellStyle.backColor = _sigmaColor(row.sdPercent ?? 0);
      } else {
        sigmaCell.setText('');
        _applyNumberStyle(sigmaCell);
      }

      _setText(data, rowIndex, 10, row.directionCode, align: HAlignType.center);
      _setText(data, rowIndex, 11, row.timestampIso ?? '');
      _setText(data, rowIndex, 12, row.note ?? '',
          wrap: true, verticalAlign: VAlignType.top);
      _setText(data, rowIndex, 13, row.warning, wrap: true);

      rowIndex += 1;
      sequence += 1;
    }

    return rows.length;
  }

  void _buildNotesSheet(
      Worksheet notes, int dataRowCount, int renderedTableCount) {
    final title = notes.getRangeByIndex(1, 1);
    title.setText('Notes');
    final titleStyle = title.cellStyle;
    titleStyle.bold = true;
    titleStyle.fontSize = 14;
    titleStyle.hAlign = HAlignType.left;
    titleStyle.vAlign = VAlignType.center;

    final body = notes.getRangeByIndex(2, 1);
    final bullets = <String>[
      'Summary rows 3–10 store metadata and QA thresholds (σρ <= ${_sigmaGreenThreshold.toStringAsFixed(2)} green, < ${_sigmaAmberThreshold.toStringAsFixed(2)} amber).',
      'Data sheet headers remain in row 1; long notes and warnings wrap automatically.',
      if (renderedTableCount > 0)
        'Table sheet${renderedTableCount == 1 ? '' : 's'} mirror the deliverable layout and reference Data sheet formulas.',
      'Direction codes use ns / we / other.',
      'ρₐ and σρ formulas remain visible for transparency.',
      'Export generated ${DateFormat('yyyy-MM-dd').format(generatedAt)} with $dataRowCount data rows.',
    ];
    body.setText(bullets.map((line) => '• $line').join('\n'));
    final bodyStyle = body.cellStyle;
    bodyStyle.hAlign = HAlignType.left;
    bodyStyle.vAlign = VAlignType.top;
    bodyStyle.wrapText = true;

    notes.setColumnWidthInPixels(1, 520);
    notes.setRowHeightInPixels(2, 120);
  }

  void _configureDataSheetLayout(Worksheet data) {
    data.getRangeByIndex(2, 1).freezePanes();
    data.pageSetup
      ..fitToPagesWide = 1
      ..fitToPagesTall = 0;
  }

  List<_SiteTableData> _buildSiteTables() {
    final tables = <_SiteTableData>[];
    for (final site in sites) {
      final sortedSpacings = [...site.spacings]
        ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
      final spacingData = <_SpacingTableData>[];
      for (final spacing in sortedSpacings) {
        final directionData = <_DirectionTableData>[];
        final first = _ExcelDataRow.from(
          site: site,
          spacing: spacing,
          history: spacing.orientationA,
          arrayType: project.arrayType,
        );
        if (first.isRenderable) {
          directionData.add(_DirectionTableData(row: first));
        }
        final second = _ExcelDataRow.from(
          site: site,
          spacing: spacing,
          history: spacing.orientationB,
          arrayType: project.arrayType,
        );
        if (second.isRenderable) {
          directionData.add(_DirectionTableData(row: second));
        }
        if (directionData.isNotEmpty) {
          spacingData.add(
            _SpacingTableData(
              spacingFeet: spacing.spacingFeet,
              directions: directionData,
            ),
          );
        }
      }
      if (spacingData.isNotEmpty) {
        tables.add(_SiteTableData(site: site, spacings: spacingData));
      }
    }
    return tables;
  }

  void _buildTableSheets(
    Workbook workbook,
    List<_SiteTableData> siteTables, {
    required int startTableIndex,
  }) {
    for (var i = 0; i < siteTables.length; i++) {
      final tableNumber = startTableIndex + i;
      final sheet = workbook.worksheets.add();
      sheet.name = _tableSheetName(siteTables[i].site.displayName, tableNumber);
      _buildSiteTableSheet(sheet, siteTables[i], tableNumber);
    }
  }

  Worksheet? _buildSpacingSummarySheet(Workbook workbook) {
    final spacingSet = <double>{};
    for (final site in sites) {
      for (final spacing in site.spacings) {
        spacingSet.add(spacing.spacingFeet);
      }
    }
    if (spacingSet.isEmpty) {
      return null;
    }
    final sheet = workbook.worksheets.add()..name = _spacingSummarySheetName();
    final spacings = spacingSet.toList()..sort();
    final notesColumnIndex = 2 + spacings.length * 2;
    final totalColumns = notesColumnIndex;
    final title = 'Table 1 - ${project.projectName} Resistivity Data';

    sheet.setColumnWidthInPixels(1, 200);
    for (var i = 0; i < spacings.length; i++) {
      final baseColumn = 2 + (i * 2);
      sheet.setColumnWidthInPixels(baseColumn, 100);
      sheet.setColumnWidthInPixels(baseColumn + 1, 120);
    }
    sheet.setColumnWidthInPixels(notesColumnIndex, 360);

    final titleRange = sheet.getRangeByIndex(1, 1, 1, totalColumns);
    titleRange.merge();
    titleRange.setText(title);
    final titleStyle = titleRange.cellStyle;
    titleStyle
      ..bold = true
      ..fontSize = 16
      ..hAlign = HAlignType.center
      ..vAlign = VAlignType.center;

    final metaRows = <List<String>>[
      ['Project ID', project.projectId],
      ['Project Name', project.projectName],
      [
        'Generated',
        DateFormat('yyyy-MM-dd').format(generatedAt),
      ],
      ['Operator', (operatorName ?? '').trim()],
      ['Array Type', _arrayTypeLabel(project.arrayType)],
      ['Units', _unitLabel],
      ['Sites Included', sites.length.toString()],
    ];

    var metaRowIndex = 3;
    for (final entry in metaRows) {
      final labelCell = sheet.getRangeByIndex(metaRowIndex, 1);
      labelCell.setText(entry[0]);
      _applyLabelStyle(labelCell);

      final valueCell =
          sheet.getRangeByIndex(metaRowIndex, 2, metaRowIndex, totalColumns);
      valueCell.merge();
      valueCell.setText(entry[1].isEmpty ? '—' : entry[1]);
      final style = valueCell.cellStyle;
      style.hAlign = HAlignType.left;
      style.vAlign = VAlignType.center;
      style.wrapText = true;
      metaRowIndex += 1;
    }

    metaRowIndex += 1; // blank spacer row

    final headerTopRow = metaRowIndex;
    final spacingHeaderRow = headerTopRow + 1;
    final valueHeaderRow = headerTopRow + 2;

    final arrayHeader = sheet.getRangeByIndex(
        headerTopRow, 2, headerTopRow, notesColumnIndex - 1);
    arrayHeader.merge();
    arrayHeader.setText('Array spacing (ft)');
    _applySummaryHeaderStyle(arrayHeader);

    final siteHeader =
        sheet.getRangeByIndex(headerTopRow, 1, valueHeaderRow, 1);
    siteHeader.merge();
    siteHeader.setText('Site');
    _applySummaryHeaderStyle(siteHeader);

    for (var i = 0; i < spacings.length; i++) {
      final baseColumn = 2 + (i * 2);
      final spacingHeader = sheet.getRangeByIndex(
          spacingHeaderRow, baseColumn, spacingHeaderRow, baseColumn + 1);
      spacingHeader.merge();
      spacingHeader
          .setText(spacings[i].toStringAsFixed(spacings[i] % 1 == 0 ? 0 : 1));
      _applySummarySubHeaderStyle(spacingHeader);

      final resistanceHeader =
          sheet.getRangeByIndex(valueHeaderRow, baseColumn);
      resistanceHeader.setText('Resistance (Ω)');
      _applySummarySubHeaderStyle(resistanceHeader);

      final rhoHeader = sheet.getRangeByIndex(valueHeaderRow, baseColumn + 1);
      rhoHeader.setText('Apparent Resistivity (Ω·m)');
      _applySummarySubHeaderStyle(rhoHeader);
    }

    final notesHeader = sheet.getRangeByIndex(
        spacingHeaderRow, notesColumnIndex, valueHeaderRow, notesColumnIndex);
    notesHeader.merge();
    notesHeader.setText('Notes');
    _applySummarySubHeaderStyle(notesHeader);

    final spacingResistanceTotals = [
      for (var i = 0; i < spacings.length; i++) <double>[],
    ];
    final spacingResistivityTotals = [
      for (var i = 0; i < spacings.length; i++) <double>[],
    ];

    var dataRow = valueHeaderRow + 1;
    for (final site in sites) {
      final label =
          site.displayName.isNotEmpty ? site.displayName : site.siteId;
      final siteCell = sheet.getRangeByIndex(dataRow, 1);
      siteCell.setText(label);
      _applySummaryDataStyle(siteCell, bold: true);

      for (var i = 0; i < spacings.length; i++) {
        final baseColumn = 2 + (i * 2);
        final spacingFeet = spacings[i];
        final record = site.spacing(spacingFeet);
        final resistanceValues = <double>[];
        if (record != null) {
          final sampleA = record.orientationA.latest;
          if (sampleA != null &&
              sampleA.resistanceOhm != null &&
              !sampleA.isBad) {
            resistanceValues.add(sampleA.resistanceOhm!);
          }
          final sampleB = record.orientationB.latest;
          if (sampleB != null &&
              sampleB.resistanceOhm != null &&
              !sampleB.isBad) {
            resistanceValues.add(sampleB.resistanceOhm!);
          }
        }

        double? averageResistance;
        if (resistanceValues.isNotEmpty) {
          final sum =
              resistanceValues.reduce((value, element) => value + element);
          averageResistance = sum / resistanceValues.length;
        }
        final averageRho = calc.averageApparentResistivity(
          spacingFeet,
          resistanceValues,
        );

        final resistanceCell = sheet.getRangeByIndex(dataRow, baseColumn);
        _setSigFigText(resistanceCell, averageResistance);
        if (averageResistance != null && averageResistance.isFinite) {
          spacingResistanceTotals[i].add(averageResistance);
        }
        _applySummaryDataStyle(resistanceCell);

        final rhoCell = sheet.getRangeByIndex(dataRow, baseColumn + 1);
        _setSigFigText(rhoCell, averageRho);
        if (averageRho != null && averageRho.isFinite) {
          spacingResistivityTotals[i].add(averageRho);
        }
        _applySummaryDataStyle(rhoCell);
      }

      final noteCell = sheet.getRangeByIndex(dataRow, notesColumnIndex);
      noteCell.setText(_buildSiteSummaryNote(site));
      final noteStyle = noteCell.cellStyle;
      noteStyle.hAlign = HAlignType.left;
      noteStyle.vAlign = VAlignType.top;
      noteStyle.wrapText = true;

      sheet.getRangeByIndex(dataRow, 1, dataRow, totalColumns).autoFitRows();
      dataRow += 1;
    }

    final averageRow = dataRow;
    final averageLabel = sheet.getRangeByIndex(averageRow, 1);
    averageLabel.setText('Average');
    _applySummaryDataStyle(averageLabel, bold: true);

    for (var i = 0; i < spacings.length; i++) {
      final baseColumn = 2 + (i * 2);
      final resistanceValues = spacingResistanceTotals[i];
      final rhoValues = spacingResistivityTotals[i];
      final resistanceCell = sheet.getRangeByIndex(averageRow, baseColumn);
      _setSigFigText(
        resistanceCell,
        resistanceValues.isEmpty
            ? null
            : resistanceValues.reduce((a, b) => a + b) /
                resistanceValues.length,
      );
      _applySummaryDataStyle(resistanceCell, bold: true);

      final rhoCell = sheet.getRangeByIndex(averageRow, baseColumn + 1);
      _setSigFigText(
        rhoCell,
        rhoValues.isEmpty
            ? null
            : rhoValues.reduce((a, b) => a + b) / rhoValues.length,
      );
      _applySummaryDataStyle(rhoCell, bold: true);
    }

    final averageNote = sheet.getRangeByIndex(averageRow, notesColumnIndex);
    averageNote.setText(
      'Values rounded to four significant digits. Notes summarize site-level differences formerly captured on per-site tables.',
    );
    final averageNoteStyle = averageNote.cellStyle;
    averageNoteStyle.hAlign = HAlignType.left;
    averageNoteStyle.vAlign = VAlignType.top;
    averageNoteStyle.wrapText = true;

    sheet
        .getRangeByIndex(averageRow, 1, averageRow, totalColumns)
        .autoFitRows();

    final outerStyle =
        sheet.getRangeByIndex(1, 1, averageRow, totalColumns).cellStyle;
    outerStyle.borders.all.lineStyle = LineStyle.thin;
    return sheet;
  }

  void _buildSiteTableSheet(
    Worksheet sheet,
    _SiteTableData siteTable,
    int index,
  ) {
    final headerRange = sheet.getRangeByIndex(1, 1, 1, 9);
    headerRange.merge();
    headerRange.setText('Table $index — Apparent Resistivity Data');
    final headerStyle = headerRange.cellStyle;
    headerStyle
      ..bold = true
      ..fontSize = 16
      ..hAlign = HAlignType.center
      ..vAlign = VAlignType.center;

    final leftMeta = <List<String>>[
      ['Project ID', project.projectId],
      ['Project Name', project.projectName],
      ['Site', siteTable.site.displayName],
      ['Array Type', _arrayTypeLabel(project.arrayType)],
      ['Generated', DateFormat('yyyy-MM-dd').format(generatedAt)],
      ['Operator', (operatorName ?? '').trim()],
    ];
    final rightMeta = <List<String>>[
      ['Current (mA)', siteTable.site.powerMilliAmps.toStringAsFixed(1)],
      ['Stacks', siteTable.site.stacks.toString()],
      [
        'Ground Temp (°F)',
        siteTable.site.groundTemperatureF.isFinite
            ? siteTable.site.groundTemperatureF.toStringAsFixed(1)
            : '—',
      ],
      ['Soil', siteTable.site.soil.label],
      ['Moisture', siteTable.site.moisture.label],
    ];
    if (includeGps && siteTable.site.location != null) {
      final location = siteTable.site.location!;
      rightMeta
        ..add(['Latitude', location.latitude.toStringAsFixed(4)])
        ..add(['Longitude', location.longitude.toStringAsFixed(4)]);
    }

    var metaRow = 3;
    for (final entry in leftMeta) {
      _writeMetadataRow(
        sheet: sheet,
        row: metaRow,
        labelColumn: 1,
        valueStartColumn: 2,
        valueEndColumn: 4,
        label: entry[0],
        value: entry[1],
      );
      metaRow += 1;
    }

    metaRow = 3;
    for (final entry in rightMeta) {
      _writeMetadataRow(
        sheet: sheet,
        row: metaRow,
        labelColumn: 6,
        valueStartColumn: 7,
        valueEndColumn: 9,
        label: entry[0],
        value: entry[1],
      );
      metaRow += 1;
    }

    const headers = <String>[
      'Spacing (ft)',
      'Direction',
      'Resistance (Ω)',
      'ρₐ (Ω-m)',
      'ρₐ (Ω-ft)',
      'σρ (Ω-m)',
      'σρ (Ω-ft)',
      'Notes',
      'Warnings',
    ];
    const headerRow = 12;
    for (var col = 0; col < headers.length; col++) {
      final headerCell = sheet.getRangeByIndex(headerRow, col + 1);
      headerCell.setText(headers[col]);
      _applyHeaderStyle(headerCell);
    }
    sheet
        .getRangeByIndex(headerRow, 1, headerRow, headers.length)
        .cellStyle
        .borders
        .all
        .lineStyle = LineStyle.thin;
    sheet.setRowHeightInPixels(headerRow, 28);
    sheet.setColumnWidthInPixels(1, 90);
    sheet.setColumnWidthInPixels(2, 120);
    sheet.setColumnWidthInPixels(3, 110);
    sheet.setColumnWidthInPixels(4, 130);
    sheet.setColumnWidthInPixels(5, 130);
    sheet.setColumnWidthInPixels(6, 130);
    sheet.setColumnWidthInPixels(7, 130);
    sheet.setColumnWidthInPixels(8, 220);
    sheet.setColumnWidthInPixels(9, 160);

    var currentRow = headerRow + 1;
    for (final spacing in siteTable.spacings) {
      for (var i = 0; i < spacing.directions.length; i++) {
        final direction = spacing.directions[i];
        final row = direction.row;
        final rowRange =
            sheet.getRangeByIndex(currentRow, 1, currentRow, headers.length);
        rowRange.cellStyle.borders.all.lineStyle = LineStyle.thin;

        final spacingCell = sheet.getRangeByIndex(currentRow, 1);
        if (i == 0) {
          spacingCell.setNumber(spacing.spacingFeet);
          spacingCell.numberFormat = spacing.spacingFeet >= 100 ? '0' : '0.0##';
          _applyNumberStyle(spacingCell);
        } else {
          spacingCell.setText('');
        }

        final directionCell = sheet.getRangeByIndex(currentRow, 2);
        directionCell.setText(row.directionLabel);
        final directionStyle = directionCell.cellStyle;
        directionStyle.hAlign = HAlignType.left;
        directionStyle.vAlign = VAlignType.center;

        final resistanceCell = sheet.getRangeByIndex(currentRow, 3);
        resistanceCell
            .setFormula('=$_dataSheetName!E${direction.dataSheetRow}');
        resistanceCell.numberFormat = '0.000';
        _applyNumberStyle(resistanceCell);

        final rhoMCell = sheet.getRangeByIndex(currentRow, 4);
        rhoMCell.setFormula('=$_dataSheetName!H${direction.dataSheetRow}');
        rhoMCell.numberFormat = '0.000';
        _applyNumberStyle(rhoMCell);

        final rhoFtCell = sheet.getRangeByIndex(currentRow, 5);
        final rhoRef = '$_dataSheetName!H${direction.dataSheetRow}';
        rhoFtCell.setFormula('=IF($rhoRef="","",$rhoRef*$_metersToFeet)');
        rhoFtCell.numberFormat = '0.000';
        _applyNumberStyle(rhoFtCell);

        final sigmaMCell = sheet.getRangeByIndex(currentRow, 6);
        sigmaMCell.setFormula('=$_dataSheetName!I${direction.dataSheetRow}');
        sigmaMCell.numberFormat = '0.000';
        _applyNumberStyle(sigmaMCell);

        final sigmaFtCell = sheet.getRangeByIndex(currentRow, 7);
        final sigmaRef = '$_dataSheetName!I${direction.dataSheetRow}';
        sigmaFtCell.setFormula('=IF($sigmaRef="","",$sigmaRef*$_metersToFeet)');
        sigmaFtCell.numberFormat = '0.000';
        _applyNumberStyle(sigmaFtCell);

        final notesCell = sheet.getRangeByIndex(currentRow, 8);
        notesCell.setFormula('=$_dataSheetName!L${direction.dataSheetRow}');
        final notesStyle = notesCell.cellStyle;
        notesStyle
          ..hAlign = HAlignType.left
          ..vAlign = VAlignType.top
          ..wrapText = true;

        final warningCell = sheet.getRangeByIndex(currentRow, 9);
        warningCell.setFormula('=$_dataSheetName!M${direction.dataSheetRow}');
        final warningStyle = warningCell.cellStyle;
        warningStyle
          ..hAlign = HAlignType.left
          ..vAlign = VAlignType.top
          ..wrapText = true;

        currentRow += 1;
      }
    }

    if (currentRow == headerRow + 1) {
      return;
    }

    final firstDataRow = headerRow + 1;
    final lastDataRow = currentRow - 1;
    final averagesRow = currentRow + 1;
    final averageLabel = sheet.getRangeByIndex(averagesRow, 1, averagesRow, 2)
      ..merge();
    averageLabel.setText('Site averages');
    final averageLabelStyle = averageLabel.cellStyle;
    averageLabelStyle
      ..bold = true
      ..hAlign = HAlignType.left
      ..vAlign = VAlignType.center;

    final averageColumns = [4, 5, 6, 7];
    for (final column in averageColumns) {
      final range = sheet.getRangeByIndex(averagesRow, column);
      range
        ..setFormula(
            '=AVERAGE(${_columnRange(column, firstDataRow, lastDataRow)})')
        ..numberFormat = '0.000';
      _applyNumberStyle(range);
    }

    final averageRange =
        sheet.getRangeByIndex(averagesRow, 1, averagesRow, headers.length);
    final averageStyle = averageRange.cellStyle;
    averageStyle
      ..backColor = '#E6EEF5'
      ..bold = true;
    averageStyle.borders.all.lineStyle = LineStyle.thin;

    sheet.getRangeByIndex(firstDataRow, 1).freezePanes();
    sheet.pageSetup
      ..fitToPagesWide = 1
      ..fitToPagesTall = 0;
  }

  void _setSigFigText(Range range, double? value, {int digits = 4}) {
    if (value == null || value.isNaN || !value.isFinite) {
      range.setText('');
      return;
    }
    final formatted = _formatSigFig(value, digits: digits);
    range.setText(formatted);
  }

  String _formatSigFig(double value, {int digits = 4}) {
    if (value == 0) {
      return '0.${'0' * digits}';
    }
    final absValue = value.abs();
    final magnitude = math.log(absValue) / math.ln10;
    final power = magnitude.floor();
    final scale = digits - power - 1;
    double rounded;
    if (scale >= 0) {
      final factor = math.pow(10, scale).toDouble();
      rounded = (value * factor).round() / factor;
      if (rounded == -0.0) {
        rounded = 0;
      }
      return rounded.toStringAsFixed(scale);
    } else {
      final factor = math.pow(10, -scale).toDouble();
      rounded = (value / factor).round() * factor;
      return rounded.toStringAsFixed(0);
    }
  }

  String _buildSiteSummaryNote(SiteRecord site) {
    final totalSpacings = site.spacings.length;
    var nsGood = 0;
    var weGood = 0;
    var flagged = 0;
    var validReadings = 0;
    for (final spacing in site.spacings) {
      final sampleA = spacing.orientationA.latest;
      if (sampleA != null) {
        if (sampleA.isBad) {
          flagged += 1;
        } else if (sampleA.resistanceOhm != null) {
          nsGood += 1;
          validReadings += 1;
        }
      }
      final sampleB = spacing.orientationB.latest;
      if (sampleB != null) {
        if (sampleB.isBad) {
          flagged += 1;
        } else if (sampleB.resistanceOhm != null) {
          weGood += 1;
          validReadings += 1;
        }
      }
    }

    final parts = <String>[];
    if (site.powerMilliAmps.isFinite) {
      parts.add('Current ${_formatSigFig(site.powerMilliAmps, digits: 4)} mA');
    }
    if (site.stacks > 0) {
      parts.add('Stacks ${site.stacks}');
    }
    if (site.soil.label.isNotEmpty) {
      parts.add('Soil ${site.soil.label}');
    }
    if (site.moisture.label.isNotEmpty) {
      parts.add('Moisture ${site.moisture.label}');
    }
    if (totalSpacings > 0) {
      parts.add(
          'NS good $nsGood/$totalSpacings, WE good $weGood/$totalSpacings');
    }
    if (validReadings > 0) {
      parts.add('Valid readings $validReadings');
    }
    if (flagged > 0) {
      parts.add('Flagged readings $flagged');
    }
    parts.add('Averages include non-flagged readings only.');
    return parts.join('; ');
  }

  void _writeMetadataRow({
    required Worksheet sheet,
    required int row,
    required int labelColumn,
    required int valueStartColumn,
    required int valueEndColumn,
    required String label,
    required String value,
  }) {
    final labelRange = sheet.getRangeByIndex(row, labelColumn);
    labelRange.setText(label);
    final labelStyle = labelRange.cellStyle;
    labelStyle
      ..bold = true
      ..hAlign = HAlignType.left
      ..vAlign = VAlignType.center;

    final valueRange =
        sheet.getRangeByIndex(row, valueStartColumn, row, valueEndColumn);
    valueRange.merge();
    valueRange.setText(value);
    final valueStyle = valueRange.cellStyle;
    valueStyle
      ..hAlign = HAlignType.left
      ..vAlign = VAlignType.center;
  }

  String _columnRange(int column, int startRow, int endRow) {
    final columnLetter = _columnLetter(column);
    return '$columnLetter$startRow:$columnLetter$endRow';
  }

  String _columnLetter(int column) {
    var dividend = column;
    var columnName = '';
    while (dividend > 0) {
      final modulo = (dividend - 1) % 26;
      columnName = String.fromCharCode(65 + modulo) + columnName;
      dividend = (dividend - modulo - 1) ~/ 26;
    }
    return columnName;
  }

  String _tableSheetName(String displayName, int index) {
    final sanitized = displayName
        .replaceAll(RegExp(r'[\\/*?:\\[\\]]'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();
    final base = sanitized.isEmpty ? 'Site $index' : sanitized;
    final prefix = 'Table $index - ';
    var candidate = '$prefix$base';
    if (candidate.length <= 31) {
      return candidate;
    }
    final maxBaseLength = 31 - prefix.length;
    var truncated = base.substring(0, maxBaseLength).trimRight();
    if (truncated.isEmpty) {
      truncated = 'Site $index';
    }
    candidate = '$prefix$truncated';
    if (candidate.length <= 31) {
      return candidate;
    }
    return 'Table $index';
  }

  String _spacingSummarySheetName() {
    final sanitized = project.projectName
        .replaceAll(RegExp(r'[\\/*?:\\[\\]]'), ' ')
        .replaceAll(RegExp(r'\\s+'), ' ')
        .trim();
    const prefix = 'Table 1 - ';
    const suffix = ' Resistivity Data';
    const maxLength = 31;
    final maxProjectLength = maxLength - prefix.length - suffix.length;
    if (maxProjectLength <= 0) {
      return 'Table 1';
    }
    var projectSegment =
        sanitized.isEmpty ? project.projectId.trim() : sanitized;
    if (projectSegment.isEmpty) {
      projectSegment = 'Project';
    }
    if (projectSegment.length > maxProjectLength) {
      projectSegment =
          projectSegment.substring(0, maxProjectLength).trimRight();
      if (projectSegment.isEmpty) {
        projectSegment = 'Project';
      }
    }
    final candidate = '$prefix$projectSegment$suffix';
    if (candidate.length <= maxLength) {
      return candidate;
    }
    return 'Table 1';
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
    final percent = sigmaPercent;
    if (percent <= _sigmaGreenThreshold * 100) {
      return _sigmaGreenHex;
    }
    if (percent <= _sigmaAmberThreshold * 100) {
      return _sigmaAmberHex;
    }
    return _sigmaRedHex;
  }

  void _setText(
    Worksheet sheet,
    int row,
    int column,
    String value, {
    HAlignType align = HAlignType.left,
    VAlignType verticalAlign = VAlignType.center,
    bool wrap = false,
  }) {
    final range = sheet.getRangeByIndex(row, column);
    range.setText(value);
    final style = range.cellStyle;
    style.hAlign = align;
    style.vAlign = verticalAlign;
    style.wrapText = wrap;
  }

  void _setNumber(Worksheet sheet, int row, int column, double value) {
    final range = sheet.getRangeByIndex(row, column);
    range.setNumber(value);
    range.numberFormat = '0.0000';
    _applyNumberStyle(range);
  }

  void _setOptionalNumber(Worksheet sheet, int row, int column, double? value) {
    final range = sheet.getRangeByIndex(row, column);
    if (value == null || value.isNaN || !value.isFinite) {
      range.setText('');
    } else {
      range.setNumber(value);
    }
    _applyNumberStyle(range);
  }

  void _applyHeaderStyle(Range range) {
    final style = range.cellStyle;
    style.backColor = '#1F4E78';
    style.fontColor = '#FFFFFF';
    style.bold = true;
    style.hAlign = HAlignType.center;
    style.vAlign = VAlignType.center;
    style.wrapText = true;
  }

  void _applySummaryHeaderStyle(Range range) {
    final style = range.cellStyle;
    style.bold = true;
    style.hAlign = HAlignType.center;
    style.vAlign = VAlignType.center;
    style.wrapText = true;
    style.backColor = '#D9E1F2';
  }

  void _applySummarySubHeaderStyle(Range range) {
    final style = range.cellStyle;
    style.bold = true;
    style.hAlign = HAlignType.center;
    style.vAlign = VAlignType.center;
    style.wrapText = true;
    style.backColor = '#EEF3FB';
  }

  void _applySummaryDataStyle(Range range, {bool bold = false}) {
    final style = range.cellStyle;
    style.hAlign = HAlignType.center;
    style.vAlign = VAlignType.center;
    style.wrapText = true;
    style.bold = bold;
  }

  void _applyLabelStyle(Range range) {
    final style = range.cellStyle;
    style.bold = true;
    style.hAlign = HAlignType.left;
    style.vAlign = VAlignType.center;
  }

  void _applyNumberStyle(Range range) {
    final style = range.cellStyle;
    style.hAlign = HAlignType.right;
    style.vAlign = VAlignType.center;
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
  static const _sigmaGreenHex = '#C6EFCE';
  static const _sigmaAmberHex = '#FFEB9C';
  static const _sigmaRedHex = '#F4C7C3';
  static const _unitLabel = 'ft / Ω·m';
  static const double _metersToFeet = 3.280839895;
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

  static const _dataColumnWidths = <int>[
    48,
    80,
    80,
    110,
    80,
    70,
    70,
    120,
    145,
    90,
    200,
    320,
    240,
  ];
}

class _ExcelDataRow {
  _ExcelDataRow({
    required this.directionLabel,
    required this.spacingFeet,
    required this.orientation,
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
      spacingFeet: spacingFeet,
      orientation: history.orientation,
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
  final double spacingFeet;
  final OrientationKind orientation;
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

class _SiteTableData {
  _SiteTableData({
    required this.site,
    required this.spacings,
  });

  final SiteRecord site;
  final List<_SpacingTableData> spacings;
}

class _SpacingTableData {
  _SpacingTableData({
    required this.spacingFeet,
    required this.directions,
  });

  final double spacingFeet;
  final List<_DirectionTableData> directions;
}

class _DirectionTableData {
  _DirectionTableData({required this.row});

  final _ExcelDataRow row;
  late final int dataSheetRow;
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
