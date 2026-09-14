import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_log.dart';
import 'singbox_core.dart';

/// Windows: runs the bundled Psiphon (psiphon-tunnel-core.exe) or Tor (tor.exe + lyrebird.exe) as a child
/// process on a local SOCKS port. sing-box then forwards the tunnel / system proxy to that port.
class WinFreeRoutes {
  WinFreeRoutes({required this.appDir, required this.dataDir});

  /// Folder of mobin_vpn.exe; binaries live in `psiphon\` and `tor\` next to it.
  final String appDir;

  /// Writable app data folder for configs and Psiphon/Tor state.
  final Directory dataDir;

  static const _pidKey = 'win_free_route_pid';

  /// Their own traffic must leave directly, not through the TUN (it would loop).
  static const processNames = ['psiphon-tunnel-core.exe', 'tor.exe', 'lyrebird.exe'];

  Process? _proc;

  String get psiphonExe => '$appDir\\psiphon\\psiphon-tunnel-core.exe';
  String get torExe => '$appDir\\tor\\tor.exe';

  bool binaryExists(String route) => File(route == 'tor' ? torExe : psiphonExe).existsSync();

  /// A previous run may have been killed while Psiphon/Tor was running: end that orphan.
  Future<void> cleanupStale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pid = prefs.getInt(_pidKey);
      if (pid == null) return;
      await prefs.remove(_pidKey);
      final list = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/NH', '/FO', 'CSV']);
      final out = '${list.stdout}'.toLowerCase();
      if (processNames.any(out.contains)) await _kill(pid);
    } catch (_) {}
  }

  static Future<void> _kill(int pid) async {
    try {
      // /T also ends lyrebird started by tor.
      await Process.run('taskkill', ['/F', '/T', '/PID', '$pid']);
    } catch (_) {
      Process.killPid(pid);
    }
  }

  Future<void> stop() async {
    final proc = _proc;
    _proc = null;
    if (proc == null) return;
    await _kill(proc.pid);
    try {
      await (await SharedPreferences.getInstance()).remove(_pidKey);
    } catch (_) {}
  }

  /// Starts [route] ('psiphon' or 'tor') and returns its local SOCKS port once it carries traffic, else null.
  Future<int?> start(String route, {required bool Function() isCancelled, void Function(String phase)? onPhase}) async {
    await stop();
    if (!binaryExists(route)) {
      AppLog.add('$route: binary not found next to the app');
      return null;
    }
    return route == 'tor' ? _startTor(isCancelled, onPhase) : _startPsiphon(isCancelled, onPhase);
  }

  // ---------------------------------------------------------------- Psiphon

  Future<int?> _startPsiphon(bool Function() isCancelled, void Function(String)? onPhase) async {
    final dir = Directory('${dataDir.path}\\psiphon')..createSync(recursive: true);
    var socksPort = await SingboxCore.freePort();
    final httpPort = await SingboxCore.freePort();
    final config = File('${dir.path}\\config.json');
    // Same public identity and keys as the Android app (MsnGuardVpnService.buildPsiphonConfig).
    await config.writeAsString(jsonEncode({
      'PropagationChannelId': 'FFFFFFFFFFFFFFFF',
      'SponsorId': '1111111111111111',
      'ClientVersion': '1',
      'ClientPlatform': 'Windows',
      'EgressRegion': '',
      'TunnelProtocol': '',
      'RemoteServerListURL': '',
      'DataRootDirectory': dir.path,
      'LocalSocksProxyPort': socksPort,
      'LocalHttpProxyPort': httpPort,
      'EstablishTunnelTimeoutSeconds': 60,
      'RemoteServerListSignaturePublicKey':
          'MIICIDANBgkqhkiG9w0BAQEFAAOCAg0AMIICCAKCAgEAt7Ls+/39r+T6zNW7GiVpJfzq/xvL9SBH5rIFnk0RXYEYavax3WS6HOD35eTAqn8AniOwiH+DOkvgSKF2caqk/y1dfq47Pdymtwzp9ikpB1C5OfAysXzBiwVJlCdajBKvBZDerV1cMvRzCKvKwRmvDmHgphQQ7WfXIGbRbmmk6opMBh3roE42KcotLFtqp0RRwLtcBRNtCdsrVsjiI1Lqz/lH+T61sGjSjQ3CHMuZYSQJZo/KrvzgQXpkaCTdbObxHqb6/+i1qaVOfEsvjoiyzTxJADvSytVtcTjijhPEV6XskJVHE1Zgl+7rATr/pDQkw6DPCNBS1+Y6fy7GstZALQXwEDN/qhQI9kWkHijT8ns+i1vGg00Mk/6J75arLhqcodWsdeG/M/moWgqQAnlZAGVtJI1OgeF5fsPpXu4kctOfuZlGjVZXQNW34aOzm8r8S0eVZitPlbhcPiR4gT/aSMz/wd8lZlzZYsje/Jr8u/YtlwjjreZrGRmG8KMOzukV3lLmMppXFMvl4bxv6YFEmIuTsOhbLTwFgh7KYNjodLj/LsqRVfwz31PgWQFTEPICV7GCvgVlPRxnofqKSjgTWI4mxDhBpVcATvaoBl1L/6WLbFvBsoAUBItWwctO2xalKxF5szhGm8lccoc5MZr8kfE0uxMgsxz4er68iCID+rsCAQM=',
      'ServerEntrySignaturePublicKey': 'sHuUVTWaRyh5pZwy4UguSgkwmBe0EHtJJkoF5WrxmvA=',
      'ExchangeObfuscationKey': 'DpXzloJk1Hw6aSzmKKky0xcahsEHubch81Mi6K0XMlU=',
      'DeviceRegion': 'IR',
      'ConnectionWorkerPoolSize': 12,
      'DNSResolverPreferredAlternateServers': ['208.67.222.222:5353', '9.9.9.9:9953', '208.67.220.220:5353'],
      'DNSResolverPreferAlternateServerProbability': 1.0,
      'DNSResolverAttemptsPerPreferredServer': 2,
    }));
    // Hex server entries shipped with the app (same list as Android's assets/server_entries.txt).
    final entries = '$appDir\\psiphon\\server_entries.txt';
    final args = ['-config', config.path, if (File(entries).existsSync()) ...['-serverList', entries]];
    onPhase?.call('در حال یافتن سرور Psiphon…');
    var logged = 0;
    final ok = await _launch(psiphonExe, args, const Duration(seconds: 60), 'psiphon', isCancelled, (line) {
      final decoded = _tryJson(line);
      if (decoded is! Map) return null;
      final type = decoded['noticeType'];
      final data = decoded['data'];
      if (type == 'ListeningSocksProxyPort' && data is Map && data['port'] is int) {
        socksPort = data['port'] as int;
      } else if (type == 'Tunnels' && data is Map && (data['count'] as num? ?? 0) >= 1) {
        return true;
      } else if (type == 'ConnectingServer' || type == 'CandidateServers') {
        onPhase?.call('اتصال به سرورهای Psiphon…');
      } else if ((type == 'Alert' || type == 'Error') && logged++ < 20) {
        AppLog.add('psiphon: $line');
      }
      return null;
    });
    return ok ? socksPort : null;
  }

  static Object? _tryJson(String line) {
    try {
      return jsonDecode(line);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- Tor

  /// Ladder like the Android TorManager: Direct, then Meek, obfs4, Snowflake (bridge lines from TorBridges.kt).
  static const _rungs = [
    (transport: '', label: 'مستقیم', seconds: 60),
    (transport: 'meek_lite', label: 'پل Meek', seconds: 120),
    (transport: 'obfs4', label: 'پل obfs4', seconds: 60),
    (transport: 'snowflake', label: 'پل Snowflake', seconds: 120),
  ];

  static const _bridges = <String, List<String>>{
    'obfs4': [
      'obfs4 51.222.13.177:80 5EDAC3B810E12B01F6FD8050D2FD3E277B289A08 cert=2uplIpLQ0q9+0qMFrK5pkaYRDOe460LL9WHBvatgkuRr/SL31wBOEupaMMJ6koRE6Ld0ew iat-mode=0',
      'obfs4 37.218.245.14:38224 D9A82D2F9C2F65A18407B1D2B764F130847F8B5D cert=bjRaMrr1BRiAW8IE9U5z27fQaYgOhX1UCmOpg2pFpoMvo6ZgQMzLsaTzzQNTlm7hNcb+Sg iat-mode=0',
      'obfs4 45.145.95.6:27015 C5B7CD6946FF10C5B3E89691A7D3F2C122D2117C cert=TD7PbUO0/0k6xYHMPW3vJxICfkMZNdkRrb63Zhl5j9dW3iRGiCx0A7mPhe5T2EDzQ35+Zw iat-mode=0',
      'obfs4 209.148.46.65:443 74FAD13168806246602538555B5521A0383A1875 cert=ssH+9rP8dG2NLDN2XuFw63hIO/9MNNinLmxQDpVa+7kTOa9/m+tGWT1SmSYpQ9uTBGa6Hw iat-mode=0',
      'obfs4 212.83.43.95:443 BFE712113A72899AD685764B211FACD30FF52C31 cert=ayq0XzCwhpdysn5o0EyDUbmSOx3X/oTEbzDMvczHOdBJKlvIdHHLJGkZARtT4dcBFArPPg iat-mode=1',
      'obfs4 212.83.43.74:443 39562501228A4D5E27FCA4C0C81A01EE23AE3EE4 cert=PBwr+S8JTVZo6MPdHnkTwXJPILWADLqfMGoVvhZClMq/Urndyd42BwX9YFJHZnBB3H0XCw iat-mode=1',
    ],
    'meek_lite': [
      'meek_lite 192.0.2.20:80 url=https://1603026938.rsc.cdn77.org front=www.phpmyadmin.net utls=HelloRandomizedALPN',
    ],
    'snowflake': [
      'snowflake 192.0.2.3:80 2B280B23E1107BB62ABFC40DDCC8824814F80A72 url=https://1098762253.rsc.cdn77.org/ '
          'front=www.cdn77.com ice=stun:stun.antisip.com:3478,stun:stun.epygi.com:3478,stun:stun.uls.co.za:3478,'
          'stun:stun.voipgate.com:3478,stun:stun.mixvoip.com:3478,stun:stun.nextcloud.com:3478,'
          'stun:stun.bethesda.net:3478,stun:stun.nextcloud.com:443,stun:stun.sipgate.net:3478,'
          'stun:stun.sipgate.net:10000,stun:stun.sonetel.com:3478,stun:stun.voipia.net:3478 '
          'utls-imitate=hellorandomizedalpn',
    ],
  };

  /// torrc string value: quoted, forward slashes (paths may contain spaces).
  static String _q(String path) => '"${path.replaceAll('\\', '/').replaceAll('"', '\\"')}"';

  Future<int?> _startTor(bool Function() isCancelled, void Function(String)? onPhase) async {
    final torDir = '$appDir\\tor';
    final lyrebird = '$torDir\\lyrebird.exe';
    final hasPt = File(lyrebird).existsSync();
    final dataPath = Directory('${dataDir.path}\\tor')..createSync(recursive: true);
    for (final (i, rung) in _rungs.indexed) {
      if (isCancelled()) return null;
      final bridged = rung.transport.isNotEmpty;
      if (bridged && !hasPt) break;
      final port = await SingboxCore.freePort();
      final torrc = StringBuffer()
        ..writeln('SocksPort 127.0.0.1:$port')
        ..writeln('DataDirectory ${_q(dataPath.path)}')
        ..writeln('ClientOnly 1')
        ..writeln('AvoidDiskWrites 1')
        ..writeln('Log notice stdout')
        ..writeln('NumEntryGuards 1')
        ..writeln('LearnCircuitBuildTimeout 0')
        ..writeln('CircuitBuildTimeout ${rung.transport == 'meek_lite' || rung.transport == 'snowflake' ? 120 : 60}')
        ..writeln('KeepalivePeriod 30');
      if (File('$torDir\\geoip').existsSync()) torrc.writeln('GeoIPFile ${_q('$torDir\\geoip')}');
      if (File('$torDir\\geoip6').existsSync()) torrc.writeln('GeoIPv6File ${_q('$torDir\\geoip6')}');
      if (bridged) {
        // ClientTransportPlugin is split on spaces, so a path with spaces cannot be used: then the bare name is
        // given and Windows finds lyrebird.exe next to tor.exe (the application directory is searched first).
        final exe = lyrebird.contains(' ') ? 'lyrebird.exe' : lyrebird.replaceAll('\\', '/');
        torrc
          ..writeln('UseBridges 1')
          ..writeln('ClientTransportPlugin meek_lite,obfs4,snowflake exec $exe');
        for (final line in _bridges[rung.transport]!) {
          torrc.writeln('Bridge $line');
        }
      }
      final torrcFile = File('${dataPath.path}\\torrc');
      await torrcFile.writeAsString(torrc.toString());
      final prefix = 'Tor (${rung.label}, ${i + 1}/${_rungs.length})';
      onPhase?.call('اتصال به شبکه‌ی $prefix…');
      AppLog.add('tor: trying ${rung.transport.isEmpty ? 'direct' : rung.transport}');
      final bootstrapped = RegExp(r'Bootstrapped (\d+)%');
      final ok = await _launch(torExe, ['-f', torrcFile.path], Duration(seconds: rung.seconds), 'tor', isCancelled, (line) {
        final m = bootstrapped.firstMatch(line);
        if (m != null) {
          final pct = int.parse(m.group(1)!);
          if (pct >= 100) return true;
          onPhase?.call('اتصال به شبکه‌ی $prefix… $pct٪');
        } else if (line.contains('[err]') || line.contains('[warn]')) {
          AppLog.add('tor: $line');
        }
        return null;
      });
      if (ok) return port;
    }
    return null;
  }

  // ---------------------------------------------------------------- process

  /// Runs [exe] until [judge] returns true (ready) or false (failed), the process exits, [limit] passes or
  /// [isCancelled]. Output keeps being read afterwards so the process never blocks on a full pipe.
  Future<bool> _launch(String exe, List<String> args, Duration limit, String label, bool Function() isCancelled,
      bool? Function(String line) judge) async {
    final Process proc;
    try {
      // detachedWithStdio: no console window.
      proc = await Process.start(exe, args,
          workingDirectory: File(exe).parent.path, mode: ProcessStartMode.detachedWithStdio);
    } catch (e) {
      AppLog.add('$label: could not start: $e');
      return false;
    }
    _proc = proc;
    try {
      await (await SharedPreferences.getInstance()).setInt(_pidKey, proc.pid);
    } catch (_) {}

    final result = Completer<bool>();
    var closed = 0;
    void onLine(String line) {
      if (result.isCompleted) return;
      final verdict = judge(line);
      if (verdict != null) result.complete(verdict);
    }

    void onDone() {
      if (++closed == 2 && !result.isCompleted) {
        AppLog.add('$label: process exited');
        result.complete(false);
      }
    }

    for (final stream in [proc.stdout, proc.stderr]) {
      stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(onLine, onDone: onDone, onError: (Object _) {});
    }

    final deadline = DateTime.now().add(limit);
    while (!result.isCompleted) {
      if (isCancelled()) {
        result.complete(false);
      } else if (DateTime.now().isAfter(deadline)) {
        AppLog.add('$label: not ready after ${limit.inSeconds} s');
        result.complete(false);
      } else {
        await Future.any<Object?>([result.future, Future<Object?>.delayed(const Duration(milliseconds: 500))]);
      }
    }
    final ok = await result.future;
    if (!ok && identical(_proc, proc)) await stop();
    if (ok) AppLog.add('$label: ready');
    return ok;
  }
}
