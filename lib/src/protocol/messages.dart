import 'dart:typed_data';

import 'protobuf.dart';

/// Field numbers and builders for the pairing ("polo") protocol, port 6467.
abstract final class Polo {
  static const int statusOk = 200;
  static const int statusError = 400;
  static const int statusBadConfiguration = 401;
  static const int statusBadSecret = 402;

  // OuterMessage fields.
  static const int fProtocolVersion = 1;
  static const int fStatus = 2;
  static const int fPairingRequest = 10;
  static const int fPairingRequestAck = 11;
  static const int fOptions = 20;
  static const int fConfiguration = 30;
  static const int fConfigurationAck = 31;
  static const int fSecret = 40;
  static const int fSecretAck = 41;

  static const int encodingHexadecimal = 3;
  static const int roleInput = 1;
  static const int symbolLength = 6;

  static ProtoWriter _outer() => ProtoWriter()
    ..varint(fProtocolVersion, 2)
    ..varint(fStatus, statusOk);

  static ProtoWriter _encoding() => ProtoWriter()
    ..varint(1, encodingHexadecimal)
    ..varint(2, symbolLength);

  static Uint8List pairingRequest(String clientName) => (_outer()
        ..message(
          fPairingRequest,
          ProtoWriter()
            ..string(1, 'atvremote')
            ..string(2, clientName),
        ))
      .toBytes();

  static Uint8List options() => (_outer()
        ..message(
          fOptions,
          ProtoWriter()
            ..message(1, _encoding())
            ..varint(3, roleInput),
        ))
      .toBytes();

  static Uint8List configuration() => (_outer()
        ..message(
          fConfiguration,
          ProtoWriter()
            ..message(1, _encoding())
            ..varint(2, roleInput),
        ))
      .toBytes();

  static Uint8List secret(Uint8List secret) =>
      (_outer()..message(fSecret, ProtoWriter()..bytes(1, secret))).toBytes();
}

/// Field numbers and builders for the remote protocol, port 6466.
abstract final class Remote {
  // RemoteMessage fields.
  static const int fConfigure = 1;
  static const int fSetActive = 2;
  static const int fError = 3;
  static const int fPingRequest = 8;
  static const int fPingResponse = 9;
  static const int fKeyInject = 10;
  static const int fImeKeyInject = 20;
  static const int fImeBatchEdit = 21;
  static const int fImeShowRequest = 22;
  static const int fStart = 40;
  static const int fSetVolumeLevel = 50;
  static const int fAppLinkLaunch = 90;

  // Feature bits negotiated in remote_configure / remote_set_active.
  static const int featurePing = 1;
  static const int featureKey = 2;
  static const int featureIme = 4;
  static const int featurePower = 32;
  static const int featureVolume = 64;
  static const int featureAppLink = 512;

  static const int wantedFeatures =
      featurePing | featureKey | featureIme | featurePower | featureVolume | featureAppLink;

  static Uint8List configure({
    required int features,
    required String packageName,
    required String appVersion,
  }) =>
      (ProtoWriter()
            ..message(
              fConfigure,
              ProtoWriter()
                ..varint(1, features)
                ..message(
                  2,
                  ProtoWriter()
                    ..varint(3, 1)
                    ..string(4, '1')
                    ..string(5, packageName)
                    ..string(6, appVersion),
                ),
            ))
          .toBytes();

  static Uint8List setActive(int features) =>
      (ProtoWriter()..message(fSetActive, ProtoWriter()..varint(1, features))).toBytes();

  static Uint8List pingResponse(int value) =>
      (ProtoWriter()..message(fPingResponse, ProtoWriter()..varint(1, value))).toBytes();

  static Uint8List keyInject(int keyCode, KeyDirection direction) => (ProtoWriter()
        ..message(
          fKeyInject,
          ProtoWriter()
            ..varint(1, keyCode)
            ..varint(2, direction.wire),
        ))
      .toBytes();

  static Uint8List appLink(String link) =>
      (ProtoWriter()..message(fAppLinkLaunch, ProtoWriter()..string(1, link))).toBytes();

  /// Replaces the focused text field's content with [text].
  static Uint8List imeText({
    required String text,
    required int imeCounter,
    required int fieldCounter,
  }) {
    final end = text.length - 1;
    return (ProtoWriter()
          ..message(
            fImeBatchEdit,
            ProtoWriter()
              ..varint(1, imeCounter)
              ..varint(2, fieldCounter)
              ..message(
                3,
                ProtoWriter()
                  ..varint(1, 1)
                  ..message(
                    2,
                    ProtoWriter()
                      ..varint(1, end)
                      ..varint(2, end)
                      ..string(3, text),
                  ),
              ),
          ))
        .toBytes();
  }
}

/// How a key event is delivered: a tap, or the start/end of a long press.
enum KeyDirection {
  short(3),
  startLong(1),
  endLong(2);

  const KeyDirection(this.wire);

  final int wire;
}
