import 'dart:io';

import 'package:csv/csv.dart';

import '../models/calc.dart';
import '../models/direction_reading.dart';
import '../models/project.dart';
import '../models/site.dart';
import 'storage_service.dart';

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
