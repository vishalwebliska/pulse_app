import 'package:flutter/material.dart';

/// Renders a Pulse message body with lightweight inline Markdown — the same
/// subset the composer toolbar produces: **bold**, *italic*, ~~strike~~,
/// `code`, [links](url) and @mentions. [color] sets the base text colour
/// (white on own orange bubbles; null keeps the themed ink). Block elements
/// (lists / quotes) keep their literal markers for now.
Widget messageBody(BuildContext context, String body, {Color? color}) {
  final cs = Theme.of(context).colorScheme;
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .copyWith(color: color);
  final mention = color ?? cs.primary;
  final link = color ?? cs.primary;
  final codeColor = color ?? cs.onSurface;
  final codeBg = color != null
      ? Colors.white.withValues(alpha: 0.18)
      : cs.surfaceContainerHighest;
  final spans = _parseInline(body, base,
      mention: mention, code: codeColor, codeBg: codeBg, link: link);
  // Explicit base style + Text.rich avoids Flutter's red/yellow "unstyled
  // text" fallback when a span resolves to an empty style.
  return Text.rich(TextSpan(children: spans), style: base);
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

List<InlineSpan> _parseInline(
  String text,
  TextStyle base, {
  required Color mention,
  required Color code,
  required Color codeBg,
  required Color link,
}) {
  final spans = <InlineSpan>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      spans.add(TextSpan(text: buf.toString(), style: base));
      buf.clear();
    }
  }

  List<InlineSpan> recurse(String inner, TextStyle style) => _parseInline(
      inner, style,
      mention: mention, code: code, codeBg: codeBg, link: link);

  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text[i];

    // `inline code` — literal, no nested parsing.
    if (c == '`') {
      final close = text.indexOf('`', i + 1);
      if (close > i) {
        flush();
        spans.add(TextSpan(
          text: text.substring(i + 1, close),
          style: base.copyWith(
              fontFamily: 'monospace', color: code, backgroundColor: codeBg),
        ));
        i = close + 1;
        continue;
      }
    }

    // **bold**
    if (c == '*' && i + 1 < n && text[i + 1] == '*') {
      final close = text.indexOf('**', i + 2);
      if (close > i + 1) {
        flush();
        spans.addAll(recurse(text.substring(i + 2, close),
            base.copyWith(fontWeight: FontWeight.bold)));
        i = close + 2;
        continue;
      }
    }

    // ~~strike~~
    if (c == '~' && i + 1 < n && text[i + 1] == '~') {
      final close = text.indexOf('~~', i + 2);
      if (close > i + 1) {
        flush();
        spans.addAll(recurse(text.substring(i + 2, close),
            base.copyWith(decoration: TextDecoration.lineThrough)));
        i = close + 2;
        continue;
      }
    }

    // *italic*
    if (c == '*') {
      final close = text.indexOf('*', i + 1);
      if (close > i) {
        flush();
        spans.addAll(recurse(text.substring(i + 1, close),
            base.copyWith(fontStyle: FontStyle.italic)));
        i = close + 1;
        continue;
      }
    }

    // [label](url) — styled, not tappable yet.
    if (c == '[') {
      final closeB = text.indexOf(']', i + 1);
      if (closeB > i && closeB + 1 < n && text[closeB + 1] == '(') {
        final closeP = text.indexOf(')', closeB + 2);
        if (closeP > closeB + 1) {
          flush();
          spans.add(TextSpan(
            text: text.substring(i + 1, closeB),
            style: base.copyWith(
                color: link, decoration: TextDecoration.underline),
          ));
          i = closeP + 1;
          continue;
        }
      }
    }

    // @mention
    if (c == '@') {
      var j = i + 1;
      while (j < n && !_isSpace(text[j]) && text[j] != '@') {
        j++;
      }
      if (j > i + 1) {
        flush();
        spans.add(TextSpan(
          text: text.substring(i, j),
          style: base.copyWith(color: mention, fontWeight: FontWeight.w600),
        ));
        i = j;
        continue;
      }
    }

    buf.write(c);
    i++;
  }
  flush();
  return spans;
}
