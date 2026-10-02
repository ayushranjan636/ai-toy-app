import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/activities/activities_screens.dart';
import '../features/auth/application/auth_controller.dart';
import '../features/auth/presentation/auth_screens.dart';
import '../features/family/family_providers.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/progress/progress_screens.dart';
import '../features/provisioning/presentation/setup_flow.dart';
import '../features/settings/settings_screens.dart';
import '../core/models.dart';
import 'shell.dart';

/// Map server onboarding step to the route that resumes it.
String routeForStep(OnboardingStep s) => switch (s) {
  OnboardingStep.verifyEmail || OnboardingStep.intro => '/onboarding/intro',
  OnboardingStep.connectToy => '/setup',
  OnboardingStep.childProfile => '/onboarding/child',
  OnboardingStep.preferences => '/onboarding/preferences',
  OnboardingStep.done => '/home',
};

const _publicRoutes = {'/welcome', '/sign-up', '/sign-in', '/forgot', '/reset'};

/// Pure redirect logic (unit-tested).
String? resolveRedirect({
  required AuthState auth,
  required AsyncValue<ParentProfile> me,
  required String location,
}) {
  final path = Uri.parse(location).path;
  final isPublic = _publicRoutes.contains(path);
  switch (auth) {
    case AuthUnknown():
      return path == '/splash' ? null : '/splash';
    case SignedOut():
      return isPublic ? null : '/welcome';
    case AwaitingVerification():
      return path == '/verify' ? null : '/verify';
    case SignedIn():
      if (me.isLoading && !me.hasValue) return path == '/splash' ? null : '/splash';
      final profile = me.value;
      if (profile == null) {
        // Backend unreachable: let the shell show offline states.
        return (isPublic || path == '/splash' || path == '/verify') ? '/home' : null;
      }
      final step = profile.onboardingStep;
      final onboardingPaths = path.startsWith('/onboarding') || path.startsWith('/setup');
      if (step != OnboardingStep.done) {
        // Resume at the last confirmed step; allow moving within onboarding.
        if (onboardingPaths) return null;
        return routeForStep(step);
      }
      if (isPublic || path == '/splash' || path == '/verify') return '/home';
      return null;
  }
}

class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authControllerProvider, (_, _) => refresh.notify());
  ref.listen(meProvider, (_, _) => refresh.notify());
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) => resolveRedirect(
      auth: ref.read(authControllerProvider),
      me: ref.read(meProvider),
      location: state.uri.toString(),
    ),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/sign-up', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/sign-in', builder: (_, _) => const SignInScreen()),
      GoRoute(path: '/verify', builder: (_, _) => const VerifyEmailScreen()),
      GoRoute(path: '/forgot', builder: (_, _) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/reset',
        builder: (_, s) => ResetPasswordScreen(email: s.uri.queryParameters['email'] ?? ''),
      ),
      GoRoute(path: '/onboarding/intro', builder: (_, _) => const ParentIntroScreen()),
      GoRoute(path: '/onboarding/child', builder: (_, _) => const ChildProfileScreen()),
      GoRoute(path: '/onboarding/preferences', builder: (_, _) => const OnboardingPreferencesScreen()),
      GoRoute(
        path: '/setup',
        builder: (_, s) => SetupFlow(
          reprovisionDeviceId: s.uri.queryParameters['device'],
          fromOnboarding: s.uri.queryParameters['device'] == null,
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/activities',
                builder: (_, _) => const ActivitiesScreen(),
                routes: [
                  GoRoute(
                    path: ':key',
                    builder: (_, s) => ActivityDetailScreen(activityKey: s.pathParameters['key']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/progress',
                builder: (_, _) => const ProgressScreen(),
                routes: [
                  GoRoute(
                    path: ':id',
                    builder: (_, s) => SessionDetailScreen(sessionId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (_, _) => const SettingsScreen(),
                routes: [
                  GoRoute(path: 'children', builder: (_, _) => const ChildrenSettingsScreen()),
                  GoRoute(
                    path: 'device/:id',
                    builder: (_, s) => DeviceSettingsScreen(deviceId: s.pathParameters['id']!),
                  ),
                  GoRoute(path: 'limits', builder: (_, _) => const LimitsSettingsScreen()),
                  GoRoute(path: 'notifications', builder: (_, _) => const NotificationSettingsScreen()),
                  GoRoute(path: 'data', builder: (_, _) => const DataSettingsScreen()),
                  GoRoute(path: 'help', builder: (_, _) => const HelpScreen()),
                  GoRoute(path: 'account', builder: (_, _) => const AccountSettingsScreen()),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final auth = ref.watch(authControllerProvider);
    if (auth is SignedIn && me.hasError && !me.isLoading) {
      return Scaffold(
        body: Center(child: SplashError(onRetry: () => ref.invalidate(meProvider))),
      );
    }
    return const Scaffold(body: Center(child: SplashMark()));
  }
}

void refreshFamily(WidgetRef ref) {
  ref.invalidate(meProvider);
  ref.invalidate(childrenProvider);
  ref.invalidate(devicesProvider);
  ref.invalidate(recentSessionsProvider);
}
