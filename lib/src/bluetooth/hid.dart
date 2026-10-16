import 'dart:typed_data';

import '../protocol/keycodes.dart';

/// The phone presents itself to the TV as a Bluetooth keyboard with media
/// keys (a HID device). This file holds everything about that which is pure
/// data: the report descriptor, the key table and the reports.

/// Report IDs in [hidReportDescriptor].
const int keyboardReportId = 1;
const int consumerReportId = 2;

/// A boot-style keyboard (report 1: modifiers, reserved, six keys) and a
/// consumer control (report 2: one 16-bit usage), like a TV remote keyboard.
final Uint8List hidReportDescriptor = Uint8List.fromList(const [
  // Keyboard
  0x05, 0x01, // Usage Page (Generic Desktop)
  0x09, 0x06, // Usage (Keyboard)
  0xA1, 0x01, // Collection (Application)
  0x85, keyboardReportId, //   Report ID (1)
  0x05, 0x07, //   Usage Page (Keyboard/Keypad)
  0x19, 0xE0, //   Usage Minimum (Left Control)
  0x29, 0xE7, //   Usage Maximum (Right GUI)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x01, //   Logical Maximum (1)
  0x75, 0x01, //   Report Size (1)
  0x95, 0x08, //   Report Count (8)
  0x81, 0x02, //   Input (Data, Variable, Absolute): modifier bits
  0x95, 0x01, //   Report Count (1)
  0x75, 0x08, //   Report Size (8)
  0x81, 0x01, //   Input (Constant): reserved byte
  0x95, 0x06, //   Report Count (6)
  0x75, 0x08, //   Report Size (8)
  0x15, 0x00, //   Logical Minimum (0)
  0x25, 0x65, //   Logical Maximum (101)
  0x05, 0x07, //   Usage Page (Keyboard/Keypad)
  0x19, 0x00, //   Usage Minimum (0)
  0x29, 0x65, //   Usage Maximum (101)
  0x81, 0x00, //   Input (Data, Array, Absolute): key codes
  0xC0, // End Collection
  // Consumer control (media and TV keys)
  0x05, 0x0C, // Usage Page (Consumer)
  0x09, 0x01, // Usage (Consumer Control)
  0xA1, 0x01, // Collection (Application)
  0x85, consumerReportId, //   Report ID (2)
  0x15, 0x00, //   Logical Minimum (0)
  0x26, 0xFF, 0x03, //   Logical Maximum (1023)
  0x19, 0x00, //   Usage Minimum (0)
  0x2A, 0xFF, 0x03, //   Usage Maximum (1023)
  0x75, 0x10, //   Report Size (16)
  0x95, 0x01, //   Report Count (1)
  0x81, 0x00, //   Input (Data, Array, Absolute)
  0xC0, // End Collection
]);

/// A key as the HID device sends it.
sealed class HidUsage {
  const HidUsage(this.usage);

  /// Usage ID on the page.
  final int usage;

  int get reportId;

  /// Report data (without the report ID) with this key held down.
  Uint8List get down;

  /// Report data with nothing pressed.
  Uint8List get up;
}

/// A key on the Keyboard/Keypad page (0x07).
final class KeyboardUsage extends HidUsage {
  const KeyboardUsage(super.usage);

  @override
  int get reportId => keyboardReportId;

  @override
  Uint8List get down => Uint8List.fromList([0, 0, usage, 0, 0, 0, 0, 0]);

  @override
  Uint8List get up => Uint8List(8);

  @override
  String toString() => 'keyboard:0x${usage.toRadixString(16).padLeft(2, '0')}';
}

/// A key on the Consumer page (0x0C).
final class ConsumerUsage extends HidUsage {
  const ConsumerUsage(super.usage);

  @override
  int get reportId => consumerReportId;

  @override
  Uint8List get down => Uint8List.fromList([usage & 0xFF, usage >> 8]);

  @override
  Uint8List get up => Uint8List(2);

  @override
  String toString() => 'consumer:0x${usage.toRadixString(16).padLeft(3, '0')}';
}

/// The remote's keys that Android 11 understands from a Bluetooth keyboard,
/// by Android key code. Checked against the Linux HID driver and Android's
/// Generic.kl in test/bluetooth_hid_test.dart. Keys missing here (Input,
/// Settings, sources, colour keys, Info) have no standard HID usage that
/// Android 11 maps, so they need the Wi-Fi link.
const Map<int, HidUsage> hidUsages = {
  KeyCode.power: ConsumerUsage(0x030),
  KeyCode.menu: ConsumerUsage(0x040),
  KeyCode.dpadCenter: ConsumerUsage(0x041),
  KeyCode.dpadUp: ConsumerUsage(0x042),
  KeyCode.dpadDown: ConsumerUsage(0x043),
  KeyCode.dpadLeft: ConsumerUsage(0x044),
  KeyCode.dpadRight: ConsumerUsage(0x045),
  KeyCode.tv: ConsumerUsage(0x089),
  KeyCode.guide: ConsumerUsage(0x08D),
  KeyCode.channelUp: ConsumerUsage(0x09C),
  KeyCode.channelDown: ConsumerUsage(0x09D),
  KeyCode.mediaFastForward: ConsumerUsage(0x0B3),
  KeyCode.mediaRewind: ConsumerUsage(0x0B4),
  KeyCode.mediaNext: ConsumerUsage(0x0B5),
  KeyCode.mediaPrevious: ConsumerUsage(0x0B6),
  KeyCode.mediaStop: ConsumerUsage(0x0B7),
  KeyCode.mediaPlayPause: ConsumerUsage(0x0CD),
  KeyCode.volumeMute: ConsumerUsage(0x0E2),
  KeyCode.volumeUp: ConsumerUsage(0x0E9),
  KeyCode.volumeDown: ConsumerUsage(0x0EA),
  KeyCode.search: ConsumerUsage(0x221),
  KeyCode.home: ConsumerUsage(0x223),
  KeyCode.back: ConsumerUsage(0x224),
  KeyCode.digit0: KeyboardUsage(0x27),
  KeyCode.digit0 + 1: KeyboardUsage(0x1E),
  KeyCode.digit0 + 2: KeyboardUsage(0x1F),
  KeyCode.digit0 + 3: KeyboardUsage(0x20),
  KeyCode.digit0 + 4: KeyboardUsage(0x21),
  KeyCode.digit0 + 5: KeyboardUsage(0x22),
  KeyCode.digit0 + 6: KeyboardUsage(0x23),
  KeyCode.digit0 + 7: KeyboardUsage(0x24),
  KeyCode.digit0 + 8: KeyboardUsage(0x25),
  KeyCode.digit0 + 9: KeyboardUsage(0x26),
  KeyCode.enter: KeyboardUsage(0x28),
  KeyCode.del: KeyboardUsage(0x2A),
};
