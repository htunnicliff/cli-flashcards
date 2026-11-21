/// Shared controls in the Frost style: buttons, keycaps, chips, command lines.
library;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../core/review_format.dart';
import 'theme.dart';

enum ButtonVariant { neutral, primary, again }

/// Whether this device has a keyboard worth advertising shortcuts for.
bool get showsKeyHints =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows ||
    defaultTargetPlatform == TargetPlatform.linux;

class FrostButton extends StatelessWidget {
  const FrostButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.variant = ButtonVariant.neutral,
    this.block = false,
    this.focusNode,
    this.autofocus = false,
    this.semanticsLabel,
    this.highlighted = false,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final ButtonVariant variant;
  final bool block;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticsLabel;

  /// A ring that marks the suggested choice.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final (fg, bg, border) = switch (variant) {
      ButtonVariant.primary => (f.onPrimary, null, Colors.transparent),
      ButtonVariant.again => (f.again, f.againTint, f.againBorder),
      ButtonVariant.neutral => (f.text, f.card, f.rim),
    };
    final disabled = onPressed == null;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.button),
      side: BorderSide(
        color: highlighted ? f.accent : border,
        width: highlighted ? 2 : 1,
      ),
    );
    Widget button = Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: ShapeDecoration(
          shape: shape,
          color: bg,
          gradient: variant == ButtonVariant.primary
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [f.primaryTop, f.primaryBottom],
                )
              : null,
          shadows: [
            if (variant == ButtonVariant.primary)
              BoxShadow(
                color: f.primaryShadow,
                blurRadius: 18,
                offset: const Offset(0, 6),
              )
            else
              BoxShadow(
                color: f.shadow.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: InkWell(
          onTap: onPressed,
          focusNode: focusNode,
          autofocus: autofocus,
          customBorder: shape,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.s4,
                vertical: Space.s2 + 2,
              ),
              child: DefaultTextStyle.merge(
                style: weight(
                  Theme.of(context).textTheme.labelLarge!.copyWith(color: fg),
                  FontWeight.w600,
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: fg, size: 18),
                  child: Row(
                    mainAxisSize: block ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [Flexible(child: child)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (semanticsLabel != null) {
      button = Semantics(
        label: semanticsLabel,
        button: true,
        excludeSemantics: true,
        child: button,
      );
    }
    return Opacity(opacity: disabled ? 0.5 : 1, child: button);
  }
}

/// A keycap, shown only where there is a keyboard.
class Kbd extends StatelessWidget {
  const Kbd(this.label, {super.key, this.onPrimary = false});
  final String label;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    if (!showsKeyHints) return const SizedBox.shrink();
    final f = Frost.of(context);
    return ExcludeSemantics(
      child: Container(
        margin: const EdgeInsets.only(left: Space.s2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: onPrimary ? Colors.white.withValues(alpha: 0.14) : f.kbd,
          borderRadius: BorderRadius.circular(Radii.kbd),
          border: Border.all(color: onPrimary ? Colors.transparent : f.border),
        ),
        child: Text(
          label,
          style: context.mono.copyWith(
            fontSize: TextSizes.xs,
            color: onPrimary ? f.onPrimary : f.muted,
          ),
        ),
      ),
    );
  }
}

class FrostChip extends StatelessWidget {
  const FrostChip(this.label, {super.key, this.mono = false, this.color});
  final String label;
  final bool mono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final base = mono ? context.mono : Theme.of(context).textTheme.labelSmall!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.s2, vertical: 2),
      decoration: BoxDecoration(
        color: f.sunken,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Text(
        label,
        style: base.copyWith(fontSize: TextSizes.xs, color: color ?? f.muted),
      ),
    );
  }
}

/// A command with the tool, flags, arguments and a cloze blank styled apart.
class CommandLine extends StatelessWidget {
  const CommandLine(this.parts, {super.key, this.large = false});
  final List<Part> parts;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    final style = context.mono.copyWith(
      fontSize: large ? TextSizes.lg : TextSizes.sm,
    );
    final spans = <InlineSpan>[
      TextSpan(
        text: r'$ ',
        style: style.copyWith(color: f.muted),
      ),
    ];
    for (final (i, part) in parts.indexed) {
      if (i > 0) spans.add(const TextSpan(text: ' '));
      switch (part.kind) {
        case PartKind.tool:
          spans.add(TextSpan(text: part.text));
        case PartKind.flag:
          spans.add(
            TextSpan(
              text: part.text,
              style: weight(style.copyWith(color: f.accent), FontWeight.w600),
            ),
          );
        case PartKind.arg:
          spans.add(
            TextSpan(
              text: part.text,
              style: context.monoCasual.copyWith(fontSize: style.fontSize),
            ),
          );
        case PartKind.blank:
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Semantics(
                label: 'blank',
                child: Container(
                  width: 56,
                  height: (style.fontSize ?? 15) * 1.3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: f.accent, width: 2),
                    ),
                    color: f.accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
          );
          if (part.text.isNotEmpty) spans.add(TextSpan(text: part.text));
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.s4,
        vertical: Space.s3,
      ),
      decoration: BoxDecoration(
        color: f.sunken,
        borderRadius: BorderRadius.circular(Radii.code),
      ),
      child: Text.rich(TextSpan(style: style, children: spans)),
    );
  }
}

/// A row of mutually exclusive choices.
class Segmented<T> extends StatelessWidget {
  const Segmented({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) label;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final f = Frost.of(context);
    return Container(
      padding: const EdgeInsets.all(Space.s1),
      decoration: BoxDecoration(
        color: f.sunken,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Wrap(
        spacing: Space.s1,
        children: [
          for (final v in values)
            Semantics(
              selected: v == selected,
              inMutuallyExclusiveGroup: true,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.pill),
                onTap: onChanged == null ? null : () => onChanged!(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.s4,
                    vertical: Space.s2,
                  ),
                  decoration: BoxDecoration(
                    color: v == selected ? f.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    boxShadow: v == selected
                        ? [
                            BoxShadow(
                              color: f.shadow.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label(v),
                    style: weight(
                      Theme.of(context).textTheme.labelMedium!
                          .copyWith(color: v == selected ? f.text : f.muted),
                      v == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A labelled checkbox with an optional hint underneath.
class CheckRow extends StatelessWidget {
  const CheckRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.strong = false,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? hint;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium!;
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.small),
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: onChanged == null ? null : (v) => onChanged!(v!),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: strong ? weight(style, FontWeight.w600) : style,
                      ),
                      if (hint != null)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.s1),
                          child: DefaultTextStyle.merge(
                            style: context.hint,
                            child: hint!,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A page's content column: centred, at most [contentWidth] wide.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.controller});
  final List<Widget> children;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final bottom = MediaQuery.paddingOf(context).bottom;
    // Transparent Material so ink and list tiles in pages have a surface.
    return Material(
      type: MaterialType.transparency,
      child: _list(narrow, bottom),
    );
  }

  Widget _list(bool narrow, double bottom) {
    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        narrow ? Space.s4 : Space.s6,
        narrow ? Space.s4 : Space.s10,
        narrow ? Space.s4 : Space.s6,
        (narrow ? 96 : Space.s12) + bottom,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: contentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// A section heading followed by its content.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Space.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const SizedBox(height: Space.s3),
          ...children,
        ],
      ),
    );
  }
}

String listOf(List<String> names) => names.length > 1
    ? '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}'
    : names.isEmpty
    ? ''
    : names.single;
