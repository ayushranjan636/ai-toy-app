import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/design/button.dart';
import '../../../core/design/layout.dart';
import '../../../core/design/tokens.dart';
import '../domain/transport.dart';
import 'setup_copy.dart';

/// Scan the setup QR code, or type the serial and setup code.
class CodeEntryScreen extends StatefulWidget {
  const CodeEntryScreen({
    super.key,
    required this.onCode,
    required this.onBack,
    this.prefilledQr,
    this.isSimulator = false,
  });

  final ValueChanged<SetupCode> onCode;
  final VoidCallback onBack;
  final String? prefilledQr;
  final bool isSimulator;

  @override
  State<CodeEntryScreen> createState() => _CodeEntryScreenState();
}

class _CodeEntryScreenState extends State<CodeEntryScreen> {
  bool _manual = false;
  final _serial = TextEditingController();
  final _code = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final qr = widget.prefilledQr == null ? null : SetupCode.parseQr(widget.prefilledQr!);
    if (qr != null) {
      _manual = true;
      _serial.text = qr.serial;
      _code.text = qr.secret;
    }
  }

  @override
  void dispose() {
    _serial.dispose();
    _code.dispose();
    super.dispose();
  }

  void _submitManual() {
    final code = SetupCode.manual(_serial.text, _code.text);
    if (code == null) {
      setState(() => _error = 'Check the serial number and the 12-character setup code.');
      return;
    }
    widget.onCode(code);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = SetupCode.parseQr(raw);
      if (code != null) {
        HapticFeedback.selectionClick();
        widget.onCode(code);
        return;
      }
    }
    setState(() => _error = "That isn't a Zivoo setup code.");
  }

  @override
  Widget build(BuildContext context) {
    if (!_manual) {
      return StepScaffold(
        title: SetupCopy.scanTitle,
        subtitle: SetupCopy.scanBody,
        onBack: widget.onBack,
        primary: ZButton(
          label: 'Enter the code instead',
          kind: ZButtonKind.secondary,
          onPressed: () => setState(() => _manual = true),
        ),
        children: [
          Semantics(
            label: 'Camera viewfinder for the setup code',
            child: ClipRRect(
              borderRadius: ZRadius.large,
              child: AspectRatio(
                aspectRatio: 1,
                child: MobileScanner(
                  onDetect: _onDetect,
                  errorBuilder: (context, error) => const ColoredBox(
                    color: ZColors.mintSurface,
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(ZSpace.lg),
                        child: Text(
                          'Camera unavailable. Enter the code instead.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: ZSpace.md),
            InlineNotice(message: _error!, kind: NoticeKind.error),
          ],
        ],
      );
    }
    return StepScaffold(
      title: 'Enter the setup code',
      subtitle: SetupCopy.scanBody,
      onBack: widget.prefilledQr != null ? widget.onBack : () => setState(() => _manual = false),
      primary: ZButton(label: 'Find my Zivoo', onPressed: _submitManual),
      children: [
        if (widget.isSimulator) ...[
          const InlineNotice(
            message: 'Development simulator. A simulated Zivoo was created and its code filled in.',
          ),
          const SizedBox(height: ZSpace.md),
        ],
        TextField(
          controller: _serial,
          decoration: const InputDecoration(labelText: 'Serial number'),
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: ZSpace.md),
        TextField(
          controller: _code,
          decoration: const InputDecoration(labelText: 'Setup code', helperText: '12 letters and numbers'),
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submitManual(),
        ),
        if (_error != null) ...[
          const SizedBox(height: ZSpace.md),
          InlineNotice(message: _error!, kind: NoticeKind.error),
        ],
      ],
    );
  }
}
