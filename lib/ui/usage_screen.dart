import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/engine.dart';
import '../core/usage_stats.dart';
import '../core/vpn_controller.dart';
import 'aurora_background.dart';
import 'glass.dart';
import 'strings.dart';
import 'style.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

List<String> get _weekdays => L10n.en
    ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    : const ['دوشنبه', 'سه‌شنبه', 'چهارشنبه', 'پنجشنبه', 'جمعه', 'شنبه', 'یکشنبه'];

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
                          child: Icon(backIcon, color: Palette.text),
                        ),
                        const SizedBox(width: 14),
                        Text(tr('آمار مصرف', 'Usage'), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Palette.text)),
                      ]),
                      const SizedBox(height: 18),
                      Row(children: [
                        Expanded(child: _TotalCard(title: tr('امروز', 'Today'), usage: today, color: Palette.connected)),
                        const SizedBox(width: 12),
                        Expanded(child: _TotalCard(title: tr('این ماه', 'This month'), usage: month, color: Palette.accent)),
                      ]),
                      const SizedBox(height: 14),
                      Glass(
                        radius: 24,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('۷ روز اخیر', 'Last 7 days'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Palette.text)),
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
                          icon: Icon(Icons.delete_sweep_rounded, color: Palette.danger),
                          label: Text(tr('پاک کردن آمار', 'Clear statistics'), style: TextStyle(color: Palette.danger)),
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
                            ? [Palette.connected, Palette.accent]
                            : [Palette.accent.withValues(alpha: 0.35), Palette.accent.withValues(alpha: 0.6)],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(isToday ? tr('امروز', 'Today') : _weekdays[date.weekday - 1],
              style: TextStyle(fontSize: 10.5, color: isToday ? Palette.text : Palette.muted)),
        ],
      ),
    );
  }
}
