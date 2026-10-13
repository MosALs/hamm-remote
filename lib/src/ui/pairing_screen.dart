import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/remote_controller.dart';
import '../protocol/errors.dart';
import '../protocol/pairing.dart';
import 'theme.dart';

enum _Step { requesting, enterCode, verifying, failed }

/// Asks the TV for a code and lets the user type it.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _code = TextEditingController();
  final FocusNode _focus = FocusNode();
  PairingSession? _session;
  _Step _step = _Step.requesting;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_request());
  }

  @override
  void dispose() {
    if (!_done) _session?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    _session?.cancel();
    _session = null;
    _code.clear();
    if (_step != _Step.requesting || _error != null) {
      setState(() {
        _step = _Step.requesting;
        _error = null;
      });
    }
    try {
      final session = await widget.controller.startPairing();
      if (!mounted) {
        session.cancel();
        return;
      }
      setState(() {
        _session = session;
        _step = _Step.enterCode;
      });
      _focus.requestFocus();
    } on TvException catch (e) {
      _fail(e is TvUnreachable
          ? 'Can\'t reach the TV. Make sure it is on and on the same Wi-Fi as this phone.'
          : e.message);
    } catch (e) {
      _fail('Pairing could not start: $e');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _step = _Step.failed;
      _error = message;
    });
  }

  Future<void> _submit() async {
    final session = _session;
    if (session == null || _step == _Step.verifying || _code.text.length != 6) return;
    setState(() {
      _step = _Step.verifying;
      _error = null;
    });
    try {
      await widget.controller.finishPairing(session, _code.text);
      _done = true;
      if (mounted) Navigator.of(context).pop(true);
    } on PairingCodeMismatch {
      // Nothing was sent; the TV still shows the same code.
      if (!mounted) return;
      setState(() {
        _step = _Step.enterCode;
        _error = 'That code doesn\'t match. Check similar characters like B and 8, or D and 0.';
      });
      _code.selection = TextSelection(baseOffset: 0, extentOffset: _code.text.length);
      _focus.requestFocus();
    } on TvException catch (e) {
      _fail(e is PairingRejected
          ? 'The TV rejected the code. Request a new code and try again.'
          : 'Pairing was interrupted: ${e.message}');
    } catch (e) {
      _fail('Pairing failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tvName = widget.controller.tv?.name ?? 'your TV';
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Cancel',
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text('Pair with TV'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            const SizedBox(height: 12),
            const Center(child: Icon(Icons.tv_rounded, size: 64, color: Palette.accent)),
            const SizedBox(height: 20),
            Text(
              switch (_step) {
                _Step.requesting => 'Asking $tvName for a code…',
                _Step.failed => 'Pairing didn\'t work',
                _ => 'Enter the code shown on $tvName',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              _step == _Step.failed
                  ? (_error ?? '')
                  : 'A 6-character code appears on the TV screen. You only need to do this once.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Palette.muted, fontSize: 14.5, height: 1.4),
            ),
            const SizedBox(height: 28),
            if (_step == _Step.requesting)
              const Center(child: CircularProgressIndicator())
            else if (_step == _Step.failed)
              FilledButton(onPressed: _request, child: const Text('Try again'))
            else ...[
              _CodeField(
                controller: _code,
                focusNode: _focus,
                enabled: _step == _Step.enterCode,
                onComplete: _submit,
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Palette.red, fontSize: 13.5),
                      ),
              ),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _code,
                builder: (context, _) => FilledButton(
                  onPressed: _step == _Step.enterCode && _code.text.length == 6 ? _submit : null,
                  child: _step == _Step.verifying
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : const Text('Pair'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _step == _Step.verifying ? null : _request,
                child: const Text('Show a new code'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Six boxes showing the typed code, backed by one hidden text field so
/// paste and the system keyboard work normally.
class _CodeField extends StatelessWidget {
  const _CodeField({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onComplete,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: focusNode.requestFocus,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The real input: invisible but focusable.
          Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              autocorrect: false,
              enableSuggestions: false,
              showCursor: false,
              keyboardType: TextInputType.visiblePassword,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                LengthLimitingTextInputFormatter(6),
                _UpperCase(),
              ],
              onChanged: (value) {
                if (value.length == 6) onComplete();
              },
              onSubmitted: (_) => onComplete(),
            ),
          ),
          IgnorePointer(
            child: ListenableBuilder(
              listenable: Listenable.merge([controller, focusNode]),
              builder: (context, _) {
                final text = controller.text;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 6; i++) ...[
                      if (i == 3) const SizedBox(width: 10),
                      _box(
                        i < text.length ? text[i] : '',
                        active: focusNode.hasFocus && (i == text.length || (i == 5 && text.length == 6)),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _box(String char, {required bool active}) {
    return Container(
      width: 40,
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.key,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? Palette.accent : Palette.keyBorder,
          width: active ? 2 : 1,
        ),
      ),
      child: Text(
        char,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
