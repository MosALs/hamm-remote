import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs tool/mock_tv/mock_tv.py: a simulated Android TV validated against
/// the reference client `androidtvremote2`.
class MockTv {
  MockTv._(this._process) {
    _process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        _events.add(decoded);
        _changed.add(null);
      }
    });
    _process.stderr.transform(utf8.decoder).listen(stderr.write);
  }

  final Process _process;
  final List<Map<String, dynamic>> _events = [];
  final StreamController<void> _changed = StreamController<void>.broadcast();
  int _cursor = 0;
  late final int pairPort;
  late final int remotePort;

  /// UDP port where the mock listens for Wake-on-LAN magic packets.
  late final int wolPort;

  /// Why the mock cannot run here, or null when it can.
  static String? unavailableReason() {
    try {
      final r = Process.runSync('python3', ['-c', 'import OpenSSL, cryptography']);
      return r.exitCode == 0 ? null : 'python3 needs pyOpenSSL and cryptography (pip install pyopenssl cryptography)';
    } on ProcessException {
      return 'python3 is not installed';
    }
  }

  /// [standby] starts with the screen off. [wakeMac] is the MAC a magic
  /// packet must carry to wake the TV from deep sleep (its Wi-Fi MAC); by
  /// default the one in its certificate.
  static Future<MockTv> start({double pingInterval = 0.5, bool standby = false, String? wakeMac}) async {
    final script = File('tool/mock_tv/mock_tv.py').absolute.path;
    final process = await Process.start('python3', [
      script,
      '--pair-port',
      '0',
      '--remote-port',
      '0',
      '--ping-interval',
      '$pingInterval',
      if (standby) '--standby',
      if (wakeMac != null) ...['--wake-mac', wakeMac],
    ]);
    final tv = MockTv._(process);
    final ready = await tv.waitFor('ready');
    tv.pairPort = ready['pair_port'] as int;
    tv.remotePort = ready['remote_port'] as int;
    tv.wolPort = ready['wol_port'] as int;
    return tv;
  }

  /// Waits for the next [event] after the previously consumed one.
  Future<Map<String, dynamic>> waitFor(String event, {Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      while (_cursor < _events.length) {
        final e = _events[_cursor++];
        if (e['event'] == event) return e;
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        throw TimeoutException('Mock TV never reported "$event". Events: $_events');
      }
      try {
        await _changed.stream.first.timeout(left);
      } on TimeoutException {
        // Loop once more, then fail with the event log.
      }
    }
  }

  /// All events seen so far (for assertions on what did NOT happen).
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  /// Deep sleep, like a TV that has been off for a while: its connections
  /// drop and nothing answers until a magic packet for its MAC arrives.
  Future<void> sleep() async {
    _process.stdin.writeln('sleep');
    await _process.stdin.flush();
    await waitFor('asleep');
  }

  /// Joins another network: same TV and identity, now at [host].
  Future<void> moveTo(String host) async {
    _process.stdin.writeln('move $host');
    await _process.stdin.flush();
    await waitFor('moved');
  }

  Future<void> close() async {
    await _process.stdin.close();
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    await _changed.close();
  }
}
