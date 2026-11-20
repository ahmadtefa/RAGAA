// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Shared responsive toolkit.
///
/// Every screen uses these helpers so the phone layout never keeps a desktop
/// horizontal row that squeezes Arabic text into vertical letters. Text always
/// stays horizontal, actions move under the data when a row no longer fits,
/// and numbers are never clipped.

/// Phone-width breakpoint (a single column, stacked rows).
const double kCompactMaxWidth = 600;

/// Tablet / desktop breakpoint (side-by-side layouts are safe from here).
const double kExpandedMinWidth = 900;

/// Width from which the shell switches to the desktop rail layout and keeps a
/// floating action button beside the content.
const double kDesktopLayoutMinWidth = 860;

/// True when the current screen is phone-sized.
bool isCompactWidth(
  BuildContext context, {
  double breakpoint = kCompactMaxWidth,
}) =>
    MediaQuery.sizeOf(context).width < breakpoint;

/// True when the screen is wide enough for desktop-style rows.
bool isExpandedWidth(
  BuildContext context, {
  double breakpoint = kExpandedMinWidth,
}) =>
    MediaQuery.sizeOf(context).width >= breakpoint;

/// Screen padding that shrinks on phones and always reserves room under the
/// last row so a floating action button can never cover the data.
EdgeInsets responsivePagePadding(
  BuildContext context, {
  bool withFabInset = false,
  double fabInset = 104,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final gap = width < 400 ? 12.0 : (width < kCompactMaxWidth ? 16.0 : 20.0);
  // The floating button only exists in the desktop layout, so only that layout
  // reserves room under the content for it.
  final bottom =
      withFabInset && width >= kDesktopLayoutMinWidth ? fabInset : gap;
  return EdgeInsets.fromLTRB(gap, gap, gap, bottom);
}

/// Header block (title + description) followed by its actions.
///
/// Wide screens keep them on one line; narrow screens stack the actions below
/// the text so the title never gets squeezed.
class ResponsiveHeader extends StatelessWidget {
  final Widget title;
  final Widget actions;
  final double breakpoint;
  final double spacing;

  const ResponsiveHeader({
    super.key,
    required this.title,
    required this.actions,
    this.breakpoint = 700,
    this.spacing = 12,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              SizedBox(height: spacing),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: title),
            SizedBox(width: spacing),
            Flexible(child: actions),
          ],
        );
      },
    );
  }
}

/// Money / numeric text that always stays on one horizontal line and is never
/// clipped: it only shrinks when a single line genuinely cannot fit.
class AmountText extends StatelessWidget {
  final String text;
  final double fontSize;
  final Color? color;
  final FontWeight fontWeight;
  final TextAlign textAlign;

  const AmountText(
    this.text, {
    super.key,
    this.fontSize = 16,
    this.color,
    this.fontWeight = FontWeight.w700,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? const Color(0xFF0F172A),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      label: text,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          textAlign: textAlign,
          style: style,
        ),
      ),
    );
  }
}

/// Dropdown form of the period selector: always fits a phone width, keeps the
/// label on one horizontal line and never clips the selected value.
class PeriodDropdown<T> extends StatelessWidget {
  final T value;
  final List<PeriodOption<T>> options;
  final ValueChanged<T> onChanged;
  final String hint;

  const PeriodDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hint = 'الفترة',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: true,
          value: value,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.expand_more),
          hint: Text(hint),
          items: [
            for (final option in options)
              DropdownMenuItem<T>(
                value: option.value,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}

/// One selectable period option.
class PeriodOption<T> {
  final T value;
  final String label;

  const PeriodOption(this.value, this.label);
}

/// Period selector that degrades to a dropdown when the segmented buttons
/// cannot fit on one row (phones), and never overflows at large text scales.
class ResponsivePeriodSelector<T> extends StatelessWidget {
  final T value;
  final List<PeriodOption<T>> options;
  final ValueChanged<T> onChanged;
  final String dropdownLabel;
  final double breakpoint;

  const ResponsivePeriodSelector({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.dropdownLabel = 'الفترة',
    this.breakpoint = 520,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return PeriodDropdown<T>(
            value: value,
            options: options,
            onChanged: onChanged,
            hint: dropdownLabel,
          );
        }
        // Segments can still be wider than the screen at big text scales, so
        // keep them horizontally scrollable instead of overflowing.
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<T>(
            showSelectedIcon: false,
            segments: [
              for (final option in options)
                ButtonSegment<T>(
                  value: option.value,
                  label: Text(option.label),
                ),
            ],
            selected: {value},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) onChanged(selection.first);
            },
          ),
        );
      },
    );
  }
}

/// Full-width, comfortably tall tap target used in stacked phone layouts.
class ResponsiveActionRow extends StatelessWidget {
  final List<Widget> children;
  final double spacing;
  final WrapAlignment alignment;

  const ResponsiveActionRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        alignment: alignment,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
