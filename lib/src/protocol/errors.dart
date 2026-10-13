/// Errors raised while pairing with or controlling a TV.
sealed class TvException implements Exception {
  const TvException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The TV could not be reached (wrong address, different network, TV off).
class TvUnreachable extends TvException {
  const TvUnreachable(super.message);
}

/// The TV does not recognise this phone (never paired, the TV was reset,
/// or the TV's own identity changed). Pairing is needed.
class TvNeedsPairing extends TvException {
  const TvNeedsPairing(super.message);
}

/// The typed pairing code is not the one on the TV screen. Nothing was
/// sent to the TV, so the user can simply retype it.
class PairingCodeMismatch extends TvException {
  const PairingCodeMismatch() : super('That code does not match the one on the TV.');
}

/// The TV refused the pairing secret.
class PairingRejected extends TvException {
  const PairingRejected(super.message);
}

/// The connection dropped.
class TvConnectionLost extends TvException {
  const TvConnectionLost(super.message);
}

/// The TV sent something we did not expect.
class TvProtocolError extends TvException {
  const TvProtocolError(super.message);
}

/// The TV refused ADB access or its "Allow debugging?" prompt was not
/// accepted in time.
class AdbNotAuthorized extends TvException {
  const AdbNotAuthorized(super.message);
}
