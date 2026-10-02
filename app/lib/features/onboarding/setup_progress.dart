import 'package:shared_preferences/shared_preferences.dart';

/// Last *confirmed* onboarding step on this phone. The server's
/// `onboarding_step` is the source of truth across phones; this only helps
/// resume quickly and survives app restarts mid-setup. Never stores Wi-Fi
/// passwords, claim tokens or setup codes.
class SetupProgressStore {
  SetupProgressStore([SharedPreferencesAsync? prefs]) : _prefs = prefs ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _prefs;
  static const _skipKey = 'zivoo.family.setup.skippedToy';

  Future<bool> toySetupSkipped() async => await _prefs.getBool(_skipKey) ?? false;

  Future<void> setToySetupSkipped(bool v) => _prefs.setBool(_skipKey, v);
}
