import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'app_log.dart';
import 'cf_clean_ip.dart';
import 'server.dart';

/// Detects networks that drop UDP (DNS to 1.1.1.1:53 and a QUIC probe to 1.1.1.1:443 both unanswered).
/// There, UDP-only routes (Hysteria2, TUIC, WireGuard/WARP) are skipped in automatic selection.
class UdpProbe {
  UdpProbe._();

  static const _timeout = Duration(milliseconds: 1500);
  static const _maxAge = Duration(minutes: 30);

  static final _results = <String, (bool blocked, DateTime at)>{};
  static String? _network;
  static bool _running = false;

  /// UDP looked blocked on the current network at the last probe (within 30 min).
  static bool get blocked {
    final r = _results[_network];
    return r != null && r.$1 && DateTime.now().difference(r.$2) < _maxAge;
  }

  static bool udpOnly(Server s) =>
      s.protocol == Protocol.hysteria2 || s.protocol == Protocol.tuic || s.protocol == Protocol.wireguard;

  /// Must run while the app's own traffic is not inside a TUN tunnel.
  static Future<void> probe() async {
    if (_running) return;
    _running = true;
    try {
      final key = await CleanIp.networkKey();
      _network = key;
      final last = _results[key];
      if (last != null && DateTime.now().difference(last.$2) < _maxAge) return;
      final target = InternetAddress('1.1.1.1');
      final results = await Future.wait([_roundTrip(target, 53, _dnsQuery()), _roundTrip(target, 443, _quicProbe())]);
      final isBlocked = !results[0] && !results[1];
      _results[key] = (isBlocked, DateTime.now());
      AppLog.add('udp probe: dns=${results[0]} quic=${results[1]} -> ${isBlocked ? 'UDP blocked' : 'UDP ok'} on $key');
    } catch (e) {
      AppLog.add('udp probe: $e');
    } finally {
      _running = false;
    }
  }

  static Future<bool> _roundTrip(InternetAddress to, int port, List<int> packet) async {
    RawDatagramSocket? socket;
    try {
      final s = socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      final done = Completer<bool>();
      s.listen((event) {
        if (event == RawSocketEvent.read && s.receive() != null && !done.isCompleted) done.complete(true);
      }, onError: (_) {
        if (!done.isCompleted) done.complete(false);
      });
      s.send(packet, to, port);
      return await done.future.timeout(_timeout, onTimeout: () => false);
    } catch (_) {
      return false;
    } finally {
      socket?.close();
    }
  }

  /// A query for example.com (A record).
  static List<int> _dnsQuery() {
    final id = math.Random().nextInt(0xFFFF);
    return [
      id >> 8, id & 0xFF, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      7, ...'example'.codeUnits, 3, ...'com'.codeUnits, 0,
      0x00, 0x01, 0x00, 0x01,
    ];
  }

  /// QUIC long-header packet with an unknown version: a QUIC server answers with Version Negotiation.
  static List<int> _quicProbe() {
    final r = math.Random();
    final packet = <int>[
      0xC0, 0x1a, 0x2a, 0x3a, 0x4a,
      8, for (var i = 0; i < 8; i++) r.nextInt(256),
      8, for (var i = 0; i < 8; i++) r.nextInt(256),
    ];
    while (packet.length < 1200) {
      packet.add(0);
    }
    return packet;
  }
}
