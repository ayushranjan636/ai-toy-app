import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/config.dart';
import '../core/design/button.dart';
import '../core/design/illustrations.dart';
import '../core/design/theme.dart';
import '../core/design/tokens.dart';
import 'router.dart';

class ZivooApp extends ConsumerWidget {
  const ZivooApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Zivoo',
      debugShowCheckedModeBanner: false,
      theme: buildZivooTheme(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        // Support large text, but cap extreme scales that would break layouts.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 2.0)),
          child: AppConfig.simulatorEnabled
              ? Banner(
                  message: 'DEV',
                  location: BannerLocation.topEnd,
                  color: ZColors.charcoal,
                  child: child!,
                )
              : child!,
        );
      },
    );
  }
}

/// Bottom navigation: Home, Activities, Progress, Settings.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: ZColors.divider)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.extension_outlined),
              selectedIcon: Icon(Icons.extension_rounded),
              label: 'Activities',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'Progress',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class SplashMark extends StatelessWidget {
  const SplashMark({super.key});

  @override
  Widget build(BuildContext context) =>
      Semantics(label: 'Zivoo is loading', child: const ZivooWordmark(size: 32));
}

class SplashError extends StatelessWidget {
  const SplashError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(ZSpace.page),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ZivooWordmark(size: 28),
        const SizedBox(height: ZSpace.xl),
        Text(
          "We can't reach Zivoo right now.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: ZSpace.xs),
        Text(
          'Check your connection, then try again.',
          textAlign: TextAlign.center,
          style: ZType.body.copyWith(color: ZColors.muted),
        ),
        const SizedBox(height: ZSpace.lg),
        ZButton(label: 'Try again', onPressed: onRetry, kind: ZButtonKind.secondary, expand: false),
      ],
    ),
  );
}
