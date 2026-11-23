import 'dart:math';

import 'types.dart';

/// ZH
/// 回复的全部文本拼接结果，用于复制与判断能否进入上下文。
///
/// EN
/// Concatenated text of all reply blocks; used for copying and context eligibility.
String getReplyText(AssistantMessage reply) => reply.blocks
    .whereType<TextBlock>()
    .map((block) => block.text)
    .join();

/// ZH
/// 只有已结束/已停止且有实际文本的回复进入请求上下文；拒答与模板提示
/// 永不进入。
///
/// EN
/// Only finished/stopped replies with text enter context; refusals and template
/// hints never enter.
bool isUsableReply(AssistantMessage reply) =>
    (reply.status == ReplyStatus.done || reply.status == ReplyStatus.stopped) &&
    reply.stopReason != StopReason.refusal &&
    !reply.blocks.any((block) => block is TextBlock && block.isTemplate) &&
    getReplyText(reply) != '';

/// ZH
/// 该回复能否作为 assistant 前缀回传以继续生成。
///
/// 调用方还需确认它是可见路径上的最后一条 assistant 消息。
///
/// EN
/// Whether this reply can be sent back as an assistant prefix to continue generation.
///
/// Callers must also confirm it is the last assistant message on the visible path.
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

/// ZH
/// 思考耗时，整秒且至少 1 秒；任一块缺时间数据时返回 null。导入的块只有
/// `elapsedSeconds`。
///
/// EN
/// Thinking seconds, whole and at least 1; null if any block lacks timing.
/// Imported blocks carry only `elapsedSeconds`.
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
