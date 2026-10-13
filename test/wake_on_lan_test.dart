import 'package:flutter_test/flutter_test.dart';
import 'package:haam_remote/src/app/wake_on_lan.dart';

void main() {
  test('magic packet is 6 x FF then the MAC 16 times', () {
    final packet = magicPacket('AA:BB:CC:DD:EE:0F');
    expect(packet.length, 102);
    expect(packet.sublist(0, 6), List<int>.filled(6, 0xFF));
    for (var i = 0; i < 16; i++) {
      expect(packet.sublist(6 + i * 6, 12 + i * 6), [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x0F]);
    }
  });

  test('accepts dashes and rejects garbage', () {
    expect(magicPacket('aa-bb-cc-dd-ee-0f').length, 102);
    expect(() => magicPacket('not a mac'), throwsFormatException);
  });
}
