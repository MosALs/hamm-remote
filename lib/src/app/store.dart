import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/identity.dart';
import '../protocol/pairing.dart';
import '../protocol/remote_session.dart';

/// A TV the user has connected to.
class SavedTv {
  const SavedTv({
    required this.name,
    required this.host,
    this.remotePort = defaultRemotePort,
    this.pairingPort = defaultPairingPort,
    this.serverFingerprint,
    this.adbEnabled = false,
    this.mac,
  });

  final String name;
  final String host;
  final int remotePort;
  final int pairingPort;

  /// SHA-256 of the TV's certificate, recorded when pairing succeeded.
  final String? serverFingerprint;

  /// Whether this TV allowed the phone's ADB key ("network debugging"),
  /// used for keys the remote service ignores.
  final bool adbEnabled;

  /// The TV's MAC address, used to wake it with Wake-on-LAN.
  final String? mac;

  bool get isPaired => serverFingerprint != null;

  SavedTv copyWith({
    String? name,
    String? host,
    int? remotePort,
    String? serverFingerprint,
    bool? adbEnabled,
    String? mac,
  }) =>
      SavedTv(
        name: name ?? this.name,
        host: host ?? this.host,
        remotePort: remotePort ?? this.remotePort,
        pairingPort: pairingPort,
        serverFingerprint: serverFingerprint ?? this.serverFingerprint,
        adbEnabled: adbEnabled ?? this.adbEnabled,
        mac: mac ?? this.mac,
      );

  Map<String, Object?> toJson() => {
        'name': name,
        'host': host,
        'remotePort': remotePort,
        'pairingPort': pairingPort,
        'serverFingerprint': serverFingerprint,
        'adb': adbEnabled,
        'mac': mac,
      };

  static SavedTv? fromJson(Object? json) {
    if (json is! Map<dynamic, dynamic>) return null;
    final name = json['name'];
    final host = json['host'];
    if (name is! String || host is! String) return null;
    final remotePort = json['remotePort'];
    final pairingPort = json['pairingPort'];
    final fingerprint = json['serverFingerprint'];
    return SavedTv(
      name: name,
      host: host,
      remotePort: remotePort is int ? remotePort : defaultRemotePort,
      pairingPort: pairingPort is int ? pairingPort : defaultPairingPort,
      serverFingerprint: fingerprint is String ? fingerprint : null,
      adbEnabled: json['adb'] == true,
      mac: json['mac'] is String ? json['mac'] as String : null,
    );
  }
}

/// Persistent app data: the phone's TLS identity and the saved TVs.
class AppStore {
  AppStore._(this._prefs);

  final SharedPreferences _prefs;

  static const _kCert = 'identity.certificate';
  static const _kKey = 'identity.privateKey';
  static const _kTvs = 'tvs';
  static const _kCurrent = 'currentTvHost';

  static Future<AppStore> open() async => AppStore._(await SharedPreferences.getInstance());

  ClientIdentity? loadIdentity() {
    final cert = _prefs.getString(_kCert);
    final key = _prefs.getString(_kKey);
    if (cert == null || key == null) return null;
    try {
      return ClientIdentity(certificatePem: cert, privateKeyPem: key);
    } on FormatException {
      return null;
    }
  }

  Future<void> saveIdentity(ClientIdentity identity) async {
    await _prefs.setString(_kCert, identity.certificatePem);
    await _prefs.setString(_kKey, identity.privateKeyPem);
  }

  List<SavedTv> loadTvs() {
    final raw = _prefs.getString(_kTvs);
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List<dynamic>) return const [];
      return [for (final item in decoded) ?SavedTv.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveTv(SavedTv tv) async {
    final tvs = [for (final t in loadTvs()) if (t.host != tv.host) t, tv];
    await _prefs.setString(_kTvs, jsonEncode([for (final t in tvs) t.toJson()]));
  }

  Future<void> removeTv(String host) async {
    final tvs = [for (final t in loadTvs()) if (t.host != host) t];
    await _prefs.setString(_kTvs, jsonEncode([for (final t in tvs) t.toJson()]));
    if (currentTvHost == host) await _prefs.remove(_kCurrent);
  }

  String? get currentTvHost => _prefs.getString(_kCurrent);

  Future<void> setCurrentTvHost(String? host) async {
    if (host == null) {
      await _prefs.remove(_kCurrent);
    } else {
      await _prefs.setString(_kCurrent, host);
    }
  }

  SavedTv? get currentTv {
    final host = currentTvHost;
    if (host == null) return null;
    for (final tv in loadTvs()) {
      if (tv.host == host) return tv;
    }
    return null;
  }
}
