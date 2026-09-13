import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/subscription.dart';
import 'style.dart';

/// Subscription link + QR code for iPhone (Hiddify) and other devices.
Future<void> showShareSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (_) => const _ShareSheet(),
  );
}

class _ShareSheet extends StatefulWidget {
  const _ShareSheet();

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(const ClipboardData(text: SubscriptionRepository.shareLink));
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          color: const Color(0xFF0B0B1A).withValues(alpha: 0.85),
          padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + MediaQuery.paddingOf(context).bottom),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 44, height: 5, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 18),
                const Text('اشتراک برای خانواده', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Palette.text)),
                const SizedBox(height: 6),
                const Text(
                  'آیفون: برنامه‌ی Hiddify را از App Store نصب کنید، سپس این QR را اسکن کنید یا لینک را کپی و در برنامه وارد کنید.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, height: 1.7, color: Palette.muted),
                ),
                const SizedBox(height: 20),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.85, end: 1),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (context, s, child) => Transform.scale(scale: s, child: child),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withValues(alpha: 0.45), blurRadius: 40)],
                    ),
                    child: QrImageView(data: SubscriptionRepository.shareLink, size: 210, backgroundColor: Colors.white),
                  ),
                ),
                const SizedBox(height: 18),
                const _Step(icon: Icons.apple_rounded, text: 'آیفون و آیپد: Hiddify یا Streisand'),
                const _Step(icon: Icons.android_rounded, text: 'اندروید بدون این برنامه: Hiddify یا v2rayNG'),
                const _Step(icon: Icons.add_link_rounded, text: 'در برنامه: + ← افزودن از کلیپ‌بورد / اسکن QR'),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _copy,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: _copied ? const Color(0xFF10B981) : const Color(0xFF7C3AED),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded),
                    label: Text(_copied ? 'کپی شد' : 'کپی لینک اشتراک', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFFA78BFA)),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, color: Palette.text))),
        ],
      ),
    );
  }
}
