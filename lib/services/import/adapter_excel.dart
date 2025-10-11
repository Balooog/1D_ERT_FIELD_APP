import 'package:excel/excel.dart';

import 'import_adapter.dart';
import 'import_models.dart';

class ExcelImportAdapter implements ImportAdapter {
  const ExcelImportAdapter();

  @override
  Future<ImportTable> parse(ImportSource source) async {
    final excel = Excel.decodeBytes(source.bytes);
    if (excel.tables.isEmpty) {
      return ImportTable(headers: const [], rows: const []);
    }
    Sheet? sheet;
    if (source.explicitSheet != null) {
      sheet = excel.tables[source.explicitSheet];
    }
    sheet ??= excel.tables.values.first;

    final issues = <ImportRowIssue>[];
    List<String>? header;
    final rows = <List<String>>[];
    String? unitDirective;

    for (var i = 0; i < sheet.maxRows; i++) {
      final row = sheet.row(i);
      final values = row
          .map((cell) => cell?.value == null ? '' : cell!.value.toString().trim())
          .toList();
      final hasData = values.any((value) => value.isNotEmpty);
      if (!hasData) {
        continue;
      }
      final firstLower = values.first.toLowerCase();
      if (firstLower.startsWith('unit=')) {
        final equalsIndex = values.first.indexOf('=');
        unitDirective = equalsIndex >= 0 ? values.first.substring(equalsIndex + 1).trim() : null;
        continue;
      }
      if (header == null) {
        header = [
          for (var col = 0; col < values.length; col++)
            values[col].isEmpty ? 'Column ${col + 1}' : values[col],
        ];
        continue;
      }
      if (values.length < header.length) {
        values.addAll(List.filled(header.length - values.length, ''));
      } else if (values.length > header.length) {
        issues.add(ImportRowIssue(index: i + 1, message: 'Row has more columns than header.')); 
        values.removeRange(header.length, values.length);
      }
      rows.add(values);
    }

    header ??= const [];
    return ImportTable(headers: header, rows: rows, issues: issues, unitDirective: unitDirective);
  }
}
