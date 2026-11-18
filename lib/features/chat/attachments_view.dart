import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'attachment_rules.dart';
import '../../shared/error_text.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import 'upload_tasks.dart';

const double _draftImageSize = 64;
const double _singleImageSize = 120;
const double _mixedImageSize = 64;

/// 输入区的附件条：图片缩略图或文档卡片，带上传中、失败与移除（`attachments.md` §7）。
class DraftAttachmentStrip extends StatelessWidget {
  const DraftAttachmentStrip({
    super.key,
    required this.attachments,
    required this.tasks,
    required this.onRetry,
    required this.onRemove,
  });

  final List<DraftAttachment> attachments;
  final Map<String, UploadTask> tasks;
  final ValueChanged<String> onRetry;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: _draftImageSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          final task = tasks[attachment.id];
          return attachment.isImage
              ? _DraftImage(
                  attachment: attachment,
                  task: task,
                  onRetry: () => onRetry(attachment.id),
                  onRemove: () => onRemove(attachment.id),
                )
              : _DraftDocument(
                  attachment: attachment,
                  task: task,
                  onRetry: () => onRetry(attachment.id),
                  onRemove: () => onRemove(attachment.id),
                );
        },
      ),
    );
  }
}

class _DraftImage extends StatelessWidget {
  const _DraftImage({
    required this.attachment,
    required this.task,
    required this.onRetry,
    required this.onRemove,
  });

  final DraftAttachment attachment;
  final UploadTask? task;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final failed = task?.status == UploadStatus.error;
    final uploading = task?.status == UploadStatus.uploading;
    final errorText =
        failed && task?.error != null ? localMessageText(l10n, task!.error!) : null;
    final retryable = failed && (task?.retryable ?? false);

    final tile = Container(
      width: _draftImageSize,
      height: _draftImageSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: failed ? colors.error : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(attachment.path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => ColoredBox(
              color: colors.surfaceContainerHighest,
              child: Icon(Icons.image_not_supported, color: colors.outline),
            ),
          ),
          if (uploading)
            ColoredBox(
              color: Colors.black45,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (failed)
            ColoredBox(
              color: Colors.black38,
              child: Center(
                child: retryable
                    ? IconButton(
                        onPressed: onRetry,
                        tooltip: l10n.uploadRetry(
                          errorText ?? l10n.uploadFileStatusFailed,
                        ),
                        icon: const Icon(Icons.refresh, color: Colors.white),
                      )
                    : Icon(
                        Icons.error_outline,
                        color: colors.onErrorContainer,
                      ),
              ),
            ),
          if (failed &&
              errorText != null &&
              errorText != l10n.uploadFileStatusFailed)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black54],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Text(
                  errorText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ),
        ],
      ),
    );

    return Tooltip(
      message: errorText ?? attachment.name,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: retryable
                ? onRetry
                : failed
                    ? () => ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              errorText ?? l10n.uploadFileStatusFailed,
                            ),
                          ),
                        )
                    : null,
            child: tile,
          ),
          Positioned(
            top: -6,
            right: -6,
            child: _RemoveButton(
              tooltip: l10n.removeAttachment,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftDocument extends StatelessWidget {
  const _DraftDocument({
    required this.attachment,
    required this.task,
    required this.onRetry,
    required this.onRemove,
  });

  final DraftAttachment attachment;
  final UploadTask? task;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final status = task?.status;
    final failed = status == UploadStatus.error;
    final errorText =
        failed && task?.error != null ? localMessageText(l10n, task!.error!) : null;
    final retryable = failed && (task?.retryable ?? false);
    final subtitle = switch (status) {
      UploadStatus.uploading => l10n.uploadFileStatusUploading,
      UploadStatus.error => errorText ?? l10n.uploadFileStatusFailed,
      _ => _documentMeta(attachment.name, attachment.size),
    };

    final card = Container(
      width: 200,
      height: _draftImageSize,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: failed ? colors.error : colors.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Icon(
            retryable ? Icons.refresh : Icons.description_outlined,
            size: 20,
            color: failed ? colors.error : colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: failed ? colors.error : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _RemoveButton(
            tooltip: l10n.removeAttachment,
            onPressed: onRemove,
          ),
        ],
      ),
    );

    return Tooltip(
      message: failed
          ? l10n.uploadRetry(errorText ?? l10n.uploadFileStatusFailed)
          : attachment.name,
      child: GestureDetector(
        onTap: retryable ? onRetry : null,
        child: card,
      ),
    );
  }
}

/// 消息里的附件：图片缩略图（点击全屏查看）或文档卡片（`attachments.md` §7）。
class MessageAttachments extends ConsumerWidget {
  const MessageAttachments({super.key, required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final hasDocument = attachments.any((attachment) => !attachment.isImage);
    final imageSize = hasDocument ? _mixedImageSize : _singleImageSize;
    final store = ref.watch(attachmentStoreProvider);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        for (final attachment in attachments)
          FutureBuilder<String?>(
            future: store.absolutePath(attachment.localPath),
            builder: (context, snapshot) {
              final path = snapshot.data;
              return attachment.isImage
                  ? _MessageImage(
                      attachment: attachment,
                      path: path,
                      size: imageSize,
                    )
                  : _MessageDocument(attachment: attachment, path: path);
            },
          ),
      ],
    );
  }
}

class _MessageImage extends StatelessWidget {
  const _MessageImage({
    required this.attachment,
    required this.path,
    required this.size,
  });

  final Attachment attachment;
  final String? path;
  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final missing = path == null;
    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(
          missing ? Icons.image_not_supported : Icons.image,
          size: 20,
          color: colors.outline,
        ),
      ),
    );
    return Tooltip(
      message: missing ? l10n.missingAttachment : attachment.name,
      child: GestureDetector(
        onTap: missing ? null : () => _showImage(context, path!, attachment.name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: size,
            height: size,
            child: missing
                ? placeholder
                : Image.file(
                    File(path!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => placeholder,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MessageDocument extends StatelessWidget {
  const _MessageDocument({required this.attachment, required this.path});

  final Attachment attachment;
  final String? path;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 20,
            color: colors.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Text(
                  path == null
                      ? l10n.missingAttachment
                      : _documentMeta(attachment.name, attachment.size),
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(Icons.close, size: 14, color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

String _documentMeta(String name, int size) => [
      fileExtensionUpper(name),
      formatFileSize(size),
    ].where((part) => part.isNotEmpty).join(' ');

void _showImage(BuildContext context, String path, String name) {
  final l10n = AppLocalizations.of(context)!;
  showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  semanticLabel: name,
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: IconButton(
                tooltip: l10n.previewImage,
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
