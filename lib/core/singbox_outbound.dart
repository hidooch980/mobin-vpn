// Share link -> sing-box outbound. Dart port of vpn-aggregator/parsers.py (used by the Windows engine).
import 'dart:convert';

import 'server.dart';
import 'warp.dart';

const _utls = {'chrome', 'firefox', 'edge', 'safari', '360', 'qq', 'ios', 'android', 'random', 'randomized'};

typedef Json = Map<String, dynamic>;

/// Returns an outbound without a tag, or null when the link is invalid/unsupported.
Json? parseOutbound(String uri) {
  try {
    if (uri.startsWith('warp://')) return _warpEndpoint(uri);
    if (uri.startsWith('vmess://')) return _vmess(uri);
    if (uri.startsWith('vless://') || uri.startsWith('trojan://')) return _vlessTrojan(uri);
    if (uri.startsWith('ss://')) return _ss(uri);
    if (uri.startsWith('hysteria2://') || uri.startsWith('hy2://')) return _hysteria2(uri);
    if (uri.startsWith('tuic://')) return _tuic(uri);
    if (uri.startsWith('anytls://')) return _anytls(uri);
    if (uri.startsWith('wireguard://') || uri.startsWith('wg://')) return _wireguard(uri);
    if (uri.startsWith('socks://') || uri.startsWith('socks5://')) return _socks(uri);
    if (uri.startsWith('http://') || uri.startsWith('https://')) return _httpProxy(uri);
  } catch (_) {
    return null;
  }
  return null;
}

/// Free WARP route: WireGuard to one Cloudflare endpoint with the registered identity (null until registered).
Json? _warpEndpoint(String uri) {
  final a = WarpRegistry.account;
  if (a == null) return null;
  final u = Uri.parse(uri);
  return {
    'type': 'wireguard', 'server': u.host, 'server_port': u.port,
    'local_address': ['${a.addressV4}/32', '${a.addressV6}/128'],
    'private_key': a.privateKey, 'peer_public_key': a.peerPublicKey, 'reserved': a.reserved, 'mtu': 1280,
  };
}

bool _validEndpoint(String? host, int? port) => host != null && host.isNotEmpty && port != null && port > 0 && port < 65536;

bool _truthy(String? v) => v == '1' || v == 'true';

Json? _tls(String security, String sni, String host, String alpn, String fp, bool insecure,
    {String pbk = '', String sid = ''}) {
  if (security != 'tls' && security != 'reality') return null;
  final tls = <String, dynamic>{'enabled': true, 'server_name': sni.isNotEmpty ? sni : host, 'insecure': insecure};
  if (alpn.isNotEmpty) tls['alpn'] = alpn.split(',').where((a) => a.isNotEmpty).toList();
  if (fp.isNotEmpty || security == 'reality') {
    tls['utls'] = {'enabled': true, 'fingerprint': _utls.contains(fp) ? fp : 'chrome'};
  }
  if (security == 'reality') {
    if (pbk.isEmpty) throw const FormatException('reality without public key');
    tls['reality'] = {'enabled': true, 'public_key': pbk, 'short_id': sid};
  }
  return tls;
}

Json? _transport(String net, String path, String host, String serviceName) {
  switch (net.isEmpty ? 'tcp' : net.toLowerCase()) {
    case 'tcp' || 'raw':
      return null;
    case 'ws':
      final t = <String, dynamic>{'type': 'ws', 'path': path.isEmpty ? '/' : path};
      final p = t['path'] as String;
      final ed = p.indexOf('?ed=');
      if (ed >= 0) {
        t['path'] = p.substring(0, ed);
        final early = int.tryParse(p.substring(ed + 4));
        if (early != null) {
          t['max_early_data'] = early;
          t['early_data_header_name'] = 'Sec-WebSocket-Protocol';
        }
      }
      if (host.isNotEmpty) t['headers'] = {'Host': host};
      return t;
    case 'grpc':
      return {'type': 'grpc', 'service_name': serviceName.isNotEmpty ? serviceName : path};
    case 'h2' || 'http':
      return {'type': 'http', 'path': path.isEmpty ? '/' : path, if (host.isNotEmpty) 'host': host.split(',')};
    case 'httpupgrade':
      return {'type': 'httpupgrade', 'path': path.isEmpty ? '/' : path, 'host': host};
    default:
      throw FormatException('unsupported transport $net');
  }
}

Json _finish(Json out, Json? tls, Json? transport) {
  if (tls != null) out['tls'] = tls;
  if (transport != null) out['transport'] = transport;
  return out;
}

Json _vmess(String uri) {
  final d = jsonDecode(decodeBase64Loose(uri.substring('vmess://'.length))) as Map<String, dynamic>;
  String s(String k) => '${d[k] ?? ''}'.trim();
  final host = s('add'), port = int.tryParse(s('port'));
  if (!_validEndpoint(host, port) || s('id').isEmpty) throw const FormatException('bad vmess');
  final net = s('net').isEmpty ? 'tcp' : s('net');
  final type = s('type').toLowerCase();
  if (type.isNotEmpty && type != 'none' && net == 'tcp') throw const FormatException('tcp header obfuscation');
  final out = <String, dynamic>{
    'type': 'vmess', 'server': host, 'server_port': port, 'uuid': s('id'),
    'security': s('scy').isEmpty ? 'auto' : s('scy'), 'alter_id': int.tryParse(s('aid')) ?? 0,
  };
  final tls = _tls(s('tls').toLowerCase(), s('sni'), s('host').isEmpty ? host : s('host'), s('alpn'), s('fp'), false);
  return _finish(out, tls, _transport(net, s('path'), s('host'), s('path')));
}

Json _vlessTrojan(String uri) {
  final u = Uri.parse(uri);
  final port = u.hasPort ? u.port : null;
  if (!_validEndpoint(u.host, port)) throw const FormatException('bad endpoint');
  final user = Uri.decodeComponent(u.userInfo);
  if (user.isEmpty) throw const FormatException('missing credential');
  final q = u.queryParameters;
  String g(String k, [String def = '']) => q[k] ?? def;
  final out = <String, dynamic>{'type': u.scheme, 'server': u.host, 'server_port': port};
  final String security;
  if (u.scheme == 'vless') {
    out['uuid'] = user;
    final flow = g('flow');
    if (flow.isNotEmpty && flow != 'xtls-rprx-vision') throw const FormatException('unsupported flow');
    if (flow.isNotEmpty) out['flow'] = flow;
    out['packet_encoding'] = 'xudp';
    security = g('security', 'none');
  } else {
    out['password'] = user;
    security = g('security', 'tls');
  }
  if (g('headerType') == 'http') throw const FormatException('tcp header obfuscation');
  final insecure = _truthy(q['allowInsecure']) || _truthy(q['insecure']);
  final tls = _tls(security, g('sni'), g('host').isEmpty ? u.host : g('host'), g('alpn'), g('fp'), insecure,
      pbk: g('pbk'), sid: g('sid'));
  return _finish(out, tls, _transport(g('type', 'tcp'), g('path'), g('host'), g('serviceName')));
}

Json _ss(String uri) {
  var body = uri.substring('ss://'.length).split('#').first;
  final qi = body.indexOf('?');
  if (qi >= 0) {
    if (body.substring(qi).contains('plugin=')) throw const FormatException('ss plugin');
    body = body.substring(0, qi);
  }
  while (body.endsWith('/')) {
    body = body.substring(0, body.length - 1);
  }
  String userinfo, hostport;
  final at = body.lastIndexOf('@');
  if (at >= 0) {
    userinfo = Uri.decodeComponent(body.substring(0, at));
    hostport = body.substring(at + 1);
    if (!userinfo.contains(':')) userinfo = decodeBase64Loose(userinfo);
  } else {
    final decoded = decodeBase64Loose(body);
    final dat = decoded.lastIndexOf('@');
    userinfo = dat < 0 ? '' : decoded.substring(0, dat);
    hostport = decoded.substring(dat + 1);
  }
  final colon = userinfo.indexOf(':');
  final method = colon < 0 ? '' : userinfo.substring(0, colon);
  final password = colon < 0 ? '' : userinfo.substring(colon + 1);
  final p = Uri.parse('ss://x@$hostport');
  final port = p.hasPort ? p.port : null;
  if (method.isEmpty || password.isEmpty || !_validEndpoint(p.host, port)) throw const FormatException('bad ss');
  return {'type': 'shadowsocks', 'server': p.host, 'server_port': port, 'method': method, 'password': password};
}

Json _hysteria2(String uri) {
  final u = Uri.parse(uri.replaceFirst('hy2://', 'hysteria2://'));
  final port = u.hasPort ? u.port : null;
  final user = Uri.decodeComponent(u.userInfo);
  if (!_validEndpoint(u.host, port) || user.isEmpty) throw const FormatException('bad hysteria2');
  final q = u.queryParameters;
  return {
    'type': 'hysteria2', 'server': u.host, 'server_port': port, 'password': user,
    'tls': {'enabled': true, 'server_name': q['sni'] ?? u.host, 'insecure': _truthy(q['insecure'])},
    if (q['obfs'] == 'salamander') 'obfs': {'type': 'salamander', 'password': q['obfs-password'] ?? ''},
  };
}

({Uri u, int port, String user}) _endpoint(String uri, {bool needUser = true}) {
  final u = Uri.parse(uri);
  final port = u.hasPort ? u.port : null;
  final user = Uri.decodeComponent(u.userInfo);
  if (!_validEndpoint(u.host, port) || (needUser && user.isEmpty)) throw const FormatException('bad endpoint');
  return (u: u, port: port!, user: user);
}

Json _anytls(String uri) {
  final e = _endpoint(uri);
  final q = e.u.queryParameters;
  return {
    'type': 'anytls', 'server': e.u.host, 'server_port': e.port, 'password': e.user,
    'tls': {
      'enabled': true, 'server_name': q['sni'] ?? e.u.host,
      'insecure': _truthy(q['insecure']) || _truthy(q['allowInsecure']),
    },
  };
}

Json _wireguard(String uri) {
  final e = _endpoint(uri.replaceFirst('wg://', 'wireguard://'));
  final q = e.u.queryParameters;
  final peer = q['publickey'] ?? q['public_key'] ?? q['peer_public_key'] ?? '';
  final addresses = (q['address'] ?? q['ip'] ?? '')
      .split(',')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .map((a) => a.contains('/') ? a : (a.contains(':') ? '$a/128' : '$a/32'))
      .toList();
  if (peer.isEmpty || addresses.isEmpty) throw const FormatException('bad wireguard');
  return {
    'type': 'wireguard', 'server': e.u.host, 'server_port': e.port, 'private_key': e.user,
    'peer_public_key': peer, 'local_address': addresses, 'mtu': int.tryParse(q['mtu'] ?? '') ?? 1280,
    if (q['presharedkey'] case final psk? when psk.isNotEmpty) 'pre_shared_key': psk,
    if (q['reserved'] case final r? when r.isNotEmpty) 'reserved': r.split(',').map(int.parse).toList(),
  };
}

Json _socks(String uri) {
  final e = _endpoint(uri.replaceFirst('socks5://', 'socks://'), needUser: false);
  var user = e.user;
  if (user.isNotEmpty && !user.contains(':')) user = decodeBase64Loose(user);
  final colon = user.indexOf(':');
  return {
    'type': 'socks', 'server': e.u.host, 'server_port': e.port, 'version': '5',
    if (colon > 0) 'username': user.substring(0, colon),
    if (colon > 0) 'password': user.substring(colon + 1),
  };
}

Json _httpProxy(String uri) {
  final e = _endpoint(uri, needUser: false);
  final colon = e.user.indexOf(':');
  return {
    'type': 'http', 'server': e.u.host, 'server_port': e.port,
    if (colon > 0) 'username': e.user.substring(0, colon),
    if (colon > 0) 'password': e.user.substring(colon + 1),
    if (e.u.scheme == 'https') 'tls': {'enabled': true, 'server_name': e.u.host},
  };
}

Json _tuic(String uri) {
  final u = Uri.parse(uri);
  final port = u.hasPort ? u.port : null;
  final user = Uri.decodeComponent(u.userInfo);
  final colon = user.indexOf(':');
  if (!_validEndpoint(u.host, port) || colon <= 0 || colon == user.length - 1) {
    throw const FormatException('bad tuic');
  }
  final q = u.queryParameters;
  return {
    'type': 'tuic', 'server': u.host, 'server_port': port,
    'uuid': user.substring(0, colon), 'password': user.substring(colon + 1),
    'congestion_control': q['congestion_control'] ?? 'bbr',
    'udp_relay_mode': q['udp_relay_mode'] ?? 'native',
    'tls': {
      'enabled': true, 'server_name': q['sni'] ?? u.host,
      'insecure': _truthy(q['allow_insecure']) || _truthy(q['insecure']),
      'alpn': (q['alpn'] ?? 'h3').split(',').where((a) => a.isNotEmpty).toList(),
    },
  };
}
