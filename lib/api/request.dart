import '../chat/reply_rules.dart';
import '../models/json.dart';
import '../models/types.dart';

const String deepSeekSystemPrompt = '该助手为DeepSeek，由深度求索公司创造。';

sealed class MessageParam {
  const MessageParam();
  Map<String, dynamic> toJson();
}

final class LatestReminderParam extends MessageParam {
  const LatestReminderParam(this.content);
  final String content;

  @override
  Map<String, dynamic> toJson() => {'role': 'latest_reminder', 'content': content};
}

final class FileBlockParam {
  const FileBlockParam({required this.fileId, required this.isImage});

  final String fileId;
  final bool isImage;

  Map<String, dynamic> toJson() => {
        'type': isImage ? 'image' : 'document',
        'source': {'type': 'file', 'file_id': fileId},
      };
}

final class UserParam extends MessageParam {
  const UserParam({this.text = '', this.files = const []});

  final String text;
  final List<FileBlockParam> files;

  @override
  Map<String, dynamic> toJson() {
    if (files.isEmpty) return {'role': 'user', 'content': text};
    return {
      'role': 'user',
      'content': [
        ...files.map((file) => file.toJson()),
        if (text.isNotEmpty) {'type': 'text', 'text': text},
      ],
    };
  }
}

final class AssistantParam extends MessageParam {
  const AssistantParam(this.content);

  /// 已转换好的协议内容块。
  final List<Map<String, dynamic>> content;

  @override
  Map<String, dynamic> toJson() => {'role': 'assistant', 'content': content};
}

sealed class ToolDeclaration {
  const ToolDeclaration();
  Map<String, dynamic> toJson();
}

final class ReadUrlTool extends ToolDeclaration {
  const ReadUrlTool();

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'deepseek_read_url', 'name': 'deepseek_read_url'};
}

final class WebSearchTool extends ToolDeclaration {
  const WebSearchTool();

  @override
  Map<String, dynamic> toJson() =>
      {'type': 'deepseek_web_search', 'name': 'deepseek_web_search'};
}

final class CreateMessageRequest {
  const CreateMessageRequest({
    required this.model,
    required this.messages,
    required this.thinking,
    required this.tools,
    this.titleEnabled = false,
  });

  final ChatModel model;
  final List<MessageParam> messages;
  final bool thinking;
  final List<ToolDeclaration> tools;
  final bool titleEnabled;

  /// 请求体含文件块时，传输层必须追加 Files API 的 beta 头。
  bool get hasFileBlocks =>
      messages.any((message) => message is UserParam && message.files.isNotEmpty);

  Map<String, dynamic> toJson() => {
        'model': model.wire,
        'system': deepSeekSystemPrompt,
        'messages': messages.map((message) => message.toJson()).toList(),
        'thinking': {'type': thinking ? 'enabled' : 'disabled'},
        'tools': tools.map((tool) => tool.toJson()).toList(),
        'safety_check': {'level': 'high'},
        if (titleEnabled) 'title': {'enabled': true},
        'stream': true,
      };
}

/// 构造新回复、重新生成或续写所需的请求。
///
/// [history] 是 [question] 之前的可见路径。[latestReminder] 是本轮快照；
/// 续写时传原回复保存的快照。[prefix] 存在时，其记录的 model/thinking/search
/// 快照优先于入参，缺省再回退到当前设置。
CreateMessageRequest buildMessageRequest({
  required List<Message> history,
  required UserMessage question,
  required bool thinking,
  required bool search,
  AssistantMessage? prefix,
  String? latestReminder,
  bool titleEnabled = false,
  ChatModel model = ChatModel.deepseekFlash,
}) {
  final effectiveThinking = prefix?.thinking ?? thinking;
  final effectiveSearch = prefix?.search ?? search;
  final effectiveModel = prefix?.model ?? model;
  final messages = <MessageParam>[];
  String? previousReminder;

  void appendReminder(String? reminder) {
    if (reminder != null && reminder.isNotEmpty && reminder != previousReminder) {
      messages.add(LatestReminderParam(reminder));
      previousReminder = reminder;
    }
  }

  for (final (userMessage, reply) in _contextRounds(history)) {
    final userParam = _userParam(userMessage);
    // 既无文本也无服务端文件的提问整轮不发送。
    if (userParam.text.isEmpty && userParam.files.isEmpty) continue;
    appendReminder(reply.latestReminder);
    messages.add(userParam);
    messages.add(AssistantParam(_assistantContent(reply)));
  }

  appendReminder(latestReminder);
  messages.add(_userParam(question));

  if (prefix != null && prefix.prefix) {
    final content =
        _assistantContent(prefix, prefix: true, thinking: effectiveThinking);
    final hasContent = content.any((block) {
      switch (block['type']) {
        case 'text':
          return (block['text'] as String).trim().isNotEmpty;
        case 'thinking':
          return (block['thinking'] as String).trim().isNotEmpty;
        default:
          return false;
      }
    });
    // 空前缀会被服务端拒绝，此时直接重发原问题。
    if (hasContent) messages.add(AssistantParam(content));
  }

  return CreateMessageRequest(
    model: effectiveModel,
    messages: messages,
    thinking: effectiveThinking,
    tools: [
      const ReadUrlTool(),
      if (effectiveSearch) const WebSearchTool(),
    ],
    titleEnabled: titleEnabled,
  );
}

Iterable<(UserMessage, AssistantMessage)> _contextRounds(List<Message> history) sync* {
  for (var i = 0; i + 1 < history.length; i++) {
    final first = history[i];
    final second = history[i + 1];
    if (first is UserMessage &&
        second is AssistantMessage &&
        isUsableReply(second)) {
      yield (first, second);
      i++;
    }
  }
}

UserParam _userParam(UserMessage message) => UserParam(
      text: message.text,
      files: [
        for (final attachment in message.attachments)
          if (attachment.serverId != null)
            FileBlockParam(
              fileId: attachment.serverId!,
              isImage: attachment.isImage,
            ),
      ],
    );

/// 把回复块转回请求内容（`api.md` §3.4）。
///
/// 文本合并与 chat-demo 一致：相邻文本块直接拼接；两个保留文本块之间夹着
/// 被丢弃的块时补一个空行；保留工具块之后的文本不加前缀。历史上下文不带
/// 思考、引用与非 read_link 工具。
List<Map<String, dynamic>> _assistantContent(
  AssistantMessage reply, {
  bool prefix = false,
  bool thinking = false,
}) {
  final unsignedReadLinks = <String>{
    for (final block in reply.blocks)
      if (block is WebFetchToolResultBlock &&
          block.kind == ServerToolKind.readLink &&
          block.content is WebFetchResult &&
          (block.signature == null || block.signature!.trim().isEmpty))
        block.toolUseId,
  };

  final content = <Map<String, dynamic>>[];
  Map<String, dynamic>? text;

  for (final block in reply.blocks) {
    // 本轮空白思考直接跳过，不打断相邻文本的拼接。
    if (prefix && block is ThinkingBlock && block.thinking.trim().isEmpty) {
      continue;
    }

    if (block is TextBlock) {
      if (text != null) {
        text['text'] = (text['text'] as String) + block.text;
      } else {
        final previous = content.isEmpty ? null : content.last;
        text = {
          'type': 'text',
          'text':
              '${previous?['type'] == 'text' ? '\n\n' : ''}${block.text}',
        };
        content.add(text);
      }
      continue;
    }

    text = null;
    if (prefix && thinking && block is ThinkingBlock) {
      content.add({
        'type': 'thinking',
        'thinking': block.thinking,
        'signature': block.signature,
      });
    } else if (block is ServerToolUseBlock &&
        block.kind == ServerToolKind.readLink &&
        !unsignedReadLinks.contains(block.id)) {
      content.add({
        'type': 'server_tool_use',
        'id': block.id,
        'name': block.name,
        'input': encodeToolInput(block.input),
        'kind': block.kind.wire,
      });
    } else if (block is WebFetchToolResultBlock &&
        block.kind == ServerToolKind.readLink &&
        !unsignedReadLinks.contains(block.toolUseId)) {
      content.add(encodeReplyBlock(block));
    }
  }

  return [
    for (final block in content)
      if (block['type'] != 'text' || (block['text'] as String).isNotEmpty) block,
  ];
}
