import 'package:flutter/material.dart';

import 'style.dart';

/// Shared building blocks that follow the Android app's layout: canvas background, rounded 20 px cards,
/// section headers with an accent tick, and rows with title + subtitle + trailing control.

/// Max content width on desktop.
const double kContentWidth = 520;

/// A plain page: back button + title bar on the canvas, centered content column.
class PageShell extends StatelessWidget {
  const PageShell({super.key, required this.title, this.subtitle, this.actions = const [], required this.child});

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentWidth),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 4),
                child: Row(children: [
                  IconButton(
                    tooltip: 'بازگشت',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(Icons.arrow_forward_rounded, color: Palette.text),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(title, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Palette.text)),
                      if (subtitle != null) Text(subtitle!, style: TextStyle(fontSize: 12, color: Palette.muted)),
                    ]),
                  ),
                  ...actions,
                ]),
              ),
              Expanded(child: child),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Section caption with a small accent tick, like Android's OrbitSectionHeader.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 22, 6, 10),
      child: Row(children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(
            color: Palette.accent,
            borderRadius: BorderRadius.circular(2),
            boxShadow: [BoxShadow(color: Palette.accent.withValues(alpha: 0.5), blurRadius: 4)],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(child: Text(text, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Palette.muted))),
        ?trailing,
      ]),
    );
  }
}

/// Rounded surface card on the canvas.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.onTap, this.borderColor, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor, color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
      color: color ?? Palette.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: borderColor ?? Palette.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// A card holding several rows separated by hairlines.
class CardGroup extends StatelessWidget {
  const CardGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) Divider(height: 1, thickness: 1, indent: 16, endIndent: 16, color: Palette.border),
          child,
        ],
      ]),
    );
  }
}

/// The one row shape used everywhere: optional icon, title, optional subtitle, trailing widget,
/// and optional content below (chips).
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.below,
    this.danger = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing, below;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? Palette.failure : Palette.text;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 13, 14, 13),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: danger ? Palette.failure : Palette.accent),
              const SizedBox(width: 13),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: color)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: TextStyle(fontSize: 12.5, height: 1.5, color: Palette.muted)),
                  ),
              ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
          if (below != null)
            Padding(padding: EdgeInsetsDirectional.only(start: icon == null ? 0 : 33, top: 10), child: below),
        ]),
      ),
    );
  }
}

class SwitchSettingRow extends StatelessWidget {
  const SwitchSettingRow({super.key, this.icon, required this.title, this.subtitle, required this.value, required this.onChanged});

  final IconData? icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: Palette.accent),
      );
}

/// Title with a dimmer value and a chevron (Android's navRow).
class NavSettingRow extends StatelessWidget {
  const NavSettingRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onTap,
    this.busy = false,
    this.danger = false,
    this.ltrValue = false,
  });

  final IconData? icon;
  final String title;
  final String? subtitle, value;
  final VoidCallback? onTap;
  final bool busy, danger, ltrValue;

  @override
  Widget build(BuildContext context) => SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        danger: danger,
        onTap: busy ? null : onTap,
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: ltrValue ? TextDirection.ltr : null,
                  style: TextStyle(fontSize: 13.5, color: Palette.muted)),
            ),
          if (busy)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Palette.accent)),
            )
          else if (onTap != null)
            Icon(Icons.chevron_left_rounded, color: Palette.muted),
        ]),
      );
}

/// Row with a set of mutually exclusive chips below.
class ChoiceSettingRow<T> extends StatelessWidget {
  const ChoiceSettingRow({super.key, this.icon, required this.title, this.subtitle, required this.options, required this.value, required this.onChanged});

  final IconData? icon;
  final String title;
  final String? subtitle;
  final Map<T, String> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SettingRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        below: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in options.entries) AppChip(label: e.value, selected: e.key == value, onTap: () => onChanged(e.key)),
        ]),
      );
}

/// Small pill chip in the accent palette.
class AppChip extends StatelessWidget {
  const AppChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Palette.accent.withValues(alpha: 0.16) : Palette.raised,
      shape: StadiumBorder(side: BorderSide(color: selected ? Palette.accent : Palette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Palette.accent : Palette.text,
              )),
        ),
      ),
    );
  }
}

/// Status chip: a glowing LED plus a short label.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.glow = true});

  final String label;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: glow ? color : color.withValues(alpha: 0.5),
            boxShadow: glow ? [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 6)] : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }
}

/// Latency pill colored with [Palette.forDelay]; null = not tested, <= 0 = failed.
class DelayPill extends StatelessWidget {
  const DelayPill({super.key, required this.ms});

  final int? ms;

  @override
  Widget build(BuildContext context) {
    final d = ms;
    final text = d == null ? '—' : (d <= 0 ? 'قطع' : '$d ms');
    final color = d == null ? Palette.muted : (d <= 0 ? Palette.failure : Palette.forDelay(d));
    return Container(
      constraints: const BoxConstraints(minWidth: 58),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
      child: Text(text, textDirection: TextDirection.ltr, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}

/// Small protocol tag.
class ProtocolTag extends StatelessWidget {
  const ProtocolTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(6), border: Border.all(color: Palette.border)),
        child: Text(label, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Palette.muted)),
      );
}
