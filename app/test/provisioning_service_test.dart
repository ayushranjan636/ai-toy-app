import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zivoo/core/api/api_error.dart';
import 'package:zivoo/features/provisioning/domain/provisioning_service.dart';
import 'package:zivoo/features/provisioning/domain/setup_state.dart';
import 'package:zivoo/features/provisioning/domain/transport.dart';

class FakeTransport implements ProvisioningTransport {
  ProvisioningException? discoverError;
  ProvisioningException? secureError;
  List<WifiJoinStatus> statuses = [WifiJoinStatus.connecting, WifiJoinStatus.connected];
  bool greetingFails = false;
  String? sentClaimToken;
  String? sentSsid;
  String? sentPassword;
  int greetings = 0;
  bool closed = false;
  Completer<void>? discoverGate;

  @override
  Future<DiscoveredToy> discover(SetupCode code, {required Duration timeout}) async {
    if (discoverGate != null) await discoverGate!.future;
    if (discoverError != null) throw discoverError!;
    return DiscoveredToy(serial: code.serial, transportId: 'x');
  }

  @override
  Future<void> openSecureSession(DiscoveredToy toy, SetupCode code, {required Duration timeout}) async {
    if (secureError != null) throw secureError!;
  }

  @override
  Future<List<WifiNetwork>> scanWifi({required Duration timeout}) async => const [
    WifiNetwork(ssid: 'Home', rssi: -70, secured: true),
    WifiNetwork(ssid: 'Home', rssi: -40, secured: true),
    WifiNetwork(ssid: '', rssi: -30, secured: false),
    WifiNetwork(ssid: 'Other', rssi: -60, secured: true),
  ];

  @override
  Future<void> sendClaimToken(String claimToken, {required Duration timeout}) async =>
      sentClaimToken = claimToken;

  @override
  Future<void> sendWifiCredentials(String ssid, String passphrase, {required Duration timeout}) async {
    sentSsid = ssid;
    sentPassword = passphrase;
  }

  @override
  Future<WifiJoinStatus> wifiStatus() async => statuses.length > 1 ? statuses.removeAt(0) : statuses.first;

  @override
  Future<void> playGreeting({required Duration timeout}) async {
    greetings++;
    if (greetingFails) throw const ProvisioningException(ProvisioningFailure.greetingFailed);
  }

  @override
  Future<void> close() async => closed = true;
}

class FakeBackend implements ClaimBackend {
  List<String> statuses = ['pending', 'completed'];
  String? reason;
  ApiException? startError;
  int offlineFailures = 0;
  final cancelled = <String>[];
  int claimsStarted = 0;

  @override
  Future<({String id, String token, String? deviceId})> startClaim(SetupCode code) async {
    if (startError != null) throw startError!;
    claimsStarted++;
    return (id: 'claim-$claimsStarted', token: 'zcl_secret', deviceId: 'dev-1');
  }

  @override
  Future<({String status, String? deviceId, String? reason})> claimStatus(String claimId) async {
    if (offlineFailures > 0) {
      offlineFailures--;
      throw ApiException.offline;
    }
    final s = statuses.length > 1 ? statuses.removeAt(0) : statuses.first;
    return (status: s, deviceId: 'dev-1', reason: reason);
  }

  @override
  Future<void> cancelClaim(String claimId) async => cancelled.add(claimId);
}

const code = SetupCode('SIM-ABCD', 'ABCDEFGHJKLM');

ProvisioningService make(FakeTransport t, FakeBackend b) =>
    ProvisioningService(transport: t, backend: b, sleep: (_) async {});

void main() {
  late FakeTransport t;
  late FakeBackend b;
  late ProvisioningService s;
  late List<SetupPhase> phases;

  setUp(() {
    t = FakeTransport();
    b = FakeBackend();
    s = make(t, b);
    phases = [];
    s.states.listen((st) => phases.add(st.phase));
  });

  test('happy path reaches done only after real acknowledgments', () async {
    await s.start(code);
    expect(s.state.phase, SetupPhase.choosingWifi);
    // Networks deduplicated (strongest wins), blank SSIDs dropped, sorted by signal.
    expect(s.state.networks.map((n) => '${n.ssid}:${n.rssi}'), ['Home:-40', 'Other:-60']);
    expect(t.sentClaimToken, 'zcl_secret');

    await s.connect('Home', 'hunter22');
    await pumpEventQueue();
    expect(s.state.phase, SetupPhase.awaitingGreetingConfirm);
    expect(t.greetings, 1);
    expect(
      phases,
      containsAllInOrder([
        SetupPhase.discovering,
        SetupPhase.securing,
        SetupPhase.registeringClaim,
        SetupPhase.scanningWifi,
        SetupPhase.choosingWifi,
        SetupPhase.sendingCredentials,
        SetupPhase.joiningWifi,
        SetupPhase.claimingCloud,
        SetupPhase.testingGreeting,
        SetupPhase.awaitingGreetingConfirm,
      ]),
    );
    expect(phases, isNot(contains(SetupPhase.done)));
    s.confirmHeard();
    expect(s.state.phase, SetupPhase.done);
  });

  test('wifi password goes only to the transport', () async {
    await s.start(code);
    await s.connect('Home', 'p@ss-word');
    expect(t.sentPassword, 'p@ss-word');
    expect(s.state.toString(), isNot(contains('p@ss-word')));
    expect(code.toString(), isNot(contains(code.secret)));
  });

  test('wrong password returns to network choice on retry without re-pairing', () async {
    t.statuses = [WifiJoinStatus.connecting, WifiJoinStatus.wrongPassword];
    await s.start(code);
    await s.connect('Home', 'bad');
    expect(s.state.phase, SetupPhase.failed);
    expect(s.state.failure, ProvisioningFailure.wrongPassword);
    await s.retry();
    expect(s.state.phase, SetupPhase.choosingWifi);
    expect(b.claimsStarted, 1); // same claim, no re-discovery
    t.statuses = [WifiJoinStatus.connected];
    await s.connect('Home', 'good');
    expect(s.state.phase, SetupPhase.awaitingGreetingConfirm);
  });

  test('toy not found fails with a recoverable error and retry restarts discovery', () async {
    t.discoverError = const ProvisioningException(ProvisioningFailure.notFound);
    await s.start(code);
    expect(s.state.failure, ProvisioningFailure.notFound);
    t.discoverError = null;
    await s.retry();
    expect(s.state.phase, SetupPhase.choosingWifi);
    expect(s.state.attempt, 2);
  });

  test('device owned by another family is reported distinctly', () async {
    b.startError = const ApiException('device_owned_elsewhere', 'x', status: 409);
    await s.start(code);
    expect(s.state.failure, ProvisioningFailure.ownedElsewhere);
  });

  test('wrong setup code is reported as invalid code', () async {
    b.startError = const ApiException('setup_code_invalid', 'x', status: 400);
    await s.start(code);
    expect(s.state.failure, ProvisioningFailure.invalidCode);
  });

  test('claim rejected by backend after wifi join', () async {
    b.statuses = ['failed'];
    b.reason = 'device_owned_elsewhere';
    await s.start(code);
    await s.connect('Home', 'pw');
    expect(s.state.failure, ProvisioningFailure.ownedElsewhere);
    expect(s.state.failedDuring, SetupPhase.claimingCloud);
  });

  test('phone briefly offline while waiting for claim: tolerated', () async {
    b.offlineFailures = 2;
    await s.start(code);
    await s.connect('Home', 'pw');
    expect(s.state.phase, SetupPhase.awaitingGreetingConfirm);
  });

  test('claim timeout then retry resumes at cloud step', () async {
    var now = DateTime(2026);
    b.statuses = ['pending'];
    s = ProvisioningService(
      transport: t,
      backend: b,
      sleep: (_) async => now = now.add(const Duration(seconds: 5)),
      clock: () => now,
    );
    await s.start(code);
    await s.connect('Home', 'pw');
    expect(s.state.failure, ProvisioningFailure.cloudUnreachable);
    b.statuses = ['completed'];
    await s.retry();
    expect(s.state.phase, SetupPhase.awaitingGreetingConfirm);
    expect(t.sentSsid, 'Home');
  });

  test('greeting failure can be replayed', () async {
    t.greetingFails = true;
    await s.start(code);
    await s.connect('Home', 'pw');
    expect(s.state.failure, ProvisioningFailure.greetingFailed);
    t.greetingFails = false;
    await s.retry();
    expect(s.state.phase, SetupPhase.awaitingGreetingConfirm);
    expect(t.greetings, 2);
  });

  test('cancel during discovery stops the flow and cancels the claim', () async {
    t.discoverGate = Completer();
    final run = s.start(code);
    await pumpEventQueue();
    await s.cancel();
    t.discoverGate!.complete();
    await run;
    expect(s.state.phase, SetupPhase.cancelled);
    expect(t.closed, isTrue);
    expect(b.claimsStarted, 0);
  });

  test('cancel after claim registered cancels it on the backend', () async {
    await s.start(code);
    await s.cancel();
    expect(b.cancelled, ['claim-1']);
    expect(s.hasClaimToken, isFalse);
  });

  test('serial mismatch from transport is treated as not found', () async {
    final wrong = _WrongSerialTransport();
    s = make(wrong, b);
    await s.start(code);
    expect(s.state.failure, ProvisioningFailure.notFound);
  });

  test('transition table rejects skipping acknowledgments', () {
    expect(SetupState.canTransition(SetupPhase.sendingCredentials, SetupPhase.done), isFalse);
    expect(SetupState.canTransition(SetupPhase.joiningWifi, SetupPhase.testingGreeting), isFalse);
    expect(SetupState.canTransition(SetupPhase.claimingCloud, SetupPhase.done), isFalse);
    expect(SetupState.canTransition(SetupPhase.awaitingGreetingConfirm, SetupPhase.done), isTrue);
    expect(SetupState.canTransition(SetupPhase.joiningWifi, SetupPhase.failed), isTrue);
  });

  group('SetupCode', () {
    test('parses QR payload', () {
      final c = SetupCode.parseQr('ZIVOO:1:sim-1234:abcd-efgh-jklm')!;
      expect(c.serial, 'SIM-1234');
      expect(c.secret, 'ABCDEFGHJKLM');
    });

    test('rejects other QR codes', () {
      expect(SetupCode.parseQr('https://example.com'), isNull);
      expect(SetupCode.parseQr('ZIVOO:2:A:B'), isNull);
      expect(SetupCode.manual('AB', 'ABCDEFGH'), isNull);
    });
  });
}

class _WrongSerialTransport extends FakeTransport {
  @override
  Future<DiscoveredToy> discover(SetupCode code, {required Duration timeout}) async =>
      const DiscoveredToy(serial: 'OTHER', transportId: 'x');
}
