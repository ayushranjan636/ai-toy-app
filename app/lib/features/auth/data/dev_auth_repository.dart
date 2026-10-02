import 'package:dio/dio.dart';

import '../domain/auth.dart';

/// DEVELOPMENT ONLY. Simulates an identity provider against the backend's
/// /dev/auth/token endpoint (which exists only when ZIVOO_ENV=development).
/// Accounts live in memory; any 6-digit code "123456" verifies. Never used in
/// release builds (see AppConfig.useDevAuth).
class DevAuthRepository implements AuthRepository {
  DevAuthRepository({required String apiBase, Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: apiBase, contentType: 'application/json'));

  final Dio _dio;

  /// Fixed local test account (see backend/scripts/seed_demo.py).
  static const demoEmail = 'demo@example.com';
  static const demoPassword = 'zivoo-test-123';

  final Map<String, String> _passwords = {demoEmail: demoPassword};
  final Set<String> _verified = {demoEmail};
  static const devCode = '123456';

  @override
  Future<SignUpResult> signUp({required String email, required String password}) async {
    final e = email.toLowerCase();
    if (_passwords.containsKey(e)) {
      throw const AuthException('user_already_exists', 'An account with this email already exists.');
    }
    _passwords[e] = password;
    return SignUpNeedsVerification(e);
  }

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) async {
    if (code != devCode) {
      throw const AuthException('otp_invalid', "That code isn't right. Check the email and try again.");
    }
    _verified.add(email.toLowerCase());
    return _mint(email);
  }

  @override
  Future<void> resendVerification(String email) async {}

  @override
  Future<AuthSession> signIn({required String email, required String password}) async {
    final e = email.toLowerCase();
    // Dev convenience: unknown emails are created on first sign-in so a second
    // simulated phone can sign in to the same family.
    final stored = _passwords.putIfAbsent(e, () => password);
    if (stored != password) {
      throw const AuthException('invalid_credentials', "That email and password don't match.");
    }
    _verified.add(e);
    return _mint(e);
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    if (code != devCode) {
      throw const AuthException('otp_invalid', "That code isn't right.");
    }
    _passwords[email.toLowerCase()] = newPassword;
    return _mint(email);
  }

  @override
  Future<AuthSession> refresh(AuthSession session) => _mint(session.email);

  @override
  Future<void> signOut(AuthSession session) async {}

  Future<AuthSession> _mint(String email) async {
    try {
      final r = await _dio.post<Map<String, dynamic>>(
        '/dev/auth/token',
        data: {'email': email.toLowerCase(), 'email_verified': true, 'ttl_seconds': 3600},
      );
      return AuthSession(
        accessToken: r.data!['access_token'] as String,
        refreshToken: 'dev-refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
        email: email.toLowerCase(),
        emailVerified: true,
      );
    } on DioException {
      throw const AuthException('offline', "Can't reach the Zivoo service.");
    }
  }
}
