import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/config.dart';
import '../../../core/design/button.dart';
import '../../../core/design/illustrations.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/tokens.dart';
import '../../../core/models.dart';
import '../../family/family_providers.dart';
import '../../onboarding/onboarding_screens.dart';
import '../../onboarding/setup_progress.dart';
import '../application/setup_controller.dart';
import '../domain/transport.dart';
import 'code_entry.dart';
import 'setup_copy.dart';
import 'setup_steps.dart';

/// Device setup: power on → setup mode → Bluetooth → code → (state machine).
class SetupFlow extends ConsumerStatefulWidget {
  const SetupFlow({super.key, this.reprovisionDeviceId, this.fromOnboarding = true});

  /// Set for "Change Wi-Fi" on a toy this family already owns.
  final String? reprovisionDeviceId;
  final bool fromOnboarding;

  @override
  ConsumerState<SetupFlow> createState() => _SetupFlowState();
}

enum _Intro { powerOn, setupMode, bluetooth, code, running }

class _SetupFlowState extends ConsumerState<SetupFlow> {
  _Intro _step = _Intro.powerOn;
  TransportChoice _choice = TransportChoice.ble;
  String? _prefilledQr;
  bool _preparing = false;

  bool get _reprovision => widget.reprovisionDeviceId != null;

  Future<void> _useSimulator() async {
    setState(() => _preparing = true);
    try {
      _choice = TransportChoice.simulator;
      final toy = await ref
          .read(setupControllerProvider.notifier)
          .prepare(_choice, reprovision: _reprovision);
      setState(() {
        _prefilledQr = toy?.qrPayload;
        _step = _Intro.code;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't start the simulator. Is the dev backend running?")),
        );
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  Future<void> _requestBluetooth() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetooth,
    ].request();
    final denied = statuses.values.any((s) => s.isPermanentlyDenied);
    if (!mounted) return;
    if (denied) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(SetupCopy.failureTitle(ProvisioningFailure.bluetoothDenied)),
          content: Text(SetupCopy.failureBody(ProvisioningFailure.bluetoothDenied)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Not now')),
            TextButton(
              onPressed: () {
                Navigator.pop(c);
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }
    await ref.read(setupControllerProvider.notifier).prepare(_choice, reprovision: _reprovision);
    setState(() => _step = _Intro.code);
  }

  Future<void> _startWithCode(SetupCode code) async {
    setState(() => _step = _Intro.running);
    await ref.read(setupControllerProvider.notifier).start(code);
  }

  Future<void> _setUpLater() async {
    await SetupProgressStore().setToySetupSkipped(true);
    await advanceOnboarding(ref, OnboardingStep.childProfile);
    if (mounted) context.go('/onboarding/child');
  }

  Future<void> _finished() async {
    ref.invalidate(devicesProvider);
    ref.invalidate(childrenProvider);
    if (widget.fromOnboarding) {
      await SetupProgressStore().setToySetupSkipped(false);
      await advanceOnboarding(ref, OnboardingStep.childProfile);
      if (mounted) context.go('/onboarding/child');
    } else if (mounted) {
      context.go('/home');
    }
  }

  Future<void> _cancel() async {
    final s = ref.read(setupControllerProvider);
    if (s.isBusy) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Stop setting up?'),
          content: const Text('You can start again at any time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep going')),
            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Stop')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(setupControllerProvider.notifier).cancel();
    if (!mounted) return;
    setState(() => _step = _Intro.code);
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(setupControllerProvider);
    final later = widget.fromOnboarding
        ? ZButton(label: 'Set up later', kind: ZButtonKind.quiet, onPressed: _setUpLater)
        : null;
    final leaving = widget.fromOnboarding ? null : () => context.pop();

    switch (_step) {
      case _Intro.powerOn:
        return StepScaffold(
          title: _reprovision ? 'Change Zivoo\u2019s Wi-Fi' : SetupCopy.powerOnTitle,
          subtitle: _reprovision
              ? 'Zivoo will stay linked to your account. You\u2019ll need the setup code again.'
              : SetupCopy.powerOnBody,
          step: widget.fromOnboarding ? 2 : null,
          totalSteps: widget.fromOnboarding ? 4 : null,
          showBack: !widget.fromOnboarding,
          onBack: leaving,
          leading: const _ToyIllustration(),
          primary: ZButton(label: "It's on", onPressed: () => setState(() => _step = _Intro.setupMode)),
          secondary: later,
          children: const [],
        );
      case _Intro.setupMode:
        return StepScaffold(
          title: SetupCopy.setupModeTitle,
          subtitle: SetupCopy.setupModeBody,
          onBack: () => setState(() => _step = _Intro.powerOn),
          leading: const ConnectionPulse(active: true),
          primary: ZButton(
            label: 'The light is pulsing',
            onPressed: () => setState(() => _step = _Intro.bluetooth),
          ),
          secondary: AppConfig.simulatorEnabled
              ? ZButton(
                  label: 'Use development simulator',
                  kind: ZButtonKind.quiet,
                  busy: _preparing,
                  onPressed: _useSimulator,
                )
              : later,
          children: const [
            InlineNotice(message: 'Setup mode lasts 10 minutes. You can turn it on again any time.'),
          ],
        );
      case _Intro.bluetooth:
        return StepScaffold(
          title: SetupCopy.bluetoothTitle,
          subtitle: SetupCopy.bluetoothBody,
          onBack: () => setState(() => _step = _Intro.setupMode),
          leading: const Icon(Icons.bluetooth_rounded, size: 48, color: ZColors.teal),
          primary: ZButton(label: 'Allow Bluetooth', onPressed: _requestBluetooth),
          children: const [],
        );
      case _Intro.code:
        return CodeEntryScreen(
          prefilledQr: _prefilledQr,
          isSimulator: _choice == TransportChoice.simulator,
          onBack: () => setState(() => _step = _Intro.setupMode),
          onCode: _startWithCode,
        );
      case _Intro.running:
        return SetupRunningView(
          state: setup,
          onCancel: _cancel,
          onFinished: _finished,
          isSimulator: _choice == TransportChoice.simulator,
        );
    }
  }
}

class _ToyIllustration extends StatelessWidget {
  const _ToyIllustration();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      height: 160,
      width: double.infinity,
      decoration: const BoxDecoration(color: ZColors.mintSurface, borderRadius: ZRadius.large),
      // Placeholder: replace with the supplied product image, unaltered.
      child: const Center(child: LeafMark(size: 88)),
    ),
  );
}
