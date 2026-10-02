import 'package:flutter/foundation.dart';

/// Build-time configuration via --dart-define. No secrets live in the app:
/// the Supabase anon key is a public client identifier, not a secret.
abstract final class AppConfig {
  static const apiBase = String.fromEnvironment('ZIVOO_API_BASE', defaultValue: 'http://localhost:8000');

  /// `supabase` (default) or `dev`. `dev` is ignored in release builds.
  static const _authMode = String.fromEnvironment('ZIVOO_AUTH', defaultValue: 'supabase');
  static const supabaseUrl = String.fromEnvironment('ZIVOO_SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('ZIVOO_SUPABASE_ANON_KEY');

  static bool get useDevAuth => !kReleaseMode && _authMode == 'dev';

  /// The device simulator is compiled out of release builds: in release this
  /// is a const `false`, so simulator branches are tree-shaken.
  static const simulatorEnabled =
      !kReleaseMode && bool.fromEnvironment('ZIVOO_SIMULATOR', defaultValue: true);
}
