import 'package:dio/dio.dart';

import '../domain/auth.dart';

/// Supabase Auth (GoTrue) over REST. Email verification and password recovery
/// use 6-digit email codes (configure the Supabase email templates to include
/// `{{ .Token }}`). Tokens are returned to the caller, which stores them in
/// platform secure storage.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required String url, required String anonKey, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$url/auth/v1',
              headers: {'apikey': anonKey},
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              contentType: 'application/json',
            ),
          );

  final Dio _dio;

  @override
  Future<SignUpResult> signUp({required String email, required String password}) async {
    final data = await _call(() => _dio.post('/signup', data: {'email': email, 'password': password}));
    if (data['access_token'] != null) return SignUpSignedIn(_session(data));
    return SignUpNeedsVerification(email);
  }

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) async => _session(
    await _call(() => _dio.post('/verify', data: {'type': 'email', 'email': email, 'token': code})),
  );

  @override
  Future<void> resendVerification(String email) =>
      _call(() => _dio.post('/resend', data: {'type': 'signup', 'email': email}));

  @override
  Future<AuthSession> signIn({required String email, required String password}) async => _session(
    await _call(
      () => _dio.post(
        '/token',
        queryParameters: {'grant_type': 'password'},
        data: {'email': email, 'password': password},
      ),
    ),
  );

  @override
  Future<void> requestPasswordReset(String email) =>
      _call(() => _dio.post('/recover', data: {'email': email}));

  @override
  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final s = _session(
      await _call(() => _dio.post('/verify', data: {'type': 'recovery', 'email': email, 'token': code})),
    );
    await _call(
      () => _dio.put(
        '/user',
        data: {'password': newPassword},
        options: Options(headers: {'authorization': 'Bearer ${s.accessToken}'}),
      ),
    );
    return s;
  }

  @override
  Future<AuthSession> refresh(AuthSession session) async => _session(
    await _call(
      () => _dio.post(
        '/token',
        queryParameters: {'grant_type': 'refresh_token'},
        data: {'refresh_token': session.refreshToken},
      ),
    ),
  );

  @override
  Future<void> signOut(AuthSession session) async {
    try {
      await _dio.post(
        '/logout',
        options: Options(headers: {'authorization': 'Bearer ${session.accessToken}'}),
      );
    } catch (_) {
      // Local sign-out proceeds even if the network call fails.
    }
  }

  AuthSession _session(Map<String, dynamic> d) {
    final user = (d['user'] as Map?) ?? const {};
    return AuthSession(
      accessToken: d['access_token'] as String,
      refreshToken: d['refresh_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: (d['expires_in'] as num?)?.toInt() ?? 3600)),
      email: '${user['email'] ?? ''}',
      emailVerified: user['email_confirmed_at'] != null,
    );
  }

  Future<Map<String, dynamic>> _call(Future<Response<dynamic>> Function() f) async {
    try {
      final r = await f();
      return r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : {};
    } on DioException catch (e) {
      if (e.response == null) {
        throw const AuthException('offline', "You're offline. Check your connection.");
      }
      final d = e.response?.data;
      final code = d is Map ? '${d['error_code'] ?? d['code'] ?? d['error'] ?? ''}' : '';
      throw AuthException(code, _message(code, e.response?.statusCode));
    }
  }

  static String _message(String code, int? status) => switch (code) {
    'invalid_credentials' || 'invalid_grant' => "That email and password don't match.",
    'email_not_confirmed' => 'Verify your email to continue.',
    'user_already_exists' || 'email_exists' => 'An account with this email already exists.',
    'weak_password' => 'Choose a longer password.',
    'otp_expired' => 'That code has expired. Send a new one.',
    'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Please wait a minute before trying again.',
    _ when status == 429 => 'Please wait a minute before trying again.',
    _ => "We couldn't complete that. Try again.",
  };
}
