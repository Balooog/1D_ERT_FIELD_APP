import 'package:shared_preferences/shared_preferences.dart';

class TablePreferences {
  TablePreferences(this._prefs);

  static const String _askForSdKey = 'table.ask_for_sd';

  final SharedPreferences _prefs;

  bool get askForSd => _prefs.getBool(_askForSdKey) ?? true;

  Future<void> setAskForSd(bool value) async {
    await _prefs.setBool(_askForSdKey, value);
  }

  static Future<TablePreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    return TablePreferences(prefs);
  }
}
