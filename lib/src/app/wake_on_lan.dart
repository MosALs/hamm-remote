import 'dart:io';
import 'dart:typed_data';

/// Builds the Wake-on-LAN "magic packet": six 0xFF bytes, then the MAC
/// address repeated 16 times.
Uint8List magicPacket(String mac) {
  final parts = mac.split(RegExp('[:-]'));
  if (parts.length != 6) throw FormatException('Not a MAC address: $mac');
  final bytes = [for (final p in parts) int.parse(p, radix: 16)];
  return Uint8List.fromList([
    ...List<int>.filled(6, 0xFF),
    for (var i = 0; i < 16; i++) ...bytes,
  ]);
}

/// Sends the magic packet for [mac] as UDP broadcasts on ports 9 and 7, to
/// the global broadcast address and to the /24 broadcast of [host]. The TV
/// must have "wake on network" enabled for this to turn it on.
Future<void> wakeOnLan(String mac, {String? host}) async {
  final packet = magicPacket(mac);
  final targets = <InternetAddress>[InternetAddress('255.255.255.255')];
  final ipv4 = host == null ? null : RegExp(r'^(\d+)\.(\d+)\.(\d+)\.\d+$').firstMatch(host);
  if (ipv4 != null) {
    targets.add(InternetAddress('${ipv4.group(1)}.${ipv4.group(2)}.${ipv4.group(3)}.255'));
  }
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    for (var round = 0; round < 3; round++) {
      for (final target in targets) {
        for (final port in const [9, 7]) {
          socket.send(packet, target, port);
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  } finally {
    socket.close();
  }
}
