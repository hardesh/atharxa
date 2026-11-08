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

/// The last failed session and whether the user started it ("Sync now",
/// Pair, Add by IP) or auto-sync did. The UI shows manual failures (and code
/// mismatches) prominently and auto-sync failures quietly.
typedef SyncFailure = ({SyncException error, bool manual});

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
    this.address,
    this.paired = const [],
    this.discovered = const {},
    this.busy = false,
    this.progress,
    this.lastResult,
    this.failure,
  });

  final bool enabled, autoSync, listening, busy;
  final String deviceName, code;
  final int intervalMin;

  /// This device's IPv4 address (for "Add device by IP" on the other side).
  final String? address;
  final List<PairedPeer> paired;

  /// Peers currently advertising on the network, by device id.
  final Map<String, DiscoveredPeer> discovered;
  final ({int received, int total})? progress;

  /// "Sent 4, received 12" of the last successful session.
  final String? lastResult;
  final SyncFailure? failure;

  bool get codeValid => SyncAuth.isValidCode(code);

  /// Most recent successful sync with any paired device.
  DateTime? get lastSync => paired
      .map((p) => p.lastSyncAt)
      .whereType<DateTime>()
      .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);

  SyncState copyWith({
    bool? enabled,
    String? deviceName,
    String? code,
    bool? autoSync,
    int? intervalMin,
    bool? listening,
    String? address,
    List<PairedPeer>? paired,
    Map<String, DiscoveredPeer>? discovered,
    bool? busy,
    ({int received, int total})? progress,
    String? lastResult,
    SyncFailure? failure,
    bool clearProgress = false,
    bool clearFailure = false,
  }) => SyncState(
    enabled: enabled ?? this.enabled,
    deviceName: deviceName ?? this.deviceName,
    code: code ?? this.code,
    autoSync: autoSync ?? this.autoSync,
    intervalMin: intervalMin ?? this.intervalMin,
    listening: listening ?? this.listening,
    address: address ?? this.address,
    paired: paired ?? this.paired,
    discovered: discovered ?? this.discovered,
    busy: busy ?? this.busy,
    progress: clearProgress ? null : (progress ?? this.progress),
    lastResult: lastResult ?? this.lastResult,
    failure: clearFailure ? null : (failure ?? this.failure),
  );
}

/// Not auto-disposed: started once from `main` and kept for the app's lifetime.
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

  @override
  SyncState build() {
    _prefs = SyncPrefs(ref.watch(prefsProvider));
    ref.onDispose(_stop);
    final s = SyncState(
      enabled: _prefs.enabled,
      deviceName: _prefs.deviceName,
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
    state = state.copyWith(enabled: on, code: code, clearFailure: true);
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
    state = state.copyWith(code: c, clearFailure: true);
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

  static String _newCode() => (math.Random.secure().nextInt(900000) + 100000).toString();

  // ----------------------------------------------------------------- actions

  /// Sync with every paired device ("Sync now").
  Future<void> syncNow() => _syncAll(manual: true);

  /// Exchange every row again with [p] (recovery after a restore).
  Future<void> fullResync(PairedPeer p) => _syncWith(p.address, full: true, manual: true);

  /// Pair with a discovered device (= first sync).
  Future<void> pair(DiscoveredPeer d) => _syncWith(d.address, manual: true);

  /// "Add device by IP" — host or host:port.
  Future<void> addByAddress(String input) {
    final a = parseAddress(input);
    return _syncWith('${a.host}:${a.port}', manual: true);
  }

  // -------------------------------------------------------------- lifecycle

  Future<void> _restart() async {
    await _stop();
    if (state.enabled && state.codeValid) await _start();
  }

  Future<void> _start() async {
    final db = ref.read(dbProvider);
    final server = SyncServer(db: db, auth: SyncAuth(state.code), name: () => state.deviceName);
    try {
      _server = await shelf_io.serve(server.handle, InternetAddress.anyIPv4, syncPort, shared: true);
    } catch (e) {
      state = state.copyWith(
        listening: false,
        failure: (
          error: SyncException(SyncErrorKind.other, 'Could not start sync on port $syncPort: $e'),
          manual: true,
        ),
      );
      return;
    }
    state = state.copyWith(listening: true, address: await _localAddress());

    _discovery = SyncDiscovery(
      deviceId: db.deviceId,
      onFound: (d) {
        state = state.copyWith(discovered: {...state.discovered, d.id: d});
        if (state.autoSync && state.paired.any((p) => p.id == d.id)) _syncWith(d.address);
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
        _debounce = Timer(const Duration(seconds: 5), _syncAll);
      });
      _lifecycle = AppLifecycleListener(onResume: _syncAll);
      _netSub = Connectivity().onConnectivityChanged.listen((r) {
        final lan = r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);
        final cameBack = lan && !_onLan;
        _onLan = lan;
        if (cameBack) _syncAll();
      });
      _schedulePeriodic();
      await BackgroundSync.schedule();
      unawaited(Future.delayed(const Duration(seconds: 2), _syncAll));
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
    if (!state.enabled || !state.codeValid || state.busy) return;
    if (!manual) {
      if (!_onLan) return;
      if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) return;
    }
    for (final p in state.paired) {
      // Prefer the address discovery currently sees (IPs change on DHCP).
      await _syncWith(state.discovered[p.id]?.address ?? p.address, manual: manual);
    }
  }

  Future<void> _syncWith(String address, {bool full = false, bool manual = false}) async {
    if (!state.codeValid || state.busy) return;
    final client = SyncClient(db: ref.read(dbProvider), auth: SyncAuth(state.code));
    state = state.copyWith(busy: true, clearProgress: true, clearFailure: manual);
    try {
      final r = await client.syncWith(
        address,
        full: full,
        onProgress: (rec, total) {
          if (ref.mounted) state = state.copyWith(progress: (received: rec, total: total));
        },
      );
      if (!ref.mounted) return;
      final a = parseAddress(address);
      final peers = await _prefs.recordSession(
        peerId: r.peerId,
        peerName: r.peerName,
        host: a.host,
        port: a.port,
        sent: r.sent,
        received: r.received,
      );
      _failures = 0;
      _retryAfter = null;
      state = state.copyWith(paired: peers, lastResult: 'Sent ${r.sent}, received ${r.received}', clearFailure: true);
    } on SyncException catch (e) {
      if (!ref.mounted) return;
      _failures++;
      // Back off auto-sync after failures: 30 s, 1 min, 2 min … up to the interval.
      final backoff = Duration(seconds: math.min(30 * (1 << math.min(_failures - 1, 10)), state.intervalMin * 60));
      _retryAfter = DateTime.now().add(backoff);
      final name =
          state.paired.where((p) => p.address == address).firstOrNull?.name ??
          state.discovered.values.where((d) => d.address == address).firstOrNull?.name ??
          address;
      state = state.copyWith(failure: (error: e.withPeer(name), manual: manual));
    } finally {
      client.close();
      if (ref.mounted) state = state.copyWith(busy: false, clearProgress: true);
    }
  }

  static Future<String?> _localAddress() async {
    try {
      final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (!a.isLoopback && !a.isLinkLocal) return a.address;
        }
      }
    } catch (_) {}
    return null;
  }
}
