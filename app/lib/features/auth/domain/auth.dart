import 'dart:convert';

/// Session as stored in secure storage.
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.email,
    required this.emailVerified,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String email;
  final bool emailVerified;

  bool get isExpired => DateTime.now().isAfter(expiresAt.subtract(const Duration(seconds: 30)));

  Map<String, dynamic> toJson() => {
    'a': accessToken,
    'r': refreshToken,
    'e': expiresAt.toUtc().toIso8601String(),
    'm': email,
    'v': emailVerified,
  };

  static AuthSession? tryParse(String? raw) {
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AuthSession(
        accessToken: j['a'] as String,
        refreshToken: j['r'] as String,
        expiresAt: DateTime.parse(j['e'] as String),
        email: j['m'] as String,
        emailVerified: j['v'] as bool,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'AuthSession(email: $email, verified: $emailVerified)'; // no tokens
}

class AuthException implements Exception {
  const AuthException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code)';
}

/// Result of sign-up: either a session (verification disabled on the IdP)
/// or a pending verification.
sealed class SignUpResult {
  const SignUpResult();
}

class SignUpNeedsVerification extends SignUpResult {
  const SignUpNeedsVerification(this.email);

  final String email;
}

class SignUpSignedIn extends SignUpResult {
  const SignUpSignedIn(this.session);

  final AuthSession session;
}

/// Managed identity provider. Implementations never log credentials.
abstract interface class AuthRepository {
  Future<SignUpResult> signUp({required String email, required String password});
  Future<AuthSession> verifyEmail({required String email, required String code});
  Future<void> resendVerification(String email);
  Future<AuthSession> signIn({required String email, required String password});
  Future<void> requestPasswordReset(String email);
  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });
  Future<AuthSession> refresh(AuthSession session);
  Future<void> signOut(AuthSession session);
}

String? validateEmail(String? v) {
  final s = v?.trim() ?? '';
  if (s.isEmpty) return 'Enter your email address.';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s)) {
    return "That doesn't look like an email address.";
  }
  return null;
}

String? validateNewPassword(String? v) {
  final s = v ?? '';
  if (s.length < 10) return 'Use at least 10 characters.';
  if (s.length > 128) return 'Use 128 characters or fewer.';
  return null;
}
