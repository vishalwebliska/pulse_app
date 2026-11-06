import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'chat_models.dart';
import 'chat_repository.dart';

/// Renders a message's attachments — image thumbnails (bytes fetched + cached)
/// and file chips — opening each via the presigned-URL resolver. Shared by the
/// channel and thread message tiles.
class AttachmentView extends StatefulWidget {
  const AttachmentView({super.key, required this.attachments});

  final List<PulseAttachment> attachments;

  @override
  State<AttachmentView> createState() => _AttachmentViewState();
}

class _AttachmentViewState extends State<AttachmentView> {
  final Map<int, Future<Uint8List>> _imgFutures = {};

  Future<Uint8List> _imgFuture(int id) => _imgFutures.putIfAbsent(
      id, () => ChatRepository.instance.fetchAttachmentBytes(id));

  Future<void> _open(PulseAttachment a) async {
    final url = await ChatRepository.instance.resolveAttachmentUrl(a.id);
    if (!mounted) return;
    final uri = url != null ? Uri.tryParse(url) : null;
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Can't open this attachment here.")));
      return;
    }
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.attachments.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final a in widget.attachments)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: a.isImage ? _imagePreview(a) : _fileChip(a),
            ),
        ],
      ),
    );
  }

  Widget _imagePreview(PulseAttachment a) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _open(a),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
          child: FutureBuilder<Uint8List>(
            future: _imgFuture(a.id),
            builder: (ctx, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Container(
                  width: 200,
                  height: 130,
                  color: cs.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                return _fileChip(a);
              }
              return Image.memory(snap.data!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _fileChip(a));
            },
          ),
        ),
      ),
    );
  }

  Widget _fileChip(PulseAttachment a) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => _open(a),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                  a.isImage
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 18,
                  color: cs.primary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 12.5)),
                  Text(a.sizeLabel,
                      style: TextStyle(color: cs.outline, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.open_in_new, size: 15, color: cs.outline),
          ],
        ),
      ),
    );
  }
}
