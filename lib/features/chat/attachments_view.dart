import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'attachment_rules.dart';
import '../../shared/error_text.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import 'upload_tasks.dart';

const double _draftImageSize = 64;
const double _draftStripHeight = 76;
const double _draftDocumentWidth = 210;

/// ZH
/// 文件卡固定 64 高，两行文字在系统字号 2.0 下放不下；卡内封顶到 1.3。
///
/// EN
/// File card fixed at 64 high; two text lines do not fit at system scale 2.0, so cap at 1.3.
const double _draftDocumentTextScaleMax = 1.3;
const double _draftImageRadius = 12;
const double _draftCardRadius = 8;
const double _draftBadgeSize = 20;
const double _draftExtensionSize = 36;
const double _singleImageSize = 120;
const double _mixedImageSize = 64;

/// ZH
/// 缩略图按显示尺寸解码：`fit` 内切，既不拉伸、也限制长截图的解码内存。
///
/// EN
/// Decode thumbnails at display size: `fit` avoids stretching and limits tall-screenshot memory.
Widget _thumbnail(
  BuildContext context,
  String path,
  double size,
  ImageErrorWidgetBuilder errorBuilder,
) {
  final pixels = (size * MediaQuery.devicePixelRatioOf(context)).ceil();
  return Image(
    image: ResizeImage(
      FileImage(File(path)),
      width: pixels,
      height: pixels,
      policy: ResizeImagePolicy.fit,
    ),
    fit: BoxFit.cover,
    errorBuilder: errorBuilder,
  );
}

/// ZH
/// 输入区的附件条：图片缩略图或文档卡片，带上传中、失败与移除（`attachments.md` §7）。
///
/// EN
/// Composer attachment strip: thumbnails/cards with upload, failure and remove (`attachments.md` §7).
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
      height: _draftStripHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: attachments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          final task = tasks[attachment.id];
          return Center(
            child: attachment.isImage
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
                  ),
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
    final errorText = failed && task?.error != null
        ? localMessageText(l10n, task!.error!)
        : null;
    final retryable = failed && (task?.retryable ?? false);
    final hasDetail =
        failed &&
        task?.error != null &&
        task!.error!.key != LocalMessageKeys.uploadFileStatusFailed;
    final showReason = failed && (hasDetail || !retryable);
    final reasonText = errorText ?? l10n.uploadFileStatusFailed;

    final tile = Container(
      key: ValueKey('draft-card-${attachment.id}'),
      width: _draftImageSize,
      height: _draftImageSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_draftImageRadius),
        border: Border.all(
          color: failed ? colors.error : colors.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _thumbnail(
            context,
            attachment.path,
            _draftImageSize,
            (context, error, stackTrace) => ColoredBox(
              color: colors.surfaceContainerHighest,
              child: Icon(LucideIcons.imageOff, color: colors.outline),
            ),
          ),
          if (uploading)
            const ColoredBox(
              color: Colors.black45,
              child: Center(
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
          if (retryable)
            const ColoredBox(
              color: Colors.black38,
              child: Center(
                child: Icon(
                  LucideIcons.refreshCw,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          if (showReason)
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
                  reasonText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ),
          Positioned(
            top: 4,
            right: 4,
            child: _RemoveBadge(
              key: ValueKey('draft-remove-${attachment.id}'),
              tooltip: l10n.removeAttachment,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: errorText ?? attachment.name,
      child: GestureDetector(onTap: retryable ? onRetry : null, child: tile),
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
    final errorText = failed && task?.error != null
        ? localMessageText(l10n, task!.error!)
        : null;
    final retryable = failed && (task?.retryable ?? false);
    final subtitle = switch (status) {
      UploadStatus.uploading => l10n.uploadFileStatusUploading,
      UploadStatus.error => errorText ?? l10n.uploadFileStatusFailed,
      _ => _documentMeta(attachment.name, attachment.size),
    };
    final extension = fileExtensionUpper(attachment.name);

    final card = Container(
      key: ValueKey('draft-card-${attachment.id}'),
      width: _draftDocumentWidth,
      height: _draftImageSize,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_draftCardRadius),
        border: Border.all(
          color: failed ? colors.error : colors.outlineVariant,
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              _ExtensionBadge(
                key: ValueKey('draft-extension-${attachment.id}'),
                extension: extension,
                retryable: retryable,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: _draftBadgeSize),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: _draftDocumentTextScaleMax,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachment.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: failed ? colors.error : colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: failed
                                ? colors.error
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _RemoveBadge(
              key: ValueKey('draft-remove-${attachment.id}'),
              tooltip: l10n.removeAttachment,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );

    return Tooltip(
      message: retryable
          ? l10n.uploadRetry(errorText ?? l10n.uploadFileStatusFailed)
          : errorText ?? attachment.name,
      child: GestureDetector(onTap: retryable ? onRetry : null, child: card),
    );
  }
}

/// ZH
/// 消息里的附件：图片缩略图（点击全屏查看）或文档卡片（`attachments.md` §7）。
///
/// EN
/// Message attachment: image thumbnail (tap for full screen) or file card (`attachments.md` §7).
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
        onTap: missing
            ? null
            : () => _showImage(context, path!, attachment.name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: size,
            height: size,
            child: missing
                ? placeholder
                : _thumbnail(
                    context,
                    path!,
                    size,
                    (context, error, stackTrace) => placeholder,
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

/// ZH
/// 36×36 扩展名配色色块；可重试失败时换成白色重试图标。
///
/// EN
/// A 36×36 extension-colored badge; shows a white retry icon on a retryable failure.
class _ExtensionBadge extends StatelessWidget {
  const _ExtensionBadge({
    super.key,
    required this.extension,
    required this.retryable,
  });

  final String extension;
  final bool retryable;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _draftExtensionSize,
      height: _draftExtensionSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _extensionColor(extension),
        borderRadius: BorderRadius.circular(_draftCardRadius),
      ),
      child: retryable
          ? const Icon(LucideIcons.refreshCw, size: 18, color: Colors.white)
          : extension.isEmpty
          ? const Icon(LucideIcons.fileText, size: 18, color: Colors.white)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                extension,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
    );
  }
}

/// ZH
/// 卡片内右上角 20 白色圆移除徽标。
///
/// EN
/// A 20 px white circular remove badge at the card's top-right.
class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Container(
            width: _draftBadgeSize,
            height: _draftBadgeSize,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: const Icon(
              LucideIcons.x,
              size: 12,
              color: Color(0xFF111113),
            ),
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 草稿文件卡扩展名配色（取自输入区原型）。
///
/// EN
/// Extension colors for draft file cards (from the composer prototype).
Color _extensionColor(String extension) => switch (extension) {
  'PDF' => const Color(0xFFE5484D),
  'DOC' || 'DOCX' => const Color(0xFF2F63F6),
  'XLS' || 'XLSX' => const Color(0xFF2E7D32),
  'PPT' || 'PPTX' => const Color(0xFFE07B39),
  _ => const Color(0xFF8A8F98),
};

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
