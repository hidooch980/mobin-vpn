import 'dart:convert';
import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  const UpdateInfo({required this.version, required this.url, required this.assetName, required this.size});

  final String version, url, assetName;
  final int size;
}

/// In-app updates from this repo's latest GitHub Release.
class Updater {
  static const _latestRelease = 'https://api.github.com/repos/hidooch980/mobin-vpn/releases/latest';

  static String get _assetName => Platform.isWindows ? 'MobinVPN-windows-x64.zip' : 'MobinVPN-android-universal.apk';

  HttpClient _client(String? proxy) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    if (proxy != null) client.findProxy = (_) => 'PROXY $proxy';
    return client;
  }

  /// Returns the newer release, or null when already up to date.
  Future<UpdateInfo?> check({String? proxy}) async {
    final installed = (await PackageInfo.fromPlatform()).version;
    final client = _client(proxy);
    try {
      final req = await client.getUrl(Uri.parse(_latestRelease));
      req.headers
        ..set(HttpHeaders.userAgentHeader, 'MobinVPN/$installed')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      final res = await req.close().timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final latest = '${json['tag_name']}'.replaceFirst(RegExp('^v'), '');
      if (!isNewer(latest, installed)) return null;
      final asset = (json['assets'] as List).cast<Map<String, dynamic>>().where((a) => a['name'] == _assetName).firstOrNull;
      if (asset == null) return null;
      return UpdateInfo(
        version: latest,
        url: asset['browser_download_url'] as String,
        assetName: _assetName,
        size: (asset['size'] as num).toInt(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static bool isNewer(String candidate, String installed) {
    List<int> parts(String v) => v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final a = parts(candidate), b = parts(installed);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  Future<File> download(UpdateInfo update, {String? proxy, required void Function(double progress) onProgress}) async {
    final file = File('${(await getTemporaryDirectory()).path}${Platform.pathSeparator}${update.assetName}');
    final client = _client(proxy);
    try {
      final res = await (await client.getUrl(Uri.parse(update.url))).close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final total = res.contentLength > 0 ? res.contentLength : update.size;
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in res.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
      } finally {
        await sink.close();
      }
      if (update.size > 0 && received != update.size) throw const FileSystemException('download incomplete');
      return file;
    } finally {
      client.close(force: true);
    }
  }

  /// Android: opens the system installer. Windows: a detached script swaps the files once this process exits,
  /// then relaunches the app — the caller must exit right after.
  Future<void> install(File file) async {
    if (Platform.isAndroid) {
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done) throw Exception(result.message);
      return;
    }
    final exe = Platform.resolvedExecutable;
    final dir = File(exe).parent.path;
    String q(String s) => "'${s.replaceAll("'", "''")}'";
    final script = File('${file.parent.path}\\mobin_update.ps1');
    await script.writeAsString('''
while (Get-Process -Id $pid -ErrorAction SilentlyContinue) { Start-Sleep -Milliseconds 300 }
Get-Process sing-box -ErrorAction SilentlyContinue | Where-Object { \$_.Path -like ${q('$dir\\*')} } | Stop-Process -Force
Start-Sleep -Milliseconds 500
Expand-Archive -LiteralPath ${q(file.path)} -DestinationPath ${q(dir)} -Force
Start-Process -FilePath ${q(exe)}
''');
    await Process.start(
      'powershell',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', script.path],
      mode: ProcessStartMode.detached,
    );
  }
}
