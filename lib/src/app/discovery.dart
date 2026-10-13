import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

/// A TV found on the local network.
class DiscoveredTv {
  const DiscoveredTv({required this.name, required this.host, required this.port});

  final String name;
  final String host;
  final int port;
}

/// Finds Android TVs on the Wi-Fi through mDNS (the TV's remote service
/// advertises `_androidtvremote2._tcp`).
class TvDiscovery extends ChangeNotifier {
  static const String serviceType = '_androidtvremote2._tcp';

  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _subscription;
  final Map<String, DiscoveredTv> _found = {};
  bool _running = false;
  String? _error;

  List<DiscoveredTv> get tvs => _found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  bool get isRunning => _running;
  String? get error => _error;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    _error = null;
    notifyListeners();
    try {
      final discovery = BonsoirDiscovery(type: serviceType, printLogs: false);
      _discovery = discovery;
      await discovery.initialize();
      _subscription = discovery.eventStream?.listen(_onEvent);
      await discovery.start();
    } catch (e) {
      _error = 'Automatic search is unavailable. Enter the TV address instead.';
      _running = false;
      notifyListeners();
    }
  }

  void _onEvent(BonsoirDiscoveryEvent event) {
    final discovery = _discovery;
    switch (event) {
      case BonsoirDiscoveryServiceFoundEvent(:final service):
        if (discovery != null) unawaited(service.resolve(discovery.serviceResolver));
      case BonsoirDiscoveryServiceResolvedEvent(:final service):
      case BonsoirDiscoveryServiceUpdatedEvent(:final service):
        final host = _pickAddress(service);
        if (host == null) return;
        _found[service.name] = DiscoveredTv(name: service.name, host: host, port: service.port);
        notifyListeners();
      case BonsoirDiscoveryServiceLostEvent(:final service):
        if (_found.remove(service.name) != null) notifyListeners();
      default:
        break;
    }
  }

  /// Prefers an IPv4 address; link-local IPv6 needs a zone and is fragile.
  static String? _pickAddress(BonsoirService service) {
    final addresses = service.hostAddresses;
    for (final a in addresses) {
      if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(a)) return a;
    }
    if (addresses.isNotEmpty) return addresses.first;
    final hostname = service.hostname;
    return (hostname == null || hostname.isEmpty) ? null : hostname;
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    final discovery = _discovery;
    _discovery = null;
    if (discovery != null && !discovery.isStopped) {
      try {
        await discovery.stop();
      } catch (_) {
        // Already stopped by the platform.
      }
    }
    _running = false;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
