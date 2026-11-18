/// API 客户端与本地存储共用的领域类型与协议类型。
///
/// 命名遵循 `GLOSSARY.md`：Session、Message、Reply、ReplyBlock、Thinking、
/// Citation、Attachment、Latest Reminder。
library;

enum ChatModel {
  deepseekFlash('deepseek-flash'),
  deepseekV4Pro('deepseek-v4-pro'); // 预留；v1 恒用 deepseek-flash

  const ChatModel(this.wire);
  final String wire;

  static ChatModel? fromWire(String? value) {
    for (final model in values) {
      if (model.wire == value) return model;
    }
    return null;
  }
}

enum ServerToolKind {
  search('search'),
  deepSearch('deep_search'),
  readLink('read_link'),
  imageSearch('image_search'),
  deepImageSearch('deep_image_search');

  const ServerToolKind(this.wire);
  final String wire;

  static ServerToolKind? fromWire(String? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    return null;
  }
}

enum StopReason {
  endTurn('end_turn'),
  maxTokens('max_tokens'),
  toolUse('tool_use'),
  refusal('refusal');

  const StopReason(this.wire);
  final String wire;

  static StopReason? fromWire(String? value) {
    for (final reason in values) {
      if (reason.wire == value) return reason;
    }
    return null;
  }
}

enum ReplyStatus { pending, streaming, done, stopped, error }

enum ApiErrorKind { http, stream, network, interrupted, protocol, upload }

enum ApiErrorCondition {
  unauthorized,
  insufficientBalance,
  tooLarge,
  rateLimited,
  serverBusy,
  network,
  other,
}

// ------------------------------------------------------------- 工具输入

sealed class ServerToolInput {
  const ServerToolInput();
}

final class SearchInput extends ServerToolInput {
  const SearchInput({this.query, required this.queries});

  final String? query;
  final List<String> queries;
}

final class OpenPageInput extends ServerToolInput {
  const OpenPageInput(this.url);
  final String url;
}

final class FindInPageInput extends ServerToolInput {
  const FindInPageInput({required this.url, required this.pattern});
  final String url;
  final String pattern;
}

final class ReadLinkInput extends ServerToolInput {
  const ReadLinkInput(this.url);
  final String url;
}

/// 未知 action 原样保留，保证块可往返序列化。
final class UnknownToolInput extends ServerToolInput {
  const UnknownToolInput(this.json);
  final Map<String, dynamic> json;
}

// ------------------------------------------------------------------- 引用

final class TextCitation {
  const TextCitation({
    required this.url,
    required this.title,
    required this.citedText,
    required this.encryptedIndex,
  });

  final String url;
  final String? title;
  final String citedText;
  final String encryptedIndex;
}

// ------------------------------------------------------------- 回复块

sealed class ReplyBlock {
  const ReplyBlock();
}

final class TextBlock extends ReplyBlock {
  const TextBlock({
    required this.text,
    this.citations = const [],
    this.isTemplate = false,
  });

  final String text;
  final List<TextCitation> citations;
  final bool isTemplate;

  TextBlock copyWith({
    String? text,
    List<TextCitation>? citations,
    bool? isTemplate,
  }) =>
      TextBlock(
        text: text ?? this.text,
        citations: citations ?? this.citations,
        isTemplate: isTemplate ?? this.isTemplate,
      );
}

final class ThinkingBlock extends ReplyBlock {
  const ThinkingBlock({
    required this.thinking,
    this.signature = '',
    this.startedAt,
    this.endedAt,
    this.elapsedSeconds,
  });

  final String thinking;
  final String signature;

  /// epoch 毫秒；仅带耗时的导入块缺省。
  final int? startedAt;
  final int? endedAt;
  final int? elapsedSeconds;

  ThinkingBlock copyWith({
    String? thinking,
    String? signature,
    int? startedAt,
    int? endedAt,
    int? elapsedSeconds,
  }) =>
      ThinkingBlock(
        thinking: thinking ?? this.thinking,
        signature: signature ?? this.signature,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        elapsedSeconds: elapsedSeconds ?? this.elapsedSeconds,
      );
}

final class ServerToolUseBlock extends ReplyBlock {
  const ServerToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
    required this.kind,
    this.caller = const {'type': 'direct'},
  });

  final String id;
  final String name;
  final ServerToolInput input;
  final ServerToolKind kind;
  final Map<String, dynamic> caller;
}

sealed class WebSearchResultItem {
  const WebSearchResultItem();
}

final class WebSearchResult extends WebSearchResultItem {
  const WebSearchResult({
    required this.title,
    required this.url,
    required this.snippet,
    required this.encryptedContent,
    this.imageUrl,
    this.siteIcon,
    this.siteName,
    this.pageAge,
  });

  final String title;
  final String url;
  final String snippet;
  final String? imageUrl;
  final String? siteIcon;
  final String? siteName;
  final String encryptedContent;
  final String? pageAge;
}

final class WebSearchResultError extends WebSearchResultItem {
  const WebSearchResultError(this.errorCode);
  final String errorCode;
}

final class WebSearchToolResultBlock extends ReplyBlock {
  const WebSearchToolResultBlock({
    required this.toolUseId,
    required this.content,
    required this.kind,
  });

  final String toolUseId;
  final List<WebSearchResultItem> content;
  final ServerToolKind kind;
}

sealed class WebFetchContent {
  const WebFetchContent();
}

final class WebFetchResult extends WebFetchContent {
  const WebFetchResult({
    required this.url,
    required this.content,
    this.publishedAt,
  });

  final String url;

  /// 协议中嵌套的 `content` 对象，原样保留：v1 不读正文，但必须能往返。
  final Map<String, dynamic> content;
  final String? publishedAt;

  String? get title => content['title'] as String?;
}

final class WebFetchResultError extends WebFetchContent {
  const WebFetchResultError(this.errorCode);
  final String errorCode;
}

final class WebFetchToolResultBlock extends ReplyBlock {
  const WebFetchToolResultBlock({
    required this.toolUseId,
    required this.content,
    required this.kind,
    this.signature,
  });

  final String toolUseId;
  final WebFetchContent content;
  final ServerToolKind kind;
  final String? signature;
}

// ------------------------------------------------------------------- 用量

final class Usage {
  const Usage({
    required this.inputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
    required this.outputTokens,
    this.webSearchRequests,
    this.toolSearch,
  });

  final int inputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  /// `message_delta` 中为整轮累计输出数。
  final int outputTokens;
  final int? webSearchRequests;
  final int? toolSearch;
}

final class StopDetails {
  const StopDetails({this.type = 'refusal', this.category, this.explanation});

  final String type;
  final String? category;
  final String? explanation;
}

// ------------------------------------------------------------------- 实体

final class SessionSummary {
  const SessionSummary({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
}

final class Session {
  const Session({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.rootMessageId,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 选中分支的第一条消息；空会话为 null。
  final String? rootMessageId;
}

sealed class Message {
  const Message({
    required this.id,
    this.parentId,
    this.selectedChildId,
    required this.createdAt,
  });

  final String id;
  final String? parentId;
  final String? selectedChildId;
  final DateTime createdAt;
}

final class UserMessage extends Message {
  const UserMessage({
    required super.id,
    super.parentId,
    super.selectedChildId,
    required super.createdAt,
    required this.text,
    this.attachments = const [],
  });

  final String text;
  final List<Attachment> attachments;

  UserMessage withAttachments(List<Attachment> attachments) => UserMessage(
        id: id,
        parentId: parentId,
        selectedChildId: selectedChildId,
        createdAt: createdAt,
        text: text,
        attachments: attachments,
      );
}

final class AssistantMessage extends Message {
  const AssistantMessage({
    required super.id,
    super.parentId,
    super.selectedChildId,
    required super.createdAt,
    required this.status,
    required this.blocks,
    this.model,
    this.thinking,
    this.search,
    this.latestReminder,
    this.prefix = true,
    this.stopReason,
    this.stopDetails,
    this.usage,
    this.error,
  });

  final ChatModel? model;
  final bool? thinking;
  final bool? search;
  final String? latestReminder;
  final bool prefix;
  final ReplyStatus status;
  final List<ReplyBlock> blocks;
  final StopReason? stopReason;
  final StopDetails? stopDetails;
  final Usage? usage;
  final ReplyError? error;

  /// 已创建且尚未结束：`pending` 或 `streaming`。
  bool get isInFlight =>
      status == ReplyStatus.pending || status == ReplyStatus.streaming;
}

final class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.size,
    this.isImage = false,
    this.mimeType = '',
    this.localPath,
    this.serverId,
  });

  final String id;
  final String name;
  final int size;
  final bool isImage;
  final String mimeType;

  /// 相对应用支持目录的路径。
  final String? localPath;

  /// Files API 的 `file_id`，按附件 id 在所有引用间共享。
  final String? serverId;

  /// 传 null 表示 `serverId` 已失效。
  Attachment withServerId(String? serverId) => Attachment(
        id: id,
        name: name,
        size: size,
        isImage: isImage,
        mimeType: mimeType,
        localPath: localPath,
        serverId: serverId,
      );
}

/// 输入区里尚未发送的附件；原件仍在选择器给出的临时路径。
final class DraftAttachment {
  const DraftAttachment({
    required this.id,
    required this.path,
    required this.name,
    required this.size,
    required this.isImage,
    required this.mimeType,
  });

  final String id;
  final String path;
  final String name;
  final int size;
  final bool isImage;
  final String mimeType;
}

final class LocalMessage {
  const LocalMessage({required this.key, this.params = const {}});

  final String key;
  final Map<String, Object?> params;
}

/// 本地化键（`data-model.md` §2.2）。键名与 ARB 条目一致，`app/` 负责翻译。
abstract final class LocalMessageKeys {
  static const errorNoApiKey = 'errorNoApiKey';
  static const errorSaveReplyFailed = 'errorSaveReplyFailed';
  static const apiErrorUnauthorized = 'apiErrorUnauthorized';
  static const apiErrorInsufficientBalance = 'apiErrorInsufficientBalance';
  static const apiErrorTooLarge = 'apiErrorTooLarge';
  static const apiErrorRateLimited = 'apiErrorRateLimited';
  static const apiErrorServerBusy = 'apiErrorServerBusy';
  static const apiErrorNetwork = 'apiErrorNetwork';
  static const apiErrorOther = 'apiErrorOther';
  static const uploadUnsupportedFormat = 'uploadUnsupportedFormat';
  static const uploadMaxMBSize = 'uploadMaxMBSize';
  static const uploadMaxFiles = 'uploadMaxFiles';
  static const uploadFileStatusFailed = 'uploadFileStatusFailed';
  static const uploadServerBusy = 'uploadServerBusy';
  static const uploadParseFailed = 'uploadParseFailed';
  static const uploadFileCountLimit = 'uploadFileCountLimit';
  static const uploadStorageLimit = 'uploadStorageLimit';
  static const errorSaveAttachmentFailed = 'errorSaveAttachmentFailed';
}

final class ReplyError {
  const ReplyError({
    required this.kind,
    required this.message,
    this.status,
    this.localMessage,
    this.retryable,
  });

  final ApiErrorKind kind;
  final String message;
  final int? status;
  final LocalMessage? localMessage;

  /// 仅 `upload` 错误使用：重新上传是否可能成功。
  final bool? retryable;
}
