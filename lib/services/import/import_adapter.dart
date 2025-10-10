import 'import_models.dart';

abstract class ImportAdapter {
  Future<ImportTable> parse(ImportSource source);
}
