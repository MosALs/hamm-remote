import 'dart:convert';
import 'dart:typed_data';

/// A minimal protobuf encoder covering the field types used by the
/// Android TV Remote protocol (varints, booleans, strings, bytes, messages).
class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  void _key(int field, int wireType) => writeVarint(_out, (field << 3) | wireType);

  /// Writes a varint field (uint32/int32/enum). Negative values are written
  /// as 64-bit two's complement, as protobuf does for int32.
  void varint(int field, int value) {
    _key(field, 0);
    writeVarint(_out, value);
  }

  void boolean(int field, bool value) => varint(field, value ? 1 : 0);

  void bytes(int field, List<int> value) {
    _key(field, 2);
    writeVarint(_out, value.length);
    _out.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  void message(int field, ProtoWriter value) => bytes(field, value.toBytes());

  Uint8List toBytes() => _out.toBytes();
}

/// Appends [value] as a protobuf varint.
void writeVarint(BytesBuilder out, int value) {
  var v = value;
  while (true) {
    final byte = v & 0x7F;
    v = v >>> 7;
    if (v == 0) {
      out.addByte(byte);
      return;
    }
    out.addByte(byte | 0x80);
  }
}

/// Result of reading a varint: its value and the offset just after it.
typedef VarintRead = ({int value, int next});

/// Reads a varint at [offset]. Returns null when [data] ends before the
/// varint does (more bytes are needed). Throws [FormatException] for a
/// varint longer than 10 bytes.
VarintRead? readVarint(List<int> data, int offset) {
  var result = 0;
  var shift = 0;
  var pos = offset;
  while (true) {
    if (pos >= data.length) return null;
    if (shift >= 70) throw const FormatException('Varint too long');
    final byte = data[pos++];
    result |= (byte & 0x7F) << shift;
    if (byte & 0x80 == 0) return (value: result, next: pos);
    shift += 7;
  }
}

/// A decoded protobuf message: field number -> values in wire order.
/// Varints decode to [int]; length-delimited and fixed fields to [Uint8List].
class ProtoMessage {
  ProtoMessage._(this._fields);

  final Map<int, List<Object>> _fields;

  static final ProtoMessage empty = ProtoMessage._(const {});

  factory ProtoMessage.parse(List<int> data) {
    final fields = <int, List<Object>>{};
    var pos = 0;
    while (pos < data.length) {
      final key = readVarint(data, pos);
      if (key == null) throw const FormatException('Truncated field key');
      pos = key.next;
      final field = key.value >>> 3;
      final wireType = key.value & 7;
      final Object value;
      switch (wireType) {
        case 0:
          final v = readVarint(data, pos);
          if (v == null) throw const FormatException('Truncated varint');
          value = v.value;
          pos = v.next;
        case 1:
          value = _slice(data, pos, 8);
          pos += 8;
        case 2:
          final len = readVarint(data, pos);
          if (len == null) throw const FormatException('Truncated length');
          pos = len.next;
          value = _slice(data, pos, len.value);
          pos += len.value;
        case 5:
          value = _slice(data, pos, 4);
          pos += 4;
        default:
          throw FormatException('Unsupported wire type $wireType');
      }
      (fields[field] ??= <Object>[]).add(value);
    }
    return ProtoMessage._(fields);
  }

  static Uint8List _slice(List<int> data, int start, int length) {
    if (length < 0 || start + length > data.length) {
      throw const FormatException('Field exceeds message bounds');
    }
    return Uint8List.fromList(data.sublist(start, start + length));
  }

  bool has(int field) => _fields.containsKey(field);

  int intOf(int field, [int fallback = 0]) {
    final v = _fields[field]?.first;
    return v is int ? v : fallback;
  }

  /// A varint field interpreted as a signed 32-bit integer (int32).
  int int32Of(int field, [int fallback = 0]) => intOf(field, fallback).toSigned(32);

  bool boolOf(int field) => intOf(field) != 0;

  Uint8List? bytesOf(int field) {
    final v = _fields[field]?.first;
    return v is Uint8List ? v : null;
  }

  String? stringOf(int field) {
    final b = bytesOf(field);
    return b == null ? null : utf8.decode(b, allowMalformed: true);
  }

  /// The nested message in [field], or null when absent.
  ProtoMessage? messageOf(int field) {
    final b = bytesOf(field);
    return b == null ? null : ProtoMessage.parse(b);
  }

  List<ProtoMessage> messagesOf(int field) => [
        for (final v in _fields[field] ?? const <Object>[])
          if (v is Uint8List) ProtoMessage.parse(v),
      ];

  Iterable<int> get fieldNumbers => _fields.keys;
}
