import 'dart:async';

import 'package:flutter/widgets.dart';

import '../adb/adb_client.dart';
import '../adb/adb_key.dart';
import '../crypto/identity.dart';
import '../protocol/errors.dart';
import '../protocol/keycodes.dart';
import '../protocol/messages.dart';
import '../protocol/pairing.dart';
import '../protocol/remote_session.dart';
import 'discovery.dart';
import 'store.dart';
import 'wake_on_lan.dart';

/// Connection state shown in the UI.
enum LinkState {
  /// No TV chosen.
  idle,
  connecting,
  connected,

  /// The TV does not know this phone; the user must pair.
  needsPairing,

  /// Could not reach the TV; retrying in the background.
  offline,
}

/// Owns the connection to the current TV and turns button presses into
/// key events. Reconnects automatically while the app is in the foreground.
class RemoteController extends ChangeNotifier with WidgetsBindingObserver {
  RemoteController({
    required AppStore store,
    required ClientIdentity identity,
    this.connector = _defaultConnector,
    this.pairingStarter = _defaultPairingStarter,
    this.adbConnector = _defaultAdbConnector,
    this.wakeSender = _defaultWakeSender,
    this.wakeWindow = const Duration(seconds: 45),
    this.tvFinder = _defaultTvFinder,
  })  : _store = store,
        _identity = identity,
        _tv = store.currentTv {
    WidgetsBinding.instance.addObserver(this);
    final tv = _tv;
    if (tv != null) {
      _state = tv.isPaired ? LinkState.connecting : LinkState.needsPairing;
      // Reconnect to the last TV as soon as the app opens.
      if (tv.isPaired) scheduleMicrotask(() => unawaited(connect()));
    }
  }

  final AppStore _store;
  final ClientIdentity _identity;

  /// Seam for tests.
  final Future<RemoteSession> Function(SavedTv tv, ClientIdentity identity) connector;

  /// Seam for tests.
  final Future<PairingSession> Function(SavedTv tv, ClientIdentity identity) pairingStarter;

  /// Seam for tests.
  final Future<AdbClient> Function(SavedTv tv, AdbKey key, void Function() onApprovalNeeded) adbConnector;

  /// Seam for tests: sends one round of wake-up packets.
  final Future<void> Function(List<String> macs, String host) wakeSender;

  /// How long [wake] keeps signalling and trying to reach the TV. Waking
  /// from deep sleep can take a TV half a minute.
  final Duration wakeWindow;

  /// Seam for tests: lists the TVs announcing themselves on the network now.
  final Future<List<DiscoveredTv>> Function() tvFinder;

  /// Keys the Android TV Remote Service drops on some TVs (TCL-made ones
  /// among them). With ADB enabled they go through ADB, which delivers them
  /// like the physical remote.
  static const Set<int> adbKeys = {
    KeyCode.tvInput,
    KeyCode.settings,
    KeyCode.tv,
    KeyCode.tvSatellite,
    KeyCode.tvInputHdmi1,
    KeyCode.tvInputHdmi2,
    KeyCode.tvInputHdmi3,
    KeyCode.tvInputComposite1,
    KeyCode.tvTerrestrialDigital,
    KeyCode.tvAntennaCable,
    KeyCode.red,
    KeyCode.green,
    KeyCode.yellow,
    KeyCode.blue,
    KeyCode.info,
    KeyCode.guide,
    KeyCode.captions,
    KeyCode.mediaAudioTrack,
    KeyCode.lastChannel,
  };

  /// Incremented when a key that needs ADB is pressed while ADB is off, so
  /// the UI can offer to set it up.
  final ValueNotifier<int> adbSuggestions = ValueNotifier<int>(0);

  AdbClient? _adb;
  Future<AdbClient>? _adbConnecting;
  AdbKey? _adbKey;
  String? _adbError;

  /// The last ADB problem, shown on the remote; null when ADB is fine.
  String? get adbError => _adbError;

  SavedTv? _tv;
  RemoteSession? _session;
  StreamSubscription<RemoteEvent>? _events;
  LinkState _state = LinkState.idle;
  String? _message;
  VolumeInfo? _volume;
  bool _foreground = true;
  bool _disposed = false;
  Future<void>? _connecting;
  Timer? _retry;
  int _failures = 0;
  DateTime? _lastSearch;
  Future<bool>? _waking;
  DateTime? _wakeUntil;
  bool _wakeFailed = false;
  String? _lastWake;
  void Function(RemoteSession session)? _pendingAction;
  Timer? _pendingExpiry;

  SavedTv? get tv => _tv;
  LinkState get state => _state;
  String? get message => _message;
  VolumeInfo? get volume => _volume;
  bool get isConnected => _state == LinkState.connected;

  /// True while [wake] is signalling the TV.
  bool get isWaking => _waking != null;

  /// The last [wake] ended without reaching the TV.
  bool get wakeFailed => _wakeFailed;

  /// One line describing the last [wake] attempt, for diagnostics.
  String? get lastWake => _lastWake;
  bool get supportsText => _session?.supportsText ?? false;
  List<SavedTv> get savedTvs => _store.loadTvs();
  ClientIdentity get identity => _identity;

  static Future<RemoteSession> _defaultConnector(SavedTv tv, ClientIdentity identity) =>
      RemoteSession.connect(
        host: tv.host,
        port: tv.remotePort,
        identity: identity,
        expectedServerFingerprint: tv.serverFingerprint,
      );

  static Future<PairingSession> _defaultPairingStarter(SavedTv tv, ClientIdentity identity) =>
      PairingSession.start(host: tv.host, port: tv.pairingPort, identity: identity);

  static Future<List<DiscoveredTv>> _defaultTvFinder() async {
    final discovery = TvDiscovery();
    try {
      await discovery.start();
      if (discovery.error != null) return const [];
      await Future<void>.delayed(const Duration(seconds: 4));
      return discovery.tvs;
    } finally {
      await discovery.stop();
      discovery.dispose();
    }
  }

  static Future<void> _defaultWakeSender(List<String> macs, String host) => wakeOnLan(macs, host: host);

  static Future<AdbClient> _defaultAdbConnector(SavedTv tv, AdbKey key, void Function() onApprovalNeeded) =>
      AdbClient.connect(host: tv.host, key: key, onApprovalNeeded: onApprovalNeeded);

  // --------------------------------------------------------------------
  // TV selection and pairing
  // --------------------------------------------------------------------

  /// Makes [tv] the current TV and connects to it.
  Future<void> selectTv(SavedTv tv) async {
    final known = _store.loadTvs().where((t) => t.host == tv.host).firstOrNull;
    final chosen = known == null ? tv : known.copyWith(name: tv.name, remotePort: tv.remotePort);
    await _store.saveTv(chosen);
    await _store.setCurrentTvHost(chosen.host);
    _disconnect();
    _closeAdb();
    _tv = chosen;
    _failures = 0;
    _set(chosen.isPaired ? LinkState.connecting : LinkState.needsPairing, null);
    if (chosen.isPaired) await connect();
  }

  /// Forgets [host]; if it was the current TV, goes back to TV selection.
  Future<void> forgetTv(String host) async {
    await _store.removeTv(host);
    if (_tv?.host == host) {
      _disconnect();
      _tv = null;
      _set(LinkState.idle, null);
    } else {
      notifyListeners();
    }
  }

  /// Leaves the current TV (keeps it saved) to pick another.
  Future<void> switchTv() async {
    await _store.setCurrentTvHost(null);
    _disconnect();
    _tv = null;
    _set(LinkState.idle, null);
  }

  /// Asks the current TV to show a pairing code.
  Future<PairingSession> startPairing() {
    final tv = _tv;
    if (tv == null) throw StateError('No TV selected');
    _disconnect();
    return pairingStarter(tv, _identity);
  }

  /// Completes pairing with the code the user typed, then connects.
  Future<void> finishPairing(PairingSession session, String code) async {
    await session.finish(code);
    final tv = _tv;
    if (tv == null) return;
    final paired = tv.copyWith(serverFingerprint: session.serverFingerprint, mac: session.serverMac);
    await _store.saveTv(paired);
    _tv = paired;
    _failures = 0;
    _set(LinkState.connecting, null);
    await connect();
  }

  // --------------------------------------------------------------------
  // Connection
  // --------------------------------------------------------------------

  /// Connects to the current TV if not already connected.
  Future<void> connect() {
    if (_disposed) return Future.value();
    final pending = _connecting;
    if (pending != null) return pending;
    final tv = _tv;
    if (tv == null || !tv.isPaired || _session?.isOpen == true) return Future.value();
    final future = _connect(tv).whenComplete(() => _connecting = null);
    _connecting = future;
    return future;
  }

  Future<void> _connect(SavedTv tv) async {
    _retry?.cancel();
    if (_state != LinkState.connected) _set(LinkState.connecting, null);
    try {
      final session = await connector(tv, _identity);
      if (_disposed || _tv?.host != tv.host || !_foreground) {
        session.close();
        return;
      }
      _attach(session);
      _failures = 0;
      final mac = session.serverMac;
      if (mac != null && _tv?.mac != mac) {
        final updated = _tv!.copyWith(mac: mac);
        _tv = updated;
        unawaited(_store.saveTv(updated));
      }
      _volume = session.volume;
      _wakeFailed = false;
      _set(LinkState.connected, null);
      _ensureAwake(session);
      _runPending(session);
    } on TvNeedsPairing catch (e) {
      _clearPending();
      _set(LinkState.needsPairing, e.message);
    } on TvException catch (e) {
      if (e is TvUnreachable && await _followTv(tv)) return;
      _failures++;
      _set(LinkState.offline, _friendly(e));
      _scheduleRetry();
    } catch (e) {
      _failures++;
      _set(LinkState.offline, 'Connection failed: $e');
      _scheduleRetry();
    }
  }

  /// The TV may have moved to another address, for example after joining
  /// the phone's hotspot or getting a new address from the router. Looks for
  /// TVs on the network and connects to the one with this TV's pinned
  /// identity; another TV can never be picked up by mistake.
  Future<bool> _followTv(SavedTv tv) async {
    final fingerprint = tv.serverFingerprint;
    final last = _lastSearch;
    if (fingerprint == null || (last != null && DateTime.now().difference(last) < const Duration(seconds: 20))) {
      return false;
    }
    _lastSearch = DateTime.now();
    final List<DiscoveredTv> found;
    try {
      found = await tvFinder();
    } on Object {
      return false;
    }
    for (final candidate in found) {
      if (_disposed || _tv?.host != tv.host) return false;
      if (candidate.host == tv.host && candidate.port == tv.remotePort) continue;
      final moved = tv.copyWith(host: candidate.host, remotePort: candidate.port);
      final RemoteSession session;
      try {
        session = await connector(moved, _identity); // checks the pinned identity
      } on Object {
        continue; // another TV, or not reachable either
      }
      if (_disposed || _tv?.host != tv.host || !_foreground) {
        session.close();
        return false;
      }
      _closeAdb();
      await _store.removeTv(tv.host);
      await _store.saveTv(moved);
      await _store.setCurrentTvHost(moved.host);
      _tv = moved;
      _attach(session);
      _failures = 0;
      _volume = session.volume;
      _wakeFailed = false;
      _set(LinkState.connected, null);
      _ensureAwake(session);
      _runPending(session);
      return true;
    }
    return false;
  }

  String _friendly(TvException e) => switch (e) {
        TvUnreachable() => 'Can\'t reach the TV. Check it is on and on the same Wi-Fi.',
        TvConnectionLost() => 'Connection to the TV was lost.',
        _ => e.message,
      };

  void _attach(RemoteSession session) {
    _session = session;
    unawaited(_events?.cancel());
    _events = session.events.listen((event) {
      switch (event) {
        case VolumeChanged(:final volume):
          _volume = volume;
          notifyListeners();
        case PowerChanged():
          _ensureAwake(session);
          notifyListeners();
        case CurrentAppChanged():
          break;
        case SessionClosed(:final error):
          if (!identical(_session, session)) return;
          _session = null;
          if (error != null && !_disposed) {
            _set(LinkState.offline, 'Reconnecting…');
            _scheduleRetry(immediate: true);
          }
      }
    });
  }

  void _scheduleRetry({bool immediate = false}) {
    _retry?.cancel();
    if (_disposed || !_foreground || _tv?.isPaired != true) return;
    final seconds = immediate ? 0 : [1, 2, 4, 8, 15][(_failures - 1).clamp(0, 4)];
    _retry = Timer(Duration(seconds: seconds), () => unawaited(connect()));
  }

  void _disconnect() {
    _retry?.cancel();
    _clearPending();
    unawaited(_events?.cancel());
    _events = null;
    _session?.close();
    _session = null;
  }

  // --------------------------------------------------------------------
  // Commands
  // --------------------------------------------------------------------

  /// Presses [keyCode]. When disconnected, the press is kept for a few
  /// seconds and sent as soon as the connection comes back.
  void press(int keyCode, [KeyDirection direction = KeyDirection.short]) {
    if (keyCode == KeyCode.power && !isConnected) {
      unawaited(wake());
      return;
    }
    if (adbKeys.contains(keyCode) && direction == KeyDirection.short) {
      if (_tv?.adbEnabled == true) {
        unawaited(_adbPress(keyCode));
        return;
      }
      adbSuggestions.value++;
    }
    _run((s) => s.sendKey(keyCode, direction));
  }

  /// Turns the TV on from the phone.
  ///
  /// A TV that was just turned off still has its network up, and the power
  /// key goes over the remote link. After a while it sleeps deeply and only a
  /// Wake-on-LAN packet reaches it, so this sends one to every known MAC each
  /// second while trying to reconnect, then presses power if the TV came
  /// back with its screen still off. Returns false when no MAC is known yet
  /// (it is learned when pairing, and over ADB).
  Future<bool> wake() {
    final running = _waking;
    if (running != null) return running;
    final tv = _tv;
    final macs = tv?.wakeMacs ?? const <String>[];
    if (tv == null || macs.isEmpty) {
      unawaited(connect());
      return Future.value(false);
    }
    final future = _wake(tv, macs).whenComplete(() {
      _waking = null;
      if (!_disposed) notifyListeners();
    });
    _waking = future;
    return future;
  }

  Future<bool> _wake(SavedTv tv, List<String> macs) async {
    _retry?.cancel();
    _failures = 0;
    _wakeFailed = false;
    final deadline = DateTime.now().add(wakeWindow);
    _wakeUntil = deadline;
    _set(LinkState.connecting, 'Waking the TV…');

    final started = DateTime.now();
    var sendError = '';
    var rounds = 0;
    Future<void> pulse() async {
      try {
        await wakeSender(macs, tv.host);
        rounds++;
      } on Object catch (e) {
        sendError = '$e';
      }
    }

    await pulse();
    final pulses = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(pulse()));
    try {
      while (!_disposed && _tv?.host == tv.host && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (_disposed || isConnected) break;
        await connect();
        if (_disposed || isConnected) break;
        _retry?.cancel(); // this loop does the retrying while waking
        _set(LinkState.connecting, 'Waking the TV…');
      }
    } finally {
      pulses.cancel();
    }
    final took = DateTime.now().difference(started).inSeconds;
    _lastWake = '${started.toIso8601String()}: sent $rounds rounds to ${macs.join(', ')} via ${tv.host}; '
        '${isConnected ? 'TV answered after ${took}s' : 'no answer in ${took}s'}'
        '${sendError.isEmpty ? '' : '; send error: $sendError'}';
    if (_disposed) return true;
    if (isConnected) return true;
    _wakeUntil = null;
    _wakeFailed = true;
    _set(
      LinkState.offline,
      sendError.isNotEmpty ? 'Could not send the wake-up signal: $sendError' : 'The TV did not wake up.',
    );
    _scheduleRetry();
    return true;
  }

  /// While waking, a TV that answers with its screen off gets the power key.
  /// (A session is ready only once the TV has reported its power state.)
  void _ensureAwake(RemoteSession session) {
    final until = _wakeUntil;
    if (until == null || !identical(session, _session)) return;
    if (DateTime.now().isAfter(until)) {
      _wakeUntil = null;
      return;
    }
    _wakeUntil = null;
    if (!session.isOn) session.sendKey(KeyCode.power, KeyDirection.short);
  }

  // --------------------------------------------------------------------
  // ADB channel
  // --------------------------------------------------------------------

  AdbKey get _key => _adbKey ??= AdbKey.fromIdentity(_identity);

  /// Connects over ADB; the TV shows "Allow debugging?" the first time.
  /// On success ADB is remembered for this TV.
  Future<void> enableAdb({void Function()? onApprovalNeeded}) async {
    final tv = _tv;
    if (tv == null) throw StateError('No TV selected');
    _closeAdb();
    final client = await adbConnector(tv, _key, onApprovalNeeded ?? () {});
    if (_disposed || _tv?.host != tv.host) {
      client.close();
      return;
    }
    _adb = client;
    _adbError = null;
    final updated = (_tv ?? tv).copyWith(adbEnabled: true);
    await _store.saveTv(updated);
    _tv = updated;
    notifyListeners();
    await _learnInterfaceMacs(client);
  }

  /// Collects what decides whether the TV can be woken over the network:
  /// its model, interfaces, wake/standby settings and power state (read over
  /// ADB while the TV is on), plus what the app knows and last tried.
  Future<String> powerDiagnostics() async {
    final tv = _tv;
    final out = StringBuffer()
      ..writeln('HAAM Remote power report')
      ..writeln('TV: ${tv?.name} at ${tv?.host}')
      ..writeln('Certificate MAC: ${tv?.mac ?? 'unknown'}')
      ..writeln('Interface MACs: ${tv?.interfaceMacs.isEmpty ?? true ? 'not read yet' : tv!.interfaceMacs.join(', ')}')
      ..writeln('Wake addresses: ${tv?.wakeMacs.join(', ') ?? '-'}')
      ..writeln('Last wake: ${_lastWake ?? 'none yet'}')
      ..writeln('Connected now: $isConnected, screen on: ${_session?.isOn}');
    if (tv == null || !tv.adbEnabled) {
      out.writeln('\nADB is off, so the TV settings could not be read.');
      return out.toString();
    }
    final AdbClient client;
    try {
      client = await _adbClient();
    } on Object catch (e) {
      out.writeln('\nCould not reach the TV over ADB: $e');
      return out.toString();
    }
    for (final (title, command) in diagnosticCommands) {
      out.writeln('\n## $title');
      try {
        final text = (await client.shell(command)).trim();
        out.writeln(text.isEmpty ? '(nothing)' : _clip(text, 2500));
      } on Object catch (e) {
        out.writeln('(failed: $e)');
      }
    }
    if (tv.interfaceMacs.isEmpty) await _learnInterfaceMacs(client);
    return out.toString();
  }

  static String _clip(String text, int max) => text.length <= max ? text : '${text.substring(0, max)}\n…';

  /// Saves the MACs of the TV's Wi-Fi and Ethernet interfaces, so Wake-on-LAN
  /// reaches the interface the TV actually uses. Best effort.
  Future<void> _learnInterfaceMacs(AdbClient client) async {
    final List<String> macs;
    try {
      macs = parseInterfaceMacs(await client.shell(interfaceListCommand));
    } on Object {
      return;
    }
    final tv = _tv;
    if (_disposed || tv == null || macs.isEmpty) return;
    if (tv.interfaceMacs.length == macs.length && tv.interfaceMacs.every(macs.contains)) return;
    final updated = tv.copyWith(interfaceMacs: macs);
    _tv = updated;
    await _store.saveTv(updated);
  }

  /// Stops using ADB for this TV.
  Future<void> disableAdb() async {
    _closeAdb();
    final tv = _tv;
    if (tv == null) return;
    final updated = SavedTv(
      name: tv.name,
      host: tv.host,
      remotePort: tv.remotePort,
      pairingPort: tv.pairingPort,
      serverFingerprint: tv.serverFingerprint,
      mac: tv.mac,
      interfaceMacs: tv.interfaceMacs,
    );
    await _store.saveTv(updated);
    _tv = updated;
    _adbError = null;
    notifyListeners();
  }

  Future<AdbClient> _adbClient() {
    final open = _adb;
    if (open != null && open.isOpen) return Future.value(open);
    final pending = _adbConnecting;
    if (pending != null) return pending;
    final tv = _tv!;
    final future = adbConnector(tv, _key, () {
      _adbError = 'Allow debugging on the TV (tick "Always allow").';
      notifyListeners();
    }).then((client) {
      _adb = client;
      if (_tv?.interfaceMacs.isEmpty ?? false) unawaited(_learnInterfaceMacs(client));
      return client;
    }).whenComplete(() => _adbConnecting = null);
    _adbConnecting = future;
    return future;
  }

  Future<void> _adbPress(int keyCode) => _adbShell('input keyevent $keyCode');

  Future<void> _adbShell(String command) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      // Closed on purpose (app paused, TV switched, disposed): don't reopen.
      if (_disposed || _tv?.adbEnabled != true) return;
      try {
        final client = await _adbClient();
        await client.shell(command);
        if (_adbError != null) {
          _adbError = null;
          notifyListeners();
        }
        return;
      } on TvConnectionLost {
        if (_disposed) return;
        _closeAdb(); // the TV dropped an idle connection; reconnect once
      } on TvException catch (e) {
        _setAdbError(e.message);
        return;
      } on TimeoutException {
        _closeAdb();
        _setAdbError('The TV did not answer over ADB.');
        return;
      } catch (e) {
        _closeAdb();
        _setAdbError('ADB failed: $e');
        return;
      }
    }
    _setAdbError('Lost the ADB connection to the TV.');
  }

  void _setAdbError(String message) {
    if (_disposed) return;
    _adbError = message;
    notifyListeners();
  }

  void _closeAdb() {
    _adb?.close();
    _adb = null;
  }

  void launchApp(String link) => _run((s) => s.launchApp(link));

  /// Opens [app]: by package over ADB when enabled (works for every app),
  /// otherwise through its deep link.
  void openApp(TvApp app) {
    if (_tv?.adbEnabled == true) {
      unawaited(_adbShell(app.adbLaunchCommand));
    } else {
      launchApp(app.launchLink);
    }
  }

  void sendText(String text) => _run((s) => s.sendText(text));

  void _run(void Function(RemoteSession session) action) {
    final session = _session;
    if (session != null && session.isOpen) {
      try {
        action(session);
        return;
      } on TvConnectionLost {
        // Fall through: queue it and reconnect.
      }
    }
    if (_tv?.isPaired != true || _state == LinkState.needsPairing) return;
    _pendingAction = action;
    _pendingExpiry?.cancel();
    _pendingExpiry = Timer(const Duration(seconds: 5), _clearPending);
    unawaited(connect());
  }

  void _runPending(RemoteSession session) {
    final action = _pendingAction;
    _clearPending();
    if (action == null) return;
    try {
      action(session);
    } on TvConnectionLost {
      // Dropped again; the reconnect loop takes over.
    }
  }

  void _clearPending() {
    _pendingAction = null;
    _pendingExpiry?.cancel();
    _pendingExpiry = null;
  }

  // --------------------------------------------------------------------
  // Lifecycle
  // --------------------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        _failures = 0;
        unawaited(connect());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _foreground = false;
        _disconnect();
        _closeAdb();
        if (_state == LinkState.connected || _state == LinkState.offline) {
          _set(LinkState.connecting, null);
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _set(LinkState state, String? message) {
    if (_disposed) return;
    _state = state;
    _message = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _disconnect();
    _closeAdb();
    adbSuggestions.dispose();
    super.dispose();
  }
}

/// Shell commands for [RemoteController.powerDiagnostics]. Each one is
/// filtered so the report stays short enough to paste into a message.
const List<(String, String)> diagnosticCommands = [
  (
    'TV',
    'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.build.version.release; '
        'getprop ro.build.display.id',
  ),
  ('Network', 'ip -o link | grep -E "wlan|eth"; ip -o -4 addr | grep -E "wlan|eth"'),
  (
    'Wake and standby settings',
    'for t in global secure system; do settings list \$t | '
        'grep -i -E "wake|wol|wowlan|standby|quick|instant|boot|suspend|cec|str_|power_on|poweron" | '
        'sed "s/^/\$t: /"; done',
  ),
  (
    'Vendor properties',
    'getprop | grep -i -E "wol|wake|wowlan|standby|str_|suspend|quick|instant|fastboot|poweron|power_on" | head -80',
  ),
  (
    'Power state',
    'dumpsys power | grep -E "mWakefulness=|mStayOn=|mScreenOffTimeoutSetting=|mSleepTimeoutSetting=" | head -10',
  ),
];
