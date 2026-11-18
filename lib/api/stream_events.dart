import 'dart:convert';

import '../models/json.dart';
import '../models/types.dart';
import 'errors.dart';
import 'sse.dart';

/// Anthropic 兼容消息流中的类型化事件（`api.md` §4）。
sealed class StreamEvent {
  const StreamEvent();
}

final class MessageStart extends StreamEvent {
  const MessageStart(this.messageId, this.model, this.usage);

  final String messageId;
  final String model;
  final Usage? usage;
}

final class ContentBlockStart extends StreamEvent {
  const ContentBlockStart(
    this.index,
    this.block, {
    this.isClientToolUse = false,
  });

  final int index;

  /// 为 null 表示块被丢弃：客户端 `tool_use` 或未知类型。
  final ReplyBlock? block;

  /// 客户端工具块既不展示也不保存，并禁用续写。
  final bool isClientToolUse;
}

final class ContentBlockDelta extends StreamEvent {
  const ContentBlockDelta(this.index, this.delta);

  final int index;
  final BlockDelta delta;
}

sealed class BlockDelta {
  const BlockDelta();
}

final class TextDelta extends BlockDelta {
  const TextDelta(this.text);
  final String text;
}

final class ThinkingDelta extends BlockDelta {
  const ThinkingDelta(this.thinking);
  final String thinking;
}

final class SignatureDelta extends BlockDelta {
  const SignatureDelta(this.signature);
  final String signature;
}

final class CitationsDelta extends BlockDelta {
  const CitationsDelta(this.citation);
  final TextCitation citation;
}

final class ContentBlockStop extends StreamEvent {
  const ContentBlockStop(this.index);
  final int index;
}

final class MessageDelta extends StreamEvent {
  const MessageDelta({
    required this.stopReason,
    this.stopDetails,
    this.title,
    this.usage,
  });

  final StopReason stopReason;
  final StopDetails? stopDetails;

  /// 仅在开启自动标题且生成成功时出现。
  final String? title;
  final Usage? usage;
}

final class MessageStop extends StreamEvent {
  const MessageStop();
}

/// 把 SSE 帧转换为类型化事件，并归类流内错误。
///
/// 未知事件、未知增量与无法解析的 JSON 帧静默丢弃；错误帧抛
/// [ApiException]，kind 为 [ApiErrorKind.stream]。
class StreamEventParser {
  StreamEventParser({int Function()? clock})
      : _clock = clock ?? _nowMilliseconds;

  final int Function() _clock;

  static int _nowMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  StreamEvent? parse(SseEvent frame) {
    final Object? decoded;
    try {
      decoded = jsonDecode(frame.data);
    } on FormatException {
      if (frame.event == 'error') {
        throw ApiException(ApiErrorKind.stream, frame.data);
      }
      return null;
    }

    final payload = asJsonMap(decoded);
    if (payload == null) {
      if (frame.event == 'error') {
        throw ApiException(ApiErrorKind.stream, frame.data);
      }
      return null;
    }

    final errorMessage = asString(asJsonMap(payload['error'])?['message']);
    if (errorMessage != null) {
      throw ApiException(ApiErrorKind.stream, errorMessage);
    }
    if (frame.event == 'error') {
      throw ApiException(ApiErrorKind.stream, frame.data);
    }

    final type = asString(payload['type']) ?? frame.event;
    switch (type) {
      case 'message_start':
        final message = asJsonMap(payload['message']);
        final id = asString(message?['id']);
        if (id == null) return null;
        return MessageStart(
          id,
          asString(message?['model']) ?? '',
          parseUsage(message?['usage']),
        );

      case 'content_block_start':
        final index = asInt(payload['index']);
        final raw = asJsonMap(payload['content_block']);
        if (index == null || raw == null) return null;
        final isClientToolUse = asString(raw['type']) == 'tool_use';
        final isThinking = asString(raw['type']) == 'thinking';
        return ContentBlockStart(
          index,
          isClientToolUse
              ? null
              : parseReplyBlock(
                  raw,
                  thinkingStartedAt: isThinking ? _clock() : null,
                ),
          isClientToolUse: isClientToolUse,
        );

      case 'content_block_delta':
        final index = asInt(payload['index']);
        final delta = _parseDelta(asJsonMap(payload['delta']));
        if (index == null || delta == null) return null;
        return ContentBlockDelta(index, delta);

      case 'content_block_stop':
        final index = asInt(payload['index']);
        if (index == null) return null;
        return ContentBlockStop(index);

      case 'message_delta':
        final delta = asJsonMap(payload['delta']);
        final stopReason = StopReason.fromWire(asString(delta?['stop_reason']));
        if (delta == null || stopReason == null) return null;
        return MessageDelta(
          stopReason: stopReason,
          stopDetails: parseStopDetails(delta['stop_details']),
          title: asString(delta['title']),
          usage: parseUsage(payload['usage']),
        );

      case 'message_stop':
        return const MessageStop();

      default:
        return null;
    }
  }

  BlockDelta? _parseDelta(Map<String, dynamic>? delta) {
    if (delta == null) return null;
    switch (asString(delta['type'])) {
      case 'text_delta':
        final text = asString(delta['text']);
        return text == null ? null : TextDelta(text);
      case 'thinking_delta':
        final thinking = asString(delta['thinking']);
        return thinking == null ? null : ThinkingDelta(thinking);
      case 'signature_delta':
        final signature = asString(delta['signature']);
        return signature == null ? null : SignatureDelta(signature);
      case 'citations_delta':
        final citation = parseCitation(delta['citation']);
        return citation == null ? null : CitationsDelta(citation);
      default:
        // `input_json_delta` 与后续新增的增量均不消费。
        return null;
    }
  }
}
