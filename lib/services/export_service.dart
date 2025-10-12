import 'dart:io';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:resicheck/models/calc.dart' as calc;
import 'package:resicheck/models/direction_reading.dart';
import 'package:resicheck/models/project.dart';
import 'package:resicheck/models/site.dart';
import 'package:resicheck/services/inversion.dart';
import 'package:resicheck/services/storage_service.dart';
import 'package:resicheck/utils/distance_unit.dart';
import 'package:resicheck/utils/units.dart' as units;

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
    final document = _buildInversionDocument(project, [entry]);
    final file = await storageService.ensureExportFile(
      project,
      '${project.projectId}_${_slug(project.projectName)}_${entry.site.siteId}_report',
      'pdf',
    );
    await file.writeAsBytes(await document.save());
    await _writeExportLog(
      project,
      [
        'Site: ${entry.site.displayName} (${entry.site.siteId})',
        'RMS: ${entry.result.rms.toStringAsFixed(4)}',
        'PDF: ${file.path}',
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
    final document = _buildInversionDocument(project, sorted);
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
    return file;
  }

  pw.Document _buildInversionDocument(
    ProjectRecord project,
    List<InversionReportEntry> entries,
  ) {
    final document = pw.Document();
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
            pw.SizedBox(height: 16),
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
