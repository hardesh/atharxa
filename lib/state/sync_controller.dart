import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../sync/background_sync.dart';
import '../sync/discovery.dart';
import '../sync/peers.dart';
import '../sync/sync_auth.dart';
import '../sync/sync_protocol.dart';
import 'core_providers.dart';

/// Everything the Device sync page shows.
@immutable
class SyncState {
  const SyncState({
    required this.enabled,
    required this.deviceName,
    required this.code,
    required this.autoSync,
    required this.intervalMin,
    this.listening = false,
    this.addresses = const [],
    this.paired = const [],
    this.discovered = const {},
    this.busyPeer,
    this.progress,
    this.lastResult,
    this.error,
    this.mismatchPeer,
  });

  final bool enabled, autoSync, listening;
  final String deviceName, code;
  final int intervalMin;

  /// This device's IPv4 addresses (for "Add device by IP" on the other side).
  final List<String> addresses;
  final List<PairedPeer> paired;

  /// Peers currently advertising on the network, by device id.
  final Map<String, DiscoveredPeer> discovered;

  /// Name of the peer a session is running with, if any.
  final String? busyPeer;
  final ({int received, int total})? progress;

  /// "Sent 4, received 12" of the last successful session.
  final String? lastResult;
  final SyncException? error;

  /// Set when the other device has a different code (drives the dialog).
  final String? mismatchPeer;

  bool get codeValid => SyncAuth.isValidCode(code);
  bool isOnline(String id) => discovered.containsKey(id);
  List<DiscoveredPeer> get unpaired => discovered.values.where((d) => !paired.any((p) => p.id == d.id)).toList();

  SyncState copyWith({
    bool? enabled,
    String? deviceName,
    String? code,
    bool? autoSync,
    int? intervalMin,
    bool? listening,
    List<String>? addresses,
    List<PairedPeer>? paired,
    Map<String, DiscoveredPeer>? discovered,
    String? Function()? busyPeer,
    ({int received, int total})? Function()? progress,
    String? Function()? lastResult,
    SyncException? Function()? error,
    String? Function()? mismatchPeer,
  }) => SyncState(
    enabled: enabled ?? this.enabled,
    deviceName: deviceName ?? this.deviceName,
    code: code ?? this.code,
    autoSync: autoSync ?? this.autoSync,
    intervalMin: intervalMin ?? this.intervalMin,
    listening: listening ?? this.listening,
    addresses: addresses ?? this.addresses,
    paired: paired ?? this.paired,
    discovered: discovered ?? this.discovered,
    busyPeer: busyPeer != null ? busyPeer() : this.busyPeer,
    progress: progress != null ? progress() : this.progress,
    lastResult: lastResult != null ? lastResult() : this.lastResult,
    error: error != null ? error() : this.error,
    mismatchPeer: mismatchPeer != null ? mismatchPeer() : this.mismatchPeer,
  );
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

/// Peer-to-peer Wi-Fi sync (DESIGN.md §7.2): server + mDNS while enabled,
/// auto-sync triggers, Sync now / Full resync, pairing errors.
class SyncController extends Notifier<SyncState> {
  late SyncPrefs _prefs;
  HttpServer? _server;
  SyncDiscovery? _discovery;
  Timer? _periodic, _debounce;
  StreamSubscription<String>? _localSub;
  StreamSubscription<List<ConnectivityResult>>? _netSub;
  AppLifecycleListener? _lifecycle;
  bool _onLan = true;
  int _failures = 0;
  DateTime? _retryAfter;

  static String defaultDeviceName() {
    if (Platform.isAndroid) return 'Android phone';
    final h = Platform.localHostname.replaceAll(RegExp(r'\.local$'), '').replaceAll('-', ' ');
    return h.isEmpty ? 'Mac' : h;
  }

  @override
  SyncState build() {
    _prefs = SyncPrefs(ref.watch(prefsProvider));
    ref.onDispose(_stop);
    final s = SyncState(
      enabled: _prefs.enabled,
      deviceName: _prefs.deviceName ?? defaultDeviceName(),
      code: _prefs.code,
      autoSync: _prefs.autoSync,
      intervalMin: _prefs.intervalMin,
      paired: _prefs.peers,
    );
    if (s.enabled && s.codeValid) Future.microtask(_start);
    return s;
  }

  // ---------------------------------------------------------------- settings

  Future<void> setEnabled(bool on) async {
    await _prefs.setEnabled(on);
    var code = state.code;
    if (on && !SyncAuth.isValidCode(code)) {
      code = _newCode();
      await _prefs.setCode(code);
    }
    state = state.copyWith(enabled: on, code: code, error: () => null);
    await _restart();
  }

  Future<void> setDeviceName(String name) async {
    if (name.trim().isEmpty || name.trim() == state.deviceName) return;
    await _prefs.setDeviceName(name);
    state = state.copyWith(deviceName: name.trim());
    await _restart();
  }

  /// Sets the 6-digit pairing code (digits only).
  Future<void> setCode(String code) async {
    final c = code.replaceAll(RegExp(r'\D'), '');
    if (!SyncAuth.isValidCode(c) || c == state.code) return;
    await _prefs.setCode(c);
    state = state.copyWith(code: c, error: () => null, mismatchPeer: () => null);
    await _restart();
  }

  Future<void> generateCode() => setCode(_newCode());

  Future<void> setAutoSync(bool on) async {
    await _prefs.setAutoSync(on);
    state = state.copyWith(autoSync: on);
    await _restart();
  }

  Future<void> setIntervalMin(int minutes) async {
    await _prefs.setIntervalMin(minutes);
    state = state.copyWith(intervalMin: minutes);
    _schedulePeriodic();
  }

  Future<void> forget(PairedPeer p) async {
    final peers = state.paired.where((x) => x.id != p.id).toList();
    await _prefs.setPeers(peers);
    state = state.copyWith(paired: peers);
  }

  void dismissMismatch() => state = state.copyWith(mismatchPeer: () => null);

  static String _newCode() => (math.Random.secure().nextInt(900000) + 100000).toString();

  // ----------------------------------------------------------------- actions

  /// Sync with every paired device that's reachable ("Sync now").
  Future<void> syncNow() => _syncAll(manual: true);

  /// Exchange every row again with [p] (recovery after a restore).
  Future<void> fullResync(PairedPeer p) => _syncWith(p.address, full: true);

  /// Pair with a discovered device (= first sync).
  Future<void> pair(DiscoveredPeer d) => _syncWith(d.address);

  /// "Add device by IP" — host or host:port.
  Future<void> addByAddress(String input) {
    final a = input.trim();
    return _syncWith(a.contains(':') ? a : '$a:$syncPort');
  }

  // -------------------------------------------------------------- lifecycle

  Future<void> _restart() async {
    await _stop();
    if (state.enabled && state.codeValid) await _start();
  }

  Future<void> _start() async {
    final db = ref.read(dbProvider);
    final auth = SyncAuth(state.code);
    final server = SyncServer(db: db, auth: auth, name: () => state.deviceName);
    try {
      _server = await shelf_io.serve(server.handle, InternetAddress.anyIPv4, syncPort, shared: true);
    } catch (e) {
      state = state.copyWith(
        listening: false,
        error: () => SyncException(SyncErrorKind.other, 'Could not start sync on port $syncPort: $e'),
      );
      return;
    }
    state = state.copyWith(listening: true, addresses: await _localAddresses());

    _discovery = SyncDiscovery(
      deviceId: db.deviceId,
      onFound: (d) {
        state = state.copyWith(discovered: {...state.discovered, d.id: d});
        if (state.autoSync && state.paired.any((p) => p.id == d.id)) _syncWith(d.address, quiet: true);
      },
      onLost: (id) => state = state.copyWith(discovered: Map.of(state.discovered)..remove(id)),
    );
    try {
      await _discovery!.start(name: state.deviceName, port: syncPort);
    } catch (_) {
      // Discovery is optional; Add device by IP still works.
    }

    if (state.autoSync) {
      _localSub = db.localChanges.listen((_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(seconds: 5), () => _syncAll());
      });
      _lifecycle = AppLifecycleListener(onResume: () => _syncAll());
      _netSub = Connectivity().onConnectivityChanged.listen((r) {
        final lan = r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
        final cameBack = lan && !_onLan;
        _onLan = lan;
        if (cameBack) _syncAll();
      });
      _schedulePeriodic();
      await BackgroundSync.schedule();
      unawaited(Future.delayed(const Duration(seconds: 2), () => _syncAll()));
    } else {
      await BackgroundSync.cancel();
    }
  }

  void _schedulePeriodic() {
    _periodic?.cancel();
    if (!state.enabled || !state.autoSync) return;
    _periodic = Timer.periodic(Duration(minutes: state.intervalMin), (_) => _syncAll());
  }

  Future<void> _stop() async {
    _periodic?.cancel();
    _debounce?.cancel();
    await _localSub?.cancel();
    await _netSub?.cancel();
    _lifecycle?.dispose();
    _lifecycle = null;
    await _discovery?.stop();
    _discovery = null;
    await _server?.close(force: true);
    _server = null;
    if (ref.mounted) state = state.copyWith(listening: false, discovered: const {});
  }

  // ------------------------------------------------------------------ syncing

  Future<void> _syncAll({bool manual = false}) async {
    if (!state.enabled || !state.codeValid || state.busyPeer != null) return;
    if (!manual) {
      if (!_onLan) return;
      if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) return;
    }
    for (final p in state.paired) {
      // Prefer the address discovery currently sees (IPs change on DHCP).
      final live = state.discovered[p.id];
      await _syncWith(live?.address ?? p.address, quiet: !manual);
    }
  }

  Future<void> _syncWith(String address, {bool full = false, bool quiet = false}) async {
    if (!state.codeValid || state.busyPeer != null) return;
    final db = ref.read(dbProvider);
    final client = SyncClient(db: db, auth: SyncAuth(state.code), name: state.deviceName);
    state = state.copyWith(busyPeer: () => address, progress: () => null, error: () => null);
    try {
      final r = await client.syncWith(
        address,
        full: full,
        onProgress: (rec, total) {
          if (ref.mounted) state = state.copyWith(progress: () => (received: rec, total: total));
        },
      );
      if (!ref.mounted) return;
      final host = address.split(':').first;
      final port = int.tryParse(address.split(':').last) ?? syncPort;
      final peer = PairedPeer(
        id: r.peerId,
        name: r.peerName,
        host: host,
        port: port,
        lastSyncAt: DateTime.now(),
        lastSent: r.sent,
        lastReceived: r.received,
      );
      final peers = [peer, ...state.paired.where((p) => p.id != r.peerId)];
      await _prefs.setPeers(peers);
      _failures = 0;
      _retryAfter = null;
      state = state.copyWith(
        paired: peers,
        lastResult: () => 'Sent ${r.sent}, received ${r.received}',
        mismatchPeer: () => null,
      );
    } on SyncException catch (e) {
      if (!ref.mounted) return;
      _failures++;
      // Back off auto-sync after failures: 30 s, 1 min, 2 min … up to the interval.
      final backoff = Duration(seconds: math.min(30 * (1 << (_failures - 1)), state.intervalMin * 60));
      _retryAfter = DateTime.now().add(backoff);
      final name =
          state.paired.where((p) => p.address == address).firstOrNull?.name ??
          state.discovered.values.where((d) => d.address == address).firstOrNull?.name ??
          address;
      if (!quiet || e.kind == SyncErrorKind.codeMismatch) {
        state = state.copyWith(error: () => e, mismatchPeer: e.kind == SyncErrorKind.codeMismatch ? () => name : null);
      }
    } finally {
      client.close();
      if (ref.mounted) state = state.copyWith(busyPeer: () => null, progress: () => null);
    }
  }

  static Future<List<String>> _localAddresses() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      return [
        for (final i in ifs)
          for (final a in i.addresses)
            if (!a.isLoopback && !a.isLinkLocal) a.address,
      ];
    } catch (_) {
      return const [];
    }
  }
}
