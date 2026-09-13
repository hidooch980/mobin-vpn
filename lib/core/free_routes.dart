import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import 'app_log.dart';
import 'server.dart';

/// Psiphon and Tor: free routes that need no server list (Android only).
/// The native side starts them on a local SOCKS port; Xray's VPN forwards device traffic there.
class FreeRoutes {
  static const _channel = MethodChannel('mobin/native');

  static const psiphonPort = 18190, torPort = 19050;

  static final psiphon = Server(uri: 'psiphon://auto', remark: 'Psiphon', countryCode: 'PSIPHON', protocol: Protocol.socks);
  static final tor = Server(uri: 'tor://auto', remark: 'Tor', countryCode: 'TOR', protocol: Protocol.socks);

  static bool isFree(Server s) => s.uri.startsWith('psiphon://') || s.uri.startsWith('tor://');

  static String routeOf(Server s) => s.uri.startsWith('tor://') ? 'tor' : 'psiphon';

  static int portOf(Server s) => routeOf(s) == 'tor' ? torPort : psiphonPort;

  /// Starts the route and waits until it is ready. [onProgress] gets a Persian status line.
  static Future<bool> start(Server s, {required bool Function() isCancelled, void Function(String)? onProgress}) async {
    final route = routeOf(s);
    await _channel.invokeMethod<void>('freeStart', {'route': route});
    // Psiphon usually connects in 5-40 s; Tor direct in 10-30 s, over the meek bridge up to ~3 minutes.
    final deadline = DateTime.now().add(Duration(seconds: route == 'tor' ? 200 : 120));
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled()) {
        await stop();
        return false;
      }
      final st = await _status();
      final state = st[route] as String? ?? 'idle';
      if (state == 'connected') return true;
      if (state == 'failed') return false;
      if (route == 'tor') {
        onProgress?.call('اتصال به شبکه‌ی Tor… ${st['torProgress'] ?? 0}٪');
      } else {
        onProgress?.call('در حال یافتن سرور Psiphon…');
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    AppLog.add('$route: timed out');
    await stop();
    return false;
  }

  static Future<Map<String, dynamic>> _status() async {
    try {
      final st = await _channel.invokeMapMethod<String, dynamic>('freeStatus') ?? const {};
      for (final line in (st['log'] as List? ?? const [])) {
        AppLog.add('$line');
      }
      return st;
    } catch (_) {
      return const {};
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('freeStop');
    } catch (_) {}
  }

  /// Xray config for the VpnService: everything goes to the route's local SOCKS port.
  static String tunnelConfig(Server s, {required String dns, required bool bypassIran}) => jsonEncode({
        'log': {'loglevel': 'warning'},
        'inbounds': [
          {
            'tag': 'in_proxy',
            'port': 10808,
            'protocol': 'socks',
            'listen': '127.0.0.1',
            'settings': {'auth': 'noauth', 'udp': true, 'userLevel': 8},
            'sniffing': {
              'enabled': true,
              'destOverride': ['http', 'tls'],
              'routeOnly': true,
            },
          },
        ],
        'outbounds': [
          {
            'tag': 'proxy',
            'protocol': 'socks',
            'settings': {
              'servers': [
                {'address': '127.0.0.1', 'port': portOf(s)},
              ],
            },
          },
          {'tag': 'direct', 'protocol': 'freedom', 'settings': <String, dynamic>{}},
        ],
        'dns': {
          'servers': [dns],
        },
        'routing': {
          'domainStrategy': 'AsIs',
          'rules': [
            {
              'type': 'field',
              'ip': ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '127.0.0.0/8', '169.254.0.0/16'],
              'outboundTag': 'direct',
            },
            if (bypassIran) {'type': 'field', 'domain': ['domain:ir'], 'outboundTag': 'direct'},
          ],
        },
      });
}
