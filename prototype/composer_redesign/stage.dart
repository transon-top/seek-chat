/// 输入区改版视觉原型的一次性舞台组件。
///
/// 全部为假数据、假状态，没有输入、上传、录音或网络。只回答「长什么样」，
/// 生产实现另按票 07 汇总的规格来做。见 `README.md`。
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart' show Ticker;
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 票 06 的视觉状态。
enum Scenario {
  empty('空态'),
  typed('有文本'),
  panel('面板·已选'),
  panelDenied('面板·权限拒绝'),
  panelEmpty('面板·无照片'),
  drafts('草稿附件行'),
  busy('生成中'),
  transcribing('转写中'),
  recording('录音浮层'),
  cancelling('上滑取消态');

  const Scenario(this.label);

  final String label;
}

enum DraftStatus { done, uploading, failed }

class FakeDraft {
  const FakeDraft({
    required this.name,
    required this.isImage,
    this.status = DraftStatus.done,
    this.tint = 0,
  });

  final String name;
  final bool isImage;
  final DraftStatus status;
  final int tint;

  bool get ready => status == DraftStatus.done;
}

enum StripState { loaded, denied, empty, loading }

class StageConfig {
  const StageConfig({
    this.conversation = false,
    this.text = '',
    this.drafts = const [],
    this.strip,
    this.limited = false,
    this.selected = const {},
    this.busy = false,
    this.transcribing = false,
    this.recording = false,
    this.cancelling = false,
  });

  final bool conversation;
  final String text;
  final List<FakeDraft> drafts;
  final StripState? strip;
  final bool limited;
  final Set<int> selected;
  final bool busy;
  final bool transcribing;
  final bool recording;
  final bool cancelling;

  static StageConfig of(Scenario scenario) {
    const photo = FakeDraft(name: 'IMG_2048.jpg', isImage: true, tint: 2);
    const pdf = FakeDraft(name: '如何查看微信或QQ的聊天记录.pdf', isImage: false);
    return switch (scenario) {
      Scenario.empty => const StageConfig(),
      Scenario.typed => const StageConfig(
        conversation: true,
        text: '帮我写一封简短的道歉邮件',
      ),
      Scenario.panel => const StageConfig(
        conversation: true,
        text: '1',
        drafts: [photo, pdf],
        strip: StripState.loaded,
        limited: true,
        selected: {1, 4},
      ),
      Scenario.panelDenied => const StageConfig(
        conversation: true,
        text: '1',
        drafts: [photo, pdf],
        strip: StripState.denied,
      ),
      Scenario.panelEmpty => const StageConfig(
        conversation: true,
        text: '1',
        strip: StripState.empty,
      ),
      Scenario.drafts => const StageConfig(
        conversation: true,
        drafts: [
          photo,
          FakeDraft(name: '如何查看微信或QQ的聊天记录.pdf', isImage: false),
          FakeDraft(
            name: 'IMG_2050.jpg',
            isImage: true,
            status: DraftStatus.failed,
            tint: 5,
          ),
          FakeDraft(
            name: 'IMG_2049.jpg',
            isImage: true,
            status: DraftStatus.uploading,
            tint: 0,
          ),
          FakeDraft(
            name: '设计评审纪要.docx',
            isImage: false,
            status: DraftStatus.uploading,
          ),
        ],
      ),
      Scenario.busy => const StageConfig(conversation: true, busy: true),
      Scenario.transcribing => const StageConfig(
        conversation: true,
        transcribing: true,
      ),
      Scenario.recording => const StageConfig(
        conversation: true,
        recording: true,
      ),
      Scenario.cancelling => const StageConfig(
        conversation: true,
        recording: true,
        cancelling: true,
      ),
    };
  }
}

const _photoTints = [
  [Color(0xFF9DB8E8), Color(0xFF5273A8)],
  [Color(0xFFA9C6A0), Color(0xFF5F8A57)],
  [Color(0xFFE8C49C), Color(0xFFB07A4C)],
  [Color(0xFFC7B3D9), Color(0xFF7E639B)],
  [Color(0xFF9FD0D8), Color(0xFF4E8892)],
  [Color(0xFFE5A8A8), Color(0xFFA85B5B)],
  [Color(0xFFC9C1A8), Color(0xFF8A8062)],
  [Color(0xFFA8B3D9), Color(0xFF5E6E9B)],
];

/// 整屏舞台：顶部栏、消息区 / 问候语、输入卡、附件面板、免责声明与录音浮层。
class PrototypeStage extends StatelessWidget {
  const PrototypeStage({super.key, required this.scenario});

  final Scenario scenario;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final config = StageConfig.of(scenario);
    final screenHeight = MediaQuery.sizeOf(context).height;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _TopBar(active: config.conversation),
                Expanded(
                  child: config.conversation
                      ? const _DemoMessages()
                      : const _Greeting(),
                ),
                if (!config.recording && !config.transcribing)
                  FakeComposer(config: config),
                if (!config.recording &&
                    !config.transcribing &&
                    config.strip != null)
                  AttachmentPanel(
                    state: config.strip!,
                    limited: config.limited,
                    selected: config.selected,
                  ),
                if (!config.recording && !config.transcribing)
                  const _Disclaimer(),
              ],
            ),
            if (config.recording || config.transcribing)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: screenHeight * 0.60,
                child: RecordingOverlay(
                  cancelling: config.cancelling,
                  transcribing: config.transcribing,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 16),
          Icon(LucideIcons.menu, size: 19, color: colors.foreground),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              active ? '周末去哪里玩' : '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: colors.foreground,
              ),
            ),
          ),
          Icon(LucideIcons.circlePlus, size: 20, color: colors.foreground),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 96) return const SizedBox.shrink();
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              '嗨! 今天想聊些什么?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                height: 32 / 24,
                fontWeight: FontWeight.w600,
                color: colors.foreground,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DemoMessages extends StatelessWidget {
  const _DemoMessages();

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final material = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: material.surfaceContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '帮我看看这张照片里是什么？',
              style: TextStyle(
                fontSize: 15.5,
                height: 1.55,
                color: colors.foreground,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '这是一张傍晚的城市公园照片：前景是草地和步道，远处有一排亮着路灯的树，'
          '画面的右上角还能看到一小块淡蓝色的天空。',
          style: TextStyle(
            fontSize: 15.5,
            height: 1.65,
            color: colors.foreground,
          ),
        ),
      ],
    );
  }
}

class _Disclaimer extends StatelessWidget {
  const _Disclaimer();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        '内容由 AI 生成，请仔细甄别',
        style: TextStyle(
          fontSize: 10.5,
          color: ShadTheme.of(context).colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

/// 输入卡：圆角 28、1px 描边、内部 16/12/12/10；草稿附件行 + 输入 + 按钮行。
class FakeComposer extends StatelessWidget {
  const FakeComposer({super.key, required this.config});

  final StageConfig config;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final hasText = config.text.trim().isNotEmpty;
    final hasAttachments = config.drafts.isNotEmpty;
    final locked = config.recording || config.busy || config.transcribing;
    final showMic = !hasText && !config.busy && !config.transcribing;
    final ready = config.drafts.every((draft) => draft.ready);
    final sendEnabled =
        !locked && (hasText || hasAttachments) && ready;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasAttachments)
              DraftAttachmentStrip(drafts: config.drafts),
            SizedBox(
              height: 52,
              width: double.infinity,
              child: hasText
                  ? Text(
                      config.text,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.foreground,
                      ),
                    )
                  : Text(
                      hasAttachments ? '发消息' : '发消息或按住说话',
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.6,
                        color: colors.mutedForeground,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const _TogglePill(
                  icon: LucideIcons.atom,
                  label: '深度思考',
                  selected: true,
                ),
                const SizedBox(width: 6),
                const _TogglePill(
                  icon: LucideIcons.globe,
                  label: '智能搜索',
                  selected: false,
                ),
                const Spacer(),
                _AttachButton(open: config.strip != null, enabled: !locked),
                if (showMic) const _MicButton(),
                const SizedBox(width: 2),
                _SendButton(
                  busy: config.busy,
                  transcribing: config.transcribing,
                  enabled: sendEnabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TogglePill extends StatelessWidget {
  const _TogglePill({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final foreground = selected
        ? (dark ? const Color(0xFF679EFE) : colors.primary)
        : (dark ? const Color(0xFFF9FAFB) : colors.mutedForeground);
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: selected
            ? (dark
                  ? const Color(0xFF283142)
                  : colors.primary.withValues(alpha: 0.10))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected
              ? (dark
                    ? const Color(0xFF4868B2)
                    : colors.primary.withValues(alpha: 0.45))
              : colors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              height: 16 / 12.5,
              color: foreground,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttachButton extends StatelessWidget {
  const _AttachButton({required this.open, required this.enabled});

  final bool open;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final color = enabled ? colors.mutedForeground : colors.border;
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween<double>(begin: 0, end: 0.25).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          open ? LucideIcons.x : LucideIcons.plus,
          key: ValueKey(open),
          size: 20,
          color: color,
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Icon(
        LucideIcons.mic,
        size: 18,
        color: ShadTheme.of(context).colorScheme.mutedForeground,
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.busy,
    required this.transcribing,
    required this.enabled,
  });

  final bool busy;
  final bool transcribing;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    if (transcribing) {
      return const SizedBox(
        width: 34,
        height: 34,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: busy
            ? colors.primary
            : enabled
            ? colors.primary
            : colors.primary.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      child: busy
          ? Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: colors.primaryForeground,
                borderRadius: BorderRadius.circular(2.9),
              ),
            )
          : Icon(
              LucideIcons.arrowUp,
              size: 18,
              color: colors.primaryForeground,
            ),
    );
  }
}

// ------------------------------------------------------------------ 草稿附件行

class DraftAttachmentStrip extends StatelessWidget {
  const DraftAttachmentStrip({super.key, required this.drafts});

  final List<FakeDraft> drafts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        itemCount: drafts.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => Center(
          child: drafts[index].isImage
              ? _DraftImage(draft: drafts[index])
              : _DraftDocument(draft: drafts[index]),
        ),
      ),
    );
  }
}

class _DraftImage extends StatelessWidget {
  const _DraftImage({required this.draft});

  final FakeDraft draft;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final tint = _photoTints[draft.tint % _photoTints.length];
    final failed = draft.status == DraftStatus.failed;
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: tint,
                  ),
                  border: Border.all(
                    color: failed ? colors.destructive : colors.border,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.image,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
          if (draft.status == DraftStatus.uploading)
            const Positioned.fill(child: _UploadingOverlay()),
          if (failed) const Positioned.fill(child: _FailedOverlay()),
          const Positioned(top: 4, right: 4, child: _RemoveBadge()),
        ],
      ),
    );
  }
}

class _DraftDocument extends StatelessWidget {
  const _DraftDocument({required this.draft});

  final FakeDraft draft;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final failed = draft.status == DraftStatus.failed;
    final ext = _extension(draft.name);
    return Container(
      width: 210,
      height: 64,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: failed ? colors.destructive : colors.border,
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              _FileBadge(extension: ext),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.3,
                          color: failed
                              ? colors.destructive
                              : colors.foreground,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        switch (draft.status) {
                          DraftStatus.uploading => '上传中…',
                          DraftStatus.failed => '上传失败',
                          DraftStatus.done => '${_size(draft.name)} · $ext',
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: failed
                              ? colors.destructive
                              : colors.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (failed)
            Positioned(
              right: 22,
              bottom: 0,
              child: Icon(
                LucideIcons.refreshCw,
                size: 14,
                color: colors.destructive,
              ),
            ),
          const Positioned(top: 0, right: 0, child: _RemoveBadge()),
        ],
      ),
    );
  }
}

class _FileBadge extends StatelessWidget {
  const _FileBadge({required this.extension});

  final String extension;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _extensionColor(extension),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        extension,
        style: const TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  const _RemoveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: const Icon(LucideIcons.x, size: 12, color: Color(0xFF111113)),
    );
  }
}

class _UploadingOverlay extends StatelessWidget {
  const _UploadingOverlay();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.black45,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ),
      ),
    );
  }
}

class _FailedOverlay extends StatelessWidget {
  const _FailedOverlay();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: Colors.black38,
        child: Center(
          child: Icon(
            LucideIcons.refreshCw,
            size: 20,
            color: Colors.white.withValues(alpha: 0.95),
          ),
        ),
      ),
    );
  }
}

String _extension(String name) {
  final dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'FILE';
  return name.substring(dot + 1).toUpperCase();
}

Color _extensionColor(String extension) => switch (extension) {
  'PDF' => const Color(0xFFE5484D),
  'DOC' || 'DOCX' => const Color(0xFF2F63F6),
  'XLS' || 'XLSX' => const Color(0xFF2E7D32),
  'PPT' || 'PPTX' => const Color(0xFFE07B39),
  _ => const Color(0xFF8A8F98),
};

String _size(String name) => name.contains('设计') ? '128 KB' : '304 KB';

// ------------------------------------------------------------------- 附件面板

class AttachmentPanel extends StatelessWidget {
  const AttachmentPanel({
    super.key,
    required this.state,
    required this.limited,
    required this.selected,
  });

  final StripState state;
  final bool limited;
  final Set<int> selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: 96, child: _strip(context)),
          const SizedBox(height: 8),
          const _ActionGrid(),
        ],
      ),
    );
  }

  Widget _strip(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    switch (state) {
      case StripState.loading:
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 6,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) => Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.muted,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        );
      case StripState.denied:
        return _StripNotice(
          text: '无法访问照片',
          action: '去设置',
          icon: LucideIcons.imageOff,
        );
      case StripState.empty:
        return _StripNotice(
          text: '没有最近照片',
          icon: LucideIcons.image,
        );
      case StripState.loaded:
        return ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 9,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            if (limited && index == 0) {
              return const Center(child: _ManageTile());
            }
            final photo = index - (limited ? 1 : 0);
            return Center(
              child: _PhotoTile(
                tint: photo,
                selected: selected.contains(photo),
              ),
            );
          },
        );
    }
  }
}

class _StripNotice extends StatelessWidget {
  const _StripNotice({
    required this.text,
    required this.icon,
    this.action,
  });

  final String text;
  final String? action;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: colors.mutedForeground),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: 13, color: colors.mutedForeground),
          ),
          if (action != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: colors.border),
              ),
              child: Text(
                action!,
                style: TextStyle(fontSize: 12, color: colors.foreground),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile();

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.settings, size: 18, color: colors.mutedForeground),
          const SizedBox(height: 4),
          Text(
            '管理',
            style: TextStyle(fontSize: 11, color: colors.mutedForeground),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.tint, required this.selected});

  final int tint;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final gradient = _photoTints[tint % _photoTints.length];
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: gradient,
                  ),
                ),
                child: Center(
                  child: Icon(
                    LucideIcons.image,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ),
          ),
          if (selected)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: const ColoredBox(color: Color(0x47000000)),
              ),
            ),
          Positioned(
            top: 5,
            right: 5,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: selected ? colors.primary : const Color(0x33000000),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? const Icon(LucideIcons.check, size: 12, color: Colors.white)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 88,
      child: Row(
        children: [
          Expanded(
            child: _ActionTile(icon: LucideIcons.camera, label: '拍照'),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _ActionTile(icon: LucideIcons.image, label: '相册'),
          ),
          SizedBox(width: 8),
          Expanded(
            child: _ActionTile(icon: LucideIcons.paperclip, label: '文件'),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.muted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 24, color: colors.foreground),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.foreground),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- 录音浮层

/// 贴底蓝色动态浮层：不盖顶部栏、不加全屏遮罩。
///
/// 蓝色区域不是水平渐变，而是多枚缓慢漂移的椭圆团块构成的动态不规则边缘；
/// 高光跟随按住位置并随假电平脉动。录音、识别与取消复用同一效果，只换文案，
/// 不变色。生产实现把高光锚定到真实 pointer 位置，电平取
/// `SpeechState.level`。
class RecordingOverlay extends StatefulWidget {
  const RecordingOverlay({
    super.key,
    required this.cancelling,
    required this.transcribing,
  });

  final bool cancelling;
  final bool transcribing;

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _seconds = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      setState(() => _seconds = elapsed.inMicroseconds / 1000000);
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// 假电平；生产实现换成 `SpeechState.level` 的平滑值。
  double get _level {
    if (widget.transcribing) return 0.16;
    final raw =
        0.58 +
        0.22 * math.sin(_seconds * 2.1) +
        0.12 * math.sin(_seconds * 5.7);
    return raw.clamp(0.2, 1.0);
  }

  /// 高光位置（归一化）；生产实现用按下时的全局坐标换算。
  Offset get _hotspot => Offset(
    0.5 + 0.08 * math.sin(_seconds * 0.6),
    0.78 + 0.02 * math.sin(_seconds * 0.9),
  );

  @override
  Widget build(BuildContext context) {
    final label = widget.transcribing
        ? '识别中'
        : widget.cancelling
        ? '松开取消'
        : '松手发送，上滑取消';
    final dark = ShadTheme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _AuraPainter(
                t: _seconds,
                level: _level,
                hotspot: _hotspot,
                dark: dark,
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x33000000), blurRadius: 6)],
                ),
              ),
              const SizedBox(height: 18),
              _Waveform(t: _seconds, idle: widget.transcribing),
              const SizedBox(height: 44),
            ],
          ),
        ],
      ),
    );
  }
}

/// 底部蓝色团块：长距离透明底 + 漂移椭圆的并集 + 按住位置高光。
class _AuraPainter extends CustomPainter {
  const _AuraPainter({
    required this.t,
    required this.level,
    required this.hotspot,
    required this.dark,
  });

  final double t;
  final double level;
  final Offset hotspot;
  final bool dark;

  Color get _base => dark ? const Color(0xFF2F63F6) : const Color(0xFF3D6DF6);
  Color get _deep => dark ? const Color(0xFF1E4FD6) : const Color(0xFF2455E8);
  Color get _bright =>
      dark ? const Color(0xFF7FA5FF) : const Color(0xFF89ACFF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final volume = level.clamp(0.0, 1.0);
    final base = _base;

    // 长距离底色：顶部全透明，避免出现水平分界线。
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            base.withValues(alpha: 0),
            base.withValues(alpha: 0),
            base.withValues(alpha: 0.06),
            base.withValues(alpha: 0.16),
            base.withValues(alpha: 0.36),
            base.withValues(alpha: 0.62),
          ],
          stops: const [0, 0.16, 0.34, 0.52, 0.70, 0.88],
        ).createShader(rect),
    );

    // 漂移的团块：互相重叠形成不规则的蓝色上边缘与流动感。
    final blobs = [
      (
        0.18 + 0.03 * math.sin(t * 0.53),
        0.56 + 0.03 * math.cos(t * 0.41),
        0.86,
        0.40,
        dark ? 0.42 : 0.50,
      ),
      (
        0.50 + 0.04 * math.sin(t * 0.37 + 1.2),
        0.58 + 0.02 * math.cos(t * 0.61),
        1.02,
        0.46,
        dark ? 0.46 : 0.55,
      ),
      (
        0.82 + 0.03 * math.cos(t * 0.47 + 0.4),
        0.56 + 0.03 * math.sin(t * 0.33),
        0.84,
        0.40,
        dark ? 0.42 : 0.50,
      ),
      (
        0.26 + 0.03 * math.sin(t * 0.71 + 2.0),
        0.78,
        1.04,
        0.56,
        dark ? 0.66 : 0.76,
      ),
      (
        0.76 + 0.03 * math.cos(t * 0.59 + 1.7),
        0.80,
        0.98,
        0.54,
        dark ? 0.62 : 0.72,
      ),
      (hotspot.dx, hotspot.dy, 0.70, 0.46, 0.36 + 0.30 * volume),
    ];
    for (final (x, y, w, h, alpha) in blobs) {
      final blob = Rect.fromCenter(
        center: Offset(size.width * x, size.height * y),
        width: size.width * w * (1 + 0.04 * math.sin(t * 0.9 + x * 9)),
        height: size.height * h * (1 + 0.04 * math.cos(t * 0.8 + y * 9)),
      );
      canvas.drawOval(
        blob,
        Paint()
          ..shader = RadialGradient(
            colors: [
              _bright.withValues(alpha: alpha),
              base.withValues(alpha: alpha * 0.66),
              base.withValues(alpha: 0),
            ],
            stops: const [0, 0.55, 1],
          ).createShader(blob),
      );
    }

    // 底部实心：从透明缓慢过渡到实色，确保输入卡被完全盖住且没有接缝。
    final solid = Rect.fromLTRB(0, size.height * 0.66, size.width, size.height);
    canvas.drawRect(
      solid,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _deep.withValues(alpha: 0),
            _deep.withValues(alpha: 0.92),
            _deep,
            base,
          ],
          stops: const [0, 0.45, 0.7, 1],
        ).createShader(solid),
    );

    // 按住位置的高光，随音量脉动。
    final center = Offset(size.width * hotspot.dx, size.height * hotspot.dy);
    final radius = size.width * (0.34 + 0.03 * math.sin(t * 1.7));
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFD6E4FF).withValues(alpha: 0.10 + 0.30 * volume),
            _bright.withValues(alpha: 0.06 + 0.16 * volume),
            base.withValues(alpha: 0),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_AuraPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.level != level ||
      oldDelegate.hotspot != hotspot ||
      oldDelegate.dark != dark;
}

/// 32 根波形条：假电平每帧起伏；识别中退化为低幅基线。
class _Waveform extends StatelessWidget {
  const _Waveform({required this.t, this.idle = false});

  final double t;
  final bool idle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 32; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.6),
              child: Container(
                width: 2.4,
                height: _height(i, t),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double _height(int i, double t) {
    if (idle) return 3 + 2.5 * (0.5 + 0.5 * math.sin(t * 2.2 + i * 0.5));
    final phase = i * 0.55;
    final flutter = 0.5 + 0.5 * math.sin(t * 6.1 + phase);
    final pulse = 0.5 + 0.5 * math.sin(t * 2.3 + phase * 1.7);
    final drift = 0.5 + 0.5 * math.sin(t * 0.9 + i * 0.21);
    final level = flutter * pulse * 0.78 + drift * 0.22;
    return 4 + 24 * level.clamp(0.0, 1.0);
  }
}
