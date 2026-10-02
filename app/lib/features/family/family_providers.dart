import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_error.dart';
import '../../core/api/zivoo_api.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/storage.dart';
import '../../core/util.dart';
import '../auth/application/auth_controller.dart';

/// Value + where it came from, so screens can say "Updated 5 minutes ago".
class Fresh<T> {
  const Fresh(this.value, {this.cachedAt, this.offline = false});

  final T value;

  /// Non-null when shown from cache.
  final DateTime? cachedAt;
  final bool offline;
}

/// Fetch with a cache fallback. Cache is per-family and wiped on sign-out.
Future<Fresh<T>> cachedFetch<T>({
  required LocalStore store,
  required String key,
  required Future<T> Function() fetch,
  required Object? Function(T) encode,
  required T Function(Object?) decode,
}) async {
  try {
    final v = await fetch();
    unawaited(store.writeCached(key, encode(v)));
    return Fresh(v);
  } on ApiException catch (e) {
    if (!e.isOffline) rethrow;
    final c = await store.readCached(key);
    if (c == null) rethrow;
    return Fresh(decode(c.value), cachedAt: c.savedAt, offline: true);
  }
}

/// Invalidate family data when the signed-in account changes.
final _accountKey = Provider<String?>((ref) {
  final s = ref.watch(authControllerProvider);
  return s is SignedIn ? s.session.email : null;
});

final meProvider = FutureProvider<ParentProfile>((ref) {
  ref.watch(_accountKey);
  return ref.watch(apiProvider).me();
});

final childrenProvider = FutureProvider<Fresh<List<Child>>>((ref) {
  ref.watch(_accountKey);
  final api = ref.watch(apiProvider);
  return cachedFetch(
    store: ref.read(localStoreProvider),
    key: 'children',
    fetch: api.children,
    encode: (l) => [for (final c in l) c.toJson()],
    decode: (o) => [for (final j in o as List) Child.fromJson((j as Map).cast())],
  );
});

final devicesProvider = FutureProvider<Fresh<List<Device>>>((ref) {
  ref.watch(_accountKey);
  final api = ref.watch(apiProvider);
  return cachedFetch(
    store: ref.read(localStoreProvider),
    key: 'devices',
    fetch: api.devices,
    encode: (l) => [for (final d in l) d.toJson()],
    decode: (o) => [for (final j in o as List) Device.fromJson((j as Map).cast())],
  );
});

final activitiesProvider = FutureProvider<List<Activity>>((ref) {
  ref.watch(_accountKey);
  return ref.watch(apiProvider).activities();
});

/// Which child the parent is looking at. Defaults to the device's active
/// child, else the first child.
class SelectedChild extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final selectedChildIdProvider = NotifierProvider<SelectedChild, String?>(SelectedChild.new);

final activeChildProvider = Provider<Child?>((ref) {
  final children = ref.watch(childrenProvider).value?.value ?? const [];
  if (children.isEmpty) return null;
  final selected = ref.watch(selectedChildIdProvider);
  final device = ref.watch(devicesProvider).value?.value.firstOrNull;
  final id = selected ?? device?.activeChildId;
  return children.where((c) => c.id == id).firstOrNull ?? children.first;
});

final recentSessionsProvider = FutureProvider.family<Fresh<List<SessionSummary>>, String>((ref, childId) {
  final api = ref.watch(apiProvider);
  return cachedFetch(
    store: ref.read(localStoreProvider),
    key: 'sessions.$childId',
    fetch: () async => (await api.sessions(childId: childId, limit: 5)).items,
    encode: (l) => [for (final s in l) s.toJson()],
    decode: (o) => [for (final j in o as List) SessionSummary.fromJson((j as Map).cast())],
  );
});

final sessionDetailProvider = FutureProvider.autoDispose.family<SessionDetail, String>(
  (ref, id) => ref.watch(apiProvider).session(id),
);

// ----------------------------------------------------------------- preferences with offline outbox

/// Local edit state for a child's preferences.
class PrefsState {
  const PrefsState({
    required this.server,
    required this.draft,
    this.pendingUpload = false,
    this.conflict = false,
  });

  final LearningPreferences server;
  final Map<String, dynamic> draft;

  /// Saved on this phone, not yet accepted by the server (offline).
  final bool pendingUpload;

  /// Another phone changed settings first; the parent must reload.
  final bool conflict;
}

/// Persists edits locally first, then uploads. If offline, the edit stays in
/// the outbox (with the base version) and is retried later. The server's
/// version check prevents a stale phone from overwriting newer settings.
class PreferencesController extends AsyncNotifier<PrefsState> {
  PreferencesController(this.arg);

  final String arg;

  ZivooApi get _api => ref.read(apiProvider);
  LocalStore get _store => ref.read(localStoreProvider);
  String get _outboxKey => 'outbox.prefs.$arg';

  @override
  Future<PrefsState> build() async {
    final childId = arg;
    final server = await _api.preferences(childId);
    final pending = await _store.readCached(_outboxKey);
    if (pending != null) {
      final m = (pending.value as Map).cast<String, dynamic>();
      final s = PrefsState(
        server: server,
        draft: (m['payload'] as Map).cast<String, dynamic>(),
        pendingUpload: true,
      );
      unawaited(Future.microtask(flush));
      return s;
    }
    return PrefsState(server: server, draft: _deepCopy(server.payload));
  }

  Future<void> save(Map<String, dynamic> draft) async {
    final current = state.value;
    if (current == null) return;
    await _store.writeCached(_outboxKey, {'payload': draft, 'base': current.server.version});
    state = AsyncData(PrefsState(server: current.server, draft: draft, pendingUpload: true));
    await flush();
  }

  /// Upload the outbox with bounded retries. Safe to call repeatedly.
  Future<void> flush({Backoff? backoff}) async {
    final pending = await _store.readCached(_outboxKey);
    if (pending == null) return;
    final m = (pending.value as Map).cast<String, dynamic>();
    final payload = (m['payload'] as Map).cast<String, dynamic>();
    final base = m['base'] as int;
    final b = backoff ?? Backoff(maxAttempts: 3);
    for (var attempt = 1; ; attempt++) {
      try {
        final saved = await _api.savePreferences(arg, payload, base);
        await _store.remove(_outboxKey);
        state = AsyncData(PrefsState(server: saved, draft: _deepCopy(saved.payload)));
        ref.invalidate(devicesProvider); // sync status changes to pending
        return;
      } on ApiException catch (e) {
        if (e.isConflict) {
          await _store.remove(_outboxKey);
          final server = await _api.preferences(arg);
          state = AsyncData(PrefsState(server: server, draft: _deepCopy(server.payload), conflict: true));
          return;
        }
        final delay = b.delayFor(attempt);
        if (!e.isOffline || delay == null) {
          final cur = state.value;
          if (cur != null) {
            state = AsyncData(PrefsState(server: cur.server, draft: payload, pendingUpload: true));
          }
          return;
        }
        await Future<void>.delayed(delay);
      }
    }
  }
}

final preferencesProvider = AsyncNotifierProvider.family<PreferencesController, PrefsState, String>(
  PreferencesController.new,
);

Map<String, dynamic> _deepCopy(Map<String, dynamic> m) => {
  for (final e in m.entries)
    e.key: e.value is Map
        ? _deepCopy((e.value as Map).cast<String, dynamic>())
        : (e.value is List ? List.of(e.value as List) : e.value),
};

Map<String, dynamic> deepCopyPrefs(Map<String, dynamic> m) => _deepCopy(m);
