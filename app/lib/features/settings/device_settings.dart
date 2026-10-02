import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api/api_error.dart';
import '../../core/api/zivoo_api.dart';
import '../../core/design/layout.dart';
import '../../core/design/tokens.dart';
import '../../core/models.dart';
import '../../core/providers.dart';
import '../../core/util.dart';
import '../family/family_providers.dart';
import 'settings_screens.dart' show confirmDestructive, lastSeenLabel;

String _err(Object e) => e is ApiException ? e.message : 'Something went wrong.';

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// Sends a command with a stable idempotency key and polls for the toy's ack.
/// Retrying (e.g. after a network blip) reuses the same command id.
Future<String> sendCommandAndWait(
  ZivooApi api,
  String deviceId,
  String kind, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final id = uuidV4();
  final backoff = Backoff(base: const Duration(milliseconds: 500), maxAttempts: 4);
  for (var attempt = 1; ; attempt++) {
    try {
      await api.sendCommand(deviceId, id, kind);
      break;
    } on ApiException catch (e) {
      final d = backoff.delayFor(attempt);
      if (!e.isOffline || d == null) rethrow;
      await Future<void>.delayed(d);
    }
  }
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(seconds: 2));
    final c = await api.command(deviceId, id);
    final status = c['status'] as String;
    if (status != 'pending' && status != 'delivered') return status;
  }
  return 'pending';
}

class DeviceSettingsScreen extends ConsumerWidget {
  const DeviceSettingsScreen({super.key, required this.deviceId});

  final String deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final device = devices.value?.value.where((d) => d.id == deviceId).firstOrNull;
    final children = ref.watch(childrenProvider).value?.value ?? const <Child>[];

    if (device == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Zivoo')),
        body: devices.isLoading
            ? const StateView.loading()
            : const StateView.empty(
                title: 'Zivoo not found',
                message: 'It may have been removed from this account.',
              ),
      );
    }
    final api = ref.read(apiProvider);

    Future<void> rename() async {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _RenameDialog(initial: device.name),
      );
      if (name == null || name.trim().isEmpty) return;
      try {
        await api.updateDevice(device.id, {'name': name.trim()});
        ref.invalidate(devicesProvider);
      } catch (e) {
        if (context.mounted) _toast(context, _err(e));
      }
    }

    Future<void> setChild(String? id) async {
      if (id == null) return;
      try {
        await api.updateDevice(device.id, {'active_child_id': id});
        ref.invalidate(devicesProvider);
        ref.read(selectedChildIdProvider.notifier).select(id);
      } catch (e) {
        if (context.mounted) _toast(context, _err(e));
      }
    }

    Future<void> command(String kind, String waiting, String ok) async {
      _toast(context, waiting);
      try {
        final status = await sendCommandAndWait(api, device.id, kind);
        if (!context.mounted) return;
        _toast(context, switch (status) {
          'acknowledged' => ok,
          'pending' => "Zivoo hasn't responded yet. It will do this when it reconnects.",
          _ => "Zivoo couldn't do that. Try again.",
        });
      } catch (e) {
        if (context.mounted) _toast(context, _err(e));
      }
    }

    Future<void> remove() async {
      final ok = await confirmDestructive(
        context,
        title: 'Remove ${device.name} from your account?',
        body:
            'Zivoo will stop using your family\u2019s profiles and settings. Your session history stays '
            'in the app. To give Zivoo to someone else, factory reset it too.',
        action: 'Remove',
      );
      if (!ok) return;
      try {
        await api.removeDevice(device.id);
        ref.invalidate(devicesProvider);
        if (context.mounted) context.go('/settings');
      } catch (e) {
        if (context.mounted) _toast(context, _err(e));
      }
    }

    Future<void> factoryReset() async {
      final ok = await confirmDestructive(
        context,
        title: 'Factory reset ${device.name}?',
        body:
            'Zivoo will forget its Wi-Fi and be removed from your account. It needs to be set up again '
            'before anyone can use it.',
        action: 'Factory reset',
      );
      if (!ok) return;
      await command('factory_reset', 'Asking Zivoo to reset\u2026', 'Zivoo has been reset.');
      ref.invalidate(devicesProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(device.name)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(devicesProvider),
        child: ListView(
          padding: const EdgeInsets.only(bottom: ZSpace.xl),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.sm, ZSpace.page, 0),
              child: Row(
                children: [
                  StatusLabel(
                    label: device.online ? 'Online' : 'Offline',
                    tone: device.online ? StatusTone.good : StatusTone.waiting,
                  ),
                  const SizedBox(width: ZSpace.sm),
                  Expanded(
                    child: Text(lastSeenLabel(device), style: ZType.caption.copyWith(color: ZColors.muted)),
                  ),
                ],
              ),
            ),
            if (device.isSimulated)
              const Padding(
                padding: EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, 0),
                child: InlineNotice(message: 'Development simulator. This is not a real toy.'),
              ),
            ZSection(
              title: 'Details',
              children: [
                ZRow(title: 'Name', subtitle: device.name, icon: Icons.edit_outlined, onTap: rename),
                if (children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: ZSpace.md, vertical: ZSpace.xs),
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: children.any((c) => c.id == device.activeChildId)
                          ? device.activeChildId
                          : null,
                      decoration: const InputDecoration(labelText: 'Who is playing'),
                      items: [
                        for (final c in children) DropdownMenuItem(value: c.id, child: Text(c.displayName)),
                      ],
                      onChanged: setChild,
                    ),
                  ),
                ZRow(title: 'Serial number', subtitle: device.serial, icon: Icons.tag_rounded),
                ZRow(
                  title: 'Software',
                  subtitle: device.firmwareVersion == null
                      ? 'Unknown'
                      : '${device.firmwareVersion}${device.firmwareUpdateAvailable ? ' · update available' : ' · up to date'}',
                  icon: Icons.system_update_outlined,
                  onTap: device.online
                      ? () => command(
                          'check_firmware',
                          'Asking Zivoo to check for updates\u2026',
                          'Zivoo checked for updates.',
                        )
                      : null,
                ),
                ZRow(
                  title: 'Settings on Zivoo',
                  subtitle: switch (device.configSync) {
                    ConfigSync.applied => 'Up to date',
                    ConfigSync.pending => 'Waiting for Zivoo to reconnect',
                    ConfigSync.failed => 'Couldn\u2019t apply. Tap to send again.',
                    ConfigSync.none => 'Nothing to send yet',
                  },
                  icon: Icons.sync_rounded,
                  onTap: device.configSync == ConfigSync.failed
                      ? () async {
                          await api.resendConfig(device.id);
                          ref.invalidate(devicesProvider);
                        }
                      : null,
                ),
              ],
            ),
            ZSection(
              title: 'Connection',
              children: [
                ZRow(title: 'Wi-Fi', subtitle: device.wifiSsid ?? 'Unknown', icon: Icons.wifi_rounded),
                ZRow(
                  title: 'Change Wi-Fi',
                  subtitle: 'Stays linked to your account',
                  icon: Icons.swap_horiz_rounded,
                  onTap: () => context.push('/setup?device=${device.id}'),
                ),
                ZRow(
                  title: 'Play a test hello',
                  icon: Icons.volume_up_outlined,
                  onTap: device.online
                      ? () => command('play_greeting', 'Asking Zivoo to say hello\u2026', 'Zivoo said hello.')
                      : null,
                ),
              ],
            ),
            ZSection(
              title: 'Ownership',
              children: [
                ZRow(
                  title: 'Remove from account',
                  subtitle: 'Keeps Zivoo\u2019s Wi-Fi',
                  icon: Icons.link_off_rounded,
                  destructive: true,
                  onTap: remove,
                ),
                ZRow(
                  title: 'Factory reset',
                  subtitle: device.online ? 'Erases Wi-Fi and removes from account' : 'Zivoo must be online',
                  icon: Icons.restart_alt_rounded,
                  destructive: true,
                  onTap: device.online ? factoryReset : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename Zivoo'),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 40,
      textCapitalization: TextCapitalization.words,
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      TextButton(onPressed: () => Navigator.pop(context, _c.text), child: const Text('Save')),
    ],
  );
}
