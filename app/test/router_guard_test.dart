import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zivoo/app/router.dart';
import 'package:zivoo/core/models.dart';
import 'package:zivoo/features/auth/application/auth_controller.dart';
import 'package:zivoo/features/auth/domain/auth.dart';

ParentProfile profile(OnboardingStep step) => ParentProfile(
  id: 'p',
  email: 'a@b.co',
  marketingOptIn: false,
  storeTranscripts: false,
  productAnalytics: false,
  dataChoicesConfirmed: true,
  onboardingStep: step,
  notifySessionSummaries: true,
  notifyDeviceOffline: true,
);

final signedIn = SignedIn(
  AuthSession(
    accessToken: 'a',
    refreshToken: 'r',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    email: 'a@b.co',
    emailVerified: true,
  ),
);

String? go(AuthState auth, String to, [AsyncValue<ParentProfile>? me]) =>
    resolveRedirect(auth: auth, me: me ?? const AsyncLoading(), location: to);

void main() {
  test('unknown auth shows splash', () {
    expect(go(const AuthUnknown(), '/home'), '/splash');
  });

  test('signed out users can only reach public routes', () {
    expect(go(const SignedOut(), '/home'), '/welcome');
    expect(go(const SignedOut(), '/settings/account'), '/welcome');
    expect(go(const SignedOut(), '/sign-in'), isNull);
    expect(go(const SignedOut(), '/reset?email=a'), isNull);
  });

  test('awaiting verification is pinned to verify', () {
    expect(go(const AwaitingVerification('a@b.co'), '/home'), '/verify');
  });

  test('returning user who finished onboarding goes straight home', () {
    final me = AsyncData(profile(OnboardingStep.done));
    expect(go(signedIn, '/splash', me), '/home');
    expect(go(signedIn, '/sign-in', me), '/home');
    expect(go(signedIn, '/progress', me), isNull);
  });

  test('interrupted setup resumes at the last confirmed step', () {
    expect(go(signedIn, '/home', AsyncData(profile(OnboardingStep.intro))), '/onboarding/intro');
    expect(go(signedIn, '/home', AsyncData(profile(OnboardingStep.connectToy))), '/setup');
    expect(go(signedIn, '/splash', AsyncData(profile(OnboardingStep.childProfile))), '/onboarding/child');
    expect(go(signedIn, '/home', AsyncData(profile(OnboardingStep.preferences))), '/onboarding/preferences');
    // Moving within onboarding is allowed.
    expect(go(signedIn, '/onboarding/child', AsyncData(profile(OnboardingStep.connectToy))), isNull);
  });

  test('profile still loading keeps the splash', () {
    expect(go(signedIn, '/home'), '/splash');
  });

  test('backend unreachable: signed-in user reaches the shell with offline states', () {
    final me = AsyncError<ParentProfile>(Exception('offline'), StackTrace.empty);
    expect(go(signedIn, '/splash', me), '/home');
    expect(go(signedIn, '/home', me), isNull);
  });
}
