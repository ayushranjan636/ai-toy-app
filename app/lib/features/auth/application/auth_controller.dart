import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/providers.dart';
import '../domain/auth.dart';

sealed class AuthState {
  const AuthState();
}

class AuthUnknown extends AuthState {
  const AuthUnknown();
}

class SignedOut extends AuthState {
  const SignedOut({this.expired = false});

  /// True when the session ended because it expired (show a gentle notice).
  final bool expired;
}

/// Account created but email not yet verified.
class AwaitingVerification extends AuthState {
  const AwaitingVerification(this.email);

  final String email;
}

class SignedIn extends AuthState {
  const SignedIn(this.session);

  final AuthSession session;
}

const _sessionKey = 'zivoo.auth.session';

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends Notifier<AuthState> implements TokenProvider {
  Completer<String?>? _refreshing;

  @override
  AuthState build() {
    unawaited(_restore());
    return const AuthUnknown();
  }

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _restore() async {
    final stored = AuthSession.tryParse(await ref.read(secureStoreProvider).read(_sessionKey));
    if (stored == null) {
      state = const SignedOut();
      return;
    }
    if (!stored.isExpired) {
      state = SignedIn(stored);
      return;
    }
    try {
      await _setSession(await _repo.refresh(stored));
    } on AuthException catch (e) {
      if (e.code == 'offline') {
        // Keep the user in; requests will retry refresh when back online.
        state = SignedIn(stored);
      } else {
        await _clear(expired: true);
      }
    }
  }

  Future<void> _setSession(AuthSession s) async {
    await ref.read(secureStoreProvider).write(_sessionKey, s.toJsonString());
    state = SignedIn(s);
  }

  Future<void> signUp(String email, String password) async {
    final r = await _repo.signUp(email: email.trim(), password: password);
    switch (r) {
      case SignUpSignedIn(:final session):
        await _setSession(session);
      case SignUpNeedsVerification(:final email):
        state = AwaitingVerification(email);
    }
  }

  Future<void> verify(String email, String code) async =>
      _setSession(await _repo.verifyEmail(email: email, code: code.trim()));

  Future<void> resendVerification(String email) => _repo.resendVerification(email);

  Future<void> signIn(String email, String password) async {
    try {
      await _setSession(await _repo.signIn(email: email.trim(), password: password));
    } on AuthException catch (e) {
      if (e.code == 'email_not_confirmed') {
        state = AwaitingVerification(email.trim());
        return;
      }
      rethrow;
    }
  }

  Future<void> requestReset(String email) => _repo.requestPasswordReset(email.trim());

  Future<void> resetPassword(String email, String code, String password) async =>
      _setSession(await _repo.resetPassword(email: email.trim(), code: code.trim(), newPassword: password));

  Future<void> signOut() async {
    final s = state;
    if (s is SignedIn) await _repo.signOut(s.session);
    await _clear();
  }

  /// Back to Welcome from the verify screen without an account session.
  void abandonVerification() => state = const SignedOut();

  Future<void> _clear({bool expired = false}) async {
    await ref.read(secureStoreProvider).delete(_sessionKey);
    await ref.read(localStoreProvider).clearFamilyData();
    state = SignedOut(expired: expired);
  }

  // ---------------------------------------------------------------- TokenProvider

  @override
  Future<String?> accessToken() async {
    final s = state;
    if (s is! SignedIn) return null;
    if (s.session.isExpired) return refreshAfterUnauthorized();
    return s.session.accessToken;
  }

  @override
  Future<String?> refreshAfterUnauthorized() async {
    final s = state;
    if (s is! SignedIn) return null;
    if (_refreshing != null) return _refreshing!.future; // single-flight
    final c = _refreshing = Completer<String?>();
    try {
      final fresh = await _repo.refresh(s.session);
      await _setSession(fresh);
      c.complete(fresh.accessToken);
    } on AuthException catch (e) {
      c.complete(e.code == 'offline' ? s.session.accessToken : null);
    } catch (_) {
      c.complete(null);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  @override
  void onSessionExpired() {
    if (state is SignedIn) unawaited(_clear(expired: true));
  }
}

extension on AuthSession {
  String toJsonString() => jsonEncode(toJson());
}
