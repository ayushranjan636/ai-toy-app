/// Transport to a toy in setup mode. See docs/PROVISIONING_PROTOCOL.md.
///
/// Implementations: [BleProvisioningTransport] (ESP-IDF network_provisioning
/// over BLE, needs firmware) and SimulatedProvisioningTransport (debug only).
abstract interface class ProvisioningTransport {
  /// Find an advertising toy whose serial matches the scanned setup code.
  Future<DiscoveredToy> discover(SetupCode code, {required Duration timeout});

  /// Establish the encrypted session (Security 2, SRP6a with the setup code).
  Future<void> openSecureSession(DiscoveredToy toy, SetupCode code, {required Duration timeout});

  /// Networks the toy itself can see (2.4 GHz only).
  Future<List<WifiNetwork>> scanWifi({required Duration timeout});

  /// Deliver the one-time claim token and API base. Never Wi-Fi to the cloud.
  Future<void> sendClaimToken(String claimToken, {required Duration timeout});

  /// Send Wi-Fi credentials over the encrypted session and ask the toy to join.
  Future<void> sendWifiCredentials(String ssid, String passphrase, {required Duration timeout});

  /// Poll Wi-Fi join status.
  Future<WifiJoinStatus> wifiStatus();

  /// Ask the toy to play its greeting; completes when the toy acks playback.
  Future<void> playGreeting({required Duration timeout});

  Future<void> close();
}

class SetupCode {
  const SetupCode(this.serial, this.secret);

  final String serial;
  final String secret;

  /// QR payload `ZIVOO:1:<serial>:<secret>`.
  static SetupCode? parseQr(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length != 4 || parts[0] != 'ZIVOO' || parts[1] != '1') return null;
    return manual(parts[2], parts[3]);
  }

  static SetupCode? manual(String serial, String secret) {
    final s = serial.trim().toUpperCase();
    final c = secret.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (s.length < 4 || c.length < 8) return null;
    return SetupCode(s, c);
  }

  @override
  String toString() => 'SetupCode($serial, ****)'; // never print the secret
}

class DiscoveredToy {
  const DiscoveredToy({required this.serial, required this.transportId, this.signalStrength});

  final String serial;
  final String transportId;
  final int? signalStrength;
}

class WifiNetwork {
  const WifiNetwork({required this.ssid, required this.rssi, required this.secured});

  final String ssid;
  final int rssi;
  final bool secured;

  /// 0-3 bars for display.
  int get bars => rssi >= -55 ? 3 : (rssi >= -67 ? 2 : (rssi >= -78 ? 1 : 0));
}

enum WifiJoinStatus { connecting, connected, wrongPassword, networkNotFound, failed }

class ProvisioningException implements Exception {
  const ProvisioningException(this.kind, [this.detail]);

  final ProvisioningFailure kind;
  final String? detail;

  @override
  String toString() => 'ProvisioningException($kind)';
}

enum ProvisioningFailure {
  bluetoothOff,
  bluetoothDenied,
  notFound,
  secureSessionFailed,
  timeout,
  wifiScanFailed,
  wrongPassword,
  networkNotFound,
  wifiFailed,
  claimRejected,
  ownedElsewhere,
  claimExpired,
  cloudUnreachable,
  greetingFailed,
  backendOffline,
  invalidCode,
}
