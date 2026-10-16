import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/errors.dart';
import 'theme.dart';

/// Sets up control from outside home: the phone and the TV both join the
/// user's private Tailscale network, and the app also tries the TV's
/// Tailscale address.
class AwayScreen extends StatefulWidget {
  const AwayScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<AwayScreen> createState() => _AwayScreenState();
}

class _AwayScreenState extends State<AwayScreen> {
  late final TextEditingController _address = TextEditingController(text: widget.controller.tv?.awayHost ?? '');
  bool _busy = false;
  String? _message;
  bool _ok = false;

  RemoteController get c => widget.controller;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    String? found;
    String? error;
    try {
      found = await c.detectAwayHost();
    } on TvException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (found != null) _address.text = found;
      _ok = false;
      _message = error ??
          (found == null
              ? 'Tailscale is not running on the TV. Open Tailscale on the TV and connect, then try again.'
              : 'Found the TV\'s address. Tap Save and test.');
    });
  }

  Future<void> _saveAndTest() async {
    final host = _address.text.trim();
    if (host.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _message = null;
    });
    final problem = await c.testAwayHost(host);
    if (problem == null) await c.setAwayHost(host);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = problem == null;
      _message = problem ?? 'Saved. The app now reaches the TV from anywhere while Tailscale is on.';
    });
  }

  Future<void> _remove() async {
    await c.setAwayHost(null);
    if (!mounted) return;
    setState(() {
      _address.clear();
      _ok = false;
      _message = 'Removed. The app only connects at home now.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final adbOn = c.tv?.adbEnabled == true;
    final saved = c.tv?.awayHost;
    return Scaffold(
      appBar: AppBar(title: const Text('Control from outside home')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const Text(
              'Use the remote from anywhere while the TV is on: switch to Satellite, close YouTube, turn it off. '
              'The phone and the TV join your own private network with the free Tailscale app.',
              style: TextStyle(color: Palette.muted, fontSize: 14.5, height: 1.45),
            ),
            const SizedBox(height: 20),
            const _Step(
              n: 1,
              title: 'On this phone',
              body: 'Install Tailscale from Google Play, open it and sign in (for example with Google).',
            ),
            const _Step(
              n: 2,
              title: 'On the TV',
              body: 'Open Google Play on the TV, install Tailscale, and sign in with the same account '
                  '(the TV shows a code to approve on the phone). Then press Connect.',
            ),
            const _Step(
              n: 3,
              title: 'Link it here, at home',
              body: 'Tap Find automatically, or type the TV\'s address shown in Tailscale on the TV (it starts with 100.).',
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _address,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(hintText: 'TV address, e.g. 100.101.102.103'),
              onChanged: (_) => setState(() => _message = null),
            ),
            const SizedBox(height: 12),
            if (_message != null) ...[
              _StatusCard(ok: _ok, text: _message!),
              const SizedBox(height: 12),
            ] else if (saved != null) ...[
              _StatusCard(ok: true, text: 'Set up: $saved. ${c.isAway ? 'Connected from outside home now.' : ''}'.trim()),
              const SizedBox(height: 12),
            ],
            FilledButton(
              onPressed: _busy ? null : _saveAndTest,
              child: _busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Save and test'),
            ),
            const SizedBox(height: 8),
            if (adbOn)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: Palette.accent,
                  side: const BorderSide(color: Palette.keyBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _busy ? null : _detect,
                child: const Text('Find automatically'),
              ),
            if (saved != null) TextButton(onPressed: _busy ? null : _remove, child: const Text('Stop using it')),
            const SizedBox(height: 12),
            const Text(
              'The TV has to be on: turning it on from outside home is not possible with this TV. '
              'Keep Tailscale connected on both the phone and the TV.',
              style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final int n;
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
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, color: Palette.accent)),
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
  const _StatusCard({required this.ok, required this.text});

  final bool ok;
  final String text;

  @override
  Widget build(BuildContext context) {
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
          Icon(ok ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: ok ? Palette.green : Palette.warning, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}
