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

/// Sends one round of magic packets for every address in [macs].
///
/// They go to the global broadcast address, the /24 broadcast of [host] and
/// [host] itself, on ports 9 and 7. A TV whose Wi-Fi is asleep can miss a
/// single packet, so callers repeat this every second while waiting.
/// The TV must allow waking over the network for any of this to work.
Future<void> wakeOnLan(
  List<String> macs, {
  String? host,
  List<int> ports = const [9, 7],
  bool broadcast = true,
}) async {
  final packets = [for (final mac in macs) magicPacket(mac)];
  final targets = <InternetAddress>[
    if (broadcast) InternetAddress('255.255.255.255'),
  ];
  final ipv4 = host == null ? null : RegExp(r'^(\d+)\.(\d+)\.(\d+)\.\d+$').firstMatch(host);
  if (ipv4 != null) {
    if (broadcast) targets.add(InternetAddress('${ipv4.group(1)}.${ipv4.group(2)}.${ipv4.group(3)}.255'));
    targets.add(InternetAddress(host!));
  }
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  try {
    socket.broadcastEnabled = true;
    for (final packet in packets) {
      for (final target in targets) {
        for (final port in ports) {
          socket.send(packet, target, port);
        }
      }
    }
  } finally {
    socket.close();
  }
}

/// Reads the MAC addresses of the TV's Wi-Fi and Ethernet interfaces from
/// the output of [interfaceListCommand].
List<String> parseInterfaceMacs(String output) {
  final ipLink = RegExp(r'^\d+:\s+([^:@\s]+)(?:@\S+)?:.*?link/ether\s+([0-9a-fA-F:]{17})');
  final plain = RegExp(r'^(\S+)\s+([0-9a-fA-F:]{17})\s*$');
  final found = <String>{};
  for (final line in output.split('\n')) {
    final m = ipLink.firstMatch(line.trim()) ?? plain.firstMatch(line.trim());
    if (m == null) continue;
    final name = m.group(1)!;
    final mac = m.group(2)!.toUpperCase();
    if (!RegExp(r'^(wlan|eth)\d+$').hasMatch(name)) continue;
    if (mac == '00:00:00:00:00:00' || mac == '02:00:00:00:00:00') continue;
    found.add(mac);
  }
  return found.toList();
}

/// Lists the TV's interfaces over ADB, with a fallback for builds whose
/// shell cannot run `ip`.
const String interfaceListCommand =
    'ip -o link 2>/dev/null; for i in wlan0 eth0; do echo "\$i \$(cat /sys/class/net/\$i/address 2>/dev/null)"; done';
