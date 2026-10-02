import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../domain/transport.dart';

/// BLE transport for ESP-IDF `network_provisioning` (Security 2).
///
/// HARDWARE INTEGRATION STATUS:
/// - [discover] is implemented (scans for `ZIVOO-<last4>` and matches the
///   serial from manufacturer data when present). Not yet tested on hardware.
/// - Everything after discovery needs the firmware's protobuf endpoints and an
///   SRP6a/AES-GCM session implementation (or a maintained ESP provisioning
///   plugin). Those methods throw until implemented, so the app never shows
///   success it did not receive.
class BleProvisioningTransport implements ProvisioningTransport {
  BluetoothDevice? _device;

  @override
  Future<DiscoveredToy> discover(SetupCode code, {required Duration timeout}) async {
    if (!await FlutterBluePlus.isSupported) {
      throw const ProvisioningException(ProvisioningFailure.bluetoothOff, 'unsupported');
    }
    final adapter = await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
    if (adapter == BluetoothAdapterState.unauthorized) {
      throw const ProvisioningException(ProvisioningFailure.bluetoothDenied);
    }
    if (adapter != BluetoothAdapterState.on) {
      throw const ProvisioningException(ProvisioningFailure.bluetoothOff);
    }

    final suffix = code.serial.length >= 4 ? code.serial.substring(code.serial.length - 4) : code.serial;
    final expectedName = 'ZIVOO-$suffix';
    final found = Completer<ScanResult>();
    final sub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.advName.toUpperCase() == expectedName && _serialMatches(r, code)) {
          if (!found.isCompleted) found.complete(r);
        }
      }
    });
    try {
      await FlutterBluePlus.startScan(withKeywords: ['ZIVOO-'], timeout: timeout);
      final r = await found.future.timeout(
        timeout,
        onTimeout: () => throw const ProvisioningException(ProvisioningFailure.notFound),
      );
      _device = r.device;
      return DiscoveredToy(serial: code.serial, transportId: r.device.remoteId.str, signalStrength: r.rssi);
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  bool _serialMatches(ScanResult r, SetupCode code) {
    final md = r.advertisementData.manufacturerData;
    if (md.isEmpty) return true; // name match only; serial verified in secure session
    final ascii = String.fromCharCodes(md.values.expand((b) => b).where((b) => b >= 32 && b < 127));
    return ascii.toUpperCase().contains(code.serial.toUpperCase());
  }

  Never _needsFirmware(String step) => throw ProvisioningException(
    ProvisioningFailure.secureSessionFailed,
    'BLE $step not implemented: needs firmware',
  );

  @override
  Future<void> openSecureSession(DiscoveredToy toy, SetupCode code, {required Duration timeout}) async =>
      _needsFirmware('security2 session');

  @override
  Future<List<WifiNetwork>> scanWifi({required Duration timeout}) async => _needsFirmware('prov-scan');

  @override
  Future<void> sendClaimToken(String claimToken, {required Duration timeout}) async =>
      _needsFirmware('zivoo-claim');

  @override
  Future<void> sendWifiCredentials(String ssid, String passphrase, {required Duration timeout}) async =>
      _needsFirmware('prov-config');

  @override
  Future<WifiJoinStatus> wifiStatus() async => _needsFirmware('get_status');

  @override
  Future<void> playGreeting({required Duration timeout}) async => _needsFirmware('zivoo-greet');

  @override
  Future<void> close() async {
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
  }
}
