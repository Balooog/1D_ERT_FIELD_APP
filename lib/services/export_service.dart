import 'dart:io';
import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:csv/csv.dart';

import '../models/calc.dart';
import '../models/direction_reading.dart';
import '../models/project.dart';
import '../models/site.dart';
import '../services/inversion.dart';
import '../utils/distance_unit.dart';
import 'storage_service.dart';

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

    final converter = const ListToCsvConverter();
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
            pw.Container(
              height: 220,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey500, width: 0.5),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.CustomPaint(
                painter: _InversionPdfPainter(entry.result, entry.distanceUnit),
              ),
            ),
            pw.SizedBox(height: 16),
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
          style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
        ),
      ],
    );
  }

  pw.Widget _buildPdfSummary(InversionReportEntry entry) {
    final result = entry.result;
    final chips = <pw.Widget>[
      _summaryChip('ρ₁', _formatRhoValue(result.rho1), _pdfBlue),
      _summaryChip('ρ₂', _formatRhoValue(result.rho2), _pdfOrange),
      if (result.halfSpaceRho != null)
        _summaryChip('ρ₃', _formatRhoValue(result.halfSpaceRho!), _pdfVermillion),
      if (result.thicknessM != null)
        _summaryChip(
          'h',
          '${_formatSpacing(entry.distanceUnit, result.thicknessM!)} ${_unitLabel(entry.distanceUnit)}',
          PdfColors.blueGrey600,
        ),
      _summaryChip('RMS', '${(result.rms * 100).toStringAsFixed(1)} %', PdfColors.indigo),
    ];
    return pw.Wrap(
      spacing: 12,
      runSpacing: 8,
      children: chips,
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
      final spacingMeters = feetToMeters(result.spacingFeet[i]);
      final depthMeters = i < result.measurementDepthsM.length
          ? result.measurementDepthsM[i]
          : (result.measurementDepthsM.isEmpty ? 0 : result.measurementDepthsM.last);
      final observed = i < result.observedRho.length ? result.observedRho[i] : 0;
      final predicted = i < result.predictedRho.length ? result.predictedRho[i] : observed;
      rows.add([
        _formatSpacing(entry.distanceUnit, spacingMeters),
        _formatSpacing(entry.distanceUnit, depthMeters),
        _formatRhoValue(observed),
        _formatRhoValue(predicted),
      ]);
    }
    return pw.Table.fromTextArray(
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

  String _unitLabel(DistanceUnit unit) => unit == DistanceUnit.feet ? 'ft' : 'm';

  PdfColor _mixColors(PdfColor a, PdfColor b, double t) {
    final clamped = t.clamp(0, 1);
    return PdfColor(
      a.red + (b.red - a.red) * clamped,
      a.green + (b.green - a.green) * clamped,
      a.blue + (b.blue - a.blue) * clamped,
    );
  }

  Future<void> _writeExportLog(ProjectRecord project, List<String> lines) async {
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
        : rhoAWenner(spacing.spacingFeet, resistance);
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
    final rho = rhoAWenner(spacing.spacingFeet, resistance);
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
const PdfColor _pdfGray = PdfColor.fromInt(0xFF595959);

class _InversionPdfPainter extends pw.CustomPainter {
  _InversionPdfPainter(this.result, this.distanceUnit);

  final TwoLayerInversionResult result;
  final DistanceUnit distanceUnit;

  @override
  void paint(pw.Context context, pw.Canvas canvas, pw.Size size) {
    final left = 36.0;
    final right = size.width - 16.0;
    final top = 12.0;
    final bottom = size.height - 26.0;
    final chartWidth = math.max(right - left, 1);
    final chartHeight = math.max(bottom - top, 1);

    final minRho = math.max(result.minRho * 0.8, 0.5);
    final maxRho = result.maxRho * 1.2;
    final minLog = math.log(minRho) / math.ln10;
    final maxLog = math.log(maxRho) / math.ln10;
    final logSpan = (maxLog - minLog).abs() < 1e-3 ? 1 : maxLog - minLog;
    final depthMax = math.max(result.maxDepthMeters * 1.1, 0.5);

    double mapX(double rho) {
      final log = math.log(rho) / math.ln10;
      final normalized = (log - minLog) / logSpan;
      return left + normalized * chartWidth;
    }

    double mapY(double depthMeters) {
      final normalized = depthMeters / depthMax;
      return top + normalized * chartHeight;
    }

    final axisPaint = pw.Paint()
      ..color = PdfColors.grey600
      ..strokeWidth = 0.7;
    final gridPaint = pw.Paint()
      ..color = PdfColors.grey400
      ..strokeWidth = 0.4;

    canvas.drawLine(pw.Offset(left, top), pw.Offset(left, bottom), axisPaint);
    canvas.drawLine(pw.Offset(left, bottom), pw.Offset(right, bottom), axisPaint);

    final depthTicks = _buildDepthTicks(depthMax);
    final resistivityTicks = _buildResistivityTicks(minLog, maxLog);
    final font = pw.Theme.of(context).defaultTextStyle.font ?? pw.Font.helvetica();
    const tickFontSize = 8.0;

    for (final tick in depthTicks) {
      final y = mapY(tick);
      canvas.drawLine(pw.Offset(left, y), pw.Offset(right, y), gridPaint);
      final label = distanceUnit.formatSpacing(tick);
      final metrics = font.stringMetrics(label, tickFontSize);
      canvas.drawString(
        font,
        tickFontSize,
        label,
        pw.Offset(left - metrics.width - 4, y + metrics.descent),
      );
    }

    for (final tick in resistivityTicks) {
      final rho = math.pow(10, tick).toDouble();
      final x = mapX(rho);
      canvas.drawLine(pw.Offset(x, top), pw.Offset(x, bottom), gridPaint);
      final label = rho.toStringAsFixed(0);
      final metrics = font.stringMetrics(label, tickFontSize);
      canvas.drawString(
        font,
        tickFontSize,
        label,
        pw.Offset(x - metrics.width / 2, bottom + metrics.ascent + 4),
      );
    }

    canvas.drawString(
      font,
      tickFontSize + 2,
      'Depth (${_unitLabel(distanceUnit)})',
      pw.Offset(left - 30, top - 6),
    );
    canvas.drawString(
      font,
      tickFontSize + 2,
      'Resistivity (Ω·m)',
      pw.Offset((left + right) / 2 - 38, bottom + 18),
    );

    final profilePath = pw.Path();
    final boundary = result.thicknessM ??
        (result.layerDepths.isNotEmpty ? result.layerDepths.first : depthMax / 2);
    final cappedBoundary = math.min(boundary, depthMax);
    profilePath.moveTo(mapX(result.rho1), mapY(0));
    profilePath.lineTo(mapX(result.rho1), mapY(cappedBoundary));
    profilePath.lineTo(mapX(result.rho2), mapY(cappedBoundary));
    profilePath.lineTo(mapX(result.rho2), mapY(depthMax));
    canvas.drawPath(
      profilePath,
      pw.Paint()
        ..color = _pdfOrange
        ..strokeWidth = 1.2
        ..style = pw.PaintingStyle.stroke,
    );

    if (result.predictedRho.isNotEmpty && result.measurementDepthsM.isNotEmpty) {
      final predictedPath = pw.Path();
      for (var i = 0; i < result.predictedRho.length; i++) {
        final rho = result.predictedRho[i];
        if (!rho.isFinite || rho <= 0) {
          continue;
        }
        final depth = i < result.measurementDepthsM.length
            ? result.measurementDepthsM[i]
            : result.measurementDepthsM.last;
        final point = pw.Offset(mapX(rho), mapY(depth));
        if (predictedPath.isEmpty) {
          predictedPath.moveTo(point.x, point.y);
        } else {
          predictedPath.lineTo(point.x, point.y);
        }
      }
      canvas.drawPath(
        predictedPath,
        pw.Paint()
          ..color = _pdfBlue
          ..strokeWidth = 0.9
          ..style = pw.PaintingStyle.stroke
          ..dashPattern = const [4, 2],
      );
    }

    for (var i = 0; i < result.observedRho.length; i++) {
      final rho = result.observedRho[i];
      if (!rho.isFinite || rho <= 0) {
        continue;
      }
      final depth = i < result.measurementDepthsM.length
          ? result.measurementDepthsM[i]
          : (result.measurementDepthsM.isEmpty ? 0 : result.measurementDepthsM.last);
      final center = pw.Offset(mapX(rho), mapY(depth));
      canvas.drawCircle(
        center,
        2.2,
        pw.Paint()
          ..color = _pdfGray
          ..style = pw.PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _InversionPdfPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.distanceUnit != distanceUnit;
  }

  List<double> _buildDepthTicks(double depth) {
    const tickCount = 4;
    final step = depth / tickCount;
    return List<double>.generate(tickCount + 1, (index) => index * step);
  }

  List<int> _buildResistivityTicks(double minLog, double maxLog) {
    final start = minLog.floor();
    final end = maxLog.ceil();
    return [for (var i = start; i <= end; i++) i];
  }

  String _unitLabel(DistanceUnit unit) => unit == DistanceUnit.feet ? 'ft' : 'm';
}
