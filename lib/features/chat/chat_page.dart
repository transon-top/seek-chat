import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'attachment_panel.dart';
import 'attachment_rules.dart';
import 'chat_header.dart';
import 'photo_import.dart';
import 'photo_strip.dart';
import '../../shared/error_text.dart';
import '../../shared/logging.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/chat_options_store.dart';
import '../../shared/providers.dart';
import '../../shared/speech/permissions.dart';
import '../../shared/toast.dart';
import '../../shared/widgets/push_menu.dart';
import 'speech/speech_controller.dart';
import 'upload_tasks.dart';
import 'chat_controller.dart';
import 'composer.dart';
import 'markdown_view.dart';
import 'messages_view.dart';

/// 聊天页：顶部栏、可见路径、流式文本、停止、重新生成、续写、搜索与引用。
///
/// 会话为空时停在新对话草稿上；首条消息发出时创建会话（ui.md §5.10）。
/// 侧栏内容由 `app/` 注入，推入式布局见 `shared/widgets/push_menu.dart`。
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
  late final ImagePicker _picker = createImagePicker();
  bool _panelOpen = false;
  String? _sessionId;

  /// 横条转码登记：第二次点击取消，迟到结果作废。
  final PendingPhotoImports _pendingPhotoImports = PendingPhotoImports();

  /// 相机 / 相册 / 文件选择器打开期间不因回到前台刷新横条。
  bool _pickerActive = false;

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
    _inputFocus.addListener(_handleInputFocus);
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
    _deletePhotoDrafts(_attachments);
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
    _deletePhotoDrafts(_attachments);
    _controllerHold?.close();
    unawaited(_speech.stopAll());
    _inputFocus.removeListener(_handleInputFocus);
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
    final hadText = text.trim().isNotEmpty;
    if (!hadText && _attachments.isEmpty) return;
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
    _deletePhotoDrafts(_attachments);
    _input.clear();
    setState(() {
      _attachments.clear();
      // 有文本发送后收起面板；纯附件发送保持展开供继续选照片（ui.md §5.2）。
      if (hadText) _panelOpen = false;
    });
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

  /// 点输入框时收起面板；键盘与面板不同时出现（ui.md §5.2）。
  void _handleInputFocus() {
    if (_inputFocus.hasFocus && _panelOpen) {
      setState(() => _panelOpen = false);
    }
  }

  void _togglePanel() {
    if (_panelOpen) {
      setState(() => _panelOpen = false);
      return;
    }
    _inputFocus.unfocus();
    FocusScope.of(context).unfocus();
    setState(() => _panelOpen = true);
  }

  /// 面板展开时点麦克风：先收面板，再开始语音（ui.md §5.2）。
  void _voice() {
    if (_panelOpen) setState(() => _panelOpen = false);
    _speech.toggleVoiceInput(onTranscript: _insertTranscript);
  }

  Future<void> _takePhoto() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _pickerActive = true);
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (file == null || !mounted) return;
      await _addPickedPhotos([file]);
    } on Object catch (error) {
      debugLog('camera pick failed', error);
      if (mounted) _showToast(l10n.uploadFileStatusFailed);
    } finally {
      if (mounted) setState(() => _pickerActive = false);
    }
  }

  Future<void> _pickPhotos() async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = maxAttachmentCount - _attachments.length;
    if (remaining <= 0) {
      _showToast(l10n.uploadMaxFiles(maxAttachmentCount));
      return;
    }
    setState(() => _pickerActive = true);
    try {
      final files = await _picker.pickMultiImage(limit: remaining);
      if (files.isEmpty || !mounted) return;
      await _addPickedPhotos(files);
    } on Object catch (error) {
      debugLog('photo picker failed', error);
      if (mounted) _showToast(l10n.uploadFileStatusFailed);
    } finally {
      if (mounted) setState(() => _pickerActive = false);
    }
  }

  /// 相机 / 相册产物：嗅探 JPEG 后加入草稿并上传；非 JPEG 提示且不入草稿。
  Future<void> _addPickedPhotos(List<XFile> files) async {
    final l10n = AppLocalizations.of(context)!;
    final drafts = <DraftAttachment>[];
    var unreadable = false;
    for (final file in files) {
      try {
        final draft = draftFromPickedPhoto(file);
        if (draft == null) {
          unreadable = true;
        } else {
          drafts.add(draft);
        }
      } on Object catch (error) {
        debugLog('photo import failed', error);
        unreadable = true;
      }
    }
    if (!mounted) return;
    if (unreadable) _showToast(l10n.photoUnreadable);
    if (drafts.isEmpty) return;

    final error = validateAttachmentSelection(
      files: [
        for (final item in drafts)
          SelectedFile(name: item.name, size: item.size),
      ],
      currentCount: _attachments.length,
    );
    if (error != null) {
      _showToast(localMessageText(l10n, error));
      return;
    }

    _addDrafts(drafts);
  }

  /// 横条缩略图切换选中：选中即转码、追加到草稿末尾并上传；再点即取消
  /// （`attachments.md` §9.2）。
  Future<void> _togglePhotoAsset(PhotoAsset asset) async {
    final l10n = AppLocalizations.of(context)!;
    for (final item in _attachments) {
      if (item.sourceAssetId == asset.id) {
        _removeAttachment(item.id);
        return;
      }
    }
    if (_attachments.length >= maxAttachmentCount) {
      _showToast(l10n.uploadMaxFiles(maxAttachmentCount));
      return;
    }
    final token = _pendingPhotoImports.toggle(asset.id);
    if (token == null) return;
    try {
      final result = await draftFromPhotoAsset(
        asset,
        preferOriginalFile: defaultTargetPlatform == TargetPlatform.iOS,
        outputDir: await getTemporaryDirectory(),
      );
      if (!mounted) return;
      // 转码期间再次点击已取消：迟到结果直接丢弃。
      if (!_pendingPhotoImports.isCurrent(asset.id, token)) return;
      final failure = result.failure;
      if (failure != null) {
        _showToast(
          failure == PhotoImportFailure.tooLarge
              ? l10n.uploadMaxMBSize(maxPhotoSizeMb)
              : l10n.photoUnreadable,
        );
        return;
      }
      final draft = result.draft!;
      if (_attachments.length >= maxAttachmentCount) {
        _showToast(l10n.uploadMaxFiles(maxAttachmentCount));
        return;
      }
      _addDrafts([draft]);
    } on Object catch (error) {
      debugLog('photo strip import failed', error);
      if (mounted) _showToast(l10n.photoUnreadable);
    } finally {
      _pendingPhotoImports.finish(asset.id, token);
    }
  }

  Future<void> _pickFiles() async {
    final l10n = AppLocalizations.of(context)!;
    final List<PlatformFile> files;
    setState(() => _pickerActive = true);
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } on Object {
      if (mounted) _showToast(l10n.uploadFileStatusFailed);
      return;
    } finally {
      if (mounted) setState(() => _pickerActive = false);
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

    _addDrafts(picked);
  }

  /// 横条转码产生的临时文件在移除、发送或销毁时删除；其余草稿原件留给系统清理。
  void _deletePhotoDrafts(Iterable<DraftAttachment> drafts) {
    final paths = [
      for (final item in drafts)
        if (item.sourceAssetId != null) item.path,
    ];
    if (paths.isEmpty) return;
    unawaited(_deleteFiles(paths));
  }

  Future<void> _deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await File(path).delete();
      } on FileSystemException catch (error) {
        debugLog('draft photo cleanup failed', error);
      }
    }
  }

  /// 追加到草稿行末尾并开始上传。
  void _addDrafts(List<DraftAttachment> drafts) {
    setState(() => _attachments.addAll(drafts));
    for (final item in drafts) {
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
    for (final item in _attachments) {
      if (item.id == id) {
        _deletePhotoDrafts([item]);
        break;
      }
    }
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
    // 输入卡空态与有消息状态共用同一实例，始终贴底（ui.md §1.3）。
    final composer = Composer(
      input: _input,
      inputFocus: _inputFocus,
      busy: state.busy,
      phase: speech.phase,
      thinking: _thinking,
      search: _search,
      attachments: _attachments,
      tasks: tasks,
      panelOpen: _panelOpen,
      attachmentPanel: AttachmentPanel(
        attachmentCount: _attachments.length,
        photoStrip: photoStripEnabledFor(defaultTargetPlatform)
            ? PhotoStrip(
                library: ref.watch(photoLibraryProvider),
                selectedAssetIds: {
                  for (final item in _attachments)
                    if (item.sourceAssetId != null) item.sourceAssetId!,
                },
                full: _attachments.length >= maxAttachmentCount,
                reloadOnResume: !_pickerActive,
                onToggle: _togglePhotoAsset,
                onLimitReached: () =>
                    _showToast(strings.uploadMaxFiles(maxAttachmentCount)),
              )
            : null,
        onTakePhoto: _takePhoto,
        onPickPhotos: _pickPhotos,
        onPickFiles: _pickFiles,
        onLimitReached: () =>
            _showToast(strings.uploadMaxFiles(maxAttachmentCount)),
      ),
      onThinkingChanged: _setThinking,
      onSearchChanged: _setSearch,
      onTogglePanel: _togglePanel,
      onRetryAttachment: _retryAttachment,
      onRemoveAttachment: _removeAttachment,
      onSend: _send,
      onStop: _stopGeneration,
      onVoice: _voice,
    );
    // 输入卡始终贴底；空态问候语在顶部栏与输入卡之间居中（ui.md §1.3）。
    return PushMenu(
      menu: widget.drawer ?? const SizedBox.shrink(),
      child: PopScope(
        canPop: !_panelOpen,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && _panelOpen) {
            setState(() => _panelOpen = false);
          }
        },
        child: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: PushMenuSwipeDetector(
                  child: Column(
                    children: [
                      SafeArea(
                        bottom: false,
                        child: ChatHeader(
                          title: state.title.isEmpty
                              ? strings.untitledChat
                              : state.title,
                          onNewChat: widget.onNewChat,
                          inConversation: messages.isNotEmpty,
                        ),
                      ),
                      if (state.error != null)
                        _ErrorBanner(
                          message: localMessageText(strings, state.error!),
                          onDismiss: _controller.clearError,
                        ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 150),
                          child: messages.isEmpty
                              ? const _EmptyGreeting()
                              : ChatMessageList(
                                  // 切换会话时重建状态，初始窗口随之重置。
                                  key: ValueKey(sessionId),
                                  messages: messages,
                                  versions: state.versions,
                                  busy: state.busy,
                                  speech: speech,
                                  onReadAloud: (reply, text) =>
                                      _speech.toggleReadAloud(
                                        messageId: reply.id,
                                        text: text,
                                      ),
                                  onEdit: state.busy ? null : _editMessage,
                                  onSelectVersion: state.busy
                                      ? null
                                      : _selectVersion,
                                  onRegenerate: state.busy
                                      ? null
                                      : _regenerate,
                                  onContinue: state.busy ? null : _continue,
                                  onRetryUpload: state.busy
                                      ? null
                                      : (reply) => _controller.retryUpload(
                                          reply,
                                          thinking: _thinking,
                                          search: _search,
                                        ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              composer,
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态问候语：在剩余区域内垂直居中，剩余高度不足 96 时隐藏（ui.md §1.3）。
class _EmptyGreeting extends StatelessWidget {
  const _EmptyGreeting();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxHeight < 96) return const SizedBox.shrink();
        final strings = AppLocalizations.of(context)!;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
          ),
        );
      },
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
