import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zivoo/app/shell.dart';
import 'package:zivoo/core/models.dart';
import 'package:zivoo/core/providers.dart';
import 'package:zivoo/core/storage.dart';
import 'package:zivoo/features/home/home_screen.dart';
import 'package:zivoo/features/progress/progress_screens.dart';

import 'fakes.dart';

void main() {
  late FakeApi api;
  late FakeAuthRepository auth;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    api = FakeApi();
    auth = FakeAuthRepository();
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340); // small-ish phone at 3x
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [
          apiProvider.overrideWithValue(api),
          authRepositoryProvider.overrideWithValue(auth),
          secureStoreProvider.overrideWithValue(MemorySecureStore()),
        ],
        child: const ZivooApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('new visitor sees Welcome with one primary action', (tester) async {
    await pumpApp(tester);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('I already have an account'), findsOneWidget);
  });

  testWidgets('returning user on a new phone signs in and lands on Home with existing data', (tester) async {
    api.devs.add(
      Device(
        id: 'd1',
        serial: 'ZV-1',
        name: 'Zivoo',
        online: false,
        lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)),
        firmwareUpdateAvailable: false,
        activeChildId: 'child-1',
        configSync: ConfigSync.pending,
        isSimulated: false,
      ),
    );
    await pumpApp(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'parent@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct-horse');
    await tester.tap(find.widgetWithText(ZButtonFinderShim.type, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Hello, Sam'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.textContaining('Last seen 5 minutes ago'), findsOneWidget);
    expect(find.text('Your changes will sync when Zivoo reconnects.'), findsOneWidget);
    expect(find.text('No sessions yet'), findsOneWidget);
    // No pairing was required.
    expect(find.text('Connect your Zivoo'), findsNothing);
  });

  testWidgets('home with no toy offers setup instead of fake status', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'parent@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct-horse');
    await tester.tap(find.widgetWithText(ZButtonFinderShim.type, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Connect your Zivoo'), findsOneWidget);
    expect(find.text('Online'), findsNothing);
  });

  testWidgets('wrong password shows an inline error', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'parent@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(ZButtonFinderShim.type, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text("That email and password don't match."), findsOneWidget);
  });

  testWidgets('unfinished onboarding resumes at the saved step after sign in', (tester) async {
    api.step = OnboardingStep.childProfile;
    await pumpApp(tester);
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'parent@example.com');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'correct-horse');
    await tester.tap(find.widgetWithText(ZButtonFinderShim.type, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Who will play with Zivoo?'), findsOneWidget);
  });

  testWidgets('UI tolerates 2x text scale without overflow on the welcome screen', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Create account'), findsOneWidget);
  });

  group('suggestion uses only real data', () {
    final prefs = LearningPreferences(version: 1, payload: defaultPayload(), updatedAt: DateTime(2026));

    SessionSummary s(String key, {int practice = 0}) => SessionSummary(
      id: key,
      childId: 'c',
      activityKey: key,
      status: 'completed',
      startedAt: DateTime(2026),
      correct: 3,
      needsPractice: practice,
      uncertain: 0,
    );

    test('no sessions -> first enabled activity, labelled as a starting point', () {
      final r = suggestNext([], prefs)!;
      expect(r.key, 'phonics');
      expect(r.reason, 'A good place to start.');
    });

    test('items to revisit win', () {
      final r = suggestNext([s('maths', practice: 2)], prefs)!;
      expect(r.key, 'maths');
      expect(r.reason, contains('2 items'));
    });
  });

  test('final outcome per item is the last attempt', () {
    AssessmentItem a(int seq, int idx, Outcome o, int attempt) => AssessmentItem(
      seq: seq,
      itemIndex: idx,
      prompt: 'q$idx',
      outcome: o,
      attempt: attempt,
      source: 'maths.deterministic',
    );
    final out = finalPerItem([
      a(1, 0, Outcome.needsPractice, 1),
      a(2, 0, Outcome.correct, 2),
      a(3, 1, Outcome.uncertain, 1),
      a(4, 1, Outcome.uncertain, 1),
      a(5, 2, Outcome.correct, 1),
    ]);
    expect(out.map((x) => x.outcome), [Outcome.correct, Outcome.uncertain, Outcome.correct]);
  });
}

/// The app's buttons are custom; find them by their label inside Semantics/InkWell.
abstract final class ZButtonFinderShim {
  static const type = InkWell;
}
