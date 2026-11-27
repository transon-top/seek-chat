import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'attachment_rules.dart';

/// ZH
/// 输入卡下方的内联附件面板：照片横条 + 拍照 / 相册 / 文件三宫格（ui.md §5.7）。
///
/// [photoStrip] 为空时只渲染三宫格并按内容收缩（Android 构建关闭横条）。
///
/// EN
/// Inline Attachment Panel below composer: Device Photo Strip + camera / photos / files (ui.md §5.7).
///
/// When [photoStrip] is null, render only the grid, shrinking to content (Android hides the strip).
class AttachmentPanel extends StatelessWidget {
  const AttachmentPanel({
    super.key,
    required this.attachmentCount,
    required this.onTakePhoto,
    required this.onPickPhotos,
    required this.onPickFiles,
    required this.onLimitReached,
    this.photoStrip,
  });

  /// ZH
  /// 当前草稿附件数；已满 50 时拍照与相册入口只提示，不打开系统界面。
  ///
  /// EN
  /// Current draft attachment count; at 50, camera and photos only show a notice, not system UI.
  final int attachmentCount;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickPhotos;
  final VoidCallback onPickFiles;
  final VoidCallback onLimitReached;
  final Widget? photoStrip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final full = attachmentCount >= maxAttachmentCount;
    void guard(VoidCallback action) {
      if (full) {
        onLimitReached();
      } else {
        action();
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ?photoStrip,
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            height: 88,
            child: Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    key: const Key('panel-take-photo'),
                    icon: LucideIcons.camera,
                    label: l10n.takePhoto,
                    onTap: () => guard(onTakePhoto),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionTile(
                    key: const Key('panel-photos'),
                    icon: LucideIcons.image,
                    label: l10n.uploadFromPhotos,
                    onTap: () => guard(onPickPhotos),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionTile(
                    key: const Key('panel-files'),
                    icon: LucideIcons.paperclip,
                    label: l10n.uploadFromFiles,
                    onTap: onPickFiles,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: colors.foreground),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: colors.foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
