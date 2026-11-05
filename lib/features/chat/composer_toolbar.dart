import 'package:flutter/material.dart';

/// A lightweight formatting toolbar for a message composer. Buttons wrap the
/// current selection (or a `text` placeholder) with Markdown, mirroring the
/// Pulse web composer: bold, italic, strikethrough, inline code, link, bullet
/// / numbered lists and blockquote. Messages are sent as Markdown (the backend
/// renders them), so this stays a plain `TextField` underneath.
class ComposerToolbar extends StatelessWidget {
  const ComposerToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  void _wrap(String left, String right) {
    final text = controller.text;
    final sel = controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    final selected = start != end ? text.substring(start, end) : '';
    final inner = selected.isEmpty ? 'text' : selected;
    final newText = text.replaceRange(start, end, '$left$inner$right');
    final innerStart = start + left.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
          baseOffset: innerStart, extentOffset: innerStart + inner.length),
    );
    focusNode.requestFocus();
  }

  void _prefixLine(String prefix) {
    final text = controller.text;
    final sel = controller.selection;
    final pos = sel.isValid ? sel.start : text.length;
    var lineStart = pos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    final newText = text.replaceRange(lineStart, lineStart, prefix);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: pos + prefix.length),
    );
    focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Widget btn(Widget child, String tip, VoidCallback onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          iconSize: 17,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          icon: child,
        );
    Widget divider() => Container(
        width: 1,
        height: 16,
        color: cs.outlineVariant,
        margin: const EdgeInsets.symmetric(horizontal: 3));

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          btn(
              Text('B',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: cs.outline)),
              'Bold',
              () => _wrap('**', '**')),
          btn(
              Text('I',
                  style: TextStyle(
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                      color: cs.outline)),
              'Italic',
              () => _wrap('*', '*')),
          btn(
              Text('S',
                  style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      fontSize: 15,
                      color: cs.outline)),
              'Strikethrough',
              () => _wrap('~~', '~~')),
          btn(Icon(Icons.code, color: cs.outline), 'Inline code',
              () => _wrap('`', '`')),
          divider(),
          btn(Icon(Icons.link, color: cs.outline), 'Link',
              () => _wrap('[', '](url)')),
          divider(),
          btn(Icon(Icons.format_list_bulleted, color: cs.outline),
              'Bulleted list', () => _prefixLine('- ')),
          btn(Icon(Icons.format_list_numbered, color: cs.outline),
              'Numbered list', () => _prefixLine('1. ')),
          btn(Icon(Icons.format_quote, color: cs.outline), 'Quote',
              () => _prefixLine('> ')),
        ],
      ),
    );
  }
}
