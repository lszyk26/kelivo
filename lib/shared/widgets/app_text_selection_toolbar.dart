import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/providers/settings_provider.dart';
import 'ios_text_selection_toolbar.dart';

/// Platform selection menus whose desktop labels use the application font.
class AppTextSelectionToolbar extends StatelessWidget {
  const AppTextSelectionToolbar({
    super.key,
    required this.anchors,
    required this.buttonItems,
    required this.selectionContext,
    required this.onDismiss,
    this.separatorsBefore = const {},
    this.shortcuts = const {},
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;
  final BuildContext selectionContext;
  final VoidCallback onDismiss;
  final Set<ContextMenuButtonItem> separatorsBefore;
  final Map<ContextMenuButtonItem, String> shortcuts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final platform = theme.platform;
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        context.select<SettingsProvider?, bool>(
          (settings) => settings?.iosNativeSelectionMenuEnabled ?? true,
        )) {
      return IosTextSelectionToolbar(
        anchors: anchors,
        buttonItems: buttonItems,
        selectionContext: selectionContext,
        onDismiss: onDismiss,
      );
    }
    if (platform != TargetPlatform.macOS &&
        platform != TargetPlatform.windows &&
        platform != TargetPlatform.linux) {
      return _BoundedSelectionToolbar(
        anchors: anchors,
        buttonItems: buttonItems,
        selectionContext: selectionContext,
        onDismiss: onDismiss,
      );
    }

    // Flutter's desktop labels set inherit: false, bypassing the app font.
    // Keep their sizing while explicitly carrying over the theme's fonts.
    final appStyle = theme.textTheme.bodyMedium;
    final style = TextStyle(
      inherit: false,
      fontFamily: appStyle?.fontFamily,
      fontFamilyFallback: appStyle?.fontFamilyFallback,
      fontSize: 14,
      letterSpacing: -0.15,
      fontWeight: FontWeight.w400,
    );
    return AdaptiveTextSelectionToolbar(
      anchors: anchors,
      children: [
        for (final item in buttonItems) ...[
          if (separatorsBefore.contains(item))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Container(
                height: 1,
                color: platform == TargetPlatform.macOS
                    ? CupertinoColors.separator.resolveFrom(context)
                    : theme.dividerColor,
              ),
            ),
          if (platform == TargetPlatform.macOS)
            _MacSelectionButton(
              item: item,
              style: style,
              shortcut: shortcuts[item],
            )
          else
            DesktopTextSelectionToolbarButton(
              onPressed: item.onPressed,
              child: _SelectionButtonLabel(
                item: item,
                shortcut: shortcuts[item],
                style: style.copyWith(
                  color: theme.brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black87,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _MacSelectionButton extends StatefulWidget {
  const _MacSelectionButton({
    required this.item,
    required this.style,
    this.shortcut,
  });

  final ContextMenuButtonItem item;
  final TextStyle style;
  final String? shortcut;

  @override
  State<_MacSelectionButton> createState() => _MacSelectionButtonState();
}

class _MacSelectionButtonState extends State<_MacSelectionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CupertinoDesktopTextSelectionToolbarButton(
        onPressed: widget.item.onPressed,
        child: _SelectionButtonLabel(
          item: widget.item,
          shortcut: widget.shortcut,
          style: widget.style.copyWith(
            color: _hovered
                ? CupertinoTheme.of(context).primaryContrastingColor
                : CupertinoDynamicColor.resolve(
                    const CupertinoDynamicColor.withBrightness(
                      color: CupertinoColors.black,
                      darkColor: CupertinoColors.white,
                    ),
                    context,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SelectionButtonLabel extends StatelessWidget {
  const _SelectionButtonLabel({
    required this.item,
    required this.style,
    this.shortcut,
  });
  final ContextMenuButtonItem item;
  final TextStyle style;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    if (shortcut == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        Text(shortcut!, style: style.copyWith(fontSize: 12)),
      ],
    );
  }
}

/// Mobile selection toolbar that keeps the primary editing actions inline and
/// moves everything else into a bounded popup.
///
/// Flutter's built-in overflow menu lays its items out without width/height
/// constraints on some Android devices, where it stretches into a full-height
/// column that covers the composer and the chat above it (see #1329).
class _BoundedSelectionToolbar extends StatelessWidget {
  const _BoundedSelectionToolbar({
    required this.anchors,
    required this.buttonItems,
    required this.selectionContext,
    required this.onDismiss,
  });

  final TextSelectionToolbarAnchors anchors;
  final List<ContextMenuButtonItem> buttonItems;
  final BuildContext selectionContext;
  final VoidCallback onDismiss;

  /// Roughly the room a single inline button needs besides its label.
  static const _buttonOverhead = 36.0;

  /// Room kept free for the trailing overflow button.
  static const _overflowSlot = 52.0;

  @override
  Widget build(BuildContext context) {
    // Keep the actions inline while they still fit on one row; only spill the
    // tail into the bounded popup when the row would be wider than the screen.
    if (buttonItems.length < 2) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: buttonItems,
      );
    }
    final l10n = MaterialLocalizations.of(context);
    final available = MediaQuery.sizeOf(context).width - 32;
    final inline = <ContextMenuButtonItem>[];
    final overflow = <ContextMenuButtonItem>[];
    var used = 0.0;
    for (final item in buttonItems) {
      final width =
          _measureLabelWidth(context, _labelOf(item, l10n)) + _buttonOverhead;
      if (overflow.isEmpty &&
          (inline.isEmpty || used + width + _overflowSlot <= available)) {
        inline.add(item);
        used += width;
      } else {
        overflow.add(item);
      }
    }
    if (overflow.isEmpty) {
      return AdaptiveTextSelectionToolbar.buttonItems(
        anchors: anchors,
        buttonItems: inline,
      );
    }
    return AdaptiveTextSelectionToolbar(
      anchors: anchors,
      children: [
        for (final item in inline)
          TextSelectionToolbarTextButton(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            onPressed: item.onPressed,
            child: Text(_labelOf(item, l10n)),
          ),
        _BoundedOverflowButton(
          items: overflow,
          anchors: anchors,
          selectionContext: selectionContext,
          onDismiss: onDismiss,
        ),
      ],
    );
  }
}

String _labelOf(ContextMenuButtonItem item, MaterialLocalizations l10n) =>
    item.label ?? _defaultSelectionLabel(item.type, l10n);

double _measureLabelWidth(BuildContext context, String label) {
  if (label.isEmpty) return 0;
  final painter = TextPainter(
    text: TextSpan(text: label, style: DefaultTextStyle.of(context).style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final width = painter.size.width;
  painter.dispose();
  return width;
}

String _defaultSelectionLabel(
  ContextMenuButtonType type,
  MaterialLocalizations l10n,
) {
  if (type == ContextMenuButtonType.cut) return l10n.cutButtonLabel;
  if (type == ContextMenuButtonType.copy) return l10n.copyButtonLabel;
  if (type == ContextMenuButtonType.paste) return l10n.pasteButtonLabel;
  if (type == ContextMenuButtonType.selectAll) return l10n.selectAllButtonLabel;
  return '';
}

class _BoundedOverflowButton extends StatelessWidget {
  const _BoundedOverflowButton({
    required this.items,
    required this.anchors,
    required this.selectionContext,
    required this.onDismiss,
  });

  final List<ContextMenuButtonItem> items;
  final TextSelectionToolbarAnchors anchors;
  final BuildContext selectionContext;
  final VoidCallback onDismiss;

  Future<void> _showOverflowMenu(BuildContext context) async {
    final l10n = MaterialLocalizations.of(context);
    final overlay = Overlay.maybeOf(selectionContext);
    final overlayBox = overlay?.context.findRenderObject();
    final size = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.size
        : MediaQuery.sizeOf(selectionContext);
    final anchor = anchors.primaryAnchor;
    final dx = anchor.dx.clamp(8.0, size.width - 8);
    final dy = anchor.dy.clamp(8.0, size.height - 8);
    final selected = await showMenu<ContextMenuButtonItem>(
      context: selectionContext,
      position: RelativeRect.fromLTRB(
        dx,
        dy,
        (size.width - dx).clamp(0.0, size.width),
        (size.height - dy).clamp(0.0, size.height),
      ),
      constraints: const BoxConstraints(
        minWidth: 168,
        maxWidth: 248,
        maxHeight: 300,
      ),
      items: [
        for (final item in items)
          PopupMenuItem<ContextMenuButtonItem>(
            value: item,
            height: 42,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                item.label ?? _defaultSelectionLabel(item.type, l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
    );
    onDismiss();
    if (selected?.onPressed != null) {
      selected!.onPressed!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextSelectionToolbarTextButton(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      onPressed: () => unawaited(_showOverflowMenu(context)),
      child: const Icon(Icons.more_vert, size: 18),
    );
  }
}
