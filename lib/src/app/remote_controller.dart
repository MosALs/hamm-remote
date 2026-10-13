import 'dart:async';

import 'package:flutter/widgets.dart';

import '../crypto/identity.dart';
import '../protocol/errors.dart';
import '../protocol/messages.dart';
import '../protocol/pairing.dart';
import '../protocol/remote_session.dart';
import 'store.dart';

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
  void Function(RemoteSession session)? _pendingAction;
  Timer? _pendingExpiry;

  SavedTv? get tv => _tv;
  LinkState get state => _state;
  String? get message => _message;
  VolumeInfo? get volume => _volume;
  bool get isConnected => _state == LinkState.connected;
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
    final paired = tv.copyWith(serverFingerprint: session.serverFingerprint);
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
      _volume = session.volume;
      _set(LinkState.connected, null);
      _runPending(session);
    } on TvNeedsPairing catch (e) {
      _clearPending();
      _set(LinkState.needsPairing, e.message);
    } on TvException catch (e) {
      _failures++;
      _set(LinkState.offline, _friendly(e));
      _scheduleRetry();
    } catch (e) {
      _failures++;
      _set(LinkState.offline, 'Connection failed: $e');
      _scheduleRetry();
    }
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
  void press(int keyCode, [KeyDirection direction = KeyDirection.short]) =>
      _run((s) => s.sendKey(keyCode, direction));

  void launchApp(String link) => _run((s) => s.launchApp(link));

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
    super.dispose();
  }
}
