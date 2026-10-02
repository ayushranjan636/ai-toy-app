import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'app/shell.dart';

/// No implicit provider retries: network retries are explicit and bounded
/// (Try again, pull to refresh, the preferences outbox backoff).
Duration? noAutomaticRetry(int retryCount, Object error) => null;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(retry: noAutomaticRetry, child: ZivooApp()));
}
