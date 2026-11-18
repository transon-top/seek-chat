import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/providers.dart';
import '../../shared/api/client.dart';
import '../../shared/api/errors.dart';
import '../../shared/api/reply_accumulator.dart';
import '../../shared/api/request.dart';
import '../../shared/api/stream_events.dart';
import '../../shared/data/chat_repository.dart';
import '../../shared/logging.dart';
import '../../shared/models/reply_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/security/api_key_store.dart';

/// 一个会话的可见路径与流式回复状态（`api.md` §6）。
///
/// 流式期间只在内存里合并，终态才写库；同一会话同时只有一个请求。
/// 流式期间持有 keepAlive：离开聊天页不会取消请求，回到同一会话拿到同一个
/// 控制器与内存中的最新回复；结束后释放（architecture.md §2、§3）。
final chatControllerProvider = NotifierProvider.autoDispose
    .family<ChatController, ChatState, String>(ChatController.new);

/// 存活中的会话控制器；App 进入后台时逐个补写流式回复（architecture.md §3）。
final activeChatControllersProvider = Provider<Set<ChatController>>(
  (ref) => <ChatController>{},
);

/// 聊天页的可见状态：选中分支的消息、标题、请求闸门与本地错误。
class ChatState {
  const ChatState({
    this.messages = const [],
    this.title = '',
    this.busy = false,
    this.error,
  });

  static const Object _keepError = Object();

  /// 选中分支的可见消息；流式回复以内存中的最新状态出现在原位。
  final List<Message> messages;

  final String title;

  /// 请求进行中（含创建回复与等待首字节）。
  final bool busy;

  /// 请求未发出或请求前的本地错误；回复级错误在回复的 `error` 字段。
  final LocalMessage? error;

  ChatState copyWith({
    List<Message>? messages,
    String? title,
    bool? busy,
    Object? error = _keepError,
  }) => ChatState(
    messages: messages ?? this.messages,
    title: title ?? this.title,
    busy: busy ?? this.busy,
    error: identical(error, _keepError) ? this.error : error as LocalMessage?,
  );
}

class ChatController extends Notifier<ChatState> {
  ChatController(this.sessionId);

  final String sessionId;

  late final ChatRepository _repository;
  late final DeepSeekApiClient _client;
  late final ApiKeyStore _apiKeyStore;

  /// `KeepAliveLink` 未导出，只保存释放回调。
  void Function()? _releaseKeepAlive;
  Completer<void>? _abort;
  bool _stopRequested = false;
  String? _activeReplyId;

  @override
  ChatState build() {
    _repository = ref.read(chatRepositoryProvider);
    _client = ref.read(apiClientProvider);
    _apiKeyStore = ref.read(apiKeyStoreProvider);
    final active = ref.read(activeChatControllersProvider)..add(this);
    ref.onDispose(() {
      active.remove(this);
      _abort?.complete();
    });
    return const ChatState();
  }

  Future<void> load() async {
    final session = await _repository.getSession(sessionId);
    final messages = await _repository.loadMessagesForDisplay(sessionId);
    // 页面可能在读取期间销毁；首次读取也可能晚于请求发出，不覆盖内存状态。
    if (!ref.mounted || state.busy) return;
    state = state.copyWith(title: session?.title ?? '', messages: messages);
  }

  /// 追加提问并流式生成回复。
  Future<void> send({
    required String text,
    required bool thinking,
    required bool search,
  }) async {
    if (state.busy) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _begin();
    try {
      final apiKey = await _requireApiKey();
      if (apiKey == null) return;
      if (_cancelled) return;
      final session = await _repository.getSession(sessionId);
      if (session == null) return;

      final history = await _repository.visiblePath(sessionId);
      if (_cancelled) return;
      final question = await _repository.addUserMessage(
        sessionId: sessionId,
        text: trimmed,
      );
      final reply = await _repository.createReply(
        sessionId: sessionId,
        userMessageId: question.id,
        model: ChatModel.deepseekFlash,
        thinking: thinking,
        search: search,
      );
      state = state.copyWith(messages: [...history, question, reply]);

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: thinking,
          search: search,
          titleEnabled: state.title.isEmpty,
        ),
        reply: reply,
        accumulator: ReplyAccumulator(),
        apiKey: apiKey,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// 在提问下新增回复版本并流式生成，旧回复保留。
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
      final history = _historyBefore(question.id);

      final fresh = await _repository.createReply(
        sessionId: sessionId,
        userMessageId: question.id,
        model: ChatModel.deepseekFlash,
        thinking: thinking,
        search: search,
      );
      state = state.copyWith(
        messages: await _repository.visiblePath(sessionId),
      );

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: thinking,
          search: search,
          titleEnabled: state.title.isEmpty,
        ),
        reply: fresh,
        accumulator: ReplyAccumulator(),
        apiKey: apiKey,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// 续写可见路径末尾的回复；新块追加在原回复之后。缺快照时回退到当前
  /// 开关（`api.md` §2）。
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
      final history = _historyBefore(question.id);
      await _repository.beginContinuation(reply.id);
      _replace(_copyReply(reply, status: ReplyStatus.pending));

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: reply.thinking ?? thinking,
          search: reply.search ?? search,
          prefix: reply,
          latestReminder: reply.latestReminder,
          titleEnabled: state.title.isEmpty,
          model: reply.model ?? ChatModel.deepseekFlash,
        ),
        reply: reply,
        accumulator: ReplyAccumulator(
          blocks: reply.blocks,
          usage: reply.usage,
          prefix: reply.prefix,
        ),
        apiKey: apiKey,
      );
    } on Object catch (error) {
      _recordError(error);
    } finally {
      _end();
    }
  }

  /// 用户停止：保留已收到的块，按 `stopped` 收尾。密钥读取、建行阶段同样
  /// 生效（`api.md` §9.1 的统一取消入口）。
  void stop() {
    final abort = _abort;
    if (abort != null && !abort.isCompleted) abort.complete();
  }

  /// 应用进入后台时把内存中的流式回复补写一次（`data-model.md` §4）。
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
      // 补写失败不阻塞；启动兜底仍会把残留状态置为 stopped。
      debugLog('reply flush failed', error);
    }
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(error: null);
  }

  // ------------------------------------------------------------------ 流

  Future<void> _stream({
    required CreateMessageRequest request,
    required AssistantMessage reply,
    required ReplyAccumulator accumulator,
    required String apiKey,
  }) async {
    final abort = _abort ?? Completer<void>();
    _activeReplyId = reply.id;
    if (abort.isCompleted) {
      await _finish(reply, accumulator, ReplyStatus.stopped, null);
      return;
    }
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
            accumulator.apply(event);
            _replace(_liveReply(reply, accumulator));
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

    // 本地取消不主动取消订阅：transport 的 abortTrigger 会结束底层流；
    // 提前 cancel 会让生成器在收尾检查里误报 interrupted。
    unawaited(
      abort.future.then((_) {
        _stopRequested = true;
        finish();
      }),
    );

    ReplyStatus status;
    ReplyError? replyError;
    try {
      await done.future;
      status = _stopRequested ? ReplyStatus.stopped : ReplyStatus.done;
    } on Object catch (error) {
      if (_stopRequested || abort.isCompleted) {
        status = ReplyStatus.stopped;
      } else {
        status = ReplyStatus.error;
        replyError = _replyError(error);
      }
    }

    await _finish(reply, accumulator, status, replyError);
  }

  /// 收尾并落盘；后台补写与终态写入共用。
  Future<void> _finish(
    AssistantMessage reply,
    ReplyAccumulator accumulator,
    ReplyStatus status,
    ReplyError? error,
  ) async {
    accumulator.settle(status);
    _replace(_liveReply(reply, accumulator, error: error));
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
    error: error ?? base.error,
  );

  AssistantMessage _copyReply(
    AssistantMessage base, {
    required ReplyStatus status,
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
    latestReminder: base.latestReminder,
    prefix: base.prefix,
    stopReason: base.stopReason,
    stopDetails: base.stopDetails,
    usage: base.usage,
    error: base.error,
  );

  // ---------------------------------------------------------------- 辅助

  /// 自动标题只在标题仍为空、请求未取消且结束原因正常时采纳
  /// （`api.md` §7）。
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
        // 标题写库失败不影响本轮回复。
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

  List<Message> _historyBefore(String messageId) {
    final index = state.messages.indexWhere(
      (message) => message.id == messageId,
    );
    if (index < 0) return const [];
    return state.messages.sublist(0, index);
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
