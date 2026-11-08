import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../app_info.dart';

/// A device advertising sync on the local network.
class DiscoveredPeer {
  const DiscoveredPeer({required this.id, required this.name, required this.host, required this.port});
  final String id, name, host;
  final int port;
  String get address => '$host:$port';
}

/// mDNS/DNS-SD (Bonjour on macOS, NSD on Android).
///
/// * **Advertising** runs while sync is on, so the other device can find us.
/// * **Searching** runs in short bursts ([scan]) — browsing continuously costs
///   battery and isn't needed once devices are paired.
///
/// Discovery is a convenience; "Add device by IP" works without it.
class SyncDiscovery {
  SyncDiscovery({required this.deviceId, required this.onFound, required this.onLost});

  final String deviceId;
  final void Function(DiscoveredPeer) onFound;
  final void Function(String id) onLost;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  Timer? _scanTimer;

  bool get scanning => _discovery != null;

  Future<void> advertise({required String name, required int port}) async {
    await stopAdvertising();
    final b = _broadcast = BonsoirBroadcast(
      service: BonsoirService(name: name, type: AppInfo.syncServiceType, port: port, attributes: {'id': deviceId}),
    );
    await b.initialize();
    await b.start();
  }

  Future<void> stopAdvertising() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
  }

  /// Searches for [duration], then stops by itself; [onDone] runs when it stops.
  /// Calling it while a search runs restarts the timer.
  Future<void> scan(Duration duration, {void Function()? onDone}) async {
    _scanTimer?.cancel();
    _scanTimer = Timer(duration, () async {
      await stopScan();
      onDone?.call();
    });
    if (_discovery != null) return;
    final d = _discovery = BonsoirDiscovery(type: AppInfo.syncServiceType);
    await d.initialize();
    _sub = d.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          if (service.attributes['id'] != deviceId) d.serviceResolver.resolveService(service);
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
        case BonsoirDiscoveryServiceUpdatedEvent(:final service):
          final id = service.attributes['id'];
          final host = service.hostAddresses.where((a) => !a.contains(':')).firstOrNull ?? service.hostAddress;
          if (id != null && id != deviceId && host != null) {
            onFound(DiscoveredPeer(id: id, name: service.name, host: host, port: service.port));
          }
        case BonsoirDiscoveryServiceLostEvent(:final service):
          final id = service.attributes['id'];
          if (id != null) onLost(id);
        default:
      }
    });
    await d.start();
  }

  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _discovery?.stop();
    } catch (_) {}
    _discovery = null;
  }

  Future<void> stop() async {
    await stopScan();
    await stopAdvertising();
  }
}
