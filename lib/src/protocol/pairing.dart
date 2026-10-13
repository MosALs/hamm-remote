import '../crypto/identity.dart';
import 'errors.dart';
import 'messages.dart';
import 'protobuf.dart';
import 'tls_channel.dart';

/// Default port of the pairing service on Android TV.
const int defaultPairingPort = 6467;

/// A pairing in progress. After [start] returns, the TV shows a
/// 6-character code; pass what the user typed to [finish].
class PairingSession {
  PairingSession._(this._channel, this._identity, this._server, this.serverFingerprint);

  final TlsChannel _channel;
  final ClientIdentity _identity;
  final RsaPublicNumbers _server;

  /// SHA-256 of the TV's certificate. Saved after pairing so later
  /// connections can check they talk to the same TV.
  final String serverFingerprint;

  bool get isOpen => !_channel.isClosed;

  /// Connects to the pairing port and asks the TV to show a code.
  static Future<PairingSession> start({
    required String host,
    int port = defaultPairingPort,
    required ClientIdentity identity,
    String clientName = 'HAAM Remote',
  }) async {
    final TlsChannel channel;
    try {
      channel = await TlsChannel.connect(host: host, port: port, identity: identity);
    } on TvNeedsPairing catch (e) {
      // The pairing port accepts any certificate, so this is a TLS problem.
      throw TvProtocolError(e.message);
    }
    try {
      final serverDer = channel.peerCertificateDer;
      if (serverDer == null) throw const TvProtocolError('The TV sent no certificate.');
      final session = PairingSession._(
        channel,
        identity,
        rsaPublicKeyFromCertificate(serverDer),
        sha256Hex(serverDer),
      );
      channel.send(Polo.pairingRequest(clientName));
      await session._expect(Polo.fPairingRequestAck);
      channel.send(Polo.options());
      await session._expect(Polo.fOptions);
      channel.send(Polo.configuration());
      await session._expect(Polo.fConfigurationAck);
      return session;
    } on FormatException catch (e) {
      channel.close();
      throw TvProtocolError('Unexpected pairing data: ${e.message}');
    } catch (_) {
      channel.close();
      rethrow;
    }
  }

  /// Sends the secret for [code]. Throws [PairingCodeMismatch] (nothing is
  /// sent; the session stays open for another try) when the code cannot be
  /// right, and [PairingRejected] when the TV refuses it.
  Future<void> finish(String code) async {
    final secret = pairingSecret(client: _identity.publicKey, server: _server, code: code);
    if (secret == null) throw const PairingCodeMismatch();
    try {
      _channel.send(Polo.secret(secret));
      await _expect(Polo.fSecretAck);
    } finally {
      _channel.close();
    }
  }

  /// Abandons pairing; the TV hides the code.
  void cancel() => _channel.close();

  Future<void> _expect(int field) async {
    final ProtoMessage message;
    try {
      message = ProtoMessage.parse(await _channel.next());
    } on FormatException catch (e) {
      throw TvProtocolError('Unreadable pairing message: ${e.message}');
    }
    final status = message.intOf(Polo.fStatus);
    if (status == Polo.statusBadSecret) {
      throw const PairingRejected('The TV rejected the code.');
    }
    if (status != Polo.statusOk) {
      throw TvProtocolError('The TV reported pairing status $status.');
    }
    if (!message.has(field)) {
      throw TvProtocolError('Unexpected pairing message (fields ${message.fieldNumbers.toList()}).');
    }
  }
}
