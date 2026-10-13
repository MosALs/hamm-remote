import 'dart:async';
import 'dart:io';

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

  test('reads Wi-Fi and Ethernet MACs from the interface listing', () {
    const output = r'''
1: lo: <LOOPBACK,UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc mq state DOWN mode DEFAULT\    link/ether aa:bb:cc:dd:ee:0f brd ff:ff:ff:ff:ff:ff
3: wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP\    link/ether aa:bb:cc:dd:ee:10 brd ff:ff:ff:ff:ff:ff
4: p2p0: <BROADCAST,MULTICAST> mtu 1500 qdisc noop state DOWN\    link/ether ae:bb:cc:dd:ee:10 brd ff:ff:ff:ff:ff:ff
5: wlan1@wlan0: <BROADCAST> mtu 1500 state DOWN\    link/ether 02:00:00:00:00:00 brd ff:ff:ff:ff:ff:ff
wlan0 aa:bb:cc:dd:ee:10
eth0 
''';
    expect(parseInterfaceMacs(output), ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10']);
    expect(parseInterfaceMacs('wlan0 11:22:33:44:55:66\n'), ['11:22:33:44:55:66']);
    expect(parseInterfaceMacs('ip: permission denied\n'), isEmpty);
  });

  test('sends a packet for every MAC to the TV itself', () async {
    final listener = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(listener.close);
    final received = <List<int>>[];
    final done = Completer<void>();
    listener.listen((event) {
      if (event != RawSocketEvent.read) return;
      final d = listener.receive();
      if (d == null) return;
      received.add(d.data);
      if (received.length == 2 && !done.isCompleted) done.complete();
    });
    await wakeOnLan(
      ['AA:BB:CC:DD:EE:0F', 'AA:BB:CC:DD:EE:10'],
      host: '127.0.0.1',
      ports: [listener.port],
      broadcast: false,
    );
    await done.future.timeout(const Duration(seconds: 5));
    expect(received.map((p) => p.sublist(6, 12)), [
      [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x0F],
      [0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x10],
    ]);
  });
}
