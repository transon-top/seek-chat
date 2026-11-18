import 'dart:math';

import 'types.dart';

/// 回复的全部文本拼接结果，用于复制与判断能否进入上下文。
String getReplyText(AssistantMessage reply) => reply.blocks
    .whereType<TextBlock>()
    .map((block) => block.text)
    .join();

/// 只有已结束/已停止且有实际文本的回复进入请求上下文；拒答与模板提示
/// 永不进入。
bool isUsableReply(AssistantMessage reply) =>
    (reply.status == ReplyStatus.done || reply.status == ReplyStatus.stopped) &&
    reply.stopReason != StopReason.refusal &&
    !reply.blocks.any((block) => block is TextBlock && block.isTemplate) &&
    getReplyText(reply) != '';

/// 该回复能否作为 assistant 前缀回传以继续生成。
///
/// 调用方还需确认它是可见路径上的最后一条 assistant 消息。
bool canContinueReply(AssistantMessage reply) {
  if (!reply.prefix ||
      reply.stopReason == StopReason.refusal ||
      reply.stopReason == StopReason.toolUse ||
      reply.blocks.any((block) =>
          block is ServerToolUseBlock ||
          block is WebSearchToolResultBlock ||
          block is WebFetchToolResultBlock ||
          (block is TextBlock && block.isTemplate))) {
    return false;
  }
  return reply.status == ReplyStatus.stopped ||
      (reply.status == ReplyStatus.done &&
          reply.stopReason == StopReason.maxTokens);
}

/// 思考耗时，整秒且至少 1 秒；任一块缺时间数据时返回 null。导入的块只有
/// `elapsedSeconds`。
int? replyThinkingSeconds(AssistantMessage reply) {
  final thinking = reply.blocks.whereType<ThinkingBlock>().toList();
  if (thinking.isEmpty) return null;

  var millis = 0;
  for (final block in thinking) {
    if (block.startedAt != null && block.endedAt != null) {
      millis += block.endedAt! - block.startedAt!;
    } else if (block.elapsedSeconds != null) {
      millis += block.elapsedSeconds! * 1000;
    } else {
      return null;
    }
  }
  return max(1, (millis / 1000).round());
}
