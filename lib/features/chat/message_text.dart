import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders a Pulse message body with lightweight Markdown — the subset the
/// composer toolbar produces: **bold**, *italic*, ~~strike~~, `code`,
/// [links](url), bare URLs, @mentions, plus block-level bullet / numbered
/// lists and > quotes. [color] sets the base text colour (white on own orange
/// bubbles; null keeps the themed ink).
Widget messageBody(BuildContext context, String body, {Color? color}) {
  final lines = body.split('\n');
  final hasBlocks = lines.any((l) => _blockKind(l) != null);
  if (!hasBlocks) return _inline(context, body, color: color);

  final cs = Theme.of(context).colorScheme;
  final muted = color ?? cs.outline;
  final children = <Widget>[];
  for (final line in lines) {
    final kind = _blockKind(line);
    switch (kind) {
      case 'quote':
        children.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: muted, width: 3)),
          ),
          child: _inline(context, line.replaceFirst(RegExp(r'^\s*>\s?'), ''),
              color: color),
        ));
      case 'bullet':
        children.add(_listRow(context, '•   ',
            line.replaceFirst(RegExp(r'^\s*[-*]\s+'), ''), color, muted));
      case 'number':
        final m = RegExp(r'^\s*(\d+)\.\s+(.*)$').firstMatch(line)!;
        children.add(
            _listRow(context, '${m.group(1)}.  ', m.group(2)!, color, muted));
      default:
        children.add(_inline(context, line, color: color));
    }
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

String? _blockKind(String line) {
  if (RegExp(r'^\s*>\s').hasMatch(line)) return 'quote';
  if (RegExp(r'^\s*[-*]\s+').hasMatch(line)) return 'bullet';
  if (RegExp(r'^\s*\d+\.\s+').hasMatch(line)) return 'number';
  return null;
}

Widget _listRow(BuildContext context, String marker, String text, Color? color,
    Color muted) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .copyWith(color: color);
  return Padding(
    padding: const EdgeInsets.only(left: 2, top: 1, bottom: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(marker, style: base.copyWith(color: color ?? muted)),
        Expanded(child: _inline(context, text, color: color)),
      ],
    ),
  );
}

void _open(String url) {
  final uri = Uri.tryParse(url);
  if (uri != null) {
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Widget _inline(BuildContext context, String text, {Color? color}) {
  final cs = Theme.of(context).colorScheme;
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .copyWith(color: color);
  final mention = color ?? cs.primary;
  final link = color ?? cs.primary;
  final codeColor = color ?? cs.onSurface;
  final codeBg = color != null
      ? Colors.white.withValues(alpha: 0.18)
      : cs.surfaceContainerHighest;
  final spans = _parseInline(text, base,
      mention: mention, code: codeColor, codeBg: codeBg, link: link);
  return Text.rich(TextSpan(children: spans), style: base);
}

bool _isSpace(String c) => c == ' ' || c == '\n' || c == '\t' || c == '\r';

final _urlRe = RegExp(r'https?://[^\s<>()]+');

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

  TextSpan linkSpan(String label, String url) => TextSpan(
        text: label,
        style: base.copyWith(color: link, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = () => _open(url),
      );

  final n = text.length;
  var i = 0;
  while (i < n) {
    final c = text[i];

    // `inline code`
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

    // [label](url)
    if (c == '[') {
      final closeB = text.indexOf(']', i + 1);
      if (closeB > i && closeB + 1 < n && text[closeB + 1] == '(') {
        final closeP = text.indexOf(')', closeB + 2);
        if (closeP > closeB + 1) {
          flush();
          spans.add(linkSpan(
              text.substring(i + 1, closeB), text.substring(closeB + 2, closeP)));
          i = closeP + 1;
          continue;
        }
      }
    }

    // bare URL
    if ((c == 'h') &&
        (text.startsWith('http://', i) || text.startsWith('https://', i))) {
      final m = _urlRe.matchAsPrefix(text, i);
      if (m != null) {
        flush();
        final url = m.group(0)!;
        spans.add(linkSpan(url, url));
        i = m.end;
        continue;
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
