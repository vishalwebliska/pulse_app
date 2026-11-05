import 'package:flutter/material.dart';

/// A lightweight, dependency-free emoji picker. Reactions accept any emoji
/// string server-side, so this is purely a client convenience beyond the 6
/// quick-react emojis. Returns the chosen emoji, or null if dismissed.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _EmojiPickerSheet(),
  );
}

/// Curated common emojis grouped by section — enough for everyday reactions
/// without shipping a full Unicode table.
const Map<String, List<String>> _emojiGroups = {
  'Smileys': [
    '😀', '😁', '😂', '🤣', '😊', '😇', '🙂', '😉', '😍', '😘',
    '😜', '🤪', '🤗', '🤔', '🤨', '😐', '😴', '😎', '🥳', '😏',
    '😢', '😭', '😤', '😡', '🤯', '😳', '🥺', '😬', '🙄', '😲',
  ],
  'Gestures': [
    '👍', '👎', '👌', '🤌', '✌️', '🤞', '🤟', '🤙', '👏', '🙌',
    '🙏', '💪', '👀', '🫡', '🤝', '✍️', '👋', '🫶',
  ],
  'Hearts': [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💔', '❣️',
    '💯', '💕', '💖', '💗',
  ],
  'Objects': [
    '🎉', '🎊', '✅', '❌', '⭐', '🔥', '✨', '💡', '📌', '📣',
    '🚀', '🏆', '⚡', '🎯', '☕', '🍕', '🎁', '🔔', '⏰', '💰',
  ],
};

class _EmojiPickerSheet extends StatelessWidget {
  const _EmojiPickerSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: CustomScrollView(
          slivers: [
            for (final group in _emojiGroups.entries) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    group.key.toUpperCase(),
                    style: TextStyle(
                        color: cs.outline,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 52,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final e = group.value[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => Navigator.of(context).pop(e),
                        child: Center(
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      );
                    },
                    childCount: group.value.length,
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          ],
        ),
      ),
    );
  }
}
