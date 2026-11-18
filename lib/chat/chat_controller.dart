// 私有字段无法写成命名初始化形参（命名参数不能以下划线开头）。
// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/client.dart';
import '../api/errors.dart';
import '../api/reply_accumulator.dart';
import '../api/request.dart';
import '../api/stream_events.dart';
import '../data/chat_repository.dart';
import '../models/types.dart';
import 'reply_rules.dart';

/// 一个会话的可见路径与流式回复状态（`api.md` §6）。
///
/// 流式期间只在内存里合并，终态才写库；同一会话同时只有一个请求。
class ChatController extends ChangeNotifier {
  ChatController({
    required ChatRepository repository,
    required DeepSeekApiClient client,
    required this.sessionId,
    required Future<String?> Function() readApiKey,
  })  : _repository = repository,
        _client = client,
        _readApiKey = readApiKey;

  final ChatRepository _repository;
  final DeepSeekApiClient _client;
  final Future<String?> Function() _readApiKey;
  final String sessionId;

  List<Message> _messages = const [];
  String _title = '';
  bool _busy = false;
  String? _error;
  Completer<void>? _abort;
  bool _stopRequested = false;
  bool _disposed = false;
  String? _activeReplyId;

  /// 选中分支的可见消息；流式回复以内存中的最新状态出现在原位。
  List<Message> get messages => _messages;

  String get title => _title;

  /// 请求进行中（含创建回复与等待首字节）。
  bool get busy => _busy;

  /// 请求未发出或请求前的本地错误；回复级错误在回复的 `error` 字段。
  String? get error => _error;

  Future<void> load() async {
    final session = await _repository.getSession(sessionId);
    final messages = await _repository.loadMessagesForDisplay(sessionId);
    // 首次读取可能晚于用户发出的请求，不覆盖请求中或已更新的内存状态。
    if (_busy) return;
    _title = session?.title ?? '';
    _messages = messages;
    _notify();
  }

  /// 追加提问并流式生成回复。
  Future<void> send({
    required String text,
    required bool thinking,
    required bool search,
  }) async {
    if (_busy) return;
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
      _messages = [...history, question, reply];
      _notify();

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: thinking,
          search: search,
          titleEnabled: _title.isEmpty,
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
    if (_busy) return;
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
      _messages = await _repository.visiblePath(sessionId);
      _notify();

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: thinking,
          search: search,
          titleEnabled: _title.isEmpty,
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
    if (_busy || !canContinueReply(reply)) return;
    if (_messages.isEmpty || _messages.last.id != reply.id) return;
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
      _notify();

      await _stream(
        request: buildMessageRequest(
          history: history,
          question: question,
          thinking: reply.thinking ?? thinking,
          search: reply.search ?? search,
          prefix: reply,
          latestReminder: reply.latestReminder,
          titleEnabled: _title.isEmpty,
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
  void stop() => _abort?.complete();

  /// 应用进入后台时把内存中的流式回复补写一次（`data-model.md` §4）。
  Future<void> flush() async {
    final id = _activeReplyId;
    if (id == null) return;
    AssistantMessage? live;
    for (final message in _messages) {
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
    } on Object {
      // 补写失败不阻塞；启动兜底仍会把残留状态置为 stopped。
    }
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  // ------------------------------------------------------------------ 流

  Future<void> _stream({
    required CreateMessageRequest request,
    required AssistantMessage reply,
    required ReplyAccumulator accumulator,
    required String apiKey,
  }) async {
    _notify();
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
        _notify();
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
    unawaited(abort.future.then((_) {
      _stopRequested = true;
      finish();
    }));

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
      _error = '保存回复失败：$error';
    }
    _notify();
  }

  AssistantMessage _liveReply(
    AssistantMessage base,
    ReplyAccumulator accumulator, {
    ReplyError? error,
  }) =>
      AssistantMessage(
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
  }) =>
      AssistantMessage(
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
    if (title == null || title.isEmpty || _title.isNotEmpty) return;
    final reason = accumulator.stopReason;
    if (reason != StopReason.endTurn && reason != StopReason.maxTokens) return;
    _title = title;
    unawaited(() async {
      try {
        final session = await _repository.getSession(sessionId);
        if (session != null && session.title.isEmpty) {
          await _repository.renameSession(sessionId, title);
        }
      } on Object {
        // 标题写库失败不影响本轮回复。
      }
    }());
  }

  Future<String?> _requireApiKey() async {
    final key = (await _readApiKey())?.trim();
    if (key != null && key.isNotEmpty) return key;
    _error = '未设置 API Key，请先在设置中填写。';
    _notify();
    return null;
  }

  void _begin() {
    _busy = true;
    _error = null;
    _stopRequested = false;
    _abort = Completer<void>();
    _notify();
  }

  void _end() {
    _abort = null;
    _activeReplyId = null;
    _busy = false;
    _notify();
  }

  bool get _cancelled => _abort?.isCompleted ?? false;

  void _recordError(Object error) {
    _error = error is ApiException ? error.message : error.toString();
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
    for (final message in _messages) {
      if (message.id == parentId && message is UserMessage) return message;
    }
    return null;
  }

  List<Message> _historyBefore(String messageId) {
    final index = _messages.indexWhere((message) => message.id == messageId);
    if (index < 0) return const [];
    return _messages.sublist(0, index);
  }

  void _replace(Message message) {
    _messages = [
      for (final existing in _messages)
        existing.id == message.id ? message : existing,
    ];
  }

  // shortcut: 每个流事件都通知一次；按帧合并等渲染票 10 定稿后再做。
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _abort?.complete();
    super.dispose();
  }
}
