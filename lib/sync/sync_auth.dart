import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Authenticates sync traffic with the shared 6-digit pairing code.
///
/// The code never travels over the network. Both sides derive a key from it
/// (PBKDF2-HMAC-SHA256) and sign every request and response with
/// HMAC-SHA256 over method, path, timestamp, sender id and a body hash.
/// A wrong code therefore shows up as a signature mismatch on either side.
/// Timestamps older than [maxSkew] are rejected to limit replays.
///
/// Note: this authenticates, it does not encrypt. Data is visible to anyone
/// sniffing the local network, which is acceptable for a home Wi-Fi.
class SyncAuth {
  SyncAuth(String code) : _key = _derive(code);

  final List<int> _key;

  static const maxSkew = Duration(minutes: 5);
  static const _salt = 'app-sync-v1';
  static const _iterations = 20000;

  static final _cache = <String, List<int>>{};

  static bool isValidCode(String code) => RegExp(r'^\d{6}$').hasMatch(code);

  static List<int> _derive(String code) =>
      _cache.putIfAbsent(code, () => pbkdf2(utf8.encode(code), utf8.encode(_salt), _iterations, 32));

  /// PBKDF2 with HMAC-SHA256 (RFC 8018).
  static List<int> pbkdf2(List<int> password, List<int> salt, int iterations, int length) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    for (var block = 1; out.length < length; block++) {
      final blockBytes = ByteData(4)..setUint32(0, block);
      var u = hmac.convert([...salt, ...blockBytes.buffer.asUint8List()]).bytes;
      final t = List<int>.of(u);
      for (var i = 1; i < iterations; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
    }
    return out.toBytes().sublist(0, length);
  }

  String sign({
    required String method,
    required String path,
    required int ts,
    required String sender,
    required List<int> body,
  }) {
    final msg = '$method\n$path\n$ts\n$sender\n${sha256.convert(body)}';
    return Hmac(sha256, _key).convert(utf8.encode(msg)).toString();
  }

  bool verify({
    required String method,
    required String path,
    required int ts,
    required String sender,
    required List<int> body,
    required String? signature,
    DateTime? now,
  }) {
    if (signature == null) return false;
    final skew = ((now ?? DateTime.now()).millisecondsSinceEpoch - ts).abs();
    if (skew > maxSkew.inMilliseconds) return false;
    final expected = sign(method: method, path: path, ts: ts, sender: sender, body: body);
    return _constantTimeEquals(expected, signature);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Header names used by the sync protocol.
abstract final class SyncHeaders {
  static const device = 'x-sync-device';
  static const ts = 'x-sync-ts';
  static const sig = 'x-sync-sig';
}
