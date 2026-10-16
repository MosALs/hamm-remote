import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/remote_controller.dart';
import '../protocol/errors.dart';
import 'adb_setup_screen.dart';
import 'theme.dart';

/// Loads the TV helper bundled with the app (built from tv_app/).
typedef HelperLoader = Future<Uint8List> Function();

Future<Uint8List> _loadBundledHelper() async {
  final data = await rootBundle.load('assets/tv/keep-awake.apk');
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

enum _Phase { checking, ready, working, failed }

/// Installs or removes the small TV app that keeps the TV on the Wi-Fi while
/// its screen is off, so the phone can turn it on at any time.
class KeepAwakeScreen extends StatefulWidget {
  const KeepAwakeScreen({super.key, required this.controller, this.loadHelper = _loadBundledHelper});

  final RemoteController controller;
  final HelperLoader loadHelper;

  @override
  State<KeepAwakeScreen> createState() => _KeepAwakeScreenState();
}

class _KeepAwakeScreenState extends State<KeepAwakeScreen> {
  _Phase _phase = _Phase.checking;
  KeepAwakeState? _state;
  String? _error;

  RemoteController get c => widget.controller;
  bool get _adbOn => c.tv?.adbEnabled == true;

  @override
  void initState() {
    super.initState();
    unawaited(Future<void>.microtask(_refresh)); // after initState, so setState is allowed
  }

  Future<void> _refresh() async {
    if (!_adbOn) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    setState(() {
      _phase = _Phase.checking;
      _error = null;
    });
    await _run(() async {
      final state = await c.keepAwakeState();
      if (mounted) setState(() => _state = state);
    });
  }

  Future<void> _turnOn() => _run(() async {
        final apk = await widget.loadHelper();
        await c.enableKeepAwake(apk);
        if (mounted) setState(() => _state = KeepAwakeState.on);
      });

  Future<void> _turnOff() => _run(() async {
        await c.disableKeepAwake();
        if (mounted) setState(() => _state = KeepAwakeState.off);
      });

  Future<void> _run(Future<void> Function() job) async {
    setState(() {
      if (_phase != _Phase.checking) _phase = _Phase.working;
      _error = null;
    });
    String? error;
    try {
      await job();
    } on TvException catch (e) {
      error = e.message;
    } on FlutterError {
      error = 'This version of the app does not include the TV helper.';
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _error = error;
      _phase = error == null ? _Phase.ready : _Phase.failed;
    });
  }

  Future<void> _setUpAdb() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AdbSetupScreen(controller: c)));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _phase == _Phase.checking || _phase == _Phase.working;
    final on = _state == KeepAwakeState.on;
    return Scaffold(
      appBar: AppBar(title: const Text('Turn on from the phone')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'When you turn the TV off it soon falls into deep sleep and leaves the Wi-Fi, '
              'so the phone can no longer reach it.',
              style: TextStyle(color: Palette.muted, fontSize: 14.5, height: 1.45),
            ),
            const SizedBox(height: 12),
            const Text(
              'A small helper app on the TV stops that: the screen still goes dark, '
              'but the TV stays on the Wi-Fi, so the power button here works at any time.',
              style: TextStyle(color: Palette.muted, fontSize: 14.5, height: 1.45),
            ),
            const SizedBox(height: 16),
            const _Note(
              icon: Icons.bolt_rounded,
              text: 'While off, the TV then uses more electricity than in deep sleep, '
                  'but far less than when it is on: the screen stays off. Turn this off any time.',
            ),
            const SizedBox(height: 16),
            _StatusCard(phase: _phase, state: _state, adbOn: _adbOn, error: _error),
            const SizedBox(height: 16),
            if (!_adbOn)
              FilledButton(onPressed: _setUpAdb, child: const Text('Set up TV keys over ADB first'))
            else if (_phase == _Phase.failed && _state == null)
              FilledButton(onPressed: _refresh, child: const Text('Try again'))
            else
              FilledButton(
                onPressed: busy ? null : (on ? _turnOff : _turnOn),
                style: on
                    ? FilledButton.styleFrom(backgroundColor: Palette.raisedHi, foregroundColor: Palette.text)
                    : null,
                child: busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : Text(on ? 'Turn off' : 'Turn on'),
              ),
            if (_adbOn) ...[
              const SizedBox(height: 8),
              const Text(
                'The TV must be on and connected while you change this.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Palette.muted, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Palette.warning),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.4, color: Palette.text))),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.phase, required this.state, required this.adbOn, required this.error});

  final _Phase phase;
  final KeepAwakeState? state;
  final bool adbOn;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String text) = switch ((phase, state)) {
      _ when !adbOn => (
          Icons.developer_mode_rounded,
          Palette.warning,
          'The phone installs the helper over ADB. Set up "TV keys over ADB" first.'
        ),
      (_Phase.checking, _) => (Icons.sync_rounded, Palette.muted, 'Checking the TV…'),
      (_Phase.working, _) => (Icons.sync_rounded, Palette.warning, 'Working on the TV…'),
      (_Phase.failed, _) => (Icons.error_outline_rounded, Palette.red, error ?? 'Something went wrong.'),
      (_, KeepAwakeState.on) => (
          Icons.check_circle_rounded,
          Palette.green,
          'On. The TV stays reachable while off, so the power button works any time.'
        ),
      (_, KeepAwakeState.installed) => (
          Icons.info_outline_rounded,
          Palette.warning,
          'The helper is on the TV but not running. Tap Turn on.'
        ),
      _ => (Icons.power_settings_new_rounded, Palette.muted, 'Off. The TV sleeps deeply when turned off.'),
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
