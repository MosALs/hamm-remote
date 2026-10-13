import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../crypto/identity.dart';
import 'errors.dart';
import 'framing.dart';

/// A TLS connection to the TV that sends and receives length-prefixed
/// protobuf messages, authenticated with the phone's client certificate.
class TlsChannel {
  TlsChannel._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: () => _finish(null),
      cancelOnError: true,
    );
    // A write to a socket the TV reset fails through `done`; the same error
    // already ends the stream above, so it must not surface a second time.
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) {}));
  }

  final SecureSocket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final MessageFramer _framer = MessageFramer();
  final Queue<Uint8List> _pending = Queue<Uint8List>();
  Completer<Uint8List>? _waiter;
  void Function(Uint8List message)? _listener;
  final Completer<Object?> _closed = Completer<Object?>();
  int _received = 0;

  /// Opens the connection. Throws [TvUnreachable] when the TV cannot be
  /// reached and [TvNeedsPairing] when the TV rejects our certificate
  /// during the handshake.
  static Future<TlsChannel> connect({
    required String host,
    required int port,
    required ClientIdentity identity,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
      ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
    try {
      final socket = await SecureSocket.connect(
        host,
        port,
        context: context,
        // The TV uses a self-signed certificate. Pairing binds it to the code
        // shown on screen, and later connections pin its fingerprint.
        onBadCertificate: (_) => true,
        timeout: timeout,
      );
      socket.setOption(SocketOption.tcpNoDelay, true);
      return TlsChannel._(socket);
    } on TlsException catch (e) {
      throw TvNeedsPairing('The TV refused this phone (${e.message}).');
    } on SocketException catch (e) {
      throw TvUnreachable('Could not reach $host:$port (${e.message}).');
    } on TimeoutException {
      throw TvUnreachable('Timed out connecting to $host:$port.');
    }
  }

  /// DER bytes of the TV's certificate.
  Uint8List? get peerCertificateDer => _socket.peerCertificate?.der;

  /// Number of messages received so far.
  int get receivedCount => _received;

  /// Completes when the connection ends, with the error that ended it (or null).
  Future<Object?> get closed => _closed.future;

  bool get isClosed => _closed.isCompleted;

  void send(Uint8List payload) {
    if (isClosed) throw const TvConnectionLost('The connection is closed.');
    _socket.add(MessageFramer.frame(payload));
  }

  /// Delivers every incoming message to [listener] from now on, including
  /// any that are already queued. Use either this or [next].
  void listen(void Function(Uint8List message) listener) {
    _listener = listener;
    while (_pending.isNotEmpty) {
      listener(_pending.removeFirst());
    }
  }

  /// Waits for the next message.
  Future<Uint8List> next({Duration timeout = const Duration(seconds: 10)}) {
    if (_pending.isNotEmpty) return Future.value(_pending.removeFirst());
    if (isClosed) return Future.error(_lostError());
    final waiter = _waiter = Completer<Uint8List>();
    return waiter.future.timeout(timeout, onTimeout: () {
      if (identical(_waiter, waiter)) _waiter = null;
      throw const TvProtocolError('The TV did not answer in time.');
    });
  }

  void _onData(Uint8List chunk) {
    final List<Uint8List> messages;
    try {
      messages = _framer.add(chunk);
    } on FormatException catch (e) {
      _finish(TvProtocolError('Corrupt data from the TV: ${e.message}'));
      return;
    }
    for (final message in messages) {
      _received++;
      final listener = _listener;
      final waiter = _waiter;
      if (listener != null) {
        listener(message);
      } else if (waiter != null && !waiter.isCompleted) {
        _waiter = null;
        waiter.complete(message);
      } else {
        _pending.add(message);
      }
    }
  }

  void _onError(Object error) => _finish(error);

  /// The error that ended the connection, if any.
  Object? get closeCause => _closeCause;

  /// The exception describing why the connection ended.
  TvException lostError() => _lostError();

  TvException _lostError() {
    final cause = _closeCause;
    if (cause is TvException) return cause;
    if (cause is TlsException) return TvNeedsPairing('The TV refused this phone (${cause.message}).');
    return TvConnectionLost(cause == null ? 'The TV closed the connection.' : 'Connection lost: $cause');
  }

  Object? _closeCause;

  void _finish(Object? error) {
    if (_closed.isCompleted) return;
    _closeCause = error;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.completeError(_lostError());
    _closed.complete(error);
    unawaited(_subscription.cancel());
    _socket.destroy();
  }

  /// Closes the connection.
  void close() => _finish(null);
}
