import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/engine.dart';
import '../core/server.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

/// "My configs": add share links by pasting or scanning a QR code; they appear as their own location.
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key, required this.controller});

  final VpnController controller;

  void _toast(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));

  Future<void> _add(BuildContext context, String? text) async {
    if (text == null || text.trim().isEmpty) return;
    final added = await controller.addManualConfigs(text);
    if (context.mounted) {
      _toast(context, added == 0 ? 'کانفیگ معتبری پیدا نشد' : '$added کانفیگ اضافه شد');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.disconnected),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final mine = controller.servers.where((s) => s.countryCode == VpnController.manualCode).toList();
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      Row(children: [
                        Glass(
                          radius: 16,
                          padding: const EdgeInsets.all(10),
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(Icons.arrow_forward_rounded, color: Palette.text),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('کانفیگ‌های من', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
                            Text('VLESS، VMess، Trojan، SS، Hysteria2، TUIC، AnyTLS، WireGuard، SOCKS، HTTP',
                                style: TextStyle(fontSize: 11.5, color: Palette.muted)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(
                          child: _BigButton(
                            icon: Icons.content_paste_rounded,
                            label: 'چسباندن از کلیپ‌بورد',
                            colors: const [Color(0xFF7C3AED), Color(0xFF2563EB)],
                            onTap: () async {
                              final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
                              if (context.mounted) await _add(context, text);
                            },
                          ),
                        ),
                        if (Platform.isAndroid) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            child: _BigButton(
                              icon: Icons.qr_code_scanner_rounded,
                              label: 'اسکن QR',
                              colors: const [Color(0xFF10B981), Color(0xFF06B6D4)],
                              onTap: () async {
                                final value = await Navigator.of(context)
                                    .push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));
                                if (context.mounted) await _add(context, value);
                              },
                            ),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 10),
                      Text(
                        'لینک اشتراک (subscription) هم پشتیبانی می‌شود: متن base64 یا چند لینک در چند خط را بچسبانید.',
                        style: TextStyle(fontSize: 12, color: Palette.muted, height: 1.6),
                      ),
                      const SizedBox(height: 18),
                      if (mine.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('هنوز کانفیگی اضافه نکرده‌اید', style: TextStyle(color: Palette.muted))),
                        ),
                      for (final s in mine) _ConfigTile(server: s, controller: controller),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.icon, required this.label, required this.colors, required this.onTap});

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.first.withValues(alpha: 0.4), blurRadius: 24)],
          ),
          child: Column(children: [
            Icon(icon, color: Colors.white, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({required this.server, required this.controller});

  final Server server;
  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(server.uri)?.host ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Glass(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        onTap: () {
          Navigator.of(context).popUntil((r) => r.isFirst);
          controller.connectTo(server);
        },
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Palette.fill, borderRadius: BorderRadius.circular(8)),
            child: Text(server.protocolLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Palette.accent)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(server.remark.isEmpty ? 'بدون نام' : server.remark,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Palette.text, fontWeight: FontWeight.w700)),
              if (host.isNotEmpty)
                Text(host, maxLines: 1, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: Palette.muted)),
            ]),
          ),
          IconButton(
            tooltip: 'حذف',
            onPressed: () => controller.removeManualConfig(server.uri),
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFF87171)),
          ),
        ]),
      ),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text('اسکن QR کانفیگ')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
            if (value == null || _done) return;
            _done = true;
            Navigator.of(context).pop(value);
          },
        ),
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF34D399), width: 3),
              borderRadius: BorderRadius.circular(28),
            ),
          ),
        ),
      ]),
    );
  }
}
