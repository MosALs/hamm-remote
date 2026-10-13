import 'dart:async';

import 'package:flutter/material.dart';

import '../app/discovery.dart';
import '../app/remote_controller.dart';
import '../app/store.dart';
import '../protocol/remote_session.dart';
import 'theme.dart';

/// Lists saved TVs and TVs found on the Wi-Fi, or takes an IP address.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.controller, this.discovery});

  final RemoteController controller;

  /// Injected in tests; created here otherwise.
  final TvDiscovery? discovery;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TvDiscovery _discovery = widget.discovery ?? TvDiscovery();

  @override
  void initState() {
    super.initState();
    unawaited(_discovery.start());
  }

  @override
  void dispose() {
    if (widget.discovery == null) _discovery.dispose();
    super.dispose();
  }

  Future<void> _choose(String name, String host, int port) =>
      widget.controller.selectTv(SavedTv(name: name, host: host, remotePort: port));

  Future<void> _enterAddress() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (result != null) await _choose('Android TV ($result)', result, defaultRemotePort);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([_discovery, widget.controller]),
          builder: (context, _) {
            final saved = widget.controller.savedTvs;
            final savedHosts = {for (final t in saved) t.host};
            final found = _discovery.tvs.where((t) => !savedHosts.contains(t.host)).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              children: [
                const Text(
                  'Connect to your TV',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.15),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your phone and the TV must be on the same Wi-Fi, and the TV must be on.',
                  style: TextStyle(color: Palette.muted, fontSize: 15, height: 1.4),
                ),
                if (saved.isNotEmpty) ...[
                  const _SectionTitle('Your TVs'),
                  for (final tv in saved)
                    _TvTile(
                      name: tv.name,
                      subtitle: tv.isPaired ? '${tv.host} · paired' : tv.host,
                      onTap: () => unawaited(widget.controller.selectTv(tv)),
                      onForget: () => unawaited(widget.controller.forgetTv(tv.host)),
                    ),
                ],
                _SectionTitle(
                  'On this network',
                  trailing: _discovery.isRunning
                      ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                ),
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      _discovery.error ??
                          (_discovery.isRunning ? 'Searching for TVs…' : 'No TVs found.'),
                      style: const TextStyle(color: Palette.muted, fontSize: 14),
                    ),
                  ),
                for (final tv in found)
                  _TvTile(
                    name: tv.name,
                    subtitle: tv.host,
                    onTap: () => unawaited(_choose(tv.name, tv.host, tv.port)),
                  ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _enterAddress,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                  label: const Text('Enter TV IP address'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Find it on the TV under Settings → Network & Internet → your Wi-Fi network.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Palette.muted, fontSize: 12.5, height: 1.4),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              color: Palette.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _TvTile extends StatelessWidget {
  const _TvTile({required this.name, required this.subtitle, required this.onTap, this.onForget});

  final String name;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback? onForget;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Palette.panel,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Palette.key,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.tv_rounded, color: Palette.accent, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 13)),
                    ],
                  ),
                ),
                if (onForget != null)
                  IconButton(
                    tooltip: 'Forget',
                    icon: const Icon(Icons.delete_outline_rounded, color: Palette.muted),
                    onPressed: onForget,
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.chevron_right_rounded, color: Palette.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final TextEditingController _text = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _text.text.trim();
    final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(value);
    final validIp = ipv4 != null && [1, 2, 3, 4].every((g) => int.parse(ipv4.group(g)!) <= 255);
    final validHost = RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$').hasMatch(value) &&
        value.contains(RegExp('[a-zA-Z]'));
    if (!validIp && !validHost) {
      setState(() => _error = 'Enter an address like 192.168.1.20');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('TV IP address'),
      content: TextField(
        controller: _text,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(hintText: '192.168.1.20', errorText: _error),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
