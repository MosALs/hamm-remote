import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Runs tool/mock_tv/mock_adb.py: a simulated device with network debugging,
/// validated against the reference client adb_shell.
class MockAdb {
  MockAdb._(this._process) {
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
  late final int port;

  /// [maxPayload] is what the device announces as its largest message.
  static Future<MockAdb> start({bool reject = false, int? maxPayload}) async {
    final process = await Process.start('python3', [
      File('tool/mock_tv/mock_adb.py').absolute.path,
      '--port',
      '0',
      if (reject) '--reject',
      if (maxPayload != null) ...['--max-payload', '$maxPayload'],
    ]);
    final adb = MockAdb._(process);
    adb.port = (await adb.waitFor('ready'))['port'] as int;
    return adb;
  }

  Future<Map<String, dynamic>> waitFor(String event, {Duration timeout = const Duration(seconds: 10)}) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      while (_cursor < _events.length) {
        final e = _events[_cursor++];
        if (e['event'] == event) return e;
      }
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) throw TimeoutException('Mock ADB never reported "$event". Events: $_events');
      try {
        await _changed.stream.first.timeout(left);
      } on TimeoutException {
        // Loop once more, then fail with the event log.
      }
    }
  }

  /// All events seen so far (for assertions on what did NOT happen).
  List<Map<String, dynamic>> get events => List.unmodifiable(_events);

  Future<void> close() async {
    await _process.stdin.close();
    _process.kill();
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () => -1);
    await _changed.close();
  }
}
