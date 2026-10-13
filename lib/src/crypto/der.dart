import 'dart:convert';
import 'dart:typed_data';

/// Just enough ASN.1 DER to build a self-signed X.509 certificate and an
/// RSA private key, and to read the RSA public key out of the TV's
/// certificate.
abstract final class Der {
  static const int tagBoolean = 0x01;
  static const int tagInteger = 0x02;
  static const int tagBitString = 0x03;
  static const int tagOctetString = 0x04;
  static const int tagNull = 0x05;
  static const int tagOid = 0x06;
  static const int tagUtf8String = 0x0C;
  static const int tagUtcTime = 0x17;
  static const int tagGeneralizedTime = 0x18;
  static const int tagSequence = 0x30;
  static const int tagSet = 0x31;

  static Uint8List tlv(int tag, List<int> content) {
    final out = BytesBuilder(copy: false)..addByte(tag);
    _writeLength(out, content.length);
    out.add(content);
    return out.toBytes();
  }

  static void _writeLength(BytesBuilder out, int length) {
    if (length < 0x80) {
      out.addByte(length);
      return;
    }
    final bytes = <int>[];
    for (var v = length; v > 0; v >>= 8) {
      bytes.insert(0, v & 0xFF);
    }
    out.addByte(0x80 | bytes.length);
    out.add(bytes);
  }

  static Uint8List sequence(List<Uint8List> items) => tlv(tagSequence, _concat(items));

  static Uint8List setOf(List<Uint8List> items) => tlv(tagSet, _concat(items));

  /// `[n] EXPLICIT` wrapper (context-specific, constructed).
  static Uint8List explicit(int n, Uint8List inner) => tlv(0xA0 | n, inner);

  /// `[n] IMPLICIT` primitive (context-specific).
  static Uint8List implicitPrimitive(int n, List<int> content) => tlv(0x80 | n, content);

  static Uint8List integer(BigInt value) => tlv(tagInteger, signedBytes(value));

  static Uint8List smallInteger(int value) => integer(BigInt.from(value));

  static Uint8List boolean(bool value) => tlv(tagBoolean, [value ? 0xFF : 0x00]);

  static Uint8List nullValue() => tlv(tagNull, const []);

  static Uint8List octetString(List<int> bytes) => tlv(tagOctetString, bytes);

  static Uint8List bitString(List<int> bytes) => tlv(tagBitString, [0, ...bytes]);

  static Uint8List utf8String(String s) => tlv(tagUtf8String, utf8.encode(s));

  static Uint8List oid(String dotted) {
    final parts = dotted.split('.').map(int.parse).toList();
    final out = <int>[40 * parts[0] + parts[1]];
    for (final part in parts.skip(2)) {
      final chunk = <int>[part & 0x7F];
      for (var v = part >> 7; v > 0; v >>= 7) {
        chunk.insert(0, 0x80 | (v & 0x7F));
      }
      out.addAll(chunk);
    }
    return tlv(tagOid, out);
  }

  /// RFC 5280: UTCTime through 2049, GeneralizedTime from 2050.
  static Uint8List time(DateTime t) {
    final u = t.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final rest = '${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    if (u.year >= 1950 && u.year < 2050) {
      return tlv(tagUtcTime, ascii.encode('${two(u.year % 100)}$rest'));
    }
    return tlv(tagGeneralizedTime, ascii.encode('${u.year.toString().padLeft(4, '0')}$rest'));
  }

  /// Two's-complement big-endian bytes, minimal length (DER INTEGER content).
  static Uint8List signedBytes(BigInt value) {
    if (value == BigInt.zero) return Uint8List.fromList([0]);
    if (value.isNegative) {
      final byteLength = (value.bitLength + 8) ~/ 8;
      final mod = BigInt.one << (byteLength * 8);
      return _toFixed(value + mod, byteLength);
    }
    final magnitude = unsignedBytes(value);
    if (magnitude[0] & 0x80 != 0) return Uint8List.fromList([0, ...magnitude]);
    return magnitude;
  }

  /// Minimal unsigned big-endian bytes (at least one byte).
  static Uint8List unsignedBytes(BigInt value) {
    if (value.isNegative) throw ArgumentError('negative value');
    final length = value == BigInt.zero ? 1 : (value.bitLength + 7) ~/ 8;
    return _toFixed(value, length);
  }

  static Uint8List _toFixed(BigInt value, int length) {
    final out = Uint8List(length);
    var v = value;
    final mask = BigInt.from(0xFF);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (v & mask).toInt();
      v = v >> 8;
    }
    return out;
  }

  static BigInt bigIntFromUnsigned(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _concat(List<Uint8List> items) {
    final out = BytesBuilder(copy: false);
    for (final item in items) {
      out.add(item);
    }
    return out.toBytes();
  }
}

/// A parsed DER element. Constructed elements expose their [children].
class DerNode {
  DerNode._(this.tag, this.content);

  final int tag;
  final Uint8List content;

  bool get isConstructed => tag & 0x20 != 0;

  /// Parses exactly one element spanning all of [data].
  factory DerNode.parse(List<int> data) {
    final (node, next) = _read(data is Uint8List ? data : Uint8List.fromList(data), 0);
    if (next != data.length) throw const FormatException('Trailing bytes after DER element');
    return node;
  }

  static (DerNode, int) _read(Uint8List data, int offset) {
    if (offset + 2 > data.length) throw const FormatException('Truncated DER element');
    final tag = data[offset];
    if (tag & 0x1F == 0x1F) throw const FormatException('High tag numbers are not supported');
    var pos = offset + 1;
    var length = data[pos++];
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4) throw const FormatException('Unsupported DER length');
      if (pos + count > data.length) throw const FormatException('Truncated DER length');
      length = 0;
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[pos++];
      }
    }
    if (pos + length > data.length) throw const FormatException('DER element exceeds input');
    return (DerNode._(tag, Uint8List.sublistView(data, pos, pos + length)), pos + length);
  }

  List<DerNode> get children {
    if (!isConstructed) throw StateError('Primitive DER element has no children');
    final out = <DerNode>[];
    var pos = 0;
    while (pos < content.length) {
      final (node, next) = _read(content, pos);
      out.add(node);
      pos = next;
    }
    return out;
  }

  /// Value of an INTEGER element interpreted as unsigned.
  BigInt get unsignedInteger {
    if (tag != Der.tagInteger) throw FormatException('Expected INTEGER, got tag $tag');
    return Der.bigIntFromUnsigned(content);
  }
}
