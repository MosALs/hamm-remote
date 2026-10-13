import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/errors.dart';
import 'theme.dart';

enum _Phase { idle, connecting, waitingForTv, done, failed }

/// Turns on the ADB channel used for TV-specific keys (Input, Settings,
/// sources, colour keys) that the TV ignores over the normal remote link.
class AdbSetupScreen extends StatefulWidget {
  const AdbSetupScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<AdbSetupScreen> createState() => _AdbSetupScreenState();
}

class _AdbSetupScreenState extends State<AdbSetupScreen> {
  late _Phase _phase = widget.controller.tv?.adbEnabled == true ? _Phase.done : _Phase.idle;
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _phase = _Phase.connecting;
      _error = null;
    });
    try {
      await widget.controller.enableAdb(onApprovalNeeded: () {
        if (mounted) setState(() => _phase = _Phase.waitingForTv);
      });
      if (mounted) setState(() => _phase = _Phase.done);
    } on TvException catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = 'Could not connect: $e';
        });
      }
    }
  }

  Future<void> _turnOff() async {
    await widget.controller.disableAdb();
    if (mounted) setState(() => _phase = _Phase.idle);
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.connecting || _phase == _Phase.waitingForTv;
    return Scaffold(
      appBar: AppBar(title: const Text('TV keys over ADB')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Your TV ignores some keys sent over Wi-Fi: Input, Settings, the sources and the coloured keys. '
              'ADB delivers them exactly like the physical remote. Set it up once:',
              style: TextStyle(color: Palette.muted, fontSize: 14.5, height: 1.45),
            ),
            const SizedBox(height: 20),
            const _Step(
              number: 1,
              title: 'Turn on developer mode',
              body: 'On the TV open Settings > Device Preferences > About and click Build 7 times, '
                  'until it says you are a developer.',
            ),
            const _Step(
              number: 2,
              title: 'Turn on debugging',
              body: 'Go back to Device Preferences > Developer options and turn on USB debugging. '
                  'If you see Network debugging (or ADB over network), turn that on too.',
            ),
            const _Step(
              number: 3,
              title: 'Connect and allow',
              body: 'Tap Connect below. The TV asks "Allow debugging?": tick "Always allow from this computer" and choose OK.',
            ),
            const SizedBox(height: 12),
            _StatusCard(phase: _phase, error: _error),
            const SizedBox(height: 16),
            if (_phase == _Phase.done) ...[
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
              const SizedBox(height: 8),
              TextButton(onPressed: _turnOff, child: const Text('Stop using ADB')),
            ] else
              FilledButton(
                onPressed: busy ? null : _connect,
                child: busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(_phase == _Phase.failed ? 'Try again' : 'Connect'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});

  final int number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Palette.key, shape: BoxShape.circle),
            child: Text('$number', style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.accent)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: Palette.muted, fontSize: 14, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.phase, required this.error});

  final _Phase phase;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch (phase) {
      _Phase.idle => (Icons.info_outline_rounded, Palette.muted, 'Not connected yet.'),
      _Phase.connecting => (Icons.sync_rounded, Palette.warning, 'Connecting to the TV…'),
      _Phase.waitingForTv => (
          Icons.tv_rounded,
          Palette.warning,
          'Look at the TV: choose OK on "Allow debugging?" (tick "Always allow").'
        ),
      _Phase.done => (Icons.check_circle_rounded, Palette.green, 'Connected. Input, Settings and the coloured keys now go through ADB.'),
      _Phase.failed => (Icons.error_outline_rounded, Palette.red, error ?? 'Could not connect.'),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.keyBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}
