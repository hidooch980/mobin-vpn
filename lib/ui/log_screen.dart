import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/app_log.dart';
import '../core/engine.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

/// Diagnostic report the user can copy and send when something does not work.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  Future<String> _report() async {
    final info = await PackageInfo.fromPlatform();
    final c = widget.controller;
    final s = c.settings;
    return [
      'MolidoVPN ${info.version} (${info.buildNumber})',
      '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'state=${c.state.name} servers=${c.servers.length} locations=${c.countries.length} mode=${c.selectedCountry ?? 'auto'}',
      'fragment=${s.fragment} warp=${s.warp} bypassIran=${s.bypassIran} tun=${s.tunMode} proxyOnly=${s.proxyOnly} '
          'pool=${s.poolSize} timeout=${s.timeoutSeconds}s testUrl=${s.testUrl}',
      'last error: ${c.error ?? '-'}',
      '----',
      AppLog.dump(),
    ].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: FutureBuilder<String>(
            future: _report(),
            builder: (context, snap) {
              final text = snap.data ?? '';
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Row(children: [
                      Glass(
                        radius: 16,
                        padding: const EdgeInsets.all(10),
                        onTap: () => Navigator.of(context).pop(),
                        child: Icon(Icons.arrow_forward_rounded, color: Palette.text),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('گزارش خطا', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
                      ),
                      IconButton(
                        tooltip: 'پاک کردن',
                        onPressed: () => setState(AppLog.clear),
                        icon: Icon(Icons.delete_sweep_rounded, color: Palette.muted),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Glass(
                        radius: 20,
                        padding: const EdgeInsets.all(12),
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            text,
                            textDirection: TextDirection.ltr,
                            style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.5, color: Palette.text),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: text.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(ClipboardData(text: text));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('گزارش کپی شد؛ آن را در پیام‌رسان برای پشتیبان بفرستید'),
                                  behavior: SnackBarBehavior.floating,
                                ));
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF7C3AED),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                        ),
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('کپی گزارش', style: TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
