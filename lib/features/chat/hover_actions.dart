import 'package:flutter/material.dart';

/// Desktop hover toolbar for a message bubble/row — quick-react emojis, an
/// optional Reply, and More (the full action menu). On touch devices
/// (Android/iOS) the pointer never hovers, so this stays hidden and long-press
/// is used instead. Shared by the channel and thread screens.
class HoverActions extends StatefulWidget {
  const HoverActions({
    super.key,
    required this.child,
    required this.isOwn,
    required this.emojis,
    required this.onReactEmoji,
    required this.onMore,
    this.onReply,
  });

  final Widget child;
  final bool isOwn;
  final List<String> emojis;
  final ValueChanged<String> onReactEmoji;
  final VoidCallback onMore;

  /// When null, the Reply button is hidden (e.g. inside a thread, where
  /// replying is just the composer).
  final VoidCallback? onReply;

  @override
  State<HoverActions> createState() => _HoverActionsState();
}

class _HoverActionsState extends State<HoverActions> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_hover)
            Positioned(
              // Float above the message, offset past the avatar gutter so the
              // full bar is always visible (never clipped by bubble/avatar).
              top: -12,
              left: widget.isOwn ? null : 36,
              right: widget.isOwn ? 36 : null,
              child: _toolbar(context),
            ),
        ],
      ),
    );
  }

  Widget _toolbar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 6,
                offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in widget.emojis.take(4))
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => widget.onReactEmoji(e),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: Text(e, style: const TextStyle(fontSize: 17)),
                ),
              ),
            Container(
                width: 1,
                height: 18,
                color: cs.outlineVariant,
                margin: const EdgeInsets.symmetric(horizontal: 4)),
            if (widget.onReply != null)
              _iconBtn(context, Icons.reply_rounded, 'Reply', widget.onReply!),
            _iconBtn(context, Icons.more_horiz, 'More', widget.onMore),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn(
      BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tip,
      iconSize: 18,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      icon: Icon(icon, color: cs.outline),
      onPressed: onTap,
    );
  }
}
