import 'dart:async';

import 'package:dio/dio.dart';

import '../domain/transport.dart';

/// DEVELOPMENT SIMULATOR — not a real toy. Compiled out of release builds
/// (see AppConfig.simulatorEnabled).
///
/// Behaves like firmware would, against the real backend:
/// - Registers a simulated device via /dev/simulated-devices (dev backend only)
///   to obtain a serial, setup code and factory credential.
/// - On "Wi-Fi join" it calls POST /v1/device/claim with the claim token, as a
///   real toy would after joining the network, then heartbeats and acks
///   commands so ownership and config sync are exercised end to end.
/// - The Wi-Fi passphrase is checked locally ("wrong" simulates a bad password)
///   and is discarded; it is never sent to the backend.
class SimulatedToy {
  SimulatedToy({required this.serial, required this.setupCode, required this.credential, required this._dio});

  final String serial;
  final String setupCode;
  String credential;
  final Dio _dio;
  Timer? _heartbeat;

  String get qrPayload => 'ZIVOO:1:$serial:$setupCode';

  static Future<SimulatedToy> create(String apiBase) async {
    final dio = Dio(BaseOptions(baseUrl: apiBase, contentType: 'application/json'));
    final r = await dio.post<Map<String, dynamic>>('/dev/simulated-devices');
    final d = r.data!;
    return SimulatedToy(
      serial: d['serial'] as String,
      setupCode: d['setup_code'] as String,
      credential: d['factory_credential'] as String,
      dio: dio,
    );
  }

  Options get _auth => Options(headers: {'authorization': 'Bearer $credential'});

  Future<void> claim(String claimToken, String ssid) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/v1/device/claim',
      data: {'claim_token': claimToken, 'firmware_version': 'sim-0.1.0', 'wifi_ssid': ssid},
      options: _auth,
    );
    credential = r.data!['credential'] as String;
    await heartbeat();
    startHeartbeat();
  }

  void startHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 20), (_) => heartbeat());
  }

  /// Poll for config/commands and ack them, like firmware would.
  Future<void> heartbeat() async {
    try {
      final r = await _dio.post<Map<String, dynamic>>('/v1/device/heartbeat', data: {}, options: _auth);
      for (final c in (r.data!['commands'] as List).cast<Map<String, dynamic>>()) {
        await _dio.post<dynamic>(
          '/v1/device/commands/${c['id']}/ack',
          data: {'result': 'ok'},
          options: _auth,
        );
      }
    } catch (_) {
      // Simulated toy is best-effort.
    }
  }

  /// Run a short maths session with scripted answers so Progress has real data.
  Future<void> playDemoSession() async {
    final sid = 'sim-${DateTime.now().millisecondsSinceEpoch}';
    final start = await _dio.post<Map<String, dynamic>>(
      '/v1/device/sessions',
      data: {'client_session_id': sid, 'activity_key': 'maths'},
      options: _auth,
    );
    var reply = start.data!;
    var i = 0;
    final rng = DateTime.now().millisecond;
    while (reply['done'] != true && i < 30) {
      final say = reply['say'] as String;
      final m = RegExp(r'What is (\d+) (plus|take away) (\d+)\?').allMatches(say).lastOrNull;
      String transcript;
      String quality = 'good';
      if (m == null) {
        transcript = '';
        quality = 'silent';
      } else {
        final a = int.parse(m.group(1)!), b = int.parse(m.group(3)!);
        final answer = m.group(2) == 'plus' ? a + b : a - b;
        // Mostly right, one wrong, one unclear: demonstrates every outcome.
        if (i == 1) {
          transcript = '${answer + 1}';
        } else if (i == 3 + rng % 2) {
          transcript = '';
          quality = 'noisy';
        } else {
          transcript = 'it is $answer';
        }
      }
      final r = await _dio.post<Map<String, dynamic>>(
        '/v1/device/sessions/$sid/turns',
        data: {'turn_id': 't$i', 'transcript': transcript, 'audio_quality': quality, 'stt_confidence': 0.92},
        options: _auth,
      );
      reply = r.data!;
      i++;
    }
  }

  void dispose() => _heartbeat?.cancel();
}

class SimulatedProvisioningTransport implements ProvisioningTransport {
  SimulatedProvisioningTransport(this.toy, {this.latency = const Duration(milliseconds: 700)});

  final SimulatedToy toy;
  final Duration latency;
  String? _claimToken;
  String? _ssid;
  int _statusPolls = 0;
  bool _wrongPassword = false;

  @override
  Future<DiscoveredToy> discover(SetupCode code, {required Duration timeout}) async {
    await Future<void>.delayed(latency);
    if (code.serial != toy.serial) {
      throw const ProvisioningException(ProvisioningFailure.notFound);
    }
    return DiscoveredToy(serial: toy.serial, transportId: 'sim', signalStrength: -50);
  }

  @override
  Future<void> openSecureSession(DiscoveredToy t, SetupCode code, {required Duration timeout}) async {
    await Future<void>.delayed(latency);
    if (code.secret != toy.setupCode) {
      throw const ProvisioningException(ProvisioningFailure.secureSessionFailed);
    }
  }

  @override
  Future<List<WifiNetwork>> scanWifi({required Duration timeout}) async {
    await Future<void>.delayed(latency);
    return const [
      WifiNetwork(ssid: 'Home Wi-Fi', rssi: -48, secured: true),
      WifiNetwork(ssid: 'Home Wi-Fi', rssi: -70, secured: true),
      WifiNetwork(ssid: 'Neighbour 2.4G', rssi: -76, secured: true),
      WifiNetwork(ssid: 'Cafe Guest', rssi: -84, secured: false),
    ];
  }

  @override
  Future<void> sendClaimToken(String claimToken, {required Duration timeout}) async {
    _claimToken = claimToken;
  }

  @override
  Future<void> sendWifiCredentials(String ssid, String passphrase, {required Duration timeout}) async {
    await Future<void>.delayed(latency);
    _ssid = ssid;
    _wrongPassword = passphrase == 'wrong';
    _statusPolls = 0;
  }

  @override
  Future<WifiJoinStatus> wifiStatus() async {
    await Future<void>.delayed(latency);
    if (_statusPolls++ < 1) return WifiJoinStatus.connecting;
    if (_wrongPassword) return WifiJoinStatus.wrongPassword;
    // Joined Wi-Fi: now the "firmware" claims itself with the backend.
    final token = _claimToken;
    if (token != null) {
      _claimToken = null;
      unawaited(toy.claim(token, _ssid ?? ''));
    }
    return WifiJoinStatus.connected;
  }

  @override
  Future<void> playGreeting({required Duration timeout}) async {
    await Future<void>.delayed(latency * 2);
  }

  @override
  Future<void> close() async {}
}
