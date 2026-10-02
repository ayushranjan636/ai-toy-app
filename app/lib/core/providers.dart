import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/auth/application/auth_controller.dart';
import '../features/auth/data/dev_auth_repository.dart';
import '../features/auth/data/supabase_auth_repository.dart';
import '../features/auth/domain/auth.dart';
import 'api/api_client.dart';
import 'api/zivoo_api.dart';
import 'config.dart';
import 'storage.dart';

final secureStoreProvider = Provider<SecureStore>((_) => const PlatformSecureStore());

final localStoreProvider = Provider<LocalStore>((_) => LocalStore(SharedPreferencesAsync()));

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (AppConfig.useDevAuth) return DevAuthRepository(apiBase: AppConfig.apiBase);
  return SupabaseAuthRepository(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey);
});

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: AppConfig.apiBase, tokens: ref.read(authControllerProvider.notifier)),
);

final apiProvider = Provider<ZivooApi>((ref) => ZivooApi(ref.watch(apiClientProvider)));
