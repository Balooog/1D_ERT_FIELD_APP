import 'dart:io';
import 'dart:math' as math;

import 'package:csv/csv.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:resicheck/models/calc.dart' as calc;
import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/project.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/services/export_excel_traditional.dart';
import 'package:resicheck/services/export_excel_updated.dart';
import 'package:resicheck/services/inversion.dart';
import 'package:resicheck/services/inversion_figure_renderer.dart';
import 'package:resicheck/services/storage_service.dart';
import 'package:resicheck/utils/distance_unit.dart';
import 'package:resicheck/utils/units.dart' as units;

enum ExcelStyle { traditional, updated }

class InversionReportEntry {
  InversionReportEntry({
    required this.site,
    required this.result,
    this.distanceUnit = DistanceUnit.feet,
  });

  final SiteRecord site;
  final TwoLayerInversionResult result;
  final DistanceUnit distanceUnit;
}

class ExportService {
  ExportService(this.storageService);

  final ProjectStorageService storageService;
  static pw.ThemeData? _cachedPdfTheme;

  Future<File> exportFieldCsv(ProjectRecord project, SiteRecord site) async {
    final rows = <List<dynamic>>[
      [
        'site_id',
        'orientation',
        'a_ft',
        'inside_ft',
        'outside_ft',
        'power_ma',
        'stacks',
        'resistance_ohm',
        'sd_pct',
        'rhoa_ohm_m',
        'note',
        'is_bad',
      ],
    ];

    final spacings = [...site.spacings]
      ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
    for (final spacing in spacings) {
      rows.add(_rowForSpacing(site, spacing, spacing.orientationA));
      rows.add(_rowForSpacing(site, spacing, spacing.orientationB));
    }

    const converter = ListToCsvConverter();
    final csv = converter.convert(rows);
    final file = await storageService.ensureExportFile(
      project,
      '${project.projectId}_${_slug(project.projectName)}_${site.siteId}_field',
      'csv',
    );
    await file.writeAsString(csv);
    return file;
  }

  Future<File> exportSurferDat(ProjectRecord project, SiteRecord site) async {
    final buffer = StringBuffer();
    buffer.writeln('# ResiCheck Surfer DAT export');
    buffer.writeln('# project_id=${project.projectId}');
    buffer.writeln('# site_id=${site.siteId}');
    buffer.writeln('a_ft,orientation,resistance_ohm,rhoa_ohm_m,sd_pct,is_bad');
    final spacings = [...site.spacings]
      ..sort((a, b) => a.spacingFeet.compareTo(b.spacingFeet));
    for (final spacing in spacings) {
      buffer.writeln(_lineForSpacing(spacing, spacing.orientationA));
      buffer.writeln(_lineForSpacing(spacing, spacing.orientationB));
    }
    final file = await storageService.ensureExportFile(
      project,
      '${project.projectId}_${_slug(project.projectName)}_${site.siteId}_surfer',
      'dat',
    );
    await file.writeAsString(buffer.toString());
    return file;
  }

  Future<File> exportInversionPdf(
    ProjectRecord project,
    InversionReportEntry entry,
  ) async {
    final theme = await _loadPdfTheme();
    final document = _buildInversionDocument(project, [entry], theme);
    final file = await storageService.ensureExportFile(
      project,
      '${project.projectId}_${_slug(project.projectName)}_${entry.site.siteId}_report',
      'pdf',
    );
    await file.writeAsBytes(await document.save());
    final png = await _exportInversionPng(project, entry);
    await _writeExportLog(
      project,
      [
        'Site: ${entry.site.displayName} (${entry.site.siteId})',
        'RMS: ${entry.result.rms.toStringAsFixed(4)}',
        'PDF: ${file.path}',
        if (png != null) 'PNG: ${png.path}',
      ],
    );
    return file;
  }

  Future<File> exportBatchInversionPdf(
    ProjectRecord project,
    List<InversionReportEntry> entries,
  ) async {
    if (entries.isEmpty) {
      throw ArgumentError('entries must not be empty');
    }
    final sorted = [...entries]
      ..sort((a, b) => a.site.displayName.compareTo(b.site.displayName));
    final theme = await _loadPdfTheme();
    final document = _buildInversionDocument(project, sorted, theme);
    final file = await storageService.ensureExportFile(
      project,
      '${project.projectId}_${_slug(project.projectName)}_all_sites_report',
      'pdf',
    );
    await file.writeAsBytes(await document.save());
    final lines = <String>[
      'Sites exported: ${sorted.length}',
      for (final entry in sorted)
        ' - ${entry.site.displayName} (${entry.site.siteId}): RMS ${entry.result.rms.toStringAsFixed(4)}',
      'PDF: ${file.path}',
    ];
    await _writeExportLog(project, lines);
    for (final entry in sorted) {
      await _exportInversionPng(project, entry);
    }
    return file;
  }

  Future<File> exportExcelForSite(
    ProjectRecord project,
    SiteRecord site, {
    String? operatorName,
    ExcelStyle style = ExcelStyle.updated,
    bool includeGps = false,
  }) async {
    final exportsDir = await _ensureExportsDirectory(project);
    final generatedAt = DateTime.now();
    final siteSlug =
        _slug(site.displayName.isNotEmpty ? site.displayName : site.siteId);
    final projectSlug = _slug(project.projectName);

    late final File file;
    switch (style) {
      case ExcelStyle.traditional:
        file = await writeTraditionalTable(
          project: project,
          site: site,
          outDir: exportsDir,
          includeGps: includeGps,
          generatedAt: generatedAt,
        );
        break;
      case ExcelStyle.updated:
        final fileName = '${projectSlug}_${siteSlug}_THG_Updated.xlsx';
        file = await writeUpdatedTable(
          project: project,
          sites: [site],
          outDir: exportsDir,
          fileName: fileName,
          includeGps: includeGps,
          operatorName: operatorName,
          generatedAt: generatedAt,
        );
        break;
    }

    final logLines = <String>[
      'Excel scope: site',
      'Style: ${style.name}',
      'Include GPS: $includeGps',
      'Site: ${site.displayName} (${site.siteId})',
      if (operatorName != null && operatorName.isNotEmpty)
        'Operator: $operatorName',
      'Excel: ${file.path}',
    ];
    await _writeExportLog(project, logLines);
    return file;
  }

  Future<File> exportExcelForProject(
    ProjectRecord project, {
    String? operatorName,
    ExcelStyle style = ExcelStyle.updated,
    bool includeGps = false,
  }) async {
    if (style == ExcelStyle.traditional) {
      throw UnsupportedError(
        'Traditional table styling is available only for single-site exports.',
      );
    }
    final exportsDir = await _ensureExportsDirectory(project);
    final generatedAt = DateTime.now();
    final projectSlug = _slug(project.projectName);
    final fileName = '${projectSlug}_AllSites_THG_Updated.xlsx';
    final file = await writeUpdatedTable(
      project: project,
      sites: project.sites,
      outDir: exportsDir,
      fileName: fileName,
      includeGps: includeGps,
      operatorName: operatorName,
      generatedAt: generatedAt,
    );
    final lines = <String>[
      'Excel scope: project',
      'Style: ${style.name}',
      'Include GPS: $includeGps',
      'Sites exported: ${project.sites.length}',
      if (operatorName != null && operatorName.isNotEmpty)
        'Operator: $operatorName',
      'Excel: ${file.path}',
    ];
    await _writeExportLog(project, lines);
    return file;
  }

  pw.Document _buildInversionDocument(
    ProjectRecord project,
    List<InversionReportEntry> entries,
    pw.ThemeData theme,
  ) {
    final document = pw.Document(theme: theme);
    final generatedAt = DateTime.now();
    final dateFormat = DateFormat.yMMMMd();
    for (final entry in entries) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (context) => [
            _buildPdfHeader(project, entry.site, generatedAt, dateFormat),
            pw.SizedBox(height: 12),
            _buildPdfSummary(entry),
            pw.SizedBox(height: 14),
            _buildPdfChart(entry),
            pw.SizedBox(height: 14),
            _buildPdfSummaryFooter(entry),
            pw.SizedBox(height: 12),
            _buildPdfTable(entry),
          ],
        ),
      );
    }
    return document;
  }

  pw.Widget _buildPdfHeader(
    ProjectRecord project,
    SiteRecord site,
    DateTime generatedAt,
    DateFormat dateFormat,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          project.projectName,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Site ${site.displayName} (${site.siteId})',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.normal),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          'Generated ${dateFormat.format(generatedAt)}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSummary(InversionReportEntry entry) {
    final result = entry.result;
    final chips = <pw.Widget>[
      _summaryChip(
        'ρ₁',
        _formatRhoValue(result.rho1.toDouble()),
        _pdfBlue,
      ),
      _summaryChip(
        'ρ₂',
        _formatRhoValue(result.rho2.toDouble()),
        _pdfOrange,
      ),
      if (result.halfSpaceRho != null)
        _summaryChip(
          'ρ₃',
          _formatRhoValue(result.halfSpaceRho!.toDouble()),
          _pdfVermillion,
        ),
      if (result.thicknessM != null)
        _summaryChip(
          'h',
          '${_formatSpacing(entry.distanceUnit, result.thicknessM!.toDouble())} ${_unitLabel(entry.distanceUnit)}',
          PdfColors.blueGrey600,
        ),
      _summaryChip('RMS', '${(result.rms * 100).toStringAsFixed(1)} %',
          PdfColors.indigo),
    ];
    return pw.Wrap(
      spacing: 12,
      runSpacing: 8,
      children: chips,
    );
  }

  pw.Widget _buildPdfSummaryFooter(InversionReportEntry entry) {
    final result = entry.result;
    final rmsPercent = (result.rms * 100).toStringAsFixed(1);
    final lines = <String>[
      'Solver RMS: $rmsPercent %',
      if (result.thicknessM != null)
        'Layer thickness: ${_formatSpacing(entry.distanceUnit, result.thicknessM!.toDouble())} ${_unitLabel(entry.distanceUnit)}',
      if (result.halfSpaceRho != null)
        'Half-space resistivity: ${_formatRhoValue(result.halfSpaceRho!.toDouble())} Ω·m',
    ];
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: _mixColors(PdfColors.white, PdfColors.blueGrey100, 0.35),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blueGrey300, width: 0.4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Text(
                line,
                style: const pw.TextStyle(fontSize: 10.5),
              ),
            ),
        ],
      ),
    );
  }

  pw.Widget _summaryChip(String label, String value, PdfColor color) {
    final background = _mixColors(PdfColors.white, color, 0.12);
    final border = _mixColors(color, PdfColors.black, 0.2);
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: background,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: border, width: 0.6),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label ',
              style: pw.TextStyle(
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: color,
              ),
            ),
            pw.TextSpan(
              text: value,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildPdfTable(InversionReportEntry entry) {
    final headers = [
      'a (${_unitLabel(entry.distanceUnit)})',
      'Depth (${_unitLabel(entry.distanceUnit)})',
      'ρ obs (Ω·m)',
      'ρ fit (Ω·m)',
    ];
    final rows = <List<String>>[];
    final result = entry.result;
    for (var i = 0; i < result.spacingFeet.length; i++) {
      final double spacingFeet = result.spacingFeet[i].toDouble();
      final double spacingMeters = units.feetToMeters(spacingFeet);
      final double depthMeters = i < result.measurementDepthsM.length
          ? result.measurementDepthsM[i].toDouble()
          : (result.measurementDepthsM.isEmpty
              ? 0.0
              : result.measurementDepthsM.last.toDouble());
      final double observed = i < result.observedRho.length
          ? result.observedRho[i].toDouble()
          : 0.0;
      final double predicted = i < result.predictedRho.length
          ? result.predictedRho[i].toDouble()
          : observed;
      rows.add([
        _formatSpacing(entry.distanceUnit, spacingMeters),
        _formatSpacing(entry.distanceUnit, depthMeters),
        _formatRhoValue(observed),
        _formatRhoValue(predicted),
      ]);
    }
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      border: pw.TableBorder.all(color: PdfColors.grey500, width: 0.4),
      headerStyle: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      cellStyle: const pw.TextStyle(fontSize: 9),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      rowDecoration: const pw.BoxDecoration(color: PdfColors.white),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(1.1),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.2),
      },
    );
  }

  pw.Widget _buildPdfChart(InversionReportEntry entry) {
    final result = entry.result;
    final samplesAvailable = result.observedRho.any((value) => value > 0) ||
        result.predictedRho.any((value) => value > 0);
    if (!samplesAvailable) {
      return pw.Container(
        height: 160,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'Not enough valid samples to render two-layer profile.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      );
    }

    final minRho = math.max(result.minRho * 0.8, 0.5);
    final maxRho = math.max(result.maxRho * 1.2, minRho * 1.05);
    final minLog = _log10(minRho);
    final maxLog = _log10(maxRho);
    final depthMeters = math.max(result.maxDepthMeters * 1.1, 0.5);
    final depthTicks = _buildDepthTicks(depthMeters);
    final resistivityTicks = _buildResistivityTicks(minLog, maxLog);

    final measurementPoints = <pw.PointChartValue>[];
    final predictedPoints = <pw.PointChartValue>[];
    for (var i = 0; i < result.observedRho.length; i++) {
      final observed = result.observedRho[i].toDouble();
      if (!observed.isFinite || observed <= 0) {
        continue;
      }
      final depth = i < result.measurementDepthsM.length
          ? result.measurementDepthsM[i].toDouble()
          : (result.measurementDepthsM.isEmpty
              ? 0.0
              : result.measurementDepthsM.last.toDouble());
      measurementPoints.add(pw.PointChartValue(_log10(observed), -depth));

      if (i < result.predictedRho.length) {
        final predicted = result.predictedRho[i].toDouble();
        if (predicted.isFinite && predicted > 0) {
          predictedPoints.add(pw.PointChartValue(_log10(predicted), -depth));
        }
      }
    }

    final profilePoints = _buildProfilePoints(result, depthMeters);

    final datasets = <pw.Dataset>[
      if (profilePoints.length >= 2)
        pw.LineDataSet<pw.PointChartValue>(
          data: profilePoints,
          legend: 'Layer model',
          color: _pdfOrange,
          lineWidth: 3,
          drawPoints: false,
          drawSurface: false,
          isCurved: false,
        ),
      if (predictedPoints.isNotEmpty)
        pw.LineDataSet<pw.PointChartValue>(
          data: predictedPoints,
          legend: 'Predicted ρ',
          color: _pdfBlue,
          lineWidth: 1.6,
          drawPoints: false,
          drawSurface: false,
          isCurved: false,
        ),
      if (measurementPoints.isNotEmpty)
        pw.PointDataSet<pw.PointChartValue>(
          data: measurementPoints,
          legend: 'Measured ρ',
          color: PdfColors.grey700,
          borderColor: PdfColors.white,
          borderWidth: 0.8,
          pointSize: 3.5,
        ),
    ];

    if (datasets.isEmpty) {
      return pw.Container(
        height: 160,
        alignment: pw.Alignment.center,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Text(
          'Not enough valid samples to render two-layer profile.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      );
    }

    final xAxisTicks = [for (final tick in resistivityTicks) tick.toDouble()];
    final yAxisTicks = [
      for (final tick in depthTicks.reversed) -tick.toDouble()
    ];

    final chart = pw.Chart(
      grid: pw.CartesianGrid(
        xAxis: pw.FixedAxis<double>(
          xAxisTicks,
          format: (value) => _formatResistivityTick(value),
          divisions: true,
          divisionsColor: PdfColors.grey400,
          divisionsDashed: true,
          ticks: true,
          textStyle: const pw.TextStyle(fontSize: 9),
        ),
        yAxis: pw.FixedAxis<double>(
          yAxisTicks,
          format: (value) {
            final depth = -value.toDouble();
            if (depth < 0) {
              return '';
            }
            return entry.distanceUnit.formatSpacing(depth);
          },
          divisions: true,
          divisionsColor: PdfColors.grey400,
          ticks: true,
          textStyle: const pw.TextStyle(fontSize: 9),
        ),
      ),
      datasets: datasets,
      overlay: pw.ChartLegend(
        position: pw.Alignment.topRight,
        direction: pw.Axis.vertical,
        textStyle: const pw.TextStyle(fontSize: 9),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
        ),
      ),
    );

    final depthLabel = 'Depth (${_unitLabel(entry.distanceUnit)})';

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey400, width: 0.4),
        color: _mixColors(PdfColors.white, PdfColors.blueGrey50, 0.12),
      ),
      padding: const pw.EdgeInsets.all(12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'Two-layer resistivity profile',
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 12),
          pw.SizedBox(
            height: 180,
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Transform.rotate(
                  angle: math.pi / 2,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      depthLabel,
                      style: const pw.TextStyle(fontSize: 9),
                    ),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Expanded(child: chart),
              ],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'Resistivity (Ω·m)',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
        ],
      ),
    );
  }

  Future<File?> _exportInversionPng(
    ProjectRecord project,
    InversionReportEntry entry,
  ) async {
    try {
      final exportsDir = await _ensureExportsDirectory(project);
      final figuresDir = Directory(p.join(exportsDir.path, 'figures'));
      if (!await figuresDir.exists()) {
        await figuresDir.create(recursive: true);
      }
      final projectSlug = _slug(project.projectName);
      final siteLabel = entry.site.displayName.isNotEmpty
          ? entry.site.displayName
          : entry.site.siteId;
      final siteSlug = _slug(siteLabel);
      final fileName = '${projectSlug}_${siteSlug}_Inversion.png';
      final bytes = await InversionFigureRenderer.render(
        project: project,
        site: entry.site,
        result: entry.result,
        distanceUnit: entry.distanceUnit,
      );
      final file = File(p.join(figuresDir.path, fileName));
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<pw.ThemeData> _loadPdfTheme() async {
    if (_cachedPdfTheme != null) {
      return _cachedPdfTheme!;
    }
    final regular =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf'));
    final italic =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Italic.ttf'));
    final boldItalic = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-BoldItalic.ttf'));
    _cachedPdfTheme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
      fontFallback: [regular],
    );
    return _cachedPdfTheme!;
  }

  String _formatSpacing(DistanceUnit unit, double meters) {
    final formatted = unit.formatSpacing(meters);
    return formatted;
  }

  String _formatRhoValue(double value) {
    final absValue = value.abs();
    if (absValue >= 1000) {
      return value.toStringAsFixed(0);
    }
    if (absValue >= 100) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
  }

  String _unitLabel(DistanceUnit unit) =>
      unit == DistanceUnit.feet ? 'ft' : 'm';

  PdfColor _mixColors(PdfColor a, PdfColor b, double t) {
    final clamped = t.clamp(0, 1);
    return PdfColor(
      a.red + (b.red - a.red) * clamped,
      a.green + (b.green - a.green) * clamped,
      a.blue + (b.blue - a.blue) * clamped,
    );
  }

  Future<void> _writeExportLog(
      ProjectRecord project, List<String> lines) async {
    final directory = Directory('logs');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final timestamp = DateTime.now();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
    final file = File('${directory.path}/export_$stamp.txt');
    final buffer = StringBuffer()
      ..writeln('Project: ${project.projectName} (${project.projectId})')
      ..writeln('Generated: ${timestamp.toIso8601String()}');
    for (final line in lines) {
      buffer.writeln(line);
    }
    await file.writeAsString(buffer.toString());
  }

  Future<Directory> _ensureExportsDirectory(ProjectRecord project) async {
    final projectDir = await storageService.projectDirectory(project);
    final exportsDir = Directory(p.join(projectDir.path, 'exports'));
    if (!await exportsDir.exists()) {
      await exportsDir.create(recursive: true);
    }
    return exportsDir;
  }

  List<dynamic> _rowForSpacing(
    SiteRecord site,
    SpacingRecord spacing,
    DirectionReadingHistory history,
  ) {
    final sample = history.latest;
    final resistance = sample?.resistanceOhm;
    final rho = resistance == null
        ? null
        : calc.rhoAWenner(spacing.spacingFeet, resistance);
    return [
      site.siteId,
      history.label,
      spacing.spacingFeet,
      spacing.tapeInsideFeet,
      spacing.tapeOutsideFeet,
      site.powerMilliAmps,
      site.stacks,
      resistance,
      sample?.standardDeviationPercent,
      rho,
      sample?.note ?? '',
      sample?.isBad ?? false,
    ];
  }

  String _lineForSpacing(
    SpacingRecord spacing,
    DirectionReadingHistory history,
  ) {
    final sample = history.latest;
    final resistance = sample?.resistanceOhm ?? 0;
    final rho = calc.rhoAWenner(spacing.spacingFeet, resistance);
    final sd = sample?.standardDeviationPercent ?? 0;
    final isBad = sample?.isBad ?? false;
    return '${spacing.spacingFeet},${history.label},$resistance,$rho,$sd,${isBad ? 1 : 0}';
  }

  String _slug(String input) {
    final trimmed = input.trim();
    final sanitized = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9-_]'), '_');
    return sanitized.isEmpty ? 'project' : sanitized;
  }
}

const PdfColor _pdfBlue = PdfColor.fromInt(0xFF0072B2);
const PdfColor _pdfOrange = PdfColor.fromInt(0xFFE69F00);
const PdfColor _pdfVermillion = PdfColor.fromInt(0xFFD55E00);

double _log10(double value) => math.log(value) / math.ln10;

List<double> _buildDepthTicks(double maxDepth) {
  if (maxDepth <= 0) {
    return const [];
  }
  const tickCount = 4;
  final step = maxDepth / tickCount;
  return [
    for (var i = 0; i <= tickCount; i++) i * step,
  ];
}

List<int> _buildResistivityTicks(double minLog, double maxLog) {
  final start = minLog.floor();
  final end = maxLog.ceil();
  return [for (var i = start; i <= end; i++) i];
}

List<pw.PointChartValue> _buildProfilePoints(
  TwoLayerInversionResult summary,
  double depthMeters,
) {
  final spots = <pw.PointChartValue>[];
  final topLog = _log10(summary.rho1);
  spots.add(pw.PointChartValue(topLog, 0));
  final firstBoundary = summary.thicknessM ??
      (summary.layerDepths.isNotEmpty
          ? summary.layerDepths.first
          : summary.maxDepthMeters / 2);
  final cappedBoundary = math.min(firstBoundary, depthMeters);
  spots.add(pw.PointChartValue(topLog, -cappedBoundary));
  final secondLog = _log10(summary.rho2);
  spots.add(pw.PointChartValue(secondLog, -cappedBoundary));
  spots.add(pw.PointChartValue(secondLog, -depthMeters));
  return spots;
}

String _formatResistivityTick(num logValue) {
  final value = math.pow(10, logValue.toDouble()).toDouble();
  if (!value.isFinite) {
    return '';
  }
  final numeric = value;
  String label;
  if (numeric >= 1000) {
    label = numeric.toStringAsFixed(0);
  } else if (numeric >= 100) {
    label = numeric.toStringAsFixed(0);
  } else if (numeric >= 10) {
    label = numeric.toStringAsFixed(1);
  } else {
    label = numeric.toStringAsFixed(2);
  }
  return _trimTrailingZeros(label);
}

String _trimTrailingZeros(String value) {
  if (!value.contains('.')) {
    return value;
  }
  return value.replaceFirst(RegExp(r'\.?0+$'), '');
}
