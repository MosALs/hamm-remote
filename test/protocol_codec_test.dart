import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/protocol/framing.dart';
import 'package:haam_remote/src/protocol/messages.dart';
import 'package:haam_remote/src/protocol/protobuf.dart';

void main() {
  group('protobuf', () {
    test('round-trips varints, strings, bytes and nested messages', () {
      final bytes = (ProtoWriter()
            ..varint(1, 300)
            ..string(2, 'سلام HAAM')
            ..bytes(3, [0, 255, 7])
            ..boolean(4, true)
            ..message(5, ProtoWriter()..varint(1, 42)))
          .toBytes();
      final m = ProtoMessage.parse(bytes);
      expect(m.intOf(1), 300);
      expect(m.stringOf(2), 'سلام HAAM');
      expect(m.bytesOf(3), [0, 255, 7]);
      expect(m.boolOf(4), isTrue);
      expect(m.messageOf(5)!.intOf(1), 42);
      expect(m.has(6), isFalse);
    });

    test('encodes 300 as the canonical varint', () {
      expect((ProtoWriter()..varint(1, 300)).toBytes(), [0x08, 0xAC, 0x02]);
    });

    test('writes negative int32 as 10-byte two\'s complement and reads it back', () {
      final bytes = (ProtoWriter()..varint(1, -5)).toBytes();
      expect(bytes.length, 11);
      expect(ProtoMessage.parse(bytes).int32Of(1), -5);
    });

    test('keeps an empty nested message distinguishable from absence', () {
      final bytes = (ProtoWriter()..message(31, ProtoWriter())).toBytes();
      final m = ProtoMessage.parse(bytes);
      expect(m.has(31), isTrue);
      expect(m.messageOf(31)!.fieldNumbers, isEmpty);
    });

    test('rejects truncated input', () {
      expect(() => ProtoMessage.parse([0x12, 0x05, 0x01]), throwsFormatException);
      expect(() => ProtoMessage.parse([0x08, 0x80]), throwsFormatException);
    });

    test('pairing request matches the reference client byte for byte', () {
      // Bytes produced by androidtvremote2 for the same request.
      final expected = [
        0x08, 0x02, 0x10, 0xC8, 0x01, 0x52, 0x18, 0x0A, 0x09, //
        ...'atvremote'.codeUnits,
        0x12, 0x0B, ...'HAAM Remote'.codeUnits,
      ];
      expect(Polo.pairingRequest('HAAM Remote'), expected);
    });

    test('key inject has key code and direction', () {
      final m = ProtoMessage.parse(Remote.keyInject(185, KeyDirection.short)).messageOf(Remote.fKeyInject)!;
      expect(m.intOf(1), 185);
      expect(m.intOf(2), 3);
    });
  });

  group('framing', () {
    final payloads = [
      Uint8List.fromList(List<int>.generate(3, (i) => i)),
      Uint8List.fromList(List<int>.generate(200, (i) => i % 256)), // two-byte length
      Uint8List(0),
      Uint8List.fromList([9]),
    ];
    final stream = Uint8List.fromList([for (final p in payloads) ...MessageFramer.frame(p)]);

    test('reassembles messages split at every possible position', () {
      for (var split = 0; split <= stream.length; split++) {
        final framer = MessageFramer();
        final out = [
          ...framer.add(stream.sublist(0, split)),
          ...framer.add(stream.sublist(split)),
        ];
        expect(out, payloads, reason: 'split at $split');
      }
    });

    test('handles byte-by-byte delivery', () {
      final framer = MessageFramer();
      final out = <Uint8List>[];
      for (final b in stream) {
        out.addAll(framer.add([b]));
      }
      expect(out, payloads);
    });

    test('rejects absurd lengths', () {
      final framer = MessageFramer(maxMessageLength: 10);
      expect(() => framer.add([0x20]), throwsFormatException);
    });
  });
}
