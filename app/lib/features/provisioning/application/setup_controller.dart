import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/providers.dart';
import '../data/ble_transport.dart';
import '../data/simulator.dart';
import '../domain/provisioning_service.dart';
import '../domain/setup_state.dart';
import '../domain/transport.dart';

/// Which transport to use. Release builds always use BLE.
enum TransportChoice { ble, simulator }

class SetupSession {
  SetupSession(this.service, {this.simulatedToy});

  final ProvisioningService service;
  final SimulatedToy? simulatedToy;
}

/// Owns a ProvisioningService for the lifetime of the setup screen.
class SetupController extends Notifier<SetupState> {
  SetupSession? _session;
  StreamSubscription<SetupState>? _sub;

  @override
  SetupState build() {
    ref.onDispose(() {
      _sub?.cancel();
      _session?.service.dispose();
    });
    return const SetupState();
  }

  SimulatedToy? get simulatedToy => _session?.simulatedToy;
  ProvisioningService? get service => _session?.service;

  /// Prepare a session. For the simulator this registers a simulated toy with
  /// the development backend and returns its QR payload for the parent to "scan".
  Future<SimulatedToy?> prepare(TransportChoice choice, {bool reprovision = false}) async {
    await _sub?.cancel();
    await _session?.service.dispose();
    SimulatedToy? toy;
    ProvisioningTransport transport;
    if (choice == TransportChoice.simulator && AppConfig.simulatorEnabled) {
      toy = ref.read(simulatedToyProvider) ?? await SimulatedToy.create(AppConfig.apiBase);
      ref.read(simulatedToyProvider.notifier).set(toy);
      transport = SimulatedProvisioningTransport(toy);
    } else {
      transport = BleProvisioningTransport();
    }
    final service = ProvisioningService(
      transport: transport,
      backend: ApiClaimBackend(ref.read(apiProvider)),
      isReprovision: reprovision,
    );
    _session = SetupSession(service, simulatedToy: toy);
    _sub = service.states.listen((s) => state = s);
    state = service.state;
    return toy;
  }

  Future<void> start(SetupCode code) => _session!.service.start(code);
  Future<void> connect(String ssid, String passphrase) => _session!.service.connect(ssid, passphrase);
  Future<void> rescan() => _session!.service.rescanWifi();
  Future<void> retry() => _session!.service.retry();
  Future<void> replayGreeting() => _session!.service.replayGreeting();
  void confirmHeard() => _session!.service.confirmHeard();
  Future<void> cancel() async => _session?.service.cancel();
}

final setupControllerProvider = NotifierProvider.autoDispose<SetupController, SetupState>(
  SetupController.new,
);

/// Keeps the simulated toy alive across screens (debug builds only) so it
/// keeps heartbeating and acknowledging commands like a real toy.
class SimulatedToyHolder extends Notifier<SimulatedToy?> {
  @override
  SimulatedToy? build() => null;

  void set(SimulatedToy t) => state = t;
}

final simulatedToyProvider = NotifierProvider<SimulatedToyHolder, SimulatedToy?>(SimulatedToyHolder.new);
