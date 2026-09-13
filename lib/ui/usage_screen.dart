import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/usage_stats.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'style.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

const _weekdays = ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

class UsageScreen extends StatelessWidget {
  const UsageScreen({super.key, required this.controller});

  final VpnController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuroraBackground(
        colors: Palette.forState(VpnState.connected),
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final usage = controller.usage;
              final now = DateTime.now();
              final today = usage.day(now), month = usage.month(now);
              final week = usage.lastDays(7);
              final peak = week.map((e) => e.$2.total).fold(1, math.max);
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
                        Text('آمار مصرف', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Palette.text)),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: _TotalCard(title: 'امروز', usage: today, color: const Color(0xFF34D399))),
                        const SizedBox(width: 12),
                        Expanded(child: _TotalCard(title: 'این ماه', usage: month, color: const Color(0xFF60A5FA))),
                      ]),
                      const SizedBox(height: 14),
                      Glass(
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('۷ روز اخیر', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.text)),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 180,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (final (i, (date, u)) in week.indexed)
                                    Expanded(child: _Bar(date: date, usage: u, fraction: u.total / peak, index: i, isToday: i == week.length - 1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: TextButton.icon(
                          onPressed: () async {
                            await usage.reset();
                            controller.clearError();
                          },
                          icon: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFF87171)),
                          label: const Text('پاک کردن آمار', style: TextStyle(color: Color(0xFFF87171))),
                        ),
                      ),
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

class _TotalCard extends StatelessWidget {
  const _TotalCard({required this.title, required this.usage, required this.color});

  final String title;
  final Usage usage;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: Palette.muted)),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: usage.total.toDouble()),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => Text(formatBytes(v.round()),
                textDirection: TextDirection.ltr,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.south_rounded, size: 14, color: Palette.muted),
            Text(formatBytes(usage.down), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: Palette.muted)),
            const SizedBox(width: 10),
            Icon(Icons.north_rounded, size: 14, color: Palette.muted),
            Text(formatBytes(usage.up), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: Palette.muted)),
          ]),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.date, required this.usage, required this.fraction, required this.index, required this.isToday});

  final DateTime date;
  final Usage usage;
  final double fraction;
  final int index;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: formatBytes(usage.total),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: fraction.clamp(0.02, 1.0)),
                duration: Duration(milliseconds: 600 + index * 90),
                curve: Curves.easeOutBack,
                builder: (context, v, _) => FractionallySizedBox(
                  heightFactor: v.clamp(0.0, 1.0),
                  child: Container(
                    width: 22,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: isToday
                            ? const [Color(0xFF10B981), Color(0xFF22D3EE)]
                            : [const Color(0xFF7C3AED).withValues(alpha: 0.7), const Color(0xFF3B82F6).withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(isToday ? 'امروز' : _weekdays[date.weekday - 1],
              style: TextStyle(fontSize: 10.5, color: isToday ? Palette.text : Palette.muted)),
        ],
      ),
    );
  }
}
