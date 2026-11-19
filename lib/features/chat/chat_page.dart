import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:uuid/uuid.dart';

import 'attachment_rules.dart';
import 'chat_header.dart';
import '../../shared/error_text.dart';
import '../../shared/logging.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/chat_options_store.dart';
import '../../shared/providers.dart';
import '../../shared/speech/permissions.dart';
import 'speech/read_aloud_button.dart';
import 'speech/recording_status.dart';
import 'speech/speech_controller.dart';
import 'speech/voice_button.dart';
import 'upload_tasks.dart';
import 'attachments_view.dart';
import 'chat_controller.dart';
import 'markdown_view.dart';
import 'reply_view.dart';

typedef _SpeechView = ({
  SpeechPhase phase,
  bool voiceBusy,
  String? readingMessageId,
});

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
    var sessionId = _sessionId;
    var createdHere = false;
    if (sessionId == null) {
      final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
      if (apiKey == null || apiKey.isEmpty) {
        if (mounted) _showSnackBar(l10n.errorNoApiKey);
        return;
      }
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
      _showSnackBar(l10n.errorNoApiKey);
      return;
    }
    if (!mounted) return;
    final source = await showModalBottomSheet<_AttachmentSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.uploadFromPhotos),
              onTap: () => Navigator.of(context).pop(_AttachmentSource.photos),
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(l10n.uploadFromFiles),
              onTap: () => Navigator.of(context).pop(_AttachmentSource.files),
            ),
          ],
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
      if (mounted) _showSnackBar(l10n.uploadFileStatusFailed);
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
      _showSnackBar(localMessageText(l10n, error));
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

  void _showSnackBar(
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel != null && onAction != null
            ? SnackBarAction(label: actionLabel, onPressed: onAction)
            : null,
      ),
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

  /// 配额类上传失败：原因用 SnackBar 说明，并给出删除旧文件的文档入口。
  void _showQuotaSnackBar(LocalMessage quota) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localMessageText(l10n, quota)),
        action: SnackBarAction(
          label: l10n.uploadDeleteFiles,
          onPressed: () => openExternalLink(
            'https://api-docs.deepseek.com/api/delete-file',
            '',
          ),
        ),
      ),
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
        _showSnackBar(
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
      if (tts != null) _showSnackBar(ttsErrorText(strings, tts));
    });
    ref.listen<Map<String, UploadTask>>(uploadTasksProvider, (previous, next) {
      for (final entry in next.entries) {
        final quota = entry.value.quota;
        if (quota == null || previous?[entry.key]?.quota != null) continue;
        _showQuotaSnackBar(quota);
      }
    });
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
                ? Center(
                    child: Text(
                      strings.chatEmptyTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        height: 28 / 20,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final position = messages.length - 1 - index;
                      return _MessageView(
                        key: ValueKey(messages[position].id),
                        message: messages[position],
                        versions: state.versions[messages[position].id],
                        isLast: position == messages.length - 1,
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
                      );
                    },
                  ),
          ),
          _Composer(
            input: _input,
            inputFocus: _inputFocus,
            busy: state.busy,
            speech: speech,
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
            onVoice: () =>
                _speech.toggleVoiceInput(onTranscript: _insertTranscript),
          ),
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

class _MessageView extends StatelessWidget {
  const _MessageView({
    super.key,
    required this.message,
    required this.versions,
    required this.isLast,
    required this.busy,
    required this.speech,
    required this.onReadAloud,
    required this.onEdit,
    required this.onSelectVersion,
    required this.onRegenerate,
    required this.onContinue,
    required this.onRetryUpload,
  });

  final Message message;
  final MessageVersions? versions;
  final bool isLast;
  final bool busy;
  final _SpeechView speech;
  final void Function(AssistantMessage reply, String text)? onReadAloud;
  final Future<bool> Function(UserMessage message, String text)? onEdit;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    if (message is UserMessage) {
      return _UserMessageView(
        message: message,
        versions: versions,
        onEdit: onEdit,
        onSelectVersion: onSelectVersion,
      );
    }
    if (message is! AssistantMessage) return const SizedBox.shrink();
    return _ReplyView(
      reply: message,
      versions: versions,
      isLast: isLast,
      busy: busy,
      speech: speech,
      onReadAloud: onReadAloud,
      onSelectVersion: onSelectVersion,
      onRegenerate: onRegenerate,
      onContinue: onContinue,
      onRetryUpload: onRetryUpload,
    );
  }
}

/// 用户提问：气泡、附件、编辑入口与版本切换；编辑时就地换成输入框。
class _UserMessageView extends StatefulWidget {
  const _UserMessageView({
    required this.message,
    required this.versions,
    required this.onEdit,
    required this.onSelectVersion,
  });

  final UserMessage message;
  final MessageVersions? versions;
  final Future<bool> Function(UserMessage message, String text)? onEdit;
  final ValueChanged<String>? onSelectVersion;

  @override
  State<_UserMessageView> createState() => _UserMessageViewState();
}

class _UserMessageViewState extends State<_UserMessageView> {
  late final TextEditingController _draft = TextEditingController(
    text: widget.message.text,
  );
  bool _editing = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _startEditing() {
    _draft.text = widget.message.text;
    setState(() => _editing = true);
  }

  Future<void> _submit() async {
    final onEdit = widget.onEdit;
    if (onEdit == null) return;
    final text = _draft.text;
    if (text.trim().isEmpty && widget.message.attachments.isEmpty) return;
    if (await onEdit(widget.message, text) && mounted) {
      setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context)!;
    final message = widget.message;
    final versions = widget.versions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (message.attachments.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MessageAttachments(attachments: message.attachments),
          ),
        if (_editing)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: colors.outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                TextField(
                  key: const Key('edit-input'),
                  controller: _draft,
                  autofocus: true,
                  enabled: widget.onEdit != null,
                  minLines: 1,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: strings.composerHint,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      key: const Key('edit-cancel'),
                      onPressed: () => setState(() => _editing = false),
                      child: Text(strings.cancel),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _draft,
                      builder: (context, value, _) {
                        final canSend =
                            widget.onEdit != null &&
                            (value.text.trim().isNotEmpty ||
                                message.attachments.isNotEmpty);
                        return FilledButton(
                          key: const Key('edit-send'),
                          onPressed: canSend ? _submit : null,
                          child: Text(strings.send),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          )
        else ...[
          if (message.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                message.text,
                style: TextStyle(color: colors.onPrimaryContainer),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (versions != null && versions.hasMultiple)
                _VersionSwitcher(
                  versions: versions,
                  onSelect: widget.onSelectVersion,
                ),
              if (widget.onEdit != null)
                IconButton(
                  key: ValueKey('edit-message-${message.id}'),
                  onPressed: _startEditing,
                  tooltip: strings.editMessage,
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 兄弟版本切换：`第几条 / 共几条`，两端箭头各切一条。
class _VersionSwitcher extends StatelessWidget {
  const _VersionSwitcher({required this.versions, required this.onSelect});

  final MessageVersions versions;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final previous = versions.previousId;
    final next = versions.nextId;
    return Semantics(
      label: strings.messageVersions,
      container: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onSelect != null && previous != null
                ? () => onSelect!(previous)
                : null,
            tooltip: strings.previousVersion,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${versions.index + 1} / ${versions.ids.length}',
            style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
          ),
          IconButton(
            onPressed: onSelect != null && next != null
                ? () => onSelect!(next)
                : null,
            tooltip: strings.nextVersion,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _ReplyView extends StatelessWidget {
  const _ReplyView({
    required this.reply,
    required this.versions,
    required this.isLast,
    required this.busy,
    required this.speech,
    required this.onReadAloud,
    required this.onSelectVersion,
    required this.onRegenerate,
    required this.onContinue,
    required this.onRetryUpload,
  });

  final AssistantMessage reply;
  final MessageVersions? versions;
  final bool isLast;
  final bool busy;
  final _SpeechView speech;
  final void Function(AssistantMessage reply, String text)? onReadAloud;
  final ValueChanged<String>? onSelectVersion;
  final ValueChanged<AssistantMessage>? onRegenerate;
  final ValueChanged<AssistantMessage>? onContinue;
  final ValueChanged<AssistantMessage>? onRetryUpload;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final strings = AppLocalizations.of(context)!;
    final view = buildReplyView(reply, streaming: reply.isInFlight);
    final refused = reply.stopReason == StopReason.refusal;
    final refusal = refusalText(strings, reply);
    final continueEnabled =
        isLast && !busy && canContinueReply(reply) && onContinue != null;
    // 朗读条件：不在生成中、非拒答、正文非空（`speech.md` §2.2）。
    final answerText = view.answer?.text.trim() ?? '';
    final canReadAloud = !reply.isInFlight && !refused && answerText.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!refused) _ReplyArea(reply: reply, view: view),
          if (!refused && view.answer != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MarkdownView(
                text: view.answer!.markdown,
                streaming: reply.isInFlight,
                sources: view.sources,
              ),
            ),
          if (reply.status == ReplyStatus.error)
            Row(
              children: [
                Expanded(
                  child: Text(
                    strings.replyFailed(
                      reply.error == null
                          ? apiErrorText(strings, ApiErrorCondition.other)
                          : replyErrorText(strings, reply.error!),
                    ),
                    style: TextStyle(color: colors.error),
                  ),
                ),
                if (reply.error?.kind == ApiErrorKind.upload &&
                    reply.error?.retryable == true &&
                    onRetryUpload != null)
                  TextButton(
                    onPressed: busy ? null : () => onRetryUpload!(reply),
                    child: Text(strings.retry),
                  ),
              ],
            ),
          if (refusal != null && reply.status != ReplyStatus.error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: MarkdownView(text: refusal),
            ),
          if (!refused && !reply.isInFlight && view.searchResults.isNotEmpty)
            _SearchSummary(sources: view.searchResults),
          if (reply.isInFlight)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Row(
            children: [
              if (!reply.isInFlight &&
                  versions != null &&
                  versions!.hasMultiple)
                _VersionSwitcher(
                  versions: versions!,
                  onSelect: onSelectVersion,
                ),
              if (canReadAloud)
                ReadAloudButton(
                  phase: speech.phase,
                  active: speech.readingMessageId == reply.id,
                  enabled: !speech.voiceBusy && onReadAloud != null,
                  onPressed: () => onReadAloud!(reply, answerText),
                ),
              IconButton(
                onPressed: busy || refused || onRegenerate == null
                    ? null
                    : () => onRegenerate!(reply),
                icon: const Icon(Icons.refresh),
                tooltip: strings.regenerate,
              ),
              if (isLast && canContinueReply(reply))
                IconButton(
                  onPressed: continueEnabled ? () => onContinue!(reply) : null,
                  icon: const Icon(Icons.play_arrow),
                  tooltip: strings.continueGeneration,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 思考与工具步骤的时间线；开启深度思考时带可折叠标题。
class _ReplyArea extends StatefulWidget {
  const _ReplyArea({required this.reply, required this.view});

  final AssistantMessage reply;
  final ReplyView view;

  @override
  State<_ReplyArea> createState() => _ReplyAreaState();
}

class _ReplyAreaState extends State<_ReplyArea> {
  bool _open = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_ReplyArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 标题与思考用时每秒刷新；有正文后不再计时。
  void _syncTicker() {
    final active = widget.reply.isInFlight && widget.view.answer == null;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reply = widget.reply;
    final view = widget.view;
    final streaming = reply.isInFlight;
    final thinking =
        reply.thinking ?? view.steps.any((step) => step is ThinkingStep);
    final title = thinking ? _areaTitle(l10n) : null;
    if (view.steps.isEmpty && title == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title)),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        if (title == null || _open)
          for (var index = 0; index < view.steps.length; index++)
            _StepItem(
              step: view.steps[index],
              sources: view.sources,
              searchResults: view.searchResults,
              streaming: streaming,
              replyStatus: reply.status,
              isLast: index == view.steps.length - 1,
            ),
      ],
    );
  }

  String _areaTitle(AppLocalizations l10n) {
    final view = widget.view;
    if (view.answer != null) {
      final seconds = replyThinkingSeconds(widget.reply);
      return seconds == null
          ? l10n.deepThinking
          : l10n.thoughtForSeconds(seconds);
    }
    if (!widget.reply.isInFlight) return l10n.stopped;
    final last = view.steps.isEmpty ? null : view.steps.last;
    if (last is SearchStep && last.status == ToolStatus.wip) {
      return isImageSearchKind(last.kind)
          ? l10n.imageSearching
          : l10n.searching;
    }
    if ((last is OpenStep &&
            last.pages.any((page) => page.status == ToolStatus.wip)) ||
        (last is FindStep &&
            last.patterns.any((item) => item.status == ToolStatus.wip))) {
      return l10n.browsingWeb;
    }
    if (last is ReadLinkStep &&
        last.links.any((link) => link.status == ToolStatus.wip)) {
      return l10n.reading;
    }
    return l10n.thinking;
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.step,
    required this.sources,
    required this.searchResults,
    required this.streaming,
    required this.replyStatus,
    required this.isLast,
  });

  final ReplyStep step;
  final List<Source> sources;
  final List<Source> searchResults;
  final bool streaming;
  final ReplyStatus replyStatus;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    if (step is ThinkingStep) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MarkdownView(
          text: step.blocks.map((block) => block.thinking).join(),
          streaming: streaming && isLast,
          dense: true,
          disableLinks: true,
        ),
      );
    }
    if (step is PreambleStep) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: MarkdownView(
          text: step.markdown,
          streaming: streaming && isLast,
          sources: sources,
          dense: true,
        ),
      );
    }
    if (step is SearchStep) {
      return _SearchRow(
        step: step,
        searchResults: searchResults,
        streaming: streaming,
        replyStatus: replyStatus,
      );
    }
    if (step is OpenStep) {
      return _OpenRow(step: step, searchResults: searchResults);
    }
    if (step is FindStep) {
      return _FindRow(step: step);
    }
    if (step is ReadLinkStep) {
      return _ReadLinkRow(step: step);
    }
    return const SizedBox.shrink();
  }
}

class _SearchRow extends StatefulWidget {
  const _SearchRow({
    required this.step,
    required this.searchResults,
    required this.streaming,
    required this.replyStatus,
  });

  final SearchStep step;
  final List<Source> searchResults;
  final bool streaming;
  final ReplyStatus replyStatus;

  @override
  State<_SearchRow> createState() => _SearchRowState();
}

class _SearchRowState extends State<_SearchRow> {
  Timer? _ticker;
  int _tick = 0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(_SearchRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// 进行中且有多条查询词时每 2 秒轮播一条。
  void _syncTicker() {
    final active =
        widget.step.status == ToolStatus.wip && widget.step.queries.length > 1;
    if (active && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 2), (_) {
        if (mounted) setState(() => _tick++);
      });
    } else if (!active) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final step = widget.step;
    final failed = step.status == ToolStatus.failed;
    final interrupted =
        failed &&
        !widget.streaming &&
        widget.replyStatus == ReplyStatus.stopped;
    final clickable = step.status != ToolStatus.wip && step.results.isNotEmpty;
    final style = TextStyle(color: colors.onSurfaceVariant);
    final Widget text;
    if (step.status == ToolStatus.wip) {
      if (step.queries.isNotEmpty) {
        text = Text(
          l10n.searchingQuery(step.queries[_tick % step.queries.length]),
          style: style,
        );
      } else {
        text = Text(
          isImageSearchKind(step.kind)
              ? l10n.imageSearching
              : l10n.searchingDots,
          style: style,
        );
      }
    } else if (interrupted) {
      text = Text(l10n.searchStopped, style: style);
    } else if (failed) {
      text = Text(l10n.searchUnavailable, style: style);
    } else if (step.results.isEmpty) {
      text = Text(
        isDeepSearchKind(step.kind)
            ? l10n.noSuitableResults
            : l10n.noRelevantResults,
        style: style,
      );
    } else if (isDeepSearchKind(step.kind)) {
      text = Text(l10n.searchedPages(step.results.length), style: style);
    } else {
      text = Text(l10n.readPages(step.results.length), style: style);
    }

    return InkWell(
      onTap: clickable
          ? () => _showSourcesSheet(context, widget.searchResults)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              failed ? Icons.search_off : Icons.search,
              size: 16,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(child: text),
            if (step.status != ToolStatus.wip && step.results.isNotEmpty)
              _SiteThumbnails(sources: step.results),
          ],
        ),
      ),
    );
  }
}

class _OpenRow extends StatelessWidget {
  const _OpenRow({required this.step, required this.searchResults});

  final OpenStep step;
  final List<Source> searchResults;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final allFailed = step.pages.every(
      (page) => page.status == ToolStatus.failed,
    );
    return _ToolRow(
      icon: Icons.public,
      child: allFailed
          ? Text(
              l10n.browsePageFailed,
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.browsingPages(step.pages.length),
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                for (final page in step.pages.take(5))
                  _PageLink(page: page, failedTip: l10n.browseFailed),
                if (step.pages.length > 5)
                  InkWell(
                    onTap: () => _showSourcesSheet(context, searchResults),
                    child: Text(
                      l10n.viewAll,
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _FindRow extends StatelessWidget {
  const _FindRow({required this.step});

  final FindStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final allFailed = step.patterns.every(
      (item) => item.status == ToolStatus.failed,
    );
    return _ToolRow(
      icon: Icons.public,
      child: allFailed
          ? Text(
              l10n.findFailed,
              style: TextStyle(color: colors.onSurfaceVariant),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.findKeywords,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                for (final item in step.patterns) _FindChip(item: item),
              ],
            ),
    );
  }
}

class _ReadLinkRow extends StatelessWidget {
  const _ReadLinkRow({required this.step});

  final ReadLinkStep step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return _ToolRow(
      icon: Icons.link,
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(l10n.reading, style: TextStyle(color: colors.onSurfaceVariant)),
          for (final link in step.links) _PageLink(page: link),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _PageLink extends StatelessWidget {
  const _PageLink({required this.page, this.failedTip});

  final PageItem page;
  final String? failedTip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    if (page.status == ToolStatus.failed) {
      return Tooltip(
        message: failedTip ?? l10n.browseFailed,
        child: Text(page.title, style: TextStyle(color: colors.outline)),
      );
    }
    return InkWell(
      onTap: () => openExternalLink(page.url, page.title),
      child: Text(page.title, style: TextStyle(color: colors.primary)),
    );
  }
}

class _FindChip extends StatelessWidget {
  const _FindChip({required this.item});

  final FindItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final failed = item.status == ToolStatus.failed;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == ToolStatus.done)
            Icon(Icons.check, size: 12, color: colors.onSurfaceVariant)
          else if (failed)
            Icon(Icons.close, size: 12, color: colors.onSurfaceVariant),
          if (item.status != ToolStatus.wip) const SizedBox(width: 2),
          Text(item.pattern, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
    if (!failed) return chip;
    return Tooltip(message: l10n.noMatchingContent, child: chip);
  }
}

/// 「N 个网页」胶囊：回复完成后显示，点击打开同一个抽屉。
class _SearchSummary extends StatelessWidget {
  const _SearchSummary({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => _showSourcesSheet(context, sources),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SiteThumbnails(sources: sources),
              const SizedBox(width: 6),
              Text(
                l10n.pagesCount(sources.length),
                style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteThumbnails extends StatelessWidget {
  const _SiteThumbnails({required this.sources});

  final List<Source> sources;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final source in sources.take(4))
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: _SiteIcon(url: source.siteIcon),
          ),
      ],
    );
  }
}

class _SiteIcon extends StatelessWidget {
  const _SiteIcon({required this.url, this.size = 16});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final icon = Icon(
      Icons.link,
      size: size * 0.75,
      color: colors.onSurfaceVariant,
    );
    final uri = url == null ? null : webUri(url!);
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: uri == null
            ? ColoredBox(
                color: colors.surfaceContainerHighest,
                child: Center(child: icon),
              )
            : Image.network(
                uri.toString(),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : ColoredBox(color: colors.surfaceContainerHighest),
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Center(child: icon),
                ),
              ),
      ),
    );
  }
}

Future<void> _showSourcesSheet(BuildContext context, List<Source> sources) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                AppLocalizations.of(context)!.searchResults,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sources.length,
                itemBuilder: (context, index) =>
                    _SourceCard(source: sources[index]),
                separatorBuilder: (context, index) => const SizedBox(height: 8),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 来源卡片：站点图标与名称、日期、标题、摘要（`search.md` §6.1）。
class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.source});

  final Source source;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final date = _displayDate(source.publishedAt);
    final metaStyle = TextStyle(color: colors.onSurfaceVariant, fontSize: 12);
    return InkWell(
      onTap: () => openExternalLink(source.url, source.title),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _SiteIcon(url: source.siteIcon, size: 14),
                const SizedBox(width: 4),
                if (source.siteName.isNotEmpty)
                  Text(source.siteName, style: metaStyle),
                if (source.siteName.isNotEmpty && date.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text('·', style: metaStyle),
                  ),
                if (date.isNotEmpty) Text(date, style: metaStyle),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              source.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (source.snippet != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  source.snippet!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _displayDate(String? value) {
  if (value == null || value.isEmpty) return '';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)}';
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.input,
    required this.inputFocus,
    required this.busy,
    required this.speech,
    required this.thinking,
    required this.search,
    required this.attachments,
    required this.tasks,
    required this.onThinkingChanged,
    required this.onSearchChanged,
    required this.onAddAttachment,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onSend,
    required this.onStop,
    required this.onVoice,
  });

  final TextEditingController input;
  final FocusNode inputFocus;
  final bool busy;
  final _SpeechView speech;
  final bool thinking;
  final bool search;
  final List<DraftAttachment> attachments;
  final Map<String, UploadTask> tasks;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onSearchChanged;
  final VoidCallback onAddAttachment;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final ready = allUploadsDone(attachments, tasks);
    final voiceBusy = speech.voiceBusy;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SpeechStatus(),
            DraftAttachmentStrip(
              attachments: attachments,
              tasks: tasks,
              onRetry: onRetryAttachment,
              onRemove: onRemoveAttachment,
            ),
            Row(
              children: [
                FilterChip(
                  label: Text(l10n.deepThinking),
                  selected: thinking,
                  onSelected: onThinkingChanged,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(l10n.smartSearch),
                  selected: search,
                  onSelected: onSearchChanged,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: busy || voiceBusy ? null : onAddAttachment,
                  icon: const Icon(Icons.attach_file),
                  tooltip: l10n.uploadFile,
                ),
                Expanded(
                  child: TextField(
                    controller: input,
                    focusNode: inputFocus,
                    minLines: 1,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: l10n.composerHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                VoiceButton(phase: speech.phase, onPressed: onVoice),
                const SizedBox(width: 4),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: input,
                  builder: (context, value, child) {
                    final canSend =
                        !busy &&
                        !voiceBusy &&
                        ready &&
                        (value.text.trim().isNotEmpty ||
                            attachments.isNotEmpty);
                    return IconButton.filled(
                      onPressed: busy ? onStop : (canSend ? onSend : null),
                      icon: Icon(busy ? Icons.stop : Icons.send),
                      tooltip: busy ? l10n.stop : l10n.send,
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _AttachmentSource { photos, files }

/// 录音计时与电平只重建这一行，不触发整页重建（`speech.md` §7）。
class _SpeechStatus extends ConsumerWidget {
  const _SpeechStatus();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(
      speechControllerProvider.select(
        (state) => (
          phase: state.phase,
          seconds: state.recordingSeconds,
          level: state.level,
        ),
      ),
    );
    return RecordingStatus(
      phase: status.phase,
      seconds: status.seconds,
      level: status.level,
    );
  }
}
