import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'server.dart';

typedef XJson = Map<String, dynamic>;

/// Transports sing-box 1.12 cannot dial (XHTTP / SplitHTTP); such links run through a local Xray-core.
const _xrayOnlyNetworks = {'xhttp', 'splithttp'};

/// Whether [uri] is a VLESS / VMess / Trojan link with the XHTTP transport.
bool isXhttpLink(String uri) {
  try {
    if (uri.startsWith('vmess://')) {
      final d = jsonDecode(decodeBase64Loose(uri.substring('vmess://'.length))) as Map;
      return _xrayOnlyNetworks.contains('${d['net'] ?? ''}'.toLowerCase());
    }
    if (!uri.startsWith('vless://') && !uri.startsWith('trojan://')) return false;
    return _xrayOnlyNetworks.contains((Uri.parse(uri).queryParameters['type'] ?? '').toLowerCase());
  } catch (_) {
    return false;
  }
}

/// Xray outbound (without tag) for an XHTTP link, or null when the link is not XHTTP or invalid.
XJson? xrayOutbound(String uri) {
  if (!isXhttpLink(uri)) return null;
  try {
    return uri.startsWith('vmess://') ? _vmess(uri) : _vlessTrojan(uri);
  } catch (_) {
    return null;
  }
}

bool _truthy(String? v) => v == '1' || v == 'true';

XJson _stream({
  required String security,
  required String sni,
  required String host,
  required String path,
  required String mode,
  String fp = '',
  String alpn = '',
  bool insecure = false,
  String pbk = '',
  String sid = '',
  String spx = '',
  String extra = '',
}) {
  final xhttp = <String, dynamic>{'path': path.isEmpty ? '/' : path, 'mode': mode.isEmpty ? 'auto' : mode};
  if (host.isNotEmpty) xhttp['host'] = host;
  if (extra.isNotEmpty) {
    final decoded = jsonDecode(extra);
    if (decoded is Map) xhttp['extra'] = decoded;
  }
  final stream = <String, dynamic>{'network': 'xhttp', 'security': 'none', 'xhttpSettings': xhttp};
  if (security == 'tls') {
    stream['security'] = 'tls';
    stream['tlsSettings'] = {
      'serverName': sni.isNotEmpty ? sni : host,
      'allowInsecure': insecure,
      'fingerprint': fp.isEmpty ? 'chrome' : fp,
      if (alpn.isNotEmpty) 'alpn': alpn.split(',').where((a) => a.isNotEmpty).toList(),
    };
  } else if (security == 'reality') {
    if (pbk.isEmpty) throw const FormatException('reality without public key');
    stream['security'] = 'reality';
    stream['realitySettings'] = {
      'serverName': sni,
      'fingerprint': fp.isEmpty ? 'chrome' : fp,
      'publicKey': pbk,
      'shortId': sid,
      'spiderX': spx,
    };
  }
  return stream;
}

XJson _vlessTrojan(String uri) {
  final u = Uri.parse(uri);
  final port = u.hasPort ? u.port : 0;
  final user = Uri.decodeComponent(u.userInfo);
  if (u.host.isEmpty || port <= 0 || port > 65535 || user.isEmpty) throw const FormatException('bad endpoint');
  final q = u.queryParameters;
  String g(String k) => q[k] ?? '';
  final vless = u.scheme == 'vless';
  final stream = _stream(
    security: q['security'] ?? (vless ? 'none' : 'tls'),
    sni: g('sni'),
    host: g('host').isEmpty ? (g('sni').isEmpty ? u.host : g('sni')) : g('host'),
    path: g('path'),
    mode: g('mode'),
    fp: g('fp'),
    alpn: g('alpn'),
    insecure: _truthy(q['allowInsecure']) || _truthy(q['insecure']),
    pbk: g('pbk'),
    sid: g('sid'),
    spx: g('spx'),
    extra: g('extra'),
  );
  if (vless) {
    return {
      'protocol': 'vless',
      'settings': {
        'vnext': [
          {
            'address': u.host,
            'port': port,
            'users': [
              {'id': user, 'encryption': q['encryption'] ?? 'none', if (g('flow').isNotEmpty) 'flow': g('flow')},
            ],
          },
        ],
      },
      'streamSettings': stream,
    };
  }
  return {
    'protocol': 'trojan',
    'settings': {
      'servers': [
        {'address': u.host, 'port': port, 'password': user},
      ],
    },
    'streamSettings': stream,
  };
}

XJson _vmess(String uri) {
  final d = jsonDecode(decodeBase64Loose(uri.substring('vmess://'.length))) as Map<String, dynamic>;
  String s(String k) => '${d[k] ?? ''}'.trim();
  final port = int.tryParse(s('port')) ?? 0;
  if (s('add').isEmpty || port <= 0 || port > 65535 || s('id').isEmpty) throw const FormatException('bad vmess');
  return {
    'protocol': 'vmess',
    'settings': {
      'vnext': [
        {
          'address': s('add'),
          'port': port,
          'users': [
            {'id': s('id'), 'alterId': int.tryParse(s('aid')) ?? 0, 'security': s('scy').isEmpty ? 'auto' : s('scy')},
          ],
        },
      ],
    },
    'streamSettings': _stream(
      security: s('tls').toLowerCase(),
      sni: s('sni'),
      host: s('host').isEmpty ? s('add') : s('host'),
      path: s('path'),
      mode: s('mode'),
      fp: s('fp'),
      alpn: s('alpn'),
    ),
  };
}

/// Windows: a bundled xray.exe with one local SOCKS inbound per XHTTP server; sing-box dials those servers as a
/// `socks` outbound to `127.0.0.1:<port>`. One process serves pings, probes and the live connection.
class XrayBridge {
  XrayBridge({required this.binary, required this.workDir});

  final String binary;
  final Directory workDir;

  /// Its own traffic must leave directly, not through the TUN.
  static const processName = 'xray.exe';
  static const _pidKey = 'xray_bridge_pid';

  bool get available => File(binary).existsSync();

  final _ports = <String, int>{};
  Set<String> _running = {};
  Process? _proc;
  int _nextPort = 31000 + math.Random().nextInt(9000);

  /// sing-box outbound to the local inbound of [uri] (port reserved now), or null when not XHTTP / no xray.exe.
  Map<String, dynamic>? socksOutbound(String uri) {
    if (!available || xrayOutbound(uri) == null) return null;
    final port = _ports.putIfAbsent(uri, () => _nextPort++);
    return {'type': 'socks', 'server': '127.0.0.1', 'server_port': port, 'version': '5'};
  }

  /// Makes sure the XHTTP servers among [uris] are served (restarts Xray only when new ones appear).
  Future<void> ensure(Iterable<String> uris) async {
    final wanted = {..._running, ...uris.where(_ports.containsKey)};
    if (wanted.isEmpty || (_proc != null && wanted.length == _running.length)) return;
    final list = wanted.toList();
    final config = {
      'log': {'loglevel': 'warning'},
      'inbounds': [
        for (final (i, uri) in list.indexed)
          {'tag': 'in$i', 'listen': '127.0.0.1', 'port': _ports[uri], 'protocol': 'socks', 'settings': {'udp': true}},
      ],
      'outbounds': [
        for (final (i, uri) in list.indexed) {...xrayOutbound(uri)!, 'tag': 'out$i'},
        {'protocol': 'freedom', 'tag': 'direct'},
      ],
      'routing': {
        'rules': [
          for (var i = 0; i < list.length; i++) {'type': 'field', 'inboundTag': ['in$i'], 'outboundTag': 'out$i'},
        ],
      },
    };
    await stop();
    final file = File('${workDir.path}${Platform.pathSeparator}xray.json');
    await file.writeAsString(jsonEncode(config));
    try {
      final proc = await Process.start(binary, ['run', '-c', file.path],
          workingDirectory: File(binary).parent.path, mode: ProcessStartMode.detachedWithStdio);
      _proc = proc;
      _running = wanted;
      await (await SharedPreferences.getInstance()).setInt(_pidKey, proc.pid);
      proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter()).listen((line) {
        final l = line.toLowerCase();
        if (l.contains('failed') || l.contains('error')) AppLog.add('xray: $line');
      }, onError: (Object _) {});
      unawaited(proc.stderr.drain<void>());
      AppLog.add('xray: serving ${list.length} XHTTP server(s)');
      // Ready once the first inbound accepts connections.
      final firstPort = _ports[list.first]!;
      for (var i = 0; i < 30; i++) {
        try {
          final socket = await Socket.connect(InternetAddress.loopbackIPv4, firstPort, timeout: const Duration(milliseconds: 200));
          socket.destroy();
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      AppLog.add('xray: inbound not ready after 3 s');
    } catch (e) {
      AppLog.add('xray: could not start ($e)');
      _proc = null;
      _running = {};
    }
  }

  /// Ends an Xray left running by a previous (killed) run of the app.
  Future<void> cleanupStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pid = prefs.getInt(_pidKey);
      if (pid == null) return;
      await prefs.remove(_pidKey);
      final list = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
      if ('${list.stdout}'.toLowerCase().contains(processName)) Process.killPid(pid);
    } catch (_) {}
  }

  Future<void> stop() async {
    final proc = _proc;
    _proc = null;
    _running = {};
    if (proc == null) return;
    Process.killPid(proc.pid);
    try {
      await (await SharedPreferences.getInstance()).remove(_pidKey);
    } catch (_) {}
  }
}
