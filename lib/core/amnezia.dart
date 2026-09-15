import 'dart:convert';

/// An imported AmneziaWG config (WireGuard + junk-packet obfuscation). It holds the user's private key:
/// it is stored only in local settings and must never be logged (only endpoints may appear in AppLog).
class AmneziaConfig {
  const AmneziaConfig({
    required this.privateKey,
    required this.publicKey,
    required this.addresses,
    required this.endpoints,
    this.presharedKey = '',
    this.dns = const [],
    this.allowedIps = const ['0.0.0.0/0', '::/0'],
    this.mtu = 1280,
    this.keepalive = 0,
    this.obfuscation = const {},
  });

  final String privateKey, publicKey, presharedKey;
  final List<String> addresses, dns, allowedIps;

  /// "host:port" of every [Peer] with the same public key, in file order (tried one by one).
  final List<String> endpoints;
  final int mtu, keepalive;

  /// Amnezia parameters exactly as written (Jc, Jmin, Jmax, S1, S2, H1–H4, ...).
  final Map<String, String> obfuscation;

  static const obfuscationKeys = [
    'Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4', 'H1', 'H2', 'H3', 'H4', 'I1', 'I2', 'I3', 'I4', 'I5',
  ];

  /// Cloudflare WARP peer key: such configs are verified by `warp=on` in the Cloudflare trace.
  static const warpPublicKey = 'bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=';

  bool get isWarp => publicKey == warpPublicKey;

  /// Built-in WARP ingress endpoints for the config generated from the app's own WARP identity, tried in order.
  static const warpEndpoints = [
    '188.114.97.6:7281', '162.159.195.8:3581', '162.159.192.2:878', '8.6.112.224:8886', '162.159.192.64:894',
  ];

  /// No imported config: AmneziaWG config from the app's registered WARP identity (no private key is bundled).
  static AmneziaConfig fromWarp(
          {required String privateKey, required String peerPublicKey, required String v4, required String v6}) =>
      AmneziaConfig(
        privateKey: privateKey,
        publicKey: peerPublicKey,
        addresses: ['$v4/32', '$v6/128'],
        endpoints: warpEndpoints,
        dns: const ['1.1.1.1'],
        mtu: 1280,
        obfuscation: const {'Jc': '5', 'Jmin': '10', 'Jmax': '40', 'H1': '1', 'H2': '2', 'H3': '3', 'H4': '4'},
      );

  bool get hasJunk => (int.tryParse(obfuscation['Jc'] ?? '') ?? 0) > 0;

  /// Parses a .conf text; throws [FormatException] with a Persian message when it is not usable.
  static AmneziaConfig parse(String text) {
    String? section;
    final iface = <String, String>{};
    final peers = <Map<String, String>>[];
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.split('#').first.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim().toLowerCase();
        if (section == 'peer') peers.add({});
        continue;
      }
      final eq = line.indexOf('=');
      if (eq <= 0) throw const FormatException('خط نامعتبر در کانفیگ');
      final key = line.substring(0, eq).trim().toLowerCase();
      final value = line.substring(eq + 1).trim();
      if (section == 'interface') {
        iface[key] = value;
      } else if (section == 'peer') {
        peers.last[key] = value;
      }
    }
    List<String> list(String? v) =>
        v == null ? const [] : v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    final privateKey = iface['privatekey'] ?? '';
    if (!_isKey(privateKey)) throw const FormatException('PrivateKey نامعتبر است یا وجود ندارد');
    final addresses = list(iface['address']);
    if (addresses.isEmpty) throw const FormatException('Address در بخش [Interface] نیست');
    if (peers.isEmpty) throw const FormatException('بخش [Peer] پیدا نشد');
    final publicKey = peers.first['publickey'] ?? '';
    if (!_isKey(publicKey)) throw const FormatException('PublicKey نامعتبر است');
    final presharedKey = peers.first['presharedkey'] ?? '';
    if (presharedKey.isNotEmpty && !_isKey(presharedKey)) throw const FormatException('PresharedKey نامعتبر است');
    final endpoints = <String>[];
    for (final p in peers) {
      if ((p['publickey'] ?? publicKey) != publicKey) continue;
      final e = p['endpoint'];
      if (e != null && _isEndpoint(e) && !endpoints.contains(e)) endpoints.add(e);
    }
    if (endpoints.isEmpty) throw const FormatException('Endpoint معتبری در بخش‌های [Peer] نیست');
    final obfuscation = <String, String>{
      for (final k in obfuscationKeys)
        k: ?iface[k.toLowerCase()],
    };
    for (final k in const ['Jc', 'Jmin', 'Jmax', 'S1', 'S2', 'S3', 'S4']) {
      final v = obfuscation[k];
      if (v != null && int.tryParse(v) == null) throw FormatException('مقدار $k نامعتبر است');
    }
    final allowed = list(peers.first['allowedips']);
    return AmneziaConfig(
      privateKey: privateKey,
      publicKey: publicKey,
      presharedKey: presharedKey,
      addresses: addresses,
      dns: list(iface['dns']),
      allowedIps: allowed.isEmpty ? const ['0.0.0.0/0', '::/0'] : allowed,
      endpoints: endpoints,
      mtu: int.tryParse(iface['mtu'] ?? '') ?? 1280,
      keepalive: int.tryParse(peers.first['persistentkeepalive'] ?? '') ?? 0,
      obfuscation: obfuscation,
    );
  }

  static bool _isKey(String v) {
    try {
      return base64.decode(v).length == 32;
    } catch (_) {
      return false;
    }
  }

  static bool _isEndpoint(String v) {
    final i = v.lastIndexOf(':');
    if (i <= 0) return false;
    final port = int.tryParse(v.substring(i + 1));
    return port != null && port > 0 && port < 65536;
  }

  /// AmneziaWG .conf text with a single peer at [endpoint].
  String toConf(String endpoint) {
    final b = StringBuffer()
      ..writeln('[Interface]')
      ..writeln('PrivateKey = $privateKey')
      ..writeln('Address = ${addresses.join(', ')}');
    if (dns.isNotEmpty) b.writeln('DNS = ${dns.join(', ')}');
    b.writeln('MTU = $mtu');
    for (final e in obfuscation.entries) {
      b.writeln('${e.key} = ${e.value}');
    }
    b
      ..writeln()
      ..writeln('[Peer]')
      ..writeln('PublicKey = $publicKey');
    if (presharedKey.isNotEmpty) b.writeln('PresharedKey = $presharedKey');
    b
      ..writeln('AllowedIPs = ${allowedIps.join(', ')}')
      ..writeln('Endpoint = $endpoint');
    if (keepalive > 0) b.writeln('PersistentKeepalive = $keepalive');
    return b.toString();
  }

  Map<String, dynamic> toJson() => {
        'privateKey': privateKey,
        'publicKey': publicKey,
        'presharedKey': presharedKey,
        'addresses': addresses,
        'dns': dns,
        'allowedIps': allowedIps,
        'endpoints': endpoints,
        'mtu': mtu,
        'keepalive': keepalive,
        'obfuscation': obfuscation,
      };

  static AmneziaConfig? fromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return AmneziaConfig(
        privateKey: m['privateKey'] as String,
        publicKey: m['publicKey'] as String,
        presharedKey: m['presharedKey'] as String? ?? '',
        addresses: (m['addresses'] as List).cast<String>(),
        dns: (m['dns'] as List).cast<String>(),
        allowedIps: (m['allowedIps'] as List).cast<String>(),
        endpoints: (m['endpoints'] as List).cast<String>(),
        mtu: m['mtu'] as int,
        keepalive: m['keepalive'] as int,
        obfuscation: Map<String, String>.from(m['obfuscation'] as Map),
      );
    } catch (_) {
      return null;
    }
  }
}
