import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/button.dart';
import '../../../core/design/illustrations.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/tokens.dart';
import '../application/setup_controller.dart';
import '../domain/setup_state.dart';
import '../domain/transport.dart';
import 'setup_copy.dart';

class SetupRunningView extends ConsumerWidget {
  const SetupRunningView({
    super.key,
    required this.state,
    required this.onCancel,
    required this.onFinished,
    this.isSimulator = false,
  });

  final SetupState state;
  final VoidCallback onCancel;
  final VoidCallback onFinished;
  final bool isSimulator;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(setupControllerProvider.notifier);
    final cancel = ZButton(label: 'Cancel', kind: ZButtonKind.quiet, onPressed: onCancel);
    switch (state.phase) {
      case SetupPhase.choosingWifi:
        return WifiPickerView(
          networks: state.networks,
          onRescan: c.rescan,
          onCancel: onCancel,
          onConnect: c.connect,
        );
      case SetupPhase.awaitingGreetingConfirm:
        return StepScaffold(
          title: 'Did you hear Zivoo say hello?',
          showBack: false,
          leading: const ConnectionPulse(active: false, connected: true),
          primary: ZButton(
            label: 'Yes, I heard it',
            onPressed: () {
              c.confirmHeard();
              onFinished();
            },
          ),
          secondary: ZButton(label: 'Play it again', kind: ZButtonKind.quiet, onPressed: c.replayGreeting),
          children: const [Text("If you didn't hear anything, check Zivoo's volume and play it again.")],
        );
      case SetupPhase.done:
        return StepScaffold(
          title: 'Zivoo is ready',
          showBack: false,
          leading: const ConnectionPulse(active: false, connected: true),
          primary: ZButton(label: 'Continue', onPressed: onFinished),
          children: const [],
        );
      case SetupPhase.failed:
        final f = state.failure ?? ProvisioningFailure.timeout;
        return StepScaffold(
          title: SetupCopy.failureTitle(f),
          subtitle: SetupCopy.failureBody(f),
          showBack: false,
          leading: const Icon(Icons.error_outline_rounded, size: 48, color: ZColors.error),
          primary: ZButton(label: _retryLabel(f), onPressed: c.retry),
          secondary: cancel,
          children: [
            if (f == ProvisioningFailure.networkNotFound || f == ProvisioningFailure.wifiFailed)
              const InlineNotice(message: SetupCopy.wifi24),
          ],
        );
      case SetupPhase.cancelled:
        return StepScaffold(
          title: 'Setup stopped',
          showBack: false,
          primary: ZButton(label: 'Start again', onPressed: onCancel),
          children: const [],
        );
      default:
        return _ProgressView(state: state, cancel: cancel, isSimulator: isSimulator);
    }
  }

  static String _retryLabel(ProvisioningFailure f) => switch (f) {
    ProvisioningFailure.wrongPassword || ProvisioningFailure.networkNotFound => 'Choose Wi-Fi again',
    ProvisioningFailure.greetingFailed => 'Play greeting again',
    _ => 'Try again',
  };
}

class _ProgressView extends StatelessWidget {
  const _ProgressView({required this.state, required this.cancel, required this.isSimulator});

  final SetupState state;
  final Widget cancel;
  final bool isSimulator;

  static const _steps = [
    (SetupPhase.discovering, 'Finding your Zivoo'),
    (SetupPhase.securing, 'Connecting securely'),
    (SetupPhase.scanningWifi, 'Looking for Wi-Fi'),
    (SetupPhase.joiningWifi, 'Joining your Wi-Fi'),
    (SetupPhase.claimingCloud, 'Adding Zivoo to your account'),
    (SetupPhase.testingGreeting, 'Playing a hello'),
  ];

  int get _current => switch (state.phase) {
    SetupPhase.discovering => 0,
    SetupPhase.securing || SetupPhase.registeringClaim => 1,
    SetupPhase.scanningWifi => 2,
    SetupPhase.sendingCredentials || SetupPhase.joiningWifi => 3,
    SetupPhase.claimingCloud => 4,
    _ => 5,
  };

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final title = _steps[current].$2;
    final early = current < 3;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
          child: Column(
            children: [
              const Spacer(),
              const ConnectionPulse(active: true),
              const SizedBox(height: ZSpace.xl),
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              const SizedBox(height: ZSpace.lg),
              for (var i = (early ? 0 : 3); i < (early ? 3 : _steps.length); i++)
                _StepRow(label: _steps[i].$2, done: i < current, active: i == current),
              if (isSimulator) ...[
                const SizedBox(height: ZSpace.lg),
                const InlineNotice(message: 'Development simulator. No real toy is involved.'),
              ],
              const Spacer(),
              cancel,
              const SizedBox(height: ZSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.done, required this.active});

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, ${done ? 'done' : (active ? 'in progress' : 'waiting')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: ZSpace.xs),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 22,
              child: done
                  ? const Icon(Icons.check_circle_rounded, color: ZColors.teal, size: 22)
                  : active
                  ? const Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.circle_outlined, color: ZColors.divider, size: 22),
            ),
            const SizedBox(width: ZSpace.sm),
            Text(label, style: ZType.body.copyWith(color: done || active ? ZColors.charcoal : ZColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Networks reported by the toy, plus hidden-network entry and password.
class WifiPickerView extends StatefulWidget {
  const WifiPickerView({
    super.key,
    required this.networks,
    required this.onRescan,
    required this.onCancel,
    required this.onConnect,
  });

  final List<WifiNetwork> networks;
  final VoidCallback onRescan;
  final VoidCallback onCancel;
  final Future<void> Function(String ssid, String password) onConnect;

  @override
  State<WifiPickerView> createState() => _WifiPickerViewState();
}

class _WifiPickerViewState extends State<WifiPickerView> {
  String? _ssid;
  bool _secured = true;
  bool _hidden = false;
  bool _obscure = true;
  final _password = TextEditingController();
  final _hiddenSsid = TextEditingController();

  @override
  void dispose() {
    // Clear the password from memory as soon as this view goes away.
    _password.clear();
    _password.dispose();
    _hiddenSsid.dispose();
    super.dispose();
  }

  void _connect() {
    final ssid = _hidden ? _hiddenSsid.text.trim() : _ssid;
    if (ssid == null || ssid.isEmpty) return;
    final pw = _password.text;
    _password.clear();
    widget.onConnect(ssid, pw);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _ssid != null || _hidden;
    if (chosen) {
      final name = _hidden ? null : _ssid;
      return StepScaffold(
        title: name == null ? 'Enter network details' : 'Enter the password for $name',
        subtitle: "Zivoo receives this directly over a secure connection. We don't store it.",
        onBack: () => setState(() {
          _ssid = null;
          _hidden = false;
          _password.clear();
        }),
        primary: ZButton(label: 'Connect', onPressed: _connect),
        children: [
          if (_hidden) ...[
            TextField(
              controller: _hiddenSsid,
              decoration: const InputDecoration(labelText: 'Network name'),
              autocorrect: false,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: ZSpace.md),
          ],
          if (_secured || _hidden)
            TextField(
              controller: _password,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Wi-Fi password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _connect(),
            )
          else
            const InlineNotice(message: 'This network has no password.'),
          const SizedBox(height: ZSpace.md),
          Text(
            "Your phone can't share saved Wi-Fi passwords with Zivoo, so please type it in.",
            style: ZType.caption.copyWith(color: ZColors.muted),
          ),
        ],
      );
    }
    return StepScaffold(
      title: SetupCopy.wifiTitle,
      subtitle: SetupCopy.wifiBody,
      showBack: false,
      primary: ZButton(label: 'Search again', kind: ZButtonKind.secondary, onPressed: widget.onRescan),
      secondary: ZButton(label: 'Cancel', kind: ZButtonKind.quiet, onPressed: widget.onCancel),
      children: [
        if (widget.networks.isEmpty)
          const StateView.empty(
            title: 'No networks found',
            message: 'Move Zivoo closer to your router and search again.',
          )
        else
          ZSection(
            children: [
              for (final n in widget.networks)
                ZRow(
                  title: n.ssid,
                  icon: _bars(n.bars),
                  subtitle: n.secured ? null : 'Open network',
                  onTap: () => setState(() {
                    _ssid = n.ssid;
                    _secured = n.secured;
                  }),
                ),
              ZRow(
                title: 'Other network',
                icon: Icons.add_rounded,
                onTap: () => setState(() => _hidden = true),
              ),
            ],
          ),
        const SizedBox(height: ZSpace.md),
        const InlineNotice(message: SetupCopy.wifi24),
      ],
    );
  }

  IconData _bars(int b) => switch (b) {
    3 => Icons.wifi_rounded,
    2 => Icons.wifi_2_bar_rounded,
    _ => Icons.wifi_1_bar_rounded,
  };
}
