import 'dart:math';

import 'package:intl/intl.dart';

/// Bounded exponential backoff with jitter.
class Backoff {
  Backoff({
    this.base = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.maxAttempts = 6,
    Random? random,
  }) : _random = random ?? Random();

  final Duration base;
  final Duration max;
  final int maxAttempts;
  final Random _random;

  /// Delay before attempt [attempt] (1-based), or null when attempts are exhausted.
  Duration? delayFor(int attempt) {
    if (attempt > maxAttempts) return null;
    final exp = base.inMilliseconds * pow(2, attempt - 1);
    final capped = min(exp.toDouble(), max.inMilliseconds.toDouble());
    final jitter = capped * (0.8 + _random.nextDouble() * 0.4);
    return Duration(milliseconds: jitter.round());
  }
}

/// Random UUID v4 for idempotency keys.
String uuidV4([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  final s = List.generate(16, h).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-'
      '${s.substring(16, 20)}-${s.substring(20)}';
}

/// "Just now", "5 minutes ago", "Yesterday at 4:10 PM", "12 Mar".
String relativeTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = t.toLocal();
  final d = n.difference(local);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} ${d.inMinutes == 1 ? 'minute' : 'minutes'} ago';
  if (d.inHours < 24 && n.day == local.day) {
    return '${d.inHours} ${d.inHours == 1 ? 'hour' : 'hours'} ago';
  }
  final yesterday = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
  if (!local.isBefore(yesterday)) return 'Yesterday at ${DateFormat.jm().format(local)}';
  if (local.year == n.year) return DateFormat.MMMd().format(local);
  return DateFormat.yMMMd().format(local);
}

String durationLabel(Duration d) {
  if (d.inMinutes < 1) return 'Under a minute';
  return '${d.inMinutes} min';
}
