import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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
import 'speech/recording_overlay.dart';
import 'upload_tasks.dart';
import 'chat_controller.dart';
import 'composer.dart';
import 'markdown_view.dart';
import 'messages_view.dart';

/// ZH
/// 聊天页：顶部栏、可见路径、流式文本、停止、重新生成、续写、搜索与引用。
///
/// 会话为空时停在新对话草稿上；首条消息发出时创建会话（ui.md §5.10）。
/// 侧栏内容由 `app/` 注入，推入式布局见 `shared/widgets/push_menu.dart`。
///
/// EN
/// Chat page: header, visible path, streaming text, stop, regenerate, continue, search and citations.
///
/// Stay on the new-chat draft while empty; create the Session on the first sent message (ui.md §5.10).
/// Sidebar content is injected by `app/`; see `shared/widgets/push_menu.dart` for the push layout.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    this.drawer,
    this.onNewChat,
    this.onSessionCreated,
    this.onSessionDiscarded,
    this.onOpenKeySettings,
    this.focusRequest = 0,
  });

  final String? sessionId;
  final Widget? drawer;
  final VoidCallback? onNewChat;
  final ValueChanged<String>? onSessionCreated;

  /// ZH
  /// 首条消息未发出时回滚刚创建的空会话。
  ///
  /// EN
  /// Roll back the empty Session just created when the first message is not sent.
  final VoidCallback? onSessionDiscarded;

  /// ZH
  /// 打开设置的数据管理页并聚焦 API Key 输入框（由 `app/` 注入接线）。
  ///
  /// EN
  /// Open Settings on the data view with the API Key field focused (wired by `app/`).
  final VoidCallback? onOpenKeySettings;

  /// ZH
  /// 每次递增表示外部要求聚焦输入框（新对话）。
  ///
  /// EN
  /// Each increment asks the composer to take focus (new chat).
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

  /// ZH
  /// 横条转码登记：第二次点击取消，迟到结果作废。
  ///
  /// EN
  /// Strip transcode registry: a second tap cancels; late results are voided.
  final PendingPhotoImports _pendingPhotoImports = PendingPhotoImports();

  /// ZH
  /// 相机 / 相册 / 文件选择器打开期间不因回到前台刷新横条。
  ///
  /// EN
  /// Do not refresh the strip on resume while the camera, photo or file picker is open.
  bool _pickerActive = false;

  /// ZH
  /// 草稿会话创建后，先占住控制器，避免自动销毁丢掉首轮流式状态。
  ///
  /// EN
  /// Hold the controller after the draft Session is created so auto-dispose cannot drop the first stream.
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

  /// ZH
  /// 空回调只用于在页面开始 watch 前钉住 autoDispose 控制器。
  ///
  /// EN
  /// The empty callback only pins the autoDispose controller before the page starts watching.
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

  /// ZH
  /// 转写结果先替换当前选区，再按发送闸门尝试自动发送（`speech.md` §3.4）。
  ///
  /// EN
  /// Replace the selection with the transcript, then try auto-send through the send gate (`speech.md` §3.4).
  Future<VoiceAutoSendOutcome> _insertTranscriptAndSend(String text) async {
    // ZH
    // 麦克风在有文本时隐藏，故插入前非空即转写期间用户手动输入过。
    //
    // EN
    // Mic hides when text exists, so non-empty before insert means the user typed during transcription.
    final typedDuring = _input.value.text.isNotEmpty;
    _input.value = insertTranscript(_input.value, text);
    if (!mounted) return VoiceAutoSendOutcome.notSent;
    final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
    if (!mounted) return VoiceAutoSendOutcome.notSent;
    final blocked = voiceAutoSendBlocker(
      apiKey: apiKey,
      generating:
          _sessionId != null &&
          ref.read(chatControllerProvider(_sessionId!)).busy,
      uploadsDone: allUploadsDone(_attachments, ref.read(uploadTasksProvider)),
      typedDuring: typedDuring,
    );
    if (blocked != null) return blocked;
    return await _send()
        ? VoiceAutoSendOutcome.sent
        : VoiceAutoSendOutcome.failed;
  }

  void _stopReading() {
    unawaited(_speech.stopReadAloud());
  }

  Future<bool> _send() async {
    final text = _input.text;
    final hadText = text.trim().isNotEmpty;
    if (!hadText && _attachments.isEmpty) return false;
    if (!allUploadsDone(_attachments, ref.read(uploadTasksProvider))) {
      return false;
    }
    final l10n = AppLocalizations.of(context)!;
    final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      // ZH
      // 无 Key 不发、不弹 Toast：直达设置的数据管理页，草稿原样保留。
      //
      // EN
      // Without a key: do not send or toast, open Settings on the data view and keep the draft.
      if (mounted) {
        if (widget.onOpenKeySettings != null) {
          _openKeySettings();
        } else {
          _showToast(l10n.errorNoApiKey, tone: AppToastTone.error);
        }
      }
      return false;
    }
    var sessionId = _sessionId;
    var createdHere = false;
    if (sessionId == null) {
      final session = await ref.read(chatRepositoryProvider).createSession();
      if (!mounted) return false;
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
          onSubmitted: () {
            if (!mounted) return;
            _deletePhotoDrafts(_attachments);
            _input.clear();
            setState(() {
              _attachments.clear();
              // ZH
              // 有文本发送后收起面板；纯附件发送保持展开供继续选照片（ui.md §5.2）。
              //
              // EN
              // Close the panel after a text send; attachment-only sends stay open for more photos (ui.md §5.2).
              if (hadText) _panelOpen = false;
            });
          },
        );
    if (!sent) {
      if (createdHere) await _discardEmptySession(sessionId);
      return false;
    }
    return true;
  }

  /// ZH
  /// 请求未发出时不留下空会话；发送失败的空会话直接删除。
  ///
  /// EN
  /// Leave no empty Session when the request is not sent; delete the empty Session on failure.
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

  /// ZH
  /// 点输入框时收起面板；键盘与面板不同时出现（ui.md §5.2）。
  ///
  /// EN
  /// Collapse the panel on composer focus; the keyboard and panel never show together (ui.md §5.2).
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

  /// ZH
  /// 按下麦克风：同步失焦、收键盘与面板，再启动录音（`speech.md` §3.2）。
  ///
  /// EN
  /// Mic press: unfocus and collapse keyboard and panel together, then start recording (`speech.md` §3.2).
  void _voiceStart() {
    _inputFocus.unfocus();
    FocusScope.of(context).unfocus();
    if (_panelOpen) setState(() => _panelOpen = false);
    unawaited(_speech.startFromPress(onTranscript: _insertTranscriptAndSend));
  }

  void _voiceEnd() => _speech.finishFromRelease();

  void _voicePointerCancel() => _speech.cancelFromGesture();

  void _voiceCancelArmed(bool armed) => _speech.setCancelArmed(armed);

  /// ZH
  /// 读屏「取消录音」：丢弃并播报「已取消」。
  ///
  /// EN
  /// Screen reader 'cancel recording': discard and announce 'cancelled'.
  void _voiceCancel() {
    _speech.cancelFromSemantics();
    if (!MediaQuery.supportsAnnounceOf(context)) return;
    final l10n = AppLocalizations.of(context)!;
    unawaited(
      SemanticsService.sendAnnouncement(
        View.of(context),
        l10n.voiceCancelled,
        Directionality.of(context),
      ),
    );
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
      if (mounted) {
        _showToast(l10n.uploadFileStatusFailed, tone: AppToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _pickerActive = false);
    }
  }

  Future<void> _pickPhotos() async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = maxAttachmentCount - _attachments.length;
    if (remaining <= 0) {
      _showToast(
        l10n.uploadMaxFiles(maxAttachmentCount),
        tone: AppToastTone.warning,
      );
      return;
    }
    setState(() => _pickerActive = true);
    try {
      final files = await _picker.pickMultiImage(limit: remaining);
      if (files.isEmpty || !mounted) return;
      await _addPickedPhotos(files);
    } on Object catch (error) {
      debugLog('photo picker failed', error);
      if (mounted) {
        _showToast(l10n.uploadFileStatusFailed, tone: AppToastTone.error);
      }
    } finally {
      if (mounted) setState(() => _pickerActive = false);
    }
  }

  /// ZH
  /// 相机 / 相册产物：嗅探 JPEG 后加入草稿并上传；非 JPEG 提示且不入草稿。
  ///
  /// EN
  /// Camera / gallery output: sniff JPEG, add to drafts and upload; non-JPEG shows a hint and is skipped.
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
    if (unreadable) _showToast(l10n.photoUnreadable, tone: AppToastTone.error);
    if (drafts.isEmpty) return;

    final error = validateAttachmentSelection(
      files: [
        for (final item in drafts)
          SelectedFile(name: item.name, size: item.size),
      ],
      currentCount: _attachments.length,
    );
    if (error != null) {
      _showToast(localMessageText(l10n, error), tone: AppToastTone.warning);
      return;
    }

    _addDrafts(drafts);
  }

  /// ZH
  /// 横条缩略图切换选中：选中即转码、追加到草稿末尾并上传；再点即取消
  /// （`attachments.md` §9.2）。
  ///
  /// EN
  /// Strip tile toggle: selecting transcodes, appends to the Draft Attachment Row, uploads; tapping again
  /// cancels (`attachments.md` §9.2).
  Future<void> _togglePhotoAsset(PhotoAsset asset) async {
    final l10n = AppLocalizations.of(context)!;
    for (final item in _attachments) {
      if (item.sourceAssetId == asset.id) {
        _removeAttachment(item.id);
        return;
      }
    }
    if (_attachments.length >= maxAttachmentCount) {
      _showToast(
        l10n.uploadMaxFiles(maxAttachmentCount),
        tone: AppToastTone.warning,
      );
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
      // ZH
      // 转码期间再次点击已取消：迟到结果直接丢弃。
      //
      // EN
      // Tapped again during transcode, i.e. cancelled: drop the late result.
      if (!_pendingPhotoImports.isCurrent(asset.id, token)) return;
      final failure = result.failure;
      if (failure != null) {
        _showToast(
          failure == PhotoImportFailure.tooLarge
              ? l10n.uploadMaxMBSize(maxPhotoSizeMb)
              : l10n.photoUnreadable,
          tone: failure == PhotoImportFailure.tooLarge
              ? AppToastTone.warning
              : AppToastTone.error,
        );
        return;
      }
      final draft = result.draft!;
      if (_attachments.length >= maxAttachmentCount) {
        _showToast(
          l10n.uploadMaxFiles(maxAttachmentCount),
          tone: AppToastTone.warning,
        );
        return;
      }
      _addDrafts([draft]);
    } on Object catch (error) {
      debugLog('photo strip import failed', error);
      if (mounted) _showToast(l10n.photoUnreadable, tone: AppToastTone.error);
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
      if (mounted) {
        _showToast(l10n.uploadFileStatusFailed, tone: AppToastTone.error);
      }
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
      _showToast(localMessageText(l10n, error), tone: AppToastTone.warning);
      return;
    }

    _addDrafts(picked);
  }

  /// ZH
  /// 横条转码产生的临时文件在移除、发送或销毁时删除；其余草稿原件留给系统清理。
  ///
  /// EN
  /// Delete strip transcode temp files on remove, send or dispose; leave other draft originals to the system.
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

  /// ZH
  /// 追加到草稿行末尾并开始上传。
  ///
  /// EN
  /// Append to the end of the Draft Attachment Row and start uploading.
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

  /// ZH
  /// 收起键盘后打开设置的数据管理页；接线与数据层由 `app/` 注入。
  ///
  /// EN
  /// Dismiss the keyboard, then open Settings on the data view; `app/` injects wiring and data.
  void _openKeySettings() {
    _inputFocus.unfocus();
    FocusScope.of(context).unfocus();
    widget.onOpenKeySettings?.call();
  }

  void _showToast(
    String message, {
    AppToastTone tone = AppToastTone.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    showAppToast(
      context,
      message,
      tone: tone,
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

  /// ZH
  /// 配额类上传失败：原因用 Toast 说明，并给出删除旧文件的文档入口。
  ///
  /// EN
  /// Quota upload failure: explain with a Toast and offer the docs entry for deleting old files.
  void _showQuotaToast(LocalMessage quota) {
    final l10n = AppLocalizations.of(context)!;
    _showToast(
      localMessageText(l10n, quota),
      tone: AppToastTone.warning,
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
    // ZH
    // 只订阅按钮相关字段；电平与计时刷新由状态行单独重建（speech.md §7）。
    //
    // EN
    // Subscribe to button fields only; level and timer updates rebuild the status line alone (speech.md §7).
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
    // ZH
    // 首次读取完成前按「有 Key」渲染，避免提示条闪烁；读取失败按无 Key。
    //
    // EN
    // Treat as "has key" until the first read settles to avoid a flashing prompt; a failed read is no key.
    final hasApiKey = ref.watch(hasApiKeyProvider).value ?? true;
    ref.listen<SpeechState>(speechControllerProvider, (previous, next) {
      if (previous == null || previous.noticeId == next.noticeId) return;
      final voice = next.voiceFailure;
      if (voice != null) {
        if (voice == VoiceInputFailure.empty) {
          showVoiceEmptyToast(context, voiceInputErrorText(strings, voice));
          return;
        }
        final needsSettings = voice == VoiceInputFailure.permissionDenied;
        _showToast(
          voiceInputErrorText(strings, voice),
          tone: voiceInputFailureTone(voice),
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
      if (tts != null) {
        _showToast(ttsErrorText(strings, tts), tone: AppToastTone.error);
      }
    });
    ref.listen<Map<String, UploadTask>>(uploadTasksProvider, (previous, next) {
      for (final entry in next.entries) {
        final quota = entry.value.quota;
        if (quota == null || previous?[entry.key]?.quota != null) continue;
        _showQuotaToast(quota);
      }
    });
    // ZH
    // 输入卡空态与有消息状态共用同一实例，始终贴底（ui.md §1.3）。
    //
    // EN
    // The empty and populated input card share one instance, always sticky bottom (ui.md §1.3).
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
                onLimitReached: () => _showToast(
                  strings.uploadMaxFiles(maxAttachmentCount),
                  tone: AppToastTone.warning,
                ),
              )
            : null,
        onTakePhoto: _takePhoto,
        onPickPhotos: _pickPhotos,
        onPickFiles: _pickFiles,
        onLimitReached: () => _showToast(
          strings.uploadMaxFiles(maxAttachmentCount),
          tone: AppToastTone.warning,
        ),
      ),
      onThinkingChanged: _setThinking,
      onSearchChanged: _setSearch,
      onTogglePanel: _togglePanel,
      onRetryAttachment: _retryAttachment,
      onRemoveAttachment: _removeAttachment,
      onSend: _send,
      onStop: _stopGeneration,
      showKeyPrompt: !hasApiKey,
      onKeyPrompt: _openKeySettings,
      onVoiceStart: _voiceStart,
      onVoiceEnd: _voiceEnd,
      onVoicePointerCancel: _voicePointerCancel,
      onVoiceCancelArmed: _voiceCancelArmed,
      onVoiceCancel: _voiceCancel,
    );
    // ZH
    // 录音 / 识别浮层覆盖输入卡并向上延伸 60% 屏高（ui.md §8.2）。
    //
    // EN
    // The recording / recognition overlay covers the composer and extends 60% of screen height (ui.md §8.2).
    final voiceCancelable = speech.phase.voiceCancelable;
    // ZH
    // 输入卡始终贴底；空态问候语在顶部栏与输入卡之间居中（ui.md §1.3）。
    //
    // EN
    // The composer stays sticky bottom; the empty greeting centers between header and composer (ui.md §1.3).
    return PushMenu(
      menu: widget.drawer ?? const SizedBox.shrink(),
      child: PopScope(
        canPop: !_panelOpen && !voiceCancelable,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (_panelOpen) {
            setState(() => _panelOpen = false);
            return;
          }
          _speech.cancelFromBack();
        },
        child: Scaffold(
          body: Stack(
            children: [
              Column(
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
                                      // ZH
                                      // 切换会话时重建状态，初始窗口随之重置。
                                      //
                                      // EN
                                      // Rebuild state on Session switch, resetting the initial window.
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
                  // ZH
                  // 录音 / 识别期间隐藏输入卡，让浮层渐变铺满底部（参照官方）。
                  //
                  // EN
                  // Hide composer during recording / recognition so overlay fades over bottom (official app).
                  Visibility(
                    visible: !speech.voiceBusy,
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: composer,
                  ),
                ],
              ),
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _RecordingOverlaySlot(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ZH
/// 只在录音相关阶段重建浮层，不触发整页重建（`speech.md` §7）。
///
/// EN
/// Rebuild the overlay only on recording phases, avoiding a full-page rebuild (`speech.md` §7).
class _RecordingOverlaySlot extends ConsumerWidget {
  const _RecordingOverlaySlot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (phase, level) = ref.watch(
      speechControllerProvider.select((state) => (state.phase, state.level)),
    );
    if (!phase.voiceBusy) return const SizedBox.shrink();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: RecordingOverlay(phase: phase, level: level),
    );
  }
}

/// ZH
/// 空态问候语：在剩余区域内垂直居中，剩余高度不足 96 时隐藏（ui.md §1.3）。
///
/// EN
/// Empty greeting: centered vertically in the remaining space; hidden under 96 of height (ui.md §1.3).
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
                color: ShadTheme.of(context).colorScheme.foreground,
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
    final colors = ShadTheme.of(context).colorScheme;
    return ColoredBox(
      color: colors.destructive.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 14,
                  height: 22 / 14,
                  color: colors.destructive,
                ),
              ),
            ),
            Semantics(
              button: true,
              label: l10n.close,
              child: ShadIconButton.ghost(
                onPressed: onDismiss,
                icon: Icon(
                  LucideIcons.x,
                  size: 18,
                  color: colors.destructive,
                ),
                width: 40,
                height: 40,
                padding: EdgeInsets.zero,
                foregroundColor: colors.destructive,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
