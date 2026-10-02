import 'transport.dart';

/// Explicit setup states. Success states are entered only after real
/// acknowledgments (toy status / backend claim status), never optimistically.
enum SetupPhase {
  idle,
  discovering, // BLE scan for the scanned serial
  securing, // SRP6a handshake
  registeringClaim, // backend issues a one-time claim token
  scanningWifi,
  choosingWifi, // waiting for the parent
  sendingCredentials,
  joiningWifi, // ack: toy reports connected
  claimingCloud, // ack: backend claim status == completed
  testingGreeting, // ack: toy reports greeting played
  awaitingGreetingConfirm, // parent confirms they heard it
  done,
  failed,
  cancelled,
}

class SetupState {
  const SetupState({
    this.phase = SetupPhase.idle,
    this.code,
    this.toy,
    this.networks = const [],
    this.selectedSsid,
    this.claimId,
    this.deviceId,
    this.failure,
    this.failedDuring,
    this.attempt = 0,
    this.isReprovision = false,
  });

  final SetupPhase phase;
  final SetupCode? code;
  final DiscoveredToy? toy;
  final List<WifiNetwork> networks;
  final String? selectedSsid;
  final String? claimId;
  final String? deviceId;
  final ProvisioningFailure? failure;
  final SetupPhase? failedDuring;
  final int attempt;

  /// Change-Wi-Fi flow on an owned toy (ownership already held).
  final bool isReprovision;

  bool get isBusy => const {
    SetupPhase.discovering,
    SetupPhase.securing,
    SetupPhase.registeringClaim,
    SetupPhase.scanningWifi,
    SetupPhase.sendingCredentials,
    SetupPhase.joiningWifi,
    SetupPhase.claimingCloud,
    SetupPhase.testingGreeting,
  }.contains(phase);

  SetupState copyWith({
    SetupPhase? phase,
    SetupCode? code,
    DiscoveredToy? toy,
    List<WifiNetwork>? networks,
    String? selectedSsid,
    String? claimId,
    String? deviceId,
    ProvisioningFailure? failure,
    SetupPhase? failedDuring,
    int? attempt,
    bool clearFailure = false,
  }) => SetupState(
    phase: phase ?? this.phase,
    code: code ?? this.code,
    toy: toy ?? this.toy,
    networks: networks ?? this.networks,
    selectedSsid: selectedSsid ?? this.selectedSsid,
    claimId: claimId ?? this.claimId,
    deviceId: deviceId ?? this.deviceId,
    failure: clearFailure ? null : (failure ?? this.failure),
    failedDuring: clearFailure ? null : (failedDuring ?? this.failedDuring),
    attempt: attempt ?? this.attempt,
    isReprovision: isReprovision,
  );

  /// Legal transitions. Anything else is a programming error.
  static const transitions = <SetupPhase, Set<SetupPhase>>{
    SetupPhase.idle: {SetupPhase.discovering},
    SetupPhase.discovering: {SetupPhase.securing},
    SetupPhase.securing: {SetupPhase.registeringClaim},
    SetupPhase.registeringClaim: {SetupPhase.scanningWifi},
    SetupPhase.scanningWifi: {SetupPhase.choosingWifi},
    SetupPhase.choosingWifi: {SetupPhase.sendingCredentials, SetupPhase.scanningWifi},
    SetupPhase.sendingCredentials: {SetupPhase.joiningWifi},
    SetupPhase.joiningWifi: {SetupPhase.claimingCloud},
    SetupPhase.claimingCloud: {SetupPhase.testingGreeting},
    SetupPhase.testingGreeting: {SetupPhase.awaitingGreetingConfirm},
    SetupPhase.awaitingGreetingConfirm: {SetupPhase.done, SetupPhase.testingGreeting},
    SetupPhase.failed: {
      SetupPhase.discovering,
      SetupPhase.scanningWifi,
      SetupPhase.choosingWifi,
      SetupPhase.claimingCloud,
      SetupPhase.testingGreeting,
    },
    SetupPhase.done: {},
    SetupPhase.cancelled: {SetupPhase.discovering},
  };

  static bool canTransition(SetupPhase from, SetupPhase to) =>
      to == SetupPhase.failed || to == SetupPhase.cancelled || (transitions[from]?.contains(to) ?? false);
}

/// Timeouts from docs/PROVISIONING_PROTOCOL.md §8.
abstract final class SetupTimeouts {
  static const discover = Duration(seconds: 30);
  static const secure = Duration(seconds: 15);
  static const wifiScan = Duration(seconds: 15);
  static const sendCredentials = Duration(seconds: 10);
  static const wifiJoin = Duration(seconds: 45);
  static const cloudClaim = Duration(seconds: 60);
  static const greeting = Duration(seconds: 20);
  static const poll = Duration(milliseconds: 1500);
}
