import 'dart:typed_data';

import 'protobuf.dart';

/// Messages on both Android TV ports are protobufs prefixed with their
/// length as a varint. A TCP read may carry part of a message, several
/// messages, or a split anywhere (including inside the length prefix).
class MessageFramer {
  MessageFramer({this.maxMessageLength = 1 << 20});

  final int maxMessageLength;
  Uint8List _buffer = Uint8List(0);

  /// Adds received bytes and returns every message completed by them.
  /// Throws [FormatException] when the stream is corrupt; it cannot be
  /// resynchronised after that, so the caller should drop the connection.
  List<Uint8List> add(List<int> chunk) {
    if (chunk.isNotEmpty) {
      final merged = Uint8List(_buffer.length + chunk.length)
        ..setRange(0, _buffer.length, _buffer)
        ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);
      _buffer = merged;
    }
    final messages = <Uint8List>[];
    var pos = 0;
    while (pos < _buffer.length) {
      final header = readVarint(_buffer, pos);
      if (header == null) break;
      final length = header.value;
      if (length < 0 || length > maxMessageLength) {
        _buffer = Uint8List(0);
        throw FormatException('Invalid message length $length');
      }
      final end = header.next + length;
      if (end > _buffer.length) break;
      messages.add(Uint8List.sublistView(_buffer, header.next, end));
      pos = end;
    }
    // Copy the remainder so returned views never alias reused memory.
    _buffer = Uint8List.fromList(Uint8List.sublistView(_buffer, pos));
    return messages;
  }

  /// Prefixes [payload] with its varint length.
  static Uint8List frame(Uint8List payload) {
    final out = BytesBuilder(copy: false);
    writeVarint(out, payload.length);
    out.add(payload);
    return out.toBytes();
  }
}
