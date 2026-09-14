import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server.dart';

/// User-adjustable advanced settings, persisted in shared_preferences.
class AppSettings extends ChangeNotifier {
  static const defaultTestUrl = 'https://www.gstatic.com/generate_204';
  static const testUrls = {
    defaultTestUrl: 'Google',
    'https://cp.cloudflare.com/generate_204': 'Cloudflare',
    'https://www.apple.com/library/test/success.html': 'Apple',
  };
  /// DNS presets for the sing-box core: id -> (label, address, direct). Gaming presets only work inside Iran.
  static const dnsPresets = <String, (String, String, bool)>{
    'cloudflare': ('Cloudflare', '1.1.1.1', false),
    'google': ('Google', '8.8.8.8', false),
    'quad9': ('Quad9', '9.9.9.9', false),
    'adguard': ('AdGuard ضدتبلیغ', '94.140.14.14', false),
  };
  static const gamingDnsPresets = <String, (String, String, bool)>{
    'radar': ('Radar Game', '10.202.10.10', true),
    'electro': ('Electro', '78.157.42.100', true),
    'shecan': ('Shecan', '178.22.122.100', true),
    '403': ('403.online', '10.202.10.202', true),
  };

  /// A valid custom DNS: dotted IPv4 or an https:// DoH URL.
  static bool validDns(String value) {
    final v = value.trim();
    final ip = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(v);
    if (ip != null) return [for (var i = 1; i <= 4; i++) int.parse(ip.group(i)!)].every((n) => n <= 255);
    final uri = Uri.tryParse(v);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  /// Resolved (address, direct) for the selected DNS; null = automatic.
  (String, bool)? get tunnelDns {
    if (dnsPreset == 'custom') return validDns(customDns) ? (customDns.trim(), false) : null;
    final p = dnsPresets[dnsPreset] ?? gamingDnsPresets[dnsPreset];
    return p == null ? null : (p.$2, p.$3);
  }

  static const dnsServers = {'1.1.1.1': 'Cloudflare', '8.8.8.8': 'Google', '9.9.9.9': 'Quad9'};

  // Appearance
  String themeMode = 'system'; // system | light | dark
  bool reduceMotion = false;

  // Connection
  String androidCore = 'auto'; // auto | xray | singbox
  String connectMode = 'direct'; // direct (like v2rayNG, no ping) | test (ping first, pick fastest)
  String transport = 'auto'; // auto (V2Ray servers, WARP, then Psiphon) | v2ray | warp | psiphon | tor
  bool autoReconnect = true;
  bool connectOnLaunch = true; // "اتصال خودکار": connect once servers load (also after Windows startup)
  bool anonymousReports = false; // opt-in anonymous server quality reports
  bool proxyOnly = false; // Android: local proxy without VPN tunnel
  bool systemProxy = true; // Windows: set the Windows system proxy
  bool tunMode = false; // Windows: full-device VPN (administrator)
  bool killSwitch = false; // Windows: block traffic if the core dies
  int localPort = 0; // Windows: 0 = random free port

  // Routing / DNS / anti-censorship
  bool bypassIran = true;
  String dns = '1.1.1.1';
  String dnsPreset = 'auto'; // auto | a dnsPresets/gamingDnsPresets id | custom
  String customDns = '';
  bool fragment = false;
  Set<String> excludedApps = {}; // Android package names that skip the VPN

  // Extras
  bool warp = false; // chain Cloudflare WARP behind the server
  String warpAccount = ''; // JSON of WarpAccount, created on first use
  bool launchAtStartup = false; // Windows
  Set<String> favorites = {}; // server uris
  List<String> manualConfigs = []; // user-imported share links

  // Server selection
  int poolSize = 40;
  int timeoutSeconds = 8;
  String testUrl = defaultTestUrl;
  Set<Protocol> protocols = Protocol.values.toSet();
  String customSubscription = '';

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    themeMode = p.getString('s_themeMode') ?? themeMode;
    reduceMotion = p.getBool('s_reduceMotion') ?? reduceMotion;
    androidCore = p.getString('s_androidCore') ?? androidCore;
    connectMode = p.getString('s_connectMode') ?? connectMode;
    transport = p.getString('s_transport') ?? transport;
    autoReconnect = p.getBool('s_autoReconnect') ?? autoReconnect;
    connectOnLaunch = p.getBool('s_autoConnect') ?? connectOnLaunch;
    anonymousReports = p.getBool('s_anonReports') ?? anonymousReports;
    proxyOnly = p.getBool('s_proxyOnly') ?? proxyOnly;
    systemProxy = p.getBool('s_systemProxy') ?? systemProxy;
    tunMode = p.getBool('s_tunMode') ?? tunMode;
    killSwitch = p.getBool('s_killSwitch') ?? killSwitch;
    localPort = p.getInt('s_localPort') ?? localPort;
    bypassIran = p.getBool('s_bypassIran') ?? bypassIran;
    dns = p.getString('s_dns') ?? dns;
    dnsPreset = p.getString('s_dnsPreset') ?? dnsPreset;
    customDns = p.getString('s_customDns') ?? customDns;
    fragment = p.getBool('s_fragment') ?? fragment;
    excludedApps = (p.getStringList('s_excludedApps') ?? const []).toSet();
    warp = p.getBool('s_warp') ?? warp;
    warpAccount = p.getString('s_warpAccount') ?? warpAccount;
    launchAtStartup = p.getBool('s_launchAtStartup') ?? launchAtStartup;
    favorites = (p.getStringList('s_favorites') ?? const []).toSet();
    manualConfigs = p.getStringList('s_manualConfigs') ?? [];
    poolSize = p.getInt('s_poolSize') ?? poolSize;
    timeoutSeconds = p.getInt('s_timeout') ?? timeoutSeconds;
    testUrl = p.getString('s_testUrl') ?? testUrl;
    customSubscription = p.getString('s_customSub') ?? customSubscription;
    final names = p.getStringList('s_protocols');
    if (names != null) {
      final parsed = Protocol.values.where((x) => names.contains(x.name)).toSet();
      if (parsed.isNotEmpty) protocols = parsed;
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await Future.wait([
      p.setString('s_themeMode', themeMode),
      p.setBool('s_reduceMotion', reduceMotion),
      p.setString('s_androidCore', androidCore),
      p.setString('s_connectMode', connectMode),
      p.setString('s_transport', transport),
      p.setBool('s_autoReconnect', autoReconnect),
      p.setBool('s_autoConnect', connectOnLaunch),
      p.setBool('s_anonReports', anonymousReports),
      p.setBool('s_proxyOnly', proxyOnly),
      p.setBool('s_systemProxy', systemProxy),
      p.setBool('s_tunMode', tunMode),
      p.setBool('s_killSwitch', killSwitch),
      p.setInt('s_localPort', localPort),
      p.setBool('s_bypassIran', bypassIran),
      p.setString('s_dns', dns),
      p.setString('s_dnsPreset', dnsPreset),
      p.setString('s_customDns', customDns),
      p.setBool('s_fragment', fragment),
      p.setStringList('s_excludedApps', excludedApps.toList()),
      p.setBool('s_warp', warp),
      p.setString('s_warpAccount', warpAccount),
      p.setBool('s_launchAtStartup', launchAtStartup),
      p.setStringList('s_favorites', favorites.toList()),
      p.setStringList('s_manualConfigs', manualConfigs),
      p.setInt('s_poolSize', poolSize),
      p.setInt('s_timeout', timeoutSeconds),
      p.setString('s_testUrl', testUrl),
      p.setString('s_customSub', customSubscription),
      p.setStringList('s_protocols', protocols.map((x) => x.name).toList()),
    ]);
  }

  Future<void> update(void Function(AppSettings s) change) async {
    change(this);
    notifyListeners();
    await _save();
  }

  /// Resets tuning options; keeps personal data (favorites, imported configs, WARP identity).
  Future<void> reset() => update((s) {
        s
          ..warp = false
          ..autoReconnect = true
          ..connectOnLaunch = true
          ..proxyOnly = false
          ..systemProxy = true
          ..tunMode = false
          ..killSwitch = false
          ..localPort = 0
          ..bypassIran = true
          ..dns = '1.1.1.1'
          ..dnsPreset = 'auto'
          ..fragment = false
          ..excludedApps = {}
          ..poolSize = 40
          ..timeoutSeconds = 8
          ..testUrl = defaultTestUrl
          ..protocols = Protocol.values.toSet()
          ..customSubscription = '';
      });
}
