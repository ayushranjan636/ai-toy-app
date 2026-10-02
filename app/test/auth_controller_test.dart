import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zivoo/core/providers.dart';
import 'package:zivoo/core/storage.dart';
import 'package:zivoo/features/auth/application/auth_controller.dart';
import 'package:zivoo/features/auth/domain/auth.dart';

import 'fakes.dart';

Future<AuthState> settle(ProviderContainer c) async {
  c.read(authControllerProvider);
  for (var i = 0; i < 20 && c.read(authControllerProvider) is AuthUnknown; i++) {
    await Future<void>.delayed(Duration.zero);
  }
  return c.read(authControllerProvider);
}

void main() {
  late MemorySecureStore secure;
  late FakeAuthRepository repo;

  ProviderContainer make() => ProviderContainer(
    overrides: [
      secureStoreProvider.overrideWithValue(secure),
      authRepositoryProvider.overrideWithValue(repo),
    ],
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    secure = MemorySecureStore();
    repo = FakeAuthRepository();
  });

  test('no stored session -> signed out', () async {
    expect(await settle(make()), isA<SignedOut>());
  });

  test('sign in stores session in secure storage and restores on restart', () async {
    final c = make();
    await settle(c);
    await c.read(authControllerProvider.notifier).signIn('parent@example.com', 'correct-horse');
    expect(c.read(authControllerProvider), isA<SignedIn>());
    final raw = secure.values['zivoo.auth.session']!;
    expect(jsonDecode(raw)['a'], 'token-parent@example.com');

    final again = make();
    final s = await settle(again);
    expect(s, isA<SignedIn>());
    expect(repo.refreshes, 0);
  });

  test('expired stored session is refreshed on launch', () async {
    secure.values['zivoo.auth.session'] = jsonEncode(
      AuthSession(
        accessToken: 'old',
        refreshToken: 'r',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        email: 'parent@example.com',
        emailVerified: true,
      ).toJson(),
    );
    final s = await settle(make());
    expect(s, isA<SignedIn>());
    expect(repo.refreshes, 1);
  });

  test('refresh rejected -> signed out with expired notice, secrets cleared', () async {
    repo.refreshFails = true;
    secure.values['zivoo.auth.session'] = jsonEncode(
      AuthSession(
        accessToken: 'old',
        refreshToken: 'r',
        expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
        email: 'parent@example.com',
        emailVerified: true,
      ).toJson(),
    );
    final s = await settle(make());
    expect(s, isA<SignedOut>());
    expect((s as SignedOut).expired, isTrue);
    expect(secure.values, isEmpty);
  });

  test('wrong password surfaces a friendly error and stays signed out', () async {
    final c = make();
    await settle(c);
    await expectLater(
      c.read(authControllerProvider.notifier).signIn('parent@example.com', 'nope'),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', contains("don't match"))),
    );
    expect(c.read(authControllerProvider), isA<SignedOut>());
  });

  test('sign up requires verification before a session exists', () async {
    final c = make();
    await settle(c);
    await c.read(authControllerProvider.notifier).signUp('new@example.com', 'long-enough-pw');
    expect(c.read(authControllerProvider), isA<AwaitingVerification>());
    expect(secure.values, isEmpty);
    await c.read(authControllerProvider.notifier).verify('new@example.com', '123456');
    expect(c.read(authControllerProvider), isA<SignedIn>());
  });

  test('sign out clears tokens and family cache', () async {
    final c = make();
    await settle(c);
    await c.read(authControllerProvider.notifier).signIn('parent@example.com', 'correct-horse');
    final local = c.read(localStoreProvider);
    await local.writeCached('children', [1, 2]);
    await c.read(authControllerProvider.notifier).signOut();
    expect(secure.values, isEmpty);
    expect(await local.readCached('children'), isNull);
    expect(c.read(authControllerProvider), isA<SignedOut>());
  });

  test('concurrent 401s trigger a single refresh', () async {
    final c = make();
    await settle(c);
    await c.read(authControllerProvider.notifier).signIn('parent@example.com', 'correct-horse');
    final ctl = c.read(authControllerProvider.notifier);
    final results = await Future.wait([ctl.refreshAfterUnauthorized(), ctl.refreshAfterUnauthorized()]);
    expect(results.every((r) => r != null), isTrue);
    expect(repo.refreshes, 1);
  });

  test('session toString never includes tokens', () {
    final s = AuthSession(
      accessToken: 'SECRET',
      refreshToken: 'R',
      expiresAt: DateTime.now(),
      email: 'a@b.co',
      emailVerified: true,
    );
    expect(s.toString(), isNot(contains('SECRET')));
  });

  test('validators', () {
    expect(validateEmail(''), isNotNull);
    expect(validateEmail('nope'), isNotNull);
    expect(validateEmail('a@b.co'), isNull);
    expect(validateNewPassword('short'), isNotNull);
    expect(validateNewPassword('long enough pw'), isNull);
  });
}
