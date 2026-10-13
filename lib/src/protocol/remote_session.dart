import 'dart:async';
import 'dart:io' show TlsException;
import 'dart:typed_data';

import '../crypto/identity.dart';
import 'errors.dart';
import 'messages.dart';
import 'protobuf.dart';
import 'tls_channel.dart';

/// Default port of the remote-control service on Android TV.
const int defaultRemotePort = 6466;

/// Volume as reported by the TV.
class VolumeInfo {
  const VolumeInfo({required this.level, required this.max, required this.muted});

  final int level;
  final int max;
  final bool muted;

  double get fraction => max <= 0 ? 0 : (level / max).clamp(0.0, 1.0);
}

/// Something the TV told us after the session started.
sealed class RemoteEvent {
  const RemoteEvent();
}

class VolumeChanged extends RemoteEvent {
  const VolumeChanged(this.volume);
  final VolumeInfo volume;
}

class PowerChanged extends RemoteEvent {
  const PowerChanged(this.isOn);
  final bool isOn;
}

class CurrentAppChanged extends RemoteEvent {
  const CurrentAppChanged(this.packageName);
  final String packageName;
}

/// The session ended. [error] is null when we closed it ourselves.
class SessionClosed extends RemoteEvent {
  const SessionClosed(this.error);
  final TvException? error;
}

/// A connected remote-control session with a paired TV.
class RemoteSession {
  RemoteSession._(this._channel, this.idleTimeout, this._packageName, this._appVersion);

  final TlsChannel _channel;
  final String _packageName;
  final String _appVersion;

  /// The TV pings every few seconds; silence for this long means the
  /// connection is dead even if the socket has not noticed yet.
  final Duration idleTimeout;

  final StreamController<RemoteEvent> _events = StreamController<RemoteEvent>.broadcast();
  final Completer<void> _ready = Completer<void>();
  Timer? _watchdog;
  int _activeFeatures = Remote.wantedFeatures;
  int _imeCounter = 0;
  int _fieldCounter = 0;
  bool _closedByUs = false;

  String? model;
  String? vendor;
  bool isOn = true;
  VolumeInfo? volume;
  String? currentApp;

  Stream<RemoteEvent> get events => _events.stream;

  bool get isOpen => !_channel.isClosed;

  bool get supportsText => _activeFeatures & Remote.featureIme != 0;

  /// Connects to a paired TV and completes once it is ready for keys.
  ///
  /// Throws [TvUnreachable], [TvNeedsPairing] (not paired, or the TV's
  /// identity no longer matches [expectedServerFingerprint]) or
  /// [TvProtocolError].
  static Future<RemoteSession> connect({
    required String host,
    int port = defaultRemotePort,
    required ClientIdentity identity,
    String? expectedServerFingerprint,
    String packageName = 'com.haam.remote',
    String appVersion = '1.0.0',
    Duration readyTimeout = const Duration(seconds: 8),
    Duration idleTimeout = const Duration(seconds: 16),
  }) async {
    final channel = await TlsChannel.connect(host: host, port: port, identity: identity);
    final serverDer = channel.peerCertificateDer;
    if (expectedServerFingerprint != null &&
        (serverDer == null || sha256Hex(serverDer) != expectedServerFingerprint)) {
      channel.close();
      throw const TvNeedsPairing('The TV identity changed (it may have been reset).');
    }
    final session = RemoteSession._(channel, idleTimeout, packageName, appVersion);
    session._start();
    try {
      await Future.any<void>([
        session._ready.future,
        channel.closed.then<void>((_) => throw session._closeError()),
      ]).timeout(readyTimeout);
    } on TimeoutException {
      session.close();
      throw const TvProtocolError('The TV did not finish connecting.');
    } catch (_) {
      session.close();
      rethrow;
    }
    return session;
  }

  void _start() {
    _channel.listen(_onMessage);
    unawaited(_channel.closed.then((_) => _onClosed()));
    _resetWatchdog();
  }

  /// Why the connection ended before the session became ready. A TV that
  /// does not know our certificate fails the TLS handshake, or (with TLS
  /// 1.3) drops the connection right after it, before saying anything.
  TvException _closeError() {
    if (_channel.closeCause is TlsException || _channel.receivedCount == 0) {
      return const TvNeedsPairing('The TV does not know this phone yet.');
    }
    return _channel.lostError();
  }

  void _resetWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(idleTimeout, () {
      _channel.close();
    });
  }

  void _onClosed() {
    _watchdog?.cancel();
    if (!_events.isClosed) {
      _events.add(SessionClosed(_closedByUs ? null : const TvConnectionLost('Connection to the TV lost.')));
      unawaited(_events.close());
    }
  }

  void _send(Uint8List payload) {
    if (_channel.isClosed) throw const TvConnectionLost('Not connected to the TV.');
    _channel.send(payload);
  }

  void _onMessage(Uint8List raw) {
    _resetWatchdog();
    final ProtoMessage msg;
    try {
      msg = ProtoMessage.parse(raw);
    } on FormatException {
      return; // Ignore a message we cannot read; the TV keeps pinging.
    }
    try {
      _handle(msg);
    } on TvConnectionLost {
      // The channel closed while answering; _onClosed reports it.
    }
  }

  void _handle(ProtoMessage msg) {
    if (msg.has(Remote.fPingRequest)) {
      final ping = msg.messageOf(Remote.fPingRequest)!;
      _send(Remote.pingResponse(ping.int32Of(1)));
    } else if (msg.has(Remote.fConfigure)) {
      final cfg = msg.messageOf(Remote.fConfigure)!;
      final info = cfg.messageOf(2);
      model = info?.stringOf(1);
      vendor = info?.stringOf(2);
      final supported = cfg.int32Of(1);
      _activeFeatures = Remote.wantedFeatures & supported;
      _send(Remote.configure(
        features: _activeFeatures,
        packageName: _packageName,
        appVersion: _appVersion,
      ));
    } else if (msg.has(Remote.fSetActive)) {
      _send(Remote.setActive(_activeFeatures));
    } else if (msg.has(Remote.fStart)) {
      isOn = msg.messageOf(Remote.fStart)!.boolOf(1);
      if (!_ready.isCompleted) _ready.complete();
      _emit(PowerChanged(isOn));
    } else if (msg.has(Remote.fSetVolumeLevel)) {
      final v = msg.messageOf(Remote.fSetVolumeLevel)!;
      final info = VolumeInfo(level: v.intOf(7), max: v.intOf(6), muted: v.boolOf(8));
      volume = info;
      _emit(VolumeChanged(info));
    } else if (msg.has(Remote.fImeKeyInject)) {
      final app = msg.messageOf(Remote.fImeKeyInject)!.messageOf(1)?.stringOf(12);
      if (app != null && app.isNotEmpty) {
        currentApp = app;
        _emit(CurrentAppChanged(app));
      }
    } else if (msg.has(Remote.fImeBatchEdit)) {
      final edit = msg.messageOf(Remote.fImeBatchEdit)!;
      _imeCounter = edit.int32Of(1);
      _fieldCounter = edit.int32Of(2);
    }
    // remote_error and anything newer are ignored on purpose.
  }

  void _emit(RemoteEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// Presses a key. Throws [TvConnectionLost] when not connected.
  void sendKey(int keyCode, [KeyDirection direction = KeyDirection.short]) =>
      _send(Remote.keyInject(keyCode, direction));

  /// Opens an app link (e.g. `market://launch?id=<package>`).
  void launchApp(String link) => _send(Remote.appLink(link));

  /// Types [text] into the text field that has focus on the TV.
  void sendText(String text) {
    if (text.isEmpty) return;
    _send(Remote.imeText(text: text, imeCounter: _imeCounter, fieldCounter: _fieldCounter));
  }

  /// Ends the session.
  void close() {
    _closedByUs = true;
    _channel.close();
  }
}
