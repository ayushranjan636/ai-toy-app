import 'package:zivoo/core/api/api_client.dart';
import 'package:zivoo/core/api/api_error.dart';
import 'package:zivoo/core/api/zivoo_api.dart';
import 'package:zivoo/core/models.dart';
import 'package:zivoo/features/auth/domain/auth.dart';

class _NoTokens implements TokenProvider {
  @override
  Future<String?> accessToken() async => null;
  @override
  void onSessionExpired() {}
  @override
  Future<String?> refreshAfterUnauthorized() async => null;
}

Map<String, dynamic> defaultPayload() => {
  'daily_limit_minutes': 30,
  'quiet_start': null,
  'quiet_end': null,
  'activities': {
    for (final k in activityTitles.keys) k: {'enabled': true, 'difficulty': 'gentle', 'session_minutes': 10},
  },
  'maths': {
    'operations': ['addition'],
    'max_number': 10,
  },
  'spelling': {'words': <String>[]},
  'phonics': {
    'sounds': ['s', 'a', 't'],
  },
  'vocabulary': {
    'themes': ['animals'],
  },
  'stories': {
    'stories': ['the-lost-acorn'],
  },
};

/// In-memory backend for app tests. Behaves like the real API's contracts.
class FakeApi extends ZivooApi {
  FakeApi() : super(ApiClient(baseUrl: 'http://fake', tokens: _NoTokens()));

  bool offline = false;
  bool conflictNext = false;
  int saves = 0;
  int? lastBaseVersion;
  OnboardingStep step = OnboardingStep.done;
  final List<Child> kids = [const Child(id: 'child-1', displayName: 'Maya', language: 'en-GB')];
  final List<Device> devs = [];
  final List<SessionSummary> sessionList = [];
  LearningPreferences prefs = LearningPreferences(
    version: 1,
    payload: defaultPayload(),
    updatedAt: DateTime.utc(2026),
  );

  void _net() {
    if (offline) throw ApiException.offline;
  }

  @override
  Future<ParentProfile> me() async {
    _net();
    return ParentProfile(
      id: 'p1',
      email: 'parent@example.com',
      displayName: 'Sam',
      marketingOptIn: false,
      storeTranscripts: false,
      productAnalytics: false,
      dataChoicesConfirmed: true,
      onboardingStep: step,
      notifySessionSummaries: true,
      notifyDeviceOffline: true,
    );
  }

  @override
  Future<ParentProfile> updateMe(Map<String, dynamic> changes) async {
    _net();
    if (changes['onboarding_step'] != null) step = OnboardingStep.parse(changes['onboarding_step'] as String);
    return me();
  }

  @override
  Future<List<Child>> children() async {
    _net();
    return List.of(kids);
  }

  @override
  Future<List<Device>> devices() async {
    _net();
    return List.of(devs);
  }

  @override
  Future<List<Activity>> activities() async {
    _net();
    return [
      for (final e in activityTitles.entries)
        Activity(key: e.key, title: e.value, summary: '${e.value} summary', optionsSchema: const {}),
    ];
  }

  @override
  Future<LearningPreferences> preferences(String childId) async {
    _net();
    return prefs;
  }

  @override
  Future<LearningPreferences> savePreferences(
    String childId,
    Map<String, dynamic> payload,
    int baseVersion,
  ) async {
    _net();
    lastBaseVersion = baseVersion;
    if (conflictNext || baseVersion != prefs.version) {
      conflictNext = false;
      throw const ApiException('version_conflict', 'conflict', status: 409);
    }
    saves++;
    prefs = LearningPreferences(version: prefs.version + 1, payload: payload, updatedAt: DateTime.now());
    return prefs;
  }

  @override
  Future<Page<SessionSummary>> sessions({String? childId, String? cursor, int limit = 20}) async {
    _net();
    return Page(sessionList.where((s) => childId == null || s.childId == childId).take(limit).toList(), null);
  }
}

class FakeAuthRepository implements AuthRepository {
  final Map<String, String> accounts = {'parent@example.com': 'correct-horse'};
  int refreshes = 0;
  bool refreshFails = false;

  AuthSession _session(String email, {Duration ttl = const Duration(hours: 1)}) => AuthSession(
    accessToken: 'token-$email',
    refreshToken: 'refresh',
    expiresAt: DateTime.now().add(ttl),
    email: email,
    emailVerified: true,
  );

  @override
  Future<SignUpResult> signUp({required String email, required String password}) async {
    if (accounts.containsKey(email)) {
      throw const AuthException('user_already_exists', 'An account with this email already exists.');
    }
    accounts[email] = password;
    return SignUpNeedsVerification(email);
  }

  @override
  Future<AuthSession> verifyEmail({required String email, required String code}) async {
    if (code != '123456') throw const AuthException('otp_invalid', "That code isn't right.");
    return _session(email);
  }

  @override
  Future<void> resendVerification(String email) async {}

  @override
  Future<AuthSession> signIn({required String email, required String password}) async {
    if (accounts[email] != password) {
      throw const AuthException('invalid_credentials', "That email and password don't match.");
    }
    return _session(email);
  }

  @override
  Future<void> requestPasswordReset(String email) async {}

  @override
  Future<AuthSession> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async => _session(email);

  @override
  Future<AuthSession> refresh(AuthSession session) async {
    refreshes++;
    if (refreshFails) throw const AuthException('invalid_grant', 'expired');
    return _session(session.email);
  }

  @override
  Future<void> signOut(AuthSession session) async {}
}
