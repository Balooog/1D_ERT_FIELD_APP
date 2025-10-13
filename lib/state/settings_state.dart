import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsState {
  const SettingsState({
    this.devScreenshotEnabled = false,
  });

  final bool devScreenshotEnabled;

  SettingsState copyWith({
    bool? devScreenshotEnabled,
  }) {
    return SettingsState(
      devScreenshotEnabled: devScreenshotEnabled ?? this.devScreenshotEnabled,
    );
  }
}

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController() : super(const SettingsState());

  void setDevScreenshotEnabled(bool value) {
    if (state.devScreenshotEnabled == value) {
      return;
    }
    state = state.copyWith(devScreenshotEnabled: value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  return SettingsController();
});
