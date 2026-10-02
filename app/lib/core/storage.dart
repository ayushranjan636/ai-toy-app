import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure key-value store (Keychain / Android Keystore-backed). Used only for
/// session credentials.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecureStore implements SecureStore {
  const PlatformSecureStore();

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemorySecureStore implements SecureStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Non-secret local data: cached summaries (with timestamps), setup progress
/// checkpoints and the offline outbox. Everything is namespaced so it can be
/// wiped on sign-out. Never stores passwords, tokens or setup codes.
class LocalStore {
  LocalStore(this._prefs);

  final SharedPreferencesAsync _prefs;
  static const _prefix = 'zivoo.family.';

  Future<CachedValue?> readCached(String key) async {
    final raw = await _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CachedValue(map['v'], DateTime.parse(map['t'] as String));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCached(String key, Object? value) => _prefs.setString(
    '$_prefix$key',
    jsonEncode({'v': value, 't': DateTime.now().toUtc().toIso8601String()}),
  );

  Future<void> remove(String key) => _prefs.remove('$_prefix$key');

  /// Remove all family-specific data (on sign-out / account deletion).
  Future<void> clearFamilyData() async {
    final keys = await _prefs.getKeys();
    for (final k in keys.where((k) => k.startsWith(_prefix))) {
      await _prefs.remove(k);
    }
  }
}

class CachedValue {
  const CachedValue(this.value, this.savedAt);

  final Object? value;
  final DateTime savedAt;
}
