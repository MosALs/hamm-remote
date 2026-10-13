import 'dart:async';

import 'package:flutter/material.dart';

import '../app/remote_controller.dart';
import '../protocol/keycodes.dart';
import 'adb_setup_screen.dart';
import 'pairing_screen.dart';
import 'tabs/apps_tab.dart';
import 'tabs/cast_tab.dart';
import 'tabs/keypad_tab.dart';
import 'tabs/remote_tab.dart';
import 'theme.dart';
import 'wake_help_sheet.dart';
import 'widgets/press_target.dart';

/// The remote: a header with the TV and power, four tabs, and a tab bar.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.controller});

  final RemoteController controller;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  RemoteController get c => widget.controller;
  String? _autoPairedHost;
  bool _pairingOpen = false;
  bool _adbHintShown = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(_maybeAutoPair);
    c.adbSuggestions.addListener(_suggestAdb);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPair());
  }

  @override
  void dispose() {
    c.removeListener(_maybeAutoPair);
    c.adbSuggestions.removeListener(_suggestAdb);
    super.dispose();
  }

  /// A TV-specific key was pressed without ADB: explain once per screen.
  void _suggestAdb() {
    if (!mounted || _adbHintShown) return;
    _adbHintShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Your TV may ignore this key over Wi-Fi. Turn on TV keys over ADB to fix it.'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'Set up', onPressed: () => unawaited(_openAdbSetup())),
      ),
    );
  }

  Future<void> _openAdbSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => AdbSetupScreen(controller: c)),
    );
  }

  /// Opens pairing by itself the first time a never-paired TV is chosen.
  void _maybeAutoPair() {
    final tv = c.tv;
    if (!mounted || tv == null || tv.isPaired || c.state != LinkState.needsPairing) return;
    if (_autoPairedHost == tv.host) return;
    _autoPairedHost = tv.host;
    unawaited(_openPairing());
  }

  Future<void> _openPairing() async {
    if (_pairingOpen) return;
    _pairingOpen = true;
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => PairingScreen(controller: c),
      ),
    );
    _pairingOpen = false;
  }

  Future<void> _openTvMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => _TvMenu(controller: c),
    );
    switch (choice) {
      case 'pair':
        await _openPairing();
      case 'adb':
        await _openAdbSetup();
      case 'wake':
        if (mounted) await showWakeHelpSheet(context, c);
      case 'switch':
        await c.switchTv();
      case 'forget':
        final host = c.tv?.host;
        if (host != null) await c.forgetTv(host);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      RemoteTab(controller: c),
      KeypadTab(controller: c),
      AppsTab(controller: c),
      CastTab(controller: c),
    ];
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1.2),
            radius: 1.3,
            colors: [Palette.backgroundTop, Palette.background],
            stops: [0, 0.55],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: c,
            builder: (context, _) => Column(
              children: [
                _Header(controller: c, onMenu: _openTvMenu),
                _StatusBanner(
                  controller: c,
                  onPair: _openPairing,
                  onAdb: _openAdbSetup,
                  onWakeHelp: () => unawaited(showWakeHelpSheet(context, c)),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: IndexedStack(index: _tab, sizing: StackFit.expand, children: tabs),
                  ),
                ),
                _TabBar(index: _tab, onSelect: (i) => setState(() => _tab = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.onMenu});

  final RemoteController controller;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final tv = controller.tv;
    final volume = controller.volume;
    final (Color dot, String status) = switch (controller.state) {
      LinkState.connected => (Palette.ok, volume == null ? 'Connected' : 'Connected · Vol ${volume.level}'),
      LinkState.connecting => (Palette.warning, controller.message ?? 'Connecting…'),
      LinkState.offline => (Palette.red, 'Offline'),
      LinkState.needsPairing => (Palette.warning, 'Not paired'),
      LinkState.idle => (Palette.muted, ''),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Palette.surface,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onMenu,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Palette.line),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(11)),
                        child: const Icon(Icons.tv_rounded, color: Palette.accent, size: 19),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tv?.name ?? 'TV',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: dot,
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.7), blurRadius: 6)],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    status,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Palette.muted,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.expand_more_rounded, color: Palette.muted, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _PowerKey(controller: controller),
        ],
      ),
    );
  }
}

class _PowerKey extends StatelessWidget {
  const _PowerKey({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    return PressTarget(
      onPress: () => controller.press(KeyCode.power),
      semanticLabel: 'Power',
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 54,
        height: 54,
        transform: Matrix4.diagonal3Values(pressed ? 0.94 : 1, pressed ? 0.94 : 1, 1),
        transformAlignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A1D22), Color(0xFF1E1519)],
          ),
          border: Border.all(color: Palette.power.withValues(alpha: 0.28)),
          boxShadow: [
            BoxShadow(
              color: Palette.power.withValues(alpha: pressed ? 0.2 : 0.45),
              blurRadius: 22,
              spreadRadius: -8,
            ),
          ],
        ),
        child: const Icon(Icons.power_settings_new_rounded, color: Palette.power, size: 26),
      ),
    );
  }
}

class _TvMenu extends StatelessWidget {
  const _TvMenu({required this.controller});

  final RemoteController controller;

  @override
  Widget build(BuildContext context) {
    final adbOn = controller.tv?.adbEnabled == true;
    Widget item(String value, IconData icon, String title, String subtitle, {Color? color}) => ListTile(
          leading: Icon(icon, color: color ?? Palette.accent),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          subtitle: Text(subtitle, style: const TextStyle(color: Palette.muted, fontSize: 13)),
          onTap: () => Navigator.of(context).pop(value),
        );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(
            'adb',
            Icons.developer_mode_rounded,
            adbOn ? 'TV keys over ADB: on' : 'Fix TV keys (ADB)',
            'Input, Settings, sources and coloured keys',
          ),
          item('wake', Icons.power_settings_new_rounded, 'Turning on from the phone', 'If the TV won\'t turn on'),
          item('pair', Icons.link_rounded, 'Pair again', 'If the TV stopped responding'),
          item('switch', Icons.swap_horiz_rounded, 'Switch TV', 'Pick another TV'),
          item('forget', Icons.delete_outline_rounded, 'Forget this TV', 'Remove it from this phone', color: Palette.red),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = [
    (Icons.radio_button_checked_rounded, 'Remote'),
    (Icons.dialpad_rounded, 'Keypad'),
    (Icons.apps_rounded, 'Apps'),
    (Icons.cast_rounded, 'Cast'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 8 + bottom),
      decoration: const BoxDecoration(
        color: Color(0xF00B0D12),
        border: Border(top: BorderSide(color: Palette.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                label: _items[i].$2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == index ? Palette.accent.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_items[i].$1, size: 22, color: i == index ? Palette.accent : Palette.muted),
                        const SizedBox(height: 4),
                        Text(
                          _items[i].$2,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: i == index ? Palette.accent : Palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller, required this.onPair, required this.onAdb, required this.onWakeHelp});

  final RemoteController controller;
  final VoidCallback onPair;
  final VoidCallback onAdb;
  final VoidCallback onWakeHelp;

  @override
  Widget build(BuildContext context) {
    final Widget? content = switch (controller.state) {
      LinkState.needsPairing => _banner(
          icon: Icons.link_rounded,
          text: 'Pair this phone with the TV to start.',
          action: 'Pair',
          onAction: onPair,
        ),
      LinkState.offline when controller.wakeFailed => _banner(
          icon: Icons.power_settings_new_rounded,
          text: 'The TV didn\'t wake up. A TV setting can fix this.',
          action: 'Fix',
          onAction: onWakeHelp,
        ),
      LinkState.offline when controller.tv?.wakeMacs.isNotEmpty ?? false => _banner(
          icon: Icons.power_settings_new_rounded,
          text: 'The TV is off or unreachable.',
          action: 'Turn on',
          onAction: () => unawaited(controller.wake()),
        ),
      LinkState.offline => _banner(
          icon: Icons.wifi_off_rounded,
          text: controller.message ?? 'Can\'t reach the TV.',
          action: 'Retry',
          onAction: () => unawaited(controller.connect()),
        ),
      LinkState.connected when controller.adbError != null => _banner(
          icon: Icons.developer_mode_rounded,
          text: controller.adbError!,
          action: 'Fix',
          onAction: onAdb,
        ),
      _ => null,
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: content ?? const SizedBox(width: double.infinity),
    );
  }

  Widget _banner({
    required IconData icon,
    required String text,
    required String action,
    required VoidCallback onAction,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 2),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Palette.warning),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600))),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}
