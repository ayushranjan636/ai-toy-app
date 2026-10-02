import 'dart:async';

import '../../../core/api/api_error.dart';
import '../../../core/api/zivoo_api.dart';
import 'setup_state.dart';
import 'transport.dart';

/// Backend calls the provisioning flow needs (narrow, for testing).
abstract interface class ClaimBackend {
  /// Returns (claimId, claimToken, deviceId).
  Future<({String id, String token, String? deviceId})> startClaim(SetupCode code);
  Future<({String status, String? deviceId, String? reason})> claimStatus(String claimId);
  Future<void> cancelClaim(String claimId);
}

class ApiClaimBackend implements ClaimBackend {
  ApiClaimBackend(this._api);

  final ZivooApi _api;

  @override
  Future<({String id, String token, String? deviceId})> startClaim(SetupCode code) async {
    final j = await _api.startClaim(code.serial, code.secret);
    return (id: j['id'] as String, token: j['claim_token'] as String, deviceId: j['device_id'] as String?);
  }

  @override
  Future<({String status, String? deviceId, String? reason})> claimStatus(String claimId) async {
    final j = await _api.claim(claimId);
    return (
      status: j['status'] as String,
      deviceId: j['device_id'] as String?,
      reason: j['failure_reason'] as String?,
    );
  }

  @override
  Future<void> cancelClaim(String claimId) => _api.cancelClaim(claimId);
}

/// Runs the setup state machine. UI-independent; emits [SetupState]s.
class ProvisioningService {
  ProvisioningService({
    required ProvisioningTransport transport,
    required this._backend,
    this.isReprovision = false,
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  }) : _t = transport,
       _sleep = sleep ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final ProvisioningTransport _t;
  final ClaimBackend _backend;
  final bool isReprovision;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;

  final _states = StreamController<SetupState>.broadcast();
  late SetupState _state = SetupState(isReprovision: isReprovision);
  String? _claimToken;
  bool _cancelled = false;

  Stream<SetupState> get states => _states.stream;
  SetupState get state => _state;

  void _go(SetupState next) {
    assert(
      SetupState.canTransition(_state.phase, next.phase) || _state.phase == next.phase,
      'illegal transition ${_state.phase} -> ${next.phase}',
    );
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  void _fail(ProvisioningFailure f) {
    if (_cancelled) return;
    _go(_state.copyWith(phase: SetupPhase.failed, failure: f, failedDuring: _state.phase));
  }

  void _checkCancelled() {
    if (_cancelled) throw const _Cancelled();
  }

  /// Steps 4-6: discover the matching toy, secure the session, register a
  /// claim, then scan Wi-Fi. Ends in `choosingWifi` or `failed`.
  Future<void> start(SetupCode code) async {
    _cancelled = false;
    _go(
      _state.copyWith(
        phase: SetupPhase.discovering,
        code: code,
        attempt: _state.attempt + 1,
        clearFailure: true,
      ),
    );
    try {
      final toy = await _t.discover(code, timeout: SetupTimeouts.discover);
      _checkCancelled();
      if (toy.serial.toUpperCase() != code.serial.toUpperCase()) {
        throw const ProvisioningException(ProvisioningFailure.notFound, 'serial mismatch');
      }
      _go(_state.copyWith(phase: SetupPhase.securing, toy: toy));
      await _t.openSecureSession(toy, code, timeout: SetupTimeouts.secure);
      _checkCancelled();

      _go(_state.copyWith(phase: SetupPhase.registeringClaim));
      final claim = await _backend.startClaim(code);
      _claimToken = claim.token;
      _go(_state.copyWith(claimId: claim.id, deviceId: claim.deviceId));
      await _t.sendClaimToken(claim.token, timeout: SetupTimeouts.sendCredentials);
      _checkCancelled();
      await _scan();
    } on _Cancelled {
      return;
    } on ProvisioningException catch (e) {
      _fail(e.kind);
    } on ApiException catch (e) {
      _fail(_mapApi(e));
    } on TimeoutException {
      _fail(ProvisioningFailure.timeout);
    }
  }

  Future<void> rescanWifi() async {
    try {
      await _scan();
    } on ProvisioningException catch (e) {
      _fail(e.kind);
    } on TimeoutException {
      _fail(ProvisioningFailure.wifiScanFailed);
    }
  }

  Future<void> _scan() async {
    _go(_state.copyWith(phase: SetupPhase.scanningWifi, clearFailure: true));
    final networks = await _t.scanWifi(timeout: SetupTimeouts.wifiScan);
    _checkCancelled();
    final unique = <String, WifiNetwork>{};
    for (final n in networks.where((n) => n.ssid.isNotEmpty)) {
      final prev = unique[n.ssid];
      if (prev == null || n.rssi > prev.rssi) unique[n.ssid] = n;
    }
    final sorted = unique.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi));
    _go(_state.copyWith(phase: SetupPhase.choosingWifi, networks: sorted));
  }

  /// Steps 7-10. The passphrase exists only for the duration of this call and
  /// is handed to the transport (encrypted BLE session) and nowhere else.
  Future<void> connect(String ssid, String passphrase) async {
    if (_state.phase == SetupPhase.failed) {
      _go(_state.copyWith(phase: SetupPhase.choosingWifi, clearFailure: true));
    }
    _go(_state.copyWith(phase: SetupPhase.sendingCredentials, selectedSsid: ssid, clearFailure: true));
    try {
      await _t.sendWifiCredentials(ssid, passphrase, timeout: SetupTimeouts.sendCredentials);
      _checkCancelled();
      _go(_state.copyWith(phase: SetupPhase.joiningWifi));
      await _awaitWifi();
      _checkCancelled();
      await _awaitCloudClaim();
    } on _Cancelled {
      return;
    } on ProvisioningException catch (e) {
      _fail(e.kind);
    } on ApiException catch (e) {
      _fail(_mapApi(e));
    } on TimeoutException {
      _fail(ProvisioningFailure.timeout);
    }
  }

  Future<void> _awaitWifi() async {
    final deadline = _clock().add(SetupTimeouts.wifiJoin);
    while (true) {
      _checkCancelled();
      switch (await _t.wifiStatus()) {
        case WifiJoinStatus.connected:
          return;
        case WifiJoinStatus.wrongPassword:
          throw const ProvisioningException(ProvisioningFailure.wrongPassword);
        case WifiJoinStatus.networkNotFound:
          throw const ProvisioningException(ProvisioningFailure.networkNotFound);
        case WifiJoinStatus.failed:
          throw const ProvisioningException(ProvisioningFailure.wifiFailed);
        case WifiJoinStatus.connecting:
          if (_clock().isAfter(deadline)) {
            throw const ProvisioningException(ProvisioningFailure.wifiFailed, 'timeout');
          }
          await _sleep(SetupTimeouts.poll);
      }
    }
  }

  /// Retry entry point after a cloud-claim failure (e.g. phone was offline).
  Future<void> retryCloudClaim() async {
    try {
      await _awaitCloudClaim();
    } on ApiException catch (e) {
      _fail(_mapApi(e));
    } on ProvisioningException catch (e) {
      _fail(e.kind);
    }
  }

  Future<void> _awaitCloudClaim() async {
    _go(_state.copyWith(phase: SetupPhase.claimingCloud, clearFailure: true));
    final id = _state.claimId!;
    final deadline = _clock().add(SetupTimeouts.cloudClaim);
    var transientErrors = 0;
    while (true) {
      _checkCancelled();
      try {
        final s = await _backend.claimStatus(id);
        switch (s.status) {
          case 'completed':
            _go(_state.copyWith(deviceId: s.deviceId));
            return await _greet();
          case 'pending':
            break;
          case 'expired':
            throw const ProvisioningException(ProvisioningFailure.claimExpired);
          default:
            throw ProvisioningException(
              s.reason == 'device_owned_elsewhere'
                  ? ProvisioningFailure.ownedElsewhere
                  : ProvisioningFailure.claimRejected,
            );
        }
      } on ApiException catch (e) {
        if (!e.isOffline || ++transientErrors > 5) rethrow;
      }
      if (_clock().isAfter(deadline)) {
        throw const ProvisioningException(ProvisioningFailure.cloudUnreachable);
      }
      await _sleep(SetupTimeouts.poll);
    }
  }

  /// Step 11. Success requires the toy's playback ack *and* the parent hearing it.
  Future<void> _greet() async {
    _go(_state.copyWith(phase: SetupPhase.testingGreeting, clearFailure: true));
    try {
      await _t.playGreeting(timeout: SetupTimeouts.greeting);
      _go(_state.copyWith(phase: SetupPhase.awaitingGreetingConfirm));
    } on ProvisioningException {
      _fail(ProvisioningFailure.greetingFailed);
    } on TimeoutException {
      _fail(ProvisioningFailure.greetingFailed);
    }
  }

  Future<void> replayGreeting() => _greet();

  void confirmHeard() {
    _go(_state.copyWith(phase: SetupPhase.done));
    unawaited(_t.close());
  }

  /// Cancel at any point. Cancels the backend claim if still pending.
  Future<void> cancel() async {
    _cancelled = true;
    final claimId = _state.claimId;
    final phase = _state.phase;
    _go(_state.copyWith(phase: SetupPhase.cancelled));
    _claimToken = null;
    await _t.close();
    if (claimId != null && phase.index < SetupPhase.claimingCloud.index) {
      try {
        await _backend.cancelClaim(claimId);
      } catch (_) {
        // Claims expire server-side after 10 minutes anyway.
      }
    }
  }

  /// Retry from wherever we failed, reusing confirmed progress.
  Future<void> retry() async {
    final during = _state.failedDuring;
    final f = _state.failure;
    if (f == ProvisioningFailure.wrongPassword || f == ProvisioningFailure.networkNotFound) {
      _go(_state.copyWith(phase: SetupPhase.choosingWifi, clearFailure: true));
      return;
    }
    switch (during) {
      case SetupPhase.claimingCloud:
        return await retryCloudClaim();
      case SetupPhase.testingGreeting:
        return await _greet();
      case SetupPhase.scanningWifi:
        return await rescanWifi();
      default:
        final code = _state.code;
        if (code != null) return await start(code);
    }
  }

  Future<void> dispose() async {
    _claimToken = null;
    await _t.close();
    await _states.close();
  }

  bool get hasClaimToken => _claimToken != null;

  ProvisioningFailure _mapApi(ApiException e) => switch (e.code) {
    'setup_code_invalid' => ProvisioningFailure.invalidCode,
    'device_owned_elsewhere' => ProvisioningFailure.ownedElsewhere,
    'too_many_attempts' => ProvisioningFailure.invalidCode,
    'offline' => ProvisioningFailure.backendOffline,
    _ => ProvisioningFailure.claimRejected,
  };
}

class _Cancelled implements Exception {
  const _Cancelled();
}
