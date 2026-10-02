import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zivoo/core/api/api_error.dart';
import 'package:zivoo/core/providers.dart';
import 'package:zivoo/core/storage.dart';
import 'package:zivoo/core/util.dart';
import 'package:zivoo/features/family/family_providers.dart';

import 'fakes.dart';

void main() {
  late FakeApi api;
  late ProviderContainer c;
  final secure = MemorySecureStore();

  ProviderContainer make() => ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      apiProvider.overrideWithValue(api),
      secureStoreProvider.overrideWithValue(secure),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    ],
  );

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    api = FakeApi();
    c = make();
  });

  tearDown(() => c.dispose());

  final fastBackoff = Backoff(base: Duration.zero, max: Duration.zero, maxAttempts: 2);

  test('edit saved offline stays in the outbox and uploads once when online', () async {
    final ctl = c.read(preferencesProvider('child-1').notifier);
    await c.read(preferencesProvider('child-1').future);

    api.offline = true;
    final draft = deepCopyPrefs(c.read(preferencesProvider('child-1')).value!.draft)
      ..['daily_limit_minutes'] = 45;
    await ctl.save(draft);
    var s = c.read(preferencesProvider('child-1')).value!;
    expect(s.pendingUpload, isTrue);
    expect(s.draft['daily_limit_minutes'], 45);
    expect(api.saves, 0);

    // App restarts while offline: the outbox survives.
    c.dispose();
    c = make();
    api.offline = false;
    await c.read(preferencesProvider('child-1').future);
    await c.read(preferencesProvider('child-1').notifier).flush(backoff: fastBackoff);
    s = c.read(preferencesProvider('child-1')).value!;
    expect(api.saves, 1);
    expect(api.lastBaseVersion, 1);
    expect(s.pendingUpload, isFalse);
    expect(s.server.version, 2);
    expect(s.server.payload['daily_limit_minutes'], 45);

    // Flushing again is a no-op (no duplicate upload).
    await c.read(preferencesProvider('child-1').notifier).flush(backoff: fastBackoff);
    expect(api.saves, 1);
  });

  test('conflict with a newer edit from another phone keeps the server version', () async {
    await c.read(preferencesProvider('child-1').future);
    api.conflictNext = true;
    final draft = deepCopyPrefs(c.read(preferencesProvider('child-1')).value!.draft)
      ..['daily_limit_minutes'] = 90;
    await c.read(preferencesProvider('child-1').notifier).save(draft);
    final s = c.read(preferencesProvider('child-1')).value!;
    expect(s.conflict, isTrue);
    expect(s.pendingUpload, isFalse);
    expect(s.draft['daily_limit_minutes'], 30);
  });

  test('cached children are shown offline with a timestamp', () async {
    final first = await c.read(childrenProvider.future);
    expect(first.offline, isFalse);
    api.offline = true;
    c.invalidate(childrenProvider);
    final second = await c.read(childrenProvider.future);
    expect(second.offline, isTrue);
    expect(second.cachedAt, isNotNull);
    expect(second.value.single.displayName, 'Maya');
  });

  test('sign-out clears family cache', () async {
    await c.read(childrenProvider.future);
    await c.read(localStoreProvider).clearFamilyData();
    api.offline = true;
    c.invalidate(childrenProvider);
    await expectLater(c.read(childrenProvider.future), throwsA(isA<ApiException>()));
  });

  test('backoff is bounded', () {
    final b = Backoff(maxAttempts: 3);
    expect(b.delayFor(1), isNotNull);
    expect(b.delayFor(3)!.inMilliseconds, lessThanOrEqualTo(4800));
    expect(b.delayFor(4), isNull);
  });
}
