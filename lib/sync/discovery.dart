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

/// Advertises this device and finds others via mDNS/DNS-SD (Bonjour on macOS,
/// NSD on Android). Discovery is a convenience; "Add device by IP" works
/// without it.
class SyncDiscovery {
  SyncDiscovery({required this.deviceId, required this.onFound, required this.onLost});

  final String deviceId;
  final void Function(DiscoveredPeer) onFound;
  final void Function(String id) onLost;

  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;

  Future<void> start({required String name, required int port}) async {
    await stop();
    _broadcast = BonsoirBroadcast(
      service: BonsoirService(name: name, type: AppInfo.syncServiceType, port: port, attributes: {'id': deviceId}),
    );
    await _broadcast!.initialize();
    await _broadcast!.start();

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

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _broadcast?.stop();
      await _discovery?.stop();
    } catch (_) {}
    _broadcast = null;
    _discovery = null;
  }
}
