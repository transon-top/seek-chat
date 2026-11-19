import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:uuid/uuid.dart';

import 'attachment_rules.dart';
import 'chat_header.dart';
import '../../shared/error_text.dart';
import '../../shared/logging.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/chat_options_store.dart';
import '../../shared/providers.dart';
import '../../shared/speech/permissions.dart';
import '../../shared/toast.dart';
import 'speech/speech_controller.dart';
import 'upload_tasks.dart';
import 'chat_controller.dart';
import 'composer.dart';
import 'markdown_view.dart';
import 'messages_view.dart';

/// 聊天页：顶部栏、可见路径、流式文本、停止、重新生成、续写、搜索与引用。
///
/// 会话为空时停在新对话草稿上；首条消息发出时创建会话（ui.md §5.10）。
/// 抽屉由 `app/` 注入，聊天功能不直接 import 会话功能。
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    this.drawer,
    this.onNewChat,
    this.onSessionCreated,
    this.onSessionDiscarded,
    this.focusRequest = 0,
  });

  final String? sessionId;
  final Widget? drawer;
  final VoidCallback? onNewChat;
  final ValueChanged<String>? onSessionCreated;

  /// 首条消息未发出时回滚刚创建的空会话。
  final VoidCallback? onSessionDiscarded;

  /// 每次递增表示外部要求聚焦输入框（新对话）。
  final int focusRequest;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final List<DraftAttachment> _attachments = [];
  late final ChatOptionsStore _options;
  late final SpeechController _speech;
  late bool _thinking;
  late bool _search;
  String? _sessionId;

  /// 草稿会话创建后，先占住控制器，避免自动销毁丢掉首轮流式状态。
  ProviderSubscription<ChatState>? _controllerHold;

  @override
  void initState() {
    super.initState();
    _options = ref.read(chatOptionsStoreProvider);
    _speech = ref.read(speechControllerProvider.notifier);
    _thinking = _options.thinking;
    _search = _options.search;
    _sessionId = widget.sessionId;
    _holdController(_sessionId);
    if (_sessionId != null) _load(_sessionId!);
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequest != oldWidget.focusRequest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocus.requestFocus();
      });
    }
    if (widget.sessionId == _sessionId) return;
    unawaited(_speech.stopAll());
    _sessionId = widget.sessionId;
    _holdController(_sessionId);
    _input.clear();
    _attachments.clear();
    if (_sessionId != null) _load(_sessionId!);
  }

  /// 空回调只用于在页面开始 watch 前钉住 autoDispose 控制器。
  void _holdController(String? sessionId) {
    _controllerHold?.close();
    _controllerHold = sessionId == null
        ? null
        : ref.listenManual(chatControllerProvider(sessionId), (_, _) {});
  }

  void _load(String sessionId) {
    unawaited(ref.read(chatControllerProvider(sessionId).notifier).load());
  }

  @override
  void dispose() {
    _controllerHold?.close();
    unawaited(_speech.stopAll());
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// 转写结果替换当前选区；光标落在插入内容之后（`speech.md` §3.4）。
  void _insertTranscript(String text) {
    _input.value = insertTranscript(_input.value, text);
  }

  void _stopReading() {
    unawaited(_speech.stopReadAloud());
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty && _attachments.isEmpty) return;
    if (!allUploadsDone(_attachments, ref.read(uploadTasksProvider))) return;
    final l10n = AppLocalizations.of(context)!;
    final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      if (mounted) _showToast(l10n.errorNoApiKey);
      return;
    }
    var sessionId = _sessionId;
    var createdHere = false;
    if (sessionId == null) {
      final session = await ref.read(chatRepositoryProvider).createSession();
      if (!mounted) return;
      _sessionId = session.id;
      _holdController(session.id);
      widget.onSessionCreated?.call(session.id);
      setState(() {});
      sessionId = session.id;
      createdHere = true;
    }
    await _speech.stopReadAloud();
    final sent = await ref
        .read(chatControllerProvider(sessionId).notifier)
        .send(
          text: text,
          thinking: _thinking,
          search: _search,
          attachments: List.of(_attachments),
        );
    if (!sent) {
      if (createdHere) await _discardEmptySession(sessionId);
      return;
    }
    if (!mounted) return;
    _input.clear();
    setState(_attachments.clear);
  }

  /// 请求未发出时不留下空会话；发送失败的空会话直接删除。
  Future<void> _discardEmptySession(String sessionId) async {
    _holdController(null);
    try {
      final orphaned = await ref
          .read(chatRepositoryProvider)
          .deleteSession(sessionId);
      await ref.read(attachmentStoreProvider).deleteAttachments(orphaned);
    } on Object catch (error) {
      debugLog('discarding empty session failed', error);
    }
    if (!mounted) return;
    widget.onSessionDiscarded?.call();
    setState(() => _sessionId = null);
  }

  Future<void> _addAttachments() async {
    final l10n = AppLocalizations.of(context)!;
    final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      _showToast(l10n.errorNoApiKey);
      return;
    }
    if (!mounted) return;
    final source = await showShadSheet<_AttachmentSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AttachmentSourceRow(
                icon: LucideIcons.image,
                label: l10n.uploadFromPhotos,
                onTap: () =>
                    Navigator.of(context).pop(_AttachmentSource.photos),
              ),
              _AttachmentSourceRow(
                icon: LucideIcons.paperclip,
                label: l10n.uploadFromFiles,
                onTap: () => Navigator.of(context).pop(_AttachmentSource.files),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: source == _AttachmentSource.photos
            ? FileType.image
            : FileType.any,
      );
    } on Object {
      if (mounted) _showToast(l10n.uploadFileStatusFailed);
      return;
    }
    if (files.isEmpty || !mounted) return;

    final picked = <DraftAttachment>[];
    for (final file in files) {
      final path = file.path;
      if (path == null) continue;
      final size = file.lengthSync() ?? await file.length() ?? 0;
      picked.add(
        DraftAttachment(
          id: const Uuid().v4(),
          path: path,
          name: file.name,
          size: size,
          isImage: isImageFileName(file.name),
          mimeType: mimeTypeForFileName(file.name),
        ),
      );
    }
    if (!mounted || picked.isEmpty) return;

    final error = validateAttachmentSelection(
      files: [
        for (final item in picked)
          SelectedFile(name: item.name, size: item.size),
      ],
      currentCount: _attachments.length,
    );
    if (error != null) {
      _showToast(localMessageText(l10n, error));
      return;
    }

    setState(() => _attachments.addAll(picked));
    for (final item in picked) {
      _startUpload(item);
    }
  }

  void _startUpload(DraftAttachment item) {
    unawaited(
      ref
          .read(uploadTasksProvider.notifier)
          .upload(
            id: item.id,
            path: item.path,
            name: item.name,
            isImage: item.isImage,
          )
          .catchError((_) => null),
    );
  }

  void _removeAttachment(String id) {
    ref.read(uploadTasksProvider.notifier).remove(id);
    setState(() => _attachments.removeWhere((item) => item.id == id));
  }

  void _retryAttachment(String id) {
    for (final item in _attachments) {
      if (item.id != id) continue;
      _startUpload(item);
      return;
    }
  }

  void _showToast(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showAppToast(
      context,
      message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  void _regenerate(AssistantMessage reply) {
    _stopReading();
    unawaited(
      _controller.regenerate(reply, thinking: _thinking, search: _search),
    );
  }

  void _continue(AssistantMessage reply) {
    _stopReading();
    unawaited(
      _controller.continueReply(reply, thinking: _thinking, search: _search),
    );
  }

  Future<bool> _editMessage(UserMessage message, String text) {
    _stopReading();
    return _controller.editMessage(
      message,
      text: text,
      thinking: _thinking,
      search: _search,
    );
  }

  void _selectVersion(String messageId) {
    _stopReading();
    unawaited(_controller.selectVersion(messageId));
  }

  void _stopGeneration() {
    _stopReading();
    _controller.stop();
  }

  /// 配额类上传失败：原因用 Toast 说明，并给出删除旧文件的文档入口。
  void _showQuotaToast(LocalMessage quota) {
    final l10n = AppLocalizations.of(context)!;
    _showToast(
      localMessageText(l10n, quota),
      actionLabel: l10n.uploadDeleteFiles,
      onAction: () =>
          openExternalLink('https://api-docs.deepseek.com/api/delete-file', ''),
    );
  }

  void _setThinking(bool value) {
    setState(() => _thinking = value);
    unawaited(_options.setThinking(value));
  }

  void _setSearch(bool value) {
    setState(() => _search = value);
    unawaited(_options.setSearch(value));
  }

  ChatController get _controller =>
      ref.read(chatControllerProvider(_sessionId!).notifier);

  @override
  Widget build(BuildContext context) {
    final sessionId = _sessionId;
    final state = sessionId == null
        ? const ChatState()
        : ref.watch(chatControllerProvider(sessionId));
    final tasks = ref.watch(uploadTasksProvider);
    // 只订阅按钮相关字段；电平与计时刷新由状态行单独重建（speech.md §7）。
    final speech = ref.watch(
      speechControllerProvider.select(
        (state) => (
          phase: state.phase,
          voiceBusy: state.voiceBusy,
          readingMessageId: state.readingMessageId,
        ),
      ),
    );
    final messages = state.messages;
    final strings = AppLocalizations.of(context)!;
    ref.listen<SpeechState>(speechControllerProvider, (previous, next) {
      if (previous == null || previous.noticeId == next.noticeId) return;
      final voice = next.voiceFailure;
      if (voice != null) {
        final needsSettings = voice == VoiceInputFailure.permissionDenied;
        _showToast(
          voiceInputErrorText(strings, voice),
          actionLabel: needsSettings
              ? strings.settingsOpenSystemSettings
              : null,
          onAction: needsSettings
              ? () => ref.read(microphonePermissionsProvider).openSettings()
              : null,
        );
        return;
      }
      final tts = next.ttsFailure;
      if (tts != null) _showToast(ttsErrorText(strings, tts));
    });
    ref.listen<Map<String, UploadTask>>(uploadTasksProvider, (previous, next) {
      for (final entry in next.entries) {
        final quota = entry.value.quota;
        if (quota == null || previous?[entry.key]?.quota != null) continue;
        _showQuotaToast(quota);
      }
    });
    // 空对话时输入框与问候语居中成组；有消息后回到底部停靠。
    final composer = Composer(
      input: _input,
      inputFocus: _inputFocus,
      busy: state.busy,
      phase: speech.phase,
      thinking: _thinking,
      search: _search,
      attachments: _attachments,
      tasks: tasks,
      onThinkingChanged: _setThinking,
      onSearchChanged: _setSearch,
      onAddAttachment: _addAttachments,
      onRetryAttachment: _retryAttachment,
      onRemoveAttachment: _removeAttachment,
      onSend: _send,
      onStop: _stopGeneration,
      onVoice: () => _speech.toggleVoiceInput(onTranscript: _insertTranscript),
    );
    return Scaffold(
      drawer: widget.drawer,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ChatHeader(
              title: state.title.isEmpty ? strings.untitledChat : state.title,
              onNewChat: widget.onNewChat,
            ),
          ),
          if (state.error != null)
            _ErrorBanner(
              message: localMessageText(strings, state.error!),
              onDismiss: _controller.clearError,
            ),
          Expanded(
            child: messages.isEmpty
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/images/logo.png',
                            width: 32,
                            height: 32,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            strings.chatEmptyTitle,
                            style: TextStyle(
                              fontSize: 24,
                              height: 32 / 24,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      composer,
                    ],
                  )
                : ChatMessageList(
                    messages: messages,
                    versions: state.versions,
                    busy: state.busy,
                    speech: speech,
                    onReadAloud: (reply, text) => _speech.toggleReadAloud(
                      messageId: reply.id,
                      text: text,
                    ),
                    onEdit: state.busy ? null : _editMessage,
                    onSelectVersion: state.busy ? null : _selectVersion,
                    onRegenerate: state.busy ? null : _regenerate,
                    onContinue: state.busy ? null : _continue,
                    onRetryUpload: state.busy
                        ? null
                        : (reply) => _controller.retryUpload(
                            reply,
                            thinking: _thinking,
                            search: _search,
                          ),
                    onStop: _stopGeneration,
                  ),
          ),
          if (messages.isNotEmpty) composer,
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: colors.onErrorContainer),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
              tooltip: l10n.close,
            ),
          ],
        ),
      ),
    );
  }
}

enum _AttachmentSource { photos, files }

/// 附件来源行：图标 + 文案，整行可点（ui.md §1.2 附件来源）。
class _AttachmentSourceRow extends StatelessWidget {
  const _AttachmentSourceRow({
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: colors.mutedForeground),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(fontSize: 15, color: colors.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
