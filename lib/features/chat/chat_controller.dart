import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers.dart';
import '../../shared/api/client.dart';
import '../../shared/api/errors.dart';
import '../../shared/api/reply_accumulator.dart';
import '../../shared/api/request.dart';
import '../../shared/api/stream_events.dart';
import '../../shared/data/attachment_store.dart';
import '../../shared/data/chat_repository.dart';
import '../../shared/logging.dart';
import '../../shared/models/latest_reminder.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/prefs/user_metadata_store.dart';
import '../../shared/security/api_key_store.dart';
import 'upload_tasks.dart';

/// ZH
/// 一个会话的可见路径与流式回复状态（`api.md` §6）。
///
/// 流式期间只在内存里合并，终态才写库；同一会话同时只有一个请求。
/// 流式期间持有 keepAlive：离开聊天页不会取消请求，回到同一会话拿到同一个
/// 控制器与内存中的最新回复；结束后释放（architecture.md §2、§3）。
///
/// EN
/// The visible path and streaming reply status of one Session (`api.md` §6).
///
/// Merge in memory while streaming, persist only at the end; one request per
/// Session at a time. Hold keepAlive while streaming: leaving the chat page does
/// not cancel the request; the same Session returns the same controller and live
/// reply; freed after finish (architecture.md §2, §3).
final chatControllerProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatState, String>(ChatController.new);

/// ZH
/// 存活中的会话控制器；App 进入后台时逐个补写流式回复（architecture.md §3）。
///
/// EN
/// Live Session controllers; flush each streaming reply on App background (architecture.md §3).
final activeChatControllersProvider = Provider<Set<ChatController>>(
  (ref) => <ChatController>{},
);

/// ZH
/// 聊天页的可见状态：选中分支的消息、标题、请求闸门与本地错误。
///
/// EN
/// Visible state of the chat page: selected branch messages, title, request gate and local error.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.versions = const {},
    this.title = '',
    this.busy = false,
    this.error,
  });

  static const Object _keepError = Object();

  /// ZH
  /// 选中分支的可见消息；流式回复以内存中的最新状态出现在原位。
  ///
  /// EN
  /// Visible messages of the selected branch; a streaming reply shows in place with its latest state.
  final List<Message> messages;

  /// ZH
  /// 每条消息的兄弟版本；切换器据此显示「第几条 / 共几条」。
  ///
  /// EN
  /// Sibling versions per message; the switcher shows 'n of m' from this.
  final Map<String, MessageVersions> versions;

  final String title;

  /// ZH
  /// 请求进行中（含创建回复与等待首字节）。
  ///
  /// EN
  /// Request in progress (including creating the reply and awaiting the first byte).
  final bool busy;

  /// ZH
  /// 请求未发出或请求前的本地错误；回复级错误在回复的 `error` 字段。
  ///
  /// EN
  /// Local error before or at request start; reply-level errors live in the reply's `error` field.
  final LocalMessage? error;

  ChatState copyWith({
    List<Message>? messages,
    Map<String, MessageVersions>? versions,
    String? title,
    bool? busy,
    Object? error = _keepError,
  }) => ChatState(
    messages: messages ?? this.messages,
    versions: versions ?? this.versions,
    title: title ?? this.title,
    busy: busy ?? this.busy,
    error: identical(error, _keepError) ? this.error : error as LocalMessage?,
  );
}

class ChatController extends Notifier<ChatState> {
  ChatController(this.sessionId);

  final String sessionId;

  /// ZH
  /// 服务端判定 file_id 失效后的自动重传次数（chat-demo 同值）。
  ///
  /// EN
  /// Automatic re-upload attempts after the server reports a stale file_id (same value as chat-demo).
  static const int _fileRetryLimit = 2;
  static const int _fileRetryBaseDelayMs = 1000;

  late final ChatRepository _repository;
  late final DeepSeekApiClient _client;
  late final ApiKeyStore _apiKeyStore;
  late final AttachmentStore _attachmentStore;

  /// ZH
  /// `KeepAliveLink` 未导出，只保存释放回调。
  ///
  /// EN
  /// `KeepAliveLink` is not exported, so only the release callback is kept.
  void Function()? _releaseKeepAlive;
  Completer<void>? _abort;
  bool _stopRequested = false;
  String? _activeReplyId;

  @override
  ChatState build() {
    _repository = ref.read(chatRepositoryProvider);
    _client = ref.read(apiClientProvider);
    _apiKeyStore = ref.read(apiKeyStoreProvider);
    _attachmentStore = ref.read(attachmentStoreProvider);
    final active = ref.read(activeChatControllersProvider)..add(this);
    ref.onDispose(() {
      active.remove(this);
      _abort?.complete();
    });
    return const ChatState();
  }

  Future<void> load() async {
    final session = await _repository.getSession(sessionId);
    final view = await _repository.loadConversation(
      sessionId,
      settleInterrupted: true,
    );
    // ZH
    // 页面可能在读取期间销毁；首次读取也可能晚于请求发出，不覆盖内存状态。
    //
    // EN
    // The page may be disposed during the read; a late first read must not overwrite in-memory state.
    if (!ref.mounted || state.busy) return;
    state = state.copyWith(
      title: session?.title ?? '',
      messages: view.messages,
      versions: view.versions,
    );
  }

  /// ZH
  /// 追加提问并流式生成回复。附件原件在写入数据库前复制到应用支持目录；
  /// 返回是否已创建提问与回复。提问与回复落库后、流开始前调用
  /// [onSubmitted]，界面据此立即清空输入区。
  ///
  /// EN
  /// Append a question and stream a reply; copy attachment originals to app
  /// support before persisting; returns whether the question and reply were
  /// created. [onSubmitted] fires after both rows are persisted and before the
  /// stream starts, so the UI can clear the composer immediately.
  Future<bool> send({
    required String text,
    required bool thinking,
    required bool search,
    List<DraftAttachment> attachments = const [],
    void Function()? onSubmitted,
  }) async {
    if (state.busy) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return false;

    _begin();
    var submitted = false;
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return false;
      if (_cancelled) return false;
      final session = await _repository.getSession(sessionId);
      if (session == null) return false;

      final List<Attachment> stored;
      try {
        stored = await _storeAttachments(attachments);
      } on Object catch (error) {
        state = state.copyWith(
          error: LocalMessage(
            key: LocalMessageKeys.errorSaveAttachmentFailed,
            params: {'error': error.toString()},
          ),
        );
        return false;
      }
      if (_cancelled) return false;

      final question = await _repository.addUserMessage(
        sessionId: sessionId,
        text: trimmed,
        attachments: stored,
      );
      final reply = await _repository.createReply(
        sessionId: sessionId,
        userMessageId: question.id,
        model: ChatModel.deepseekFlash,
        thinking: thinking,
        search: search,
      );
      final view = await _repository.loadConversation(sessionId);
      state = state.copyWith(
        messages: view.messages,
        versions: view.versions,
      );
      submitted = true;
      // ZH
      // 已完成的上传任务只在发送前有用；serverId 已随消息落库。
      //
      // EN
      // Finished upload tasks only matter before send; the serverId is already persisted with the message.
      for (final attachment in stored) {
        ref.read(uploadTasksProvider.notifier).remove(attachment.id);
      }
      onSubmitted?.call();

      await _stream(
        reply: reply,
        accumulator: ReplyAccumulator(),
        apiKey: apiKey,
        questionId: question.id,
        thinking: thinking,
        search: search,
        titleEnabled: state.title.isEmpty,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
    return submitted;
  }

  /// ZH
  /// 在提问下新增回复版本并流式生成，旧回复保留。
  ///
  /// EN
  /// Add a new reply version under the question and stream it; the old reply is kept.
  Future<void> regenerate(
    AssistantMessage reply, {
    required bool thinking,
    required bool search,
  }) async {
    if (state.busy) return;
    final question = _userFor(reply);
    if (question == null) return;

    _begin();
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return;
      if (_cancelled) return;

      final fresh = await _repository.createReply(
        sessionId: sessionId,
        userMessageId: question.id,
        model: ChatModel.deepseekFlash,
        thinking: thinking,
        search: search,
      );
      final view = await _repository.loadConversation(sessionId);
      state = state.copyWith(
        messages: view.messages,
        versions: view.versions,
      );

      await _stream(
        reply: fresh,
        accumulator: ReplyAccumulator(),
        apiKey: apiKey,
        questionId: question.id,
        thinking: thinking,
        search: search,
        titleEnabled: state.title.isEmpty,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// ZH
  /// 编辑可见路径上的提问：新建同父 user 版本并流式生成回复，旧分支保留。
  /// 文本为空时沿用原附件；两者皆空则不提交。
  ///
  /// EN
  /// Edit a visible-path question: create a sibling user version and stream the
  /// reply; keep the old branch. Reuse the original attachments when text is
  /// empty; when both are empty, submit nothing.
  Future<bool> editMessage(
    UserMessage message, {
    required String text,
    required bool thinking,
    required bool search,
  }) async {
    if (state.busy) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty && message.attachments.isEmpty) return false;
    if (!state.messages.any((item) => item.id == message.id)) return false;

    _begin();
    var submitted = false;
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return false;
      if (_cancelled) return false;

      final (question, reply) = await _repository.editUserMessage(
        sessionId: sessionId,
        originalMessageId: message.id,
        text: trimmed,
        model: ChatModel.deepseekFlash,
        thinking: thinking,
        search: search,
      );
      final view = await _repository.loadConversation(sessionId);
      state = state.copyWith(
        messages: view.messages,
        versions: view.versions,
      );
      submitted = true;

      await _stream(
        reply: reply,
        accumulator: ReplyAccumulator(),
        apiKey: apiKey,
        questionId: question.id,
        thinking: thinking,
        search: search,
        titleEnabled: state.title.isEmpty,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
    return submitted;
  }

  /// ZH
  /// 切换到兄弟版本；下游每条分支保留自己的选择（`data-model.md` §3）。
  /// 新分支可能来自上次中断的会话，读取时按 `stopped` 收尾展示。
  ///
  /// EN
  /// Switch to a sibling version; each downstream branch keeps its own selection
  /// (`data-model.md` §3). The new branch may come from an interrupted Session;
  /// show it settled as `stopped` on load.
  Future<void> selectVersion(String messageId) async {
    if (state.busy || !state.versions.containsKey(messageId)) return;
    await _repository.selectVersion(
      sessionId: sessionId,
      messageId: messageId,
    );
    if (!ref.mounted || state.busy) return;
    final view = await _repository.loadConversation(
      sessionId,
      settleInterrupted: true,
    );
    if (!ref.mounted || state.busy) return;
    state = state.copyWith(messages: view.messages, versions: view.versions);
  }

  /// ZH
  /// 续写可见路径末尾的回复；新块追加在原回复之后。缺快照时回退到当前
  /// 开关（`api.md` §2）。
  ///
  /// EN
  /// Continue the reply at the end of the visible path; new blocks append after
  /// that reply. Fall back to the current toggles when the snapshot is missing
  /// (`api.md` §2).
  Future<void> continueReply(
    AssistantMessage reply, {
    required bool thinking,
    required bool search,
  }) async {
    if (state.busy || !canContinueReply(reply)) return;
    if (state.messages.isEmpty || state.messages.last.id != reply.id) return;
    final question = _userFor(reply);
    if (question == null) return;

    _begin();
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return;
      if (_cancelled) return;
      await _repository.beginContinuation(reply.id);
      _replace(_copyReply(reply, status: ReplyStatus.pending));

      await _stream(
        reply: reply,
        accumulator: ReplyAccumulator(
          blocks: reply.blocks,
          usage: reply.usage,
          prefix: reply.prefix,
        ),
        apiKey: apiKey,
        questionId: question.id,
        thinking: reply.thinking ?? thinking,
        search: reply.search ?? search,
        prefix: reply,
        latestReminder: reply.latestReminder,
        generateSnapshot: false,
        titleEnabled: state.title.isEmpty,
        model: reply.model ?? ChatModel.deepseekFlash,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// ZH
  /// 附件补传失败后重试：保留原回复位置，重新补传并请求（`attachments.md` §5）。
  ///
  /// EN
  /// Retry attachment upload failure: keep the reply position, re-upload then request (`attachments.md` §5).
  Future<void> retryUpload(
    AssistantMessage reply, {
    required bool thinking,
    required bool search,
  }) async {
    if (state.busy || reply.error?.kind != ApiErrorKind.upload) return;
    final question = _userFor(reply);
    if (question == null) return;

    _begin();
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return;
      if (_cancelled) return;
      await _repository.beginContinuation(reply.id);
      _replace(
        _copyReply(reply, status: ReplyStatus.pending, clearError: true),
      );

      await _stream(
        reply: reply,
        accumulator: ReplyAccumulator(
          blocks: reply.blocks,
          usage: reply.usage,
          prefix: reply.prefix,
        ),
        apiKey: apiKey,
        questionId: question.id,
        thinking: reply.thinking ?? thinking,
        search: reply.search ?? search,
        titleEnabled: state.title.isEmpty,
        model: reply.model ?? ChatModel.deepseekFlash,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// ZH
  /// 用户停止：保留已收到的块，按 `stopped` 收尾。密钥读取、建行阶段同样
  /// 生效（`api.md` §9.1 的统一取消入口）。
  ///
  /// EN
  /// User stop: keep received blocks and settle as `stopped`. Also applies while
  /// reading the key or creating rows (the unified cancel entry in `api.md` §9.1).
  void stop() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  /// ZH
  /// 应用进入后台时把内存中的流式回复补写一次（`data-model.md` §4）。
  ///
  /// EN
  /// Flush the in-memory streaming reply once when the App enters background (`data-model.md` §4).
  Future<void> flush() async {
    if (!ref.mounted) return;
    final id = _activeReplyId;
    if (id == null) return;
    AssistantMessage? live;
    for (final message in state.messages) {
      if (message.id == id && message is AssistantMessage) live = message;
    }
    if (live == null || !live.isInFlight) return;
    try {
      await _repository.updateReply(
        messageId: live.id,
        status: live.status,
        blocks: live.blocks,
        stopReason: live.stopReason,
        stopDetails: live.stopDetails,
        usage: live.usage,
        error: live.error,
        prefix: live.prefix,
      );
    } on Object catch (error) {
      // ZH
      // 补写失败不阻塞；启动兜底仍会把残留状态置为 stopped。
      //
      // EN
      // A failed flush is non-blocking; the startup fallback still settles leftovers as stopped.
      debugLog('reply flush failed', error);
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  // ZH
  // ------------------------------------------------------------------ 流
  //
  // EN
  // ------------------------------------------------------------------ Stream

  Future<void> _stream({
    required AssistantMessage reply,
    required ReplyAccumulator accumulator,
    required String apiKey,
    required String questionId,
    required bool thinking,
    required bool search,
    required bool titleEnabled,
    AssistantMessage? prefix,
    String? latestReminder,
    bool generateSnapshot = true,
    ChatModel model = ChatModel.deepseekFlash,
  }) async {
    final abort = _abort ?? Completer<void>();
    _activeReplyId = reply.id;
    if (abort.isCompleted) {
      await _finish(reply, accumulator, ReplyStatus.stopped, null);
      return;
    }

    var receivedContent = false;
    Object? failure;
    for (var attempt = 0; ; attempt++) {
      try {
        final prepared = await _prepareRequest(
          replyId: reply.id,
          questionId: questionId,
          apiKey: apiKey,
          thinking: thinking,
          search: search,
          titleEnabled: titleEnabled,
          prefix: prefix,
          latestReminder: latestReminder,
          generateSnapshot: generateSnapshot,
          model: model,
        );
        if (prepared.latestReminder != reply.latestReminder) {
          reply = _copyReply(
            reply,
            status: reply.status,
            latestReminder: prepared.latestReminder,
          );
          _replace(reply);
        }
        if (_stopRequested || abort.isCompleted) break;
        await _consume(
          request: prepared.request,
          reply: reply,
          accumulator: accumulator,
          apiKey: apiKey,
          abort: abort,
          onContent: () => receivedContent = true,
        );
        failure = null;
        break;
      } on _UploadFailure catch (upload) {
        failure = upload;
        break;
      } on Object catch (error) {
        if (_stopRequested || abort.isCompleted) break;
        // ZH
        // 附件失效：清掉 serverId、重新补传后重发。收到过内容块后不自动重发。
        //
        // EN
        // Stale attachment: clear serverId, re-upload, resend. No auto resend once content blocks arrived.
        final canRetry =
            attempt < _fileRetryLimit &&
            !receivedContent &&
            await _reuploadInvalidatedFiles(error, questionId);
        if (!canRetry) {
          failure = error;
          break;
        }
        await _waitForRetry(attempt, abort);
        if (abort.isCompleted) break;
      }
    }

    final stopped = _stopRequested || abort.isCompleted;
    final status = stopped
        ? ReplyStatus.stopped
        : failure == null
        ? ReplyStatus.done
        : ReplyStatus.error;
    ReplyError? replyError;
    if (failure is _UploadFailure) {
      final cause = failure.cause;
      replyError = ReplyError(
        kind: ApiErrorKind.upload,
        message: cause is ApiException ? cause.message : cause.toString(),
        localMessage: uploadErrorMessage(cause),
        retryable: isRetryable(cause),
      );
    } else if (failure != null) {
      replyError = _replyError(failure);
    }
    await _finish(reply, accumulator, status, replyError);
  }

  /// ZH
  /// 建立请求前补齐本轮与历史上下文的 serverId（`attachments.md` §5），
  /// 再用数据库里的最新消息构造请求。新回复在附件补齐后生成并落库本轮
  /// 元信息快照；续写沿用原快照（`user-metadata.md` §4）。
  ///
  /// EN
  /// Fill in serverIds for this round and history context before building the
  /// request (`attachments.md` §5), then build the request from the latest
  /// database messages. New replies generate and persist this round's Latest
  /// Reminder after uploads complete; continuation reuses the prior snapshot
  /// (`user-metadata.md` §4).
  Future<({CreateMessageRequest request, String? latestReminder})>
  _prepareRequest({
    required String replyId,
    required String questionId,
    required String apiKey,
    required bool thinking,
    required bool search,
    required bool titleEnabled,
    AssistantMessage? prefix,
    String? latestReminder,
    required bool generateSnapshot,
    ChatModel model = ChatModel.deepseekFlash,
  }) async {
    await _ensureAttachments(questionId: questionId, apiKey: apiKey);
    var snapshot = latestReminder;
    if (snapshot == null && generateSnapshot) {
      final metadata = ref.read(userMetadataProvider);
      snapshot = buildLatestReminder(
        languageCode: metadata.locale,
        location: metadata.location,
        platform: currentPlatformMarker(),
      );
      await _repository.setLatestReminder(replyId, snapshot);
    }
    final path = await _repository.visiblePath(sessionId);
    final index = path.indexWhere((message) => message.id == questionId);
    if (index < 0) throw StateError('question $questionId not found');
    final question = path[index];
    if (question is! UserMessage) {
      throw StateError('message $questionId is not a user message');
    }
    return (
      request: buildMessageRequest(
        history: path.sublist(0, index),
        question: question,
        thinking: thinking,
        search: search,
        prefix: prefix,
        latestReminder: snapshot,
        titleEnabled: titleEnabled,
        model: model,
      ),
      latestReminder: snapshot,
    );
  }

  /// ZH
  /// 本轮附件并行补传，任一失败则整体失败；历史轮次从新到旧逐张补传，
  /// 失败静默跳过，该附件不进入本次请求。
  ///
  /// EN
  /// Upload this round's attachments in parallel; any failure fails the round.
  /// Upload history rounds newest to oldest, skipping failures silently; those
  /// attachments stay out of this request.
  Future<void> _ensureAttachments({
    required String questionId,
    required String apiKey,
  }) async {
    final path = await _repository.visiblePath(sessionId);
    final index = path.indexWhere((message) => message.id == questionId);
    if (index < 0) return;
    final question = path[index];
    if (question is! UserMessage) return;
    final history = path.sublist(0, index);

    Object? firstError;
    Future<void> uploadQuestionFile(Attachment attachment) async {
      try {
        final serverId = await _ensureServerId(attachment);
        if (serverId != null) await _saveServerId(attachment.id, serverId);
      } on Object catch (error) {
        firstError ??= error;
      }
    }

    await Future.wait([
      for (final attachment in question.attachments)
        if (attachment.serverId == null) uploadQuestionFile(attachment),
    ]);
    if (firstError != null) throw _UploadFailure(firstError!);

    for (final (user, _) in contextRounds(history).toList().reversed) {
      for (final attachment in user.attachments) {
        if (attachment.serverId != null) continue;
        if (_cancelled) return;
        try {
          final serverId = await _ensureServerId(attachment);
          if (serverId != null) await _saveServerId(attachment.id, serverId);
        } on Object {
          // ZH
          // 历史附件补传失败：静默跳过，下次发送再试。
          //
          // EN
          // History attachment re-upload failed: skip silently and retry on the next send.
        }
      }
    }
  }

  /// ZH
  /// 已有 serverId 直接复用；正在上传的等待同一任务；否则按本地原件补传。
  /// 本地也没有原件时返回 null，该附件只展示、不进入请求。
  ///
  /// EN
  /// Reuse an existing serverId; await the same in-flight task; otherwise
  /// re-upload from the local original. Return null when no local original
  /// exists; the attachment is shown but kept out of the request.
  Future<String?> _ensureServerId(Attachment attachment) async {
    final task = ref.read(uploadTasksProvider)[attachment.id];
    if (task != null &&
        task.status == UploadStatus.done &&
        task.serverId != null) {
      return task.serverId;
    }
    final path = await _attachmentStore.absolutePath(attachment.localPath);
    if (path == null) return null;
    return ref
        .read(uploadTasksProvider.notifier)
        .upload(
          id: attachment.id,
          path: path,
          name: attachment.name,
          isImage: attachment.isImage,
        );
  }

  /// ZH
  /// 把补传得到的 serverId 写回附件行与内存中的全部引用。
  ///
  /// EN
  /// Write the re-uploaded serverId back to the attachment row and all in-memory references.
  Future<void> _saveServerId(String attachmentId, String serverId) async {
    await _repository.setAttachmentServerId(attachmentId, serverId);
    _setAttachmentServerId(attachmentId, serverId);
  }

  /// ZH
  /// 服务端判定 file_id 失效时清掉对应附件并丢弃旧任务，下一次补齐会重传。
  /// 报错没点名 file_id 时只重置本次请求用到的附件（提问 + 进入上下文的历史轮次）。
  ///
  /// EN
  /// On a server-side stale file_id, clear those attachments and drop old tasks;
  /// the next fill re-uploads. If no file_id is named, reset only attachments
  /// used here (question and in-context history rounds).
  Future<bool> _reuploadInvalidatedFiles(
    Object error,
    String questionId,
  ) async {
    if (fileErrorCode(error) == null) return false;
    final message = error is ApiException ? error.message : '';
    final mentioned = extractFileIds(message);
    final path = await _repository.visiblePath(sessionId);
    final index = path.indexWhere((item) => item.id == questionId);
    final question = index < 0 ? null : path[index];
    final inRequest = <UserMessage>[
      if (question is UserMessage) question,
      for (final (user, _) in contextRounds(
        index < 0 ? const [] : path.sublist(0, index),
      ))
        user,
    ];
    final targets = mentioned.isNotEmpty
        ? mentioned.toSet()
        : {
            for (final user in inRequest)
              for (final attachment in user.attachments)
                if (attachment.serverId != null) attachment.serverId!,
          };
    if (targets.isEmpty) return false;

    var changed = false;
    for (final message in path) {
      if (message is! UserMessage) continue;
      for (final attachment in message.attachments) {
        final serverId = attachment.serverId;
        if (serverId == null || !targets.contains(serverId)) continue;
        await _repository.setAttachmentServerId(attachment.id, null);
        ref.read(uploadTasksProvider.notifier).remove(attachment.id);
        _setAttachmentServerId(attachment.id, null);
        changed = true;
      }
    }
    return changed;
  }

  Future<void> _waitForRetry(int attempt, Completer<void> abort) async {
    await Future.any([
      Future<void>.delayed(
        Duration(milliseconds: _fileRetryBaseDelayMs * (1 << attempt)),
      ),
      abort.future,
    ]);
  }

  /// ZH
  /// 消费一次流：增量只在内存合并，事件到达时刷新界面。
  ///
  /// EN
  /// Consume one stream: merge deltas in memory only and refresh the UI as events arrive.
  Future<void> _consume({
    required CreateMessageRequest request,
    required AssistantMessage reply,
    required ReplyAccumulator accumulator,
    required String apiKey,
    required Completer<void> abort,
    required void Function() onContent,
  }) async {
    final done = Completer<void>();
    late final StreamSubscription<StreamEvent> subscription;

    void finish() {
      if (!done.isCompleted) done.complete();
    }

    subscription = _client
        .streamMessage(
          request: request,
          apiKey: apiKey,
          abortTrigger: abort.future,
        )
        .listen(
          (event) {
            if (done.isCompleted) return;
            if (event is ContentBlockStart) onContent();
            accumulator.apply(event);
            _replace(_liveReply(reply, accumulator, clearError: true));
            if (event is MessageDelta) _adoptTitle(accumulator);
            if (event is MessageStop) {
              subscription.cancel();
              finish();
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!done.isCompleted) done.completeError(error, stackTrace);
          },
          onDone: finish,
          cancelOnError: true,
        );

    // ZH
    // 本地取消不主动取消订阅：transport 的 abortTrigger 会结束底层流；
    // 提前 cancel 会让生成器在收尾检查里误报 interrupted。
    //
    // EN
    // Local cancel does not cancel the subscription: the transport abortTrigger
    // ends the underlying stream; cancelling early makes the generator falsely
    // report interrupted in its final check.
    unawaited(
      abort.future.then((_) {
        _stopRequested = true;
        finish();
      }),
    );

    await done.future;
  }

  /// ZH
  /// 收尾并落盘；后台补写与终态写入共用。
  ///
  /// EN
  /// Settle and persist; shared by the background flush and terminal writes.
  Future<void> _finish(
    AssistantMessage reply,
    ReplyAccumulator accumulator,
    ReplyStatus status,
    ReplyError? error,
  ) async {
    accumulator.settle(status);
    _replace(
      _liveReply(
        reply,
        accumulator,
        error: error,
        clearError: status != ReplyStatus.error,
      ),
    );
    try {
      await _repository.updateReply(
        messageId: reply.id,
        status: status,
        blocks: accumulator.blocks,
        stopReason: accumulator.stopReason,
        stopDetails: accumulator.stopDetails,
        usage: accumulator.usage,
        error: error,
        prefix: accumulator.prefix,
      );
    } on Object catch (error) {
      debugLog('saving reply failed', error);
      state = state.copyWith(
        error: LocalMessage(
          key: LocalMessageKeys.errorSaveReplyFailed,
          params: {'error': error.toString()},
        ),
      );
    }
  }

  AssistantMessage _liveReply(
    AssistantMessage base,
    ReplyAccumulator accumulator, {
    ReplyError? error,
    bool clearError = false,
  }) => AssistantMessage(
    id: base.id,
    parentId: base.parentId,
    selectedChildId: base.selectedChildId,
    createdAt: base.createdAt,
    status: accumulator.status,
    blocks: List.of(accumulator.blocks),
    model: base.model,
    thinking: base.thinking,
    search: base.search,
    latestReminder: base.latestReminder,
    prefix: accumulator.prefix,
    stopReason: accumulator.stopReason,
    stopDetails: accumulator.stopDetails,
    usage: accumulator.usage,
    error: clearError ? null : error ?? base.error,
  );

  AssistantMessage _copyReply(
    AssistantMessage base, {
    required ReplyStatus status,
    bool clearError = false,
    String? latestReminder,
  }) => AssistantMessage(
    id: base.id,
    parentId: base.parentId,
    selectedChildId: base.selectedChildId,
    createdAt: base.createdAt,
    status: status,
    blocks: base.blocks,
    model: base.model,
    thinking: base.thinking,
    search: base.search,
    latestReminder: latestReminder ?? base.latestReminder,
    prefix: base.prefix,
    stopReason: base.stopReason,
    stopDetails: base.stopDetails,
    usage: base.usage,
    error: clearError ? null : base.error,
  );

  /// ZH
  /// 复制草稿原件到应用支持目录；数据库只存相对路径。
  ///
  /// EN
  /// Copy draft originals to the app support directory; the database stores only relative paths.
  Future<List<Attachment>> _storeAttachments(
    List<DraftAttachment> drafts,
  ) async {
    final stored = <Attachment>[];
    for (final draft in drafts) {
      final localPath = await _attachmentStore.save(draft.id, draft.path);
      stored.add(
        Attachment(
          id: draft.id,
          name: draft.name,
          size: draft.size,
          isImage: draft.isImage,
          mimeType: draft.mimeType,
          localPath: localPath,
          serverId: ref.read(uploadTasksProvider)[draft.id]?.serverId,
        ),
      );
    }
    return stored;
  }

  /// ZH
  /// 同步内存中引用该附件的消息；传 null 表示 serverId 已失效。
  ///
  /// EN
  /// Sync in-memory messages referencing this attachment; null means the serverId is stale.
  void _setAttachmentServerId(String attachmentId, String? serverId) {
    state = state.copyWith(
      messages: [
        for (final message in state.messages)
          if (message is UserMessage &&
              message.attachments.any((item) => item.id == attachmentId))
            message.withAttachments([
              for (final item in message.attachments)
                item.id == attachmentId ? item.withServerId(serverId) : item,
            ])
          else
            message,
      ],
    );
  }

  // ZH
  // ---------------------------------------------------------------- 辅助
  //
  // EN
  // ---------------------------------------------------------------- Helpers

  /// ZH
  /// 自动标题只在标题仍为空、请求未取消且结束原因正常时采纳
  /// （`api.md` §7）。
  ///
  /// EN
  /// Adopt the auto title only when the title is still empty, the request was not
  /// cancelled and the stop reason is normal (`api.md` §7).
  void _adoptTitle(ReplyAccumulator accumulator) {
    if (_stopRequested || _cancelled) return;
    final title = accumulator.title?.trim();
    if (title == null || title.isEmpty || state.title.isNotEmpty) return;
    final reason = accumulator.stopReason;
    if (reason != StopReason.endTurn && reason != StopReason.maxTokens) return;
    state = state.copyWith(title: title);
    unawaited(() async {
      try {
        final session = await _repository.getSession(sessionId);
        if (session != null && session.title.isEmpty) {
          await _repository.renameSession(sessionId, title);
        }
      } on Object catch (error) {
        // ZH
        // 标题写库失败不影响本轮回复。
        //
        // EN
        // A failed title write does not affect this reply.
        debugLog('saving title failed', error);
      }
    }());
  }

  Future<String?> _requireApiKey() async {
    final key = (await _apiKeyStore.read())?.trim();
    if (key != null && key.isNotEmpty) return key;
    state = state.copyWith(
      error: const LocalMessage(key: LocalMessageKeys.errorNoApiKey),
    );
    return null;
  }

  void _begin() {
    _stopRequested = false;
    _abort = Completer<void>();
    _releaseKeepAlive ??= ref.keepAlive().close;
    state = state.copyWith(busy: true, error: null);
  }

  void _end() {
    _abort = null;
    _activeReplyId = null;
    _releaseKeepAlive?.call();
    _releaseKeepAlive = null;
    state = state.copyWith(busy: false);
  }

  bool get _cancelled => _abort?.isCompleted ?? false;

  void _recordError(Object error) {
    if (error is ApiException) {
      state = state.copyWith(
        error: LocalMessage(
          key: localMessageKeyFor(error.condition),
          params: {'detail': error.message},
        ),
      );
      return;
    }
    state = state.copyWith(
      error: LocalMessage(
        key: LocalMessageKeys.apiErrorOther,
        params: {'detail': error.toString()},
      ),
    );
  }

  ReplyError _replyError(Object error) {
    if (error is ApiException) {
      return ReplyError(
        kind: error.kind,
        message: error.message,
        status: error.status,
      );
    }
    return ReplyError(kind: ApiErrorKind.protocol, message: error.toString());
  }

  UserMessage? _userFor(AssistantMessage reply) {
    final parentId = reply.parentId;
    if (parentId == null) return null;
    for (final message in state.messages) {
      if (message.id == parentId && message is UserMessage) return message;
    }
    return null;
  }

  void _replace(Message message) {
    state = state.copyWith(
      messages: [
        for (final existing in state.messages)
          existing.id == message.id ? message : existing,
      ],
    );
  }
}

/// ZH
/// 请求发出前补传附件失败；请求没有发出（`api.md` §5）。
///
/// EN
/// Attachment re-upload failed before the request went out; no request was sent (`api.md` §5).
final class _UploadFailure implements Exception {
  const _UploadFailure(this.cause);

  final Object cause;
}
