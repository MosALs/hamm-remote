import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/errors.dart';
import 'adb_key.dart';

/// Default port for ADB over the network ("Network debugging").
const int defaultAdbPort = 5555;

/// One ADB packet: a 24-byte little-endian header and a payload.
class AdbMessage {
  const AdbMessage(this.command, this.arg0, this.arg1, this.data);

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List data;

  static int code(String name) => ByteData.sublistView(Uint8List.fromList(ascii.encode(name))).getUint32(0, Endian.little);

  static final int cnxn = code('CNXN');
  static final int auth = code('AUTH');
  static final int open = code('OPEN');
  static final int okay = code('OKAY');
  static final int clse = code('CLSE');
  static final int wrte = code('WRTE');

  static const int authToken = 1;
  static const int authSignature = 2;
  static const int authRsaPublicKey = 3;

  Uint8List encode() {
    var checksum = 0;
    for (final b in data) {
      checksum = (checksum + b) & 0xFFFFFFFF;
    }
    final header = ByteData(24)
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, data.length, Endian.little)
      ..setUint32(16, checksum, Endian.little)
      ..setUint32(20, command ^ 0xFFFFFFFF, Endian.little);
    return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
  }
}

/// Splits a byte stream into ADB messages.
class AdbFramer {
  Uint8List _buffer = Uint8List(0);

  List<AdbMessage> add(List<int> chunk) {
    _buffer = Uint8List.fromList([..._buffer, ...chunk]);
    final out = <AdbMessage>[];
    var pos = 0;
    while (_buffer.length - pos >= 24) {
      final header = ByteData.sublistView(_buffer, pos, pos + 24);
      final command = header.getUint32(0, Endian.little);
      final length = header.getUint32(12, Endian.little);
      if (header.getUint32(20, Endian.little) != (command ^ 0xFFFFFFFF)) {
        throw const FormatException('Corrupt ADB message header');
      }
      if (length > 16 * 1024 * 1024) throw const FormatException('ADB message too large');
      if (_buffer.length - pos - 24 < length) break;
      out.add(AdbMessage(
        command,
        header.getUint32(4, Endian.little),
        header.getUint32(8, Endian.little),
        Uint8List.fromList(_buffer.sublist(pos + 24, pos + 24 + length)),
      ));
      pos += 24 + length;
    }
    _buffer = Uint8List.fromList(_buffer.sublist(pos));
    return out;
  }
}

/// The TV refused the connection or the "Allow debugging?" prompt was not
/// accepted in time.
class AdbNotAuthorized extends TvException {
  const AdbNotAuthorized(super.message);
}

/// A connection to the TV's ADB daemon, used to send keys the Android TV
/// Remote Service ignores (input, settings, colour keys on some TVs).
class AdbClient {
  AdbClient._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object e) => _finish(e),
      onDone: () => _finish(null),
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final AdbFramer _framer = AdbFramer();
  final Queue<AdbMessage> _pending = Queue<AdbMessage>();
  Completer<AdbMessage>? _waiter;
  bool _closed = false;
  int _nextLocalId = 1;
  Future<void> _queue = Future<void>.value();

  bool get isOpen => !_closed;

  /// Connects and authenticates with [key]. When the TV does not know the
  /// key yet it shows "Allow debugging?"; [onApprovalNeeded] is called then
  /// and the connection waits up to [approvalTimeout] for the user.
  static Future<AdbClient> connect({
    required String host,
    int port = defaultAdbPort,
    required AdbKey key,
    Duration approvalTimeout = const Duration(seconds: 60),
    void Function()? onApprovalNeeded,
  }) async {
    final Socket socket;
    try {
      socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    } on SocketException catch (e) {
      throw TvUnreachable('ADB is not reachable at $host:$port (${e.message}). Is network debugging on?');
    }
    socket.setOption(SocketOption.tcpNoDelay, true);
    final client = AdbClient._(socket);
    try {
      await client._handshake(key, approvalTimeout, onApprovalNeeded);
      return client;
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  Future<void> _handshake(AdbKey key, Duration approvalTimeout, void Function()? onApprovalNeeded) async {
    _send(AdbMessage(AdbMessage.cnxn, 0x01000000, 256 * 1024, Uint8List.fromList(ascii.encode('host::\x00'))));
    var msg = await _next(const Duration(seconds: 8));
    if (msg.command == AdbMessage.cnxn) return; // device has auth disabled
    if (msg.command != AdbMessage.auth || msg.arg0 != AdbMessage.authToken) {
      throw const TvProtocolError('Unexpected ADB handshake reply.');
    }
    _send(AdbMessage(AdbMessage.auth, AdbMessage.authSignature, 0, key.signToken(msg.data)));
    msg = await _next(const Duration(seconds: 8));
    if (msg.command == AdbMessage.cnxn) return;
    // Unknown key: offer it, which makes the TV ask the user.
    _send(AdbMessage(AdbMessage.auth, AdbMessage.authRsaPublicKey, 0, key.publicKeyMessage()));
    onApprovalNeeded?.call();
    try {
      msg = await _next(approvalTimeout);
    } on TimeoutException {
      throw const AdbNotAuthorized('The TV did not allow debugging. Accept the prompt on the TV and try again.');
    }
    if (msg.command != AdbMessage.cnxn) {
      throw const AdbNotAuthorized('The TV refused debugging access.');
    }
  }

  /// Runs a shell command and returns its output. Commands run one at a
  /// time, in order.
  Future<String> shell(String command) {
    final result = _queue.then((_) => _runShell(command));
    _queue = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  Future<String> _runShell(String command) async {
    final localId = _nextLocalId++;
    _send(AdbMessage(AdbMessage.open, localId, 0, Uint8List.fromList([...utf8.encode('shell:$command'), 0])));
    final output = BytesBuilder();
    var remoteId = 0;
    while (true) {
      final msg = await _next(const Duration(seconds: 10));
      if (msg.arg1 != localId) continue; // stale message for another stream
      if (msg.command == AdbMessage.okay) {
        remoteId = msg.arg0;
      } else if (msg.command == AdbMessage.wrte) {
        output.add(msg.data);
        _send(AdbMessage(AdbMessage.okay, localId, msg.arg0, Uint8List(0)));
      } else if (msg.command == AdbMessage.clse) {
        if (remoteId != 0) _send(AdbMessage(AdbMessage.clse, localId, remoteId, Uint8List(0)));
        return utf8.decode(output.takeBytes(), allowMalformed: true);
      }
    }
  }

  /// Presses [keyCode] like the physical remote does.
  Future<void> keyEvent(int keyCode) => shell('input keyevent $keyCode');

  void _send(AdbMessage message) {
    if (_closed) throw const TvConnectionLost('ADB connection is closed.');
    _socket.add(message.encode());
  }

  Future<AdbMessage> _next(Duration timeout) {
    if (_pending.isNotEmpty) return Future.value(_pending.removeFirst());
    if (_closed) return Future.error(const TvConnectionLost('ADB connection closed.'));
    final waiter = _waiter = Completer<AdbMessage>();
    return waiter.future.timeout(timeout, onTimeout: () {
      if (identical(_waiter, waiter)) _waiter = null;
      throw TimeoutException('No ADB reply', timeout);
    });
  }

  void _onData(Uint8List chunk) {
    final List<AdbMessage> messages;
    try {
      messages = _framer.add(chunk);
    } on FormatException {
      _finish(const TvProtocolError('Corrupt data on the ADB connection.'));
      return;
    }
    for (final m in messages) {
      final waiter = _waiter;
      if (waiter != null && !waiter.isCompleted) {
        _waiter = null;
        waiter.complete(m);
      } else {
        _pending.add(m);
      }
    }
  }

  void _finish(Object? error) {
    if (_closed) return;
    _closed = true;
    final waiter = _waiter;
    _waiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(const TvConnectionLost('ADB connection closed.'));
    }
    unawaited(_subscription.cancel());
    _socket.destroy();
  }

  void close() => _finish(null);
}
