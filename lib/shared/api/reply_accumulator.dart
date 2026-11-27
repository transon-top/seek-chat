import '../models/types.dart';
import 'stream_events.dart';

/// ZH
/// 接收过程中把类型化流事件合并进回复。
///
/// 对齐 chat-demo 的 `applyEvent` / `settleReply`：服务端块下标映射到本地
/// 下标，被跳过的块不占位，本类不写数据库。
///
/// EN
/// Merge typed stream events into a reply while it is received.
///
/// Mirrors chat-demo's `applyEvent` / `settleReply`: server block indexes map to
/// local indexes. Skipped blocks take no slot; this class never writes to the database.
class ReplyAccumulator {
  /// ZH
  /// [blocks]、[usage]、[prefix] 传入已有回复的当前状态，用于续写；新事件
  /// 追加在原块之后。
  ///
  /// EN
  /// [blocks], [usage], and [prefix] pass an existing reply's current state for
  /// continuation. New events are appended after the existing blocks.
  ReplyAccumulator({
    Iterable<ReplyBlock> blocks = const [],
    this.usage,
    this.prefix = true,
    int Function()? clock,
  })  : blocks = [...blocks],
        _clock = clock ?? _nowMilliseconds;

  final int Function() _clock;

  static int _nowMilliseconds() => DateTime.now().millisecondsSinceEpoch;

  ReplyStatus status = ReplyStatus.pending;
  final List<ReplyBlock> blocks;
  bool prefix;
  StopReason? stopReason;
  StopDetails? stopDetails;
  Usage? usage;
  String? title;
  bool messageStopped = false;

  final Map<int, int> _indexes = <int, int>{};

  void apply(StreamEvent event) {
    status = ReplyStatus.streaming;
    switch (event) {
      case MessageStart(:final usage):
        if (usage != null) this.usage = usage;

      case ContentBlockStart(
          :final index,
          :final block,
          :final isClientToolUse,
        ):
        _indexes.remove(index);
        if (isClientToolUse) prefix = false;
        if (block == null) break;
        _indexes[index] = blocks.length;
        blocks.add(block);

      case ContentBlockDelta(:final index, :final delta):
        final local = _indexes[index];
        if (local == null) break;
        blocks[local] = _applyDelta(blocks[local], delta);

      case ContentBlockStop(:final index):
        final local = _indexes.remove(index);
        if (local == null) break;
        final block = blocks[local];
        if (block is ThinkingBlock &&
            block.startedAt != null &&
            block.endedAt == null) {
          blocks[local] = block.copyWith(endedAt: _clock());
        }

      case MessageDelta(
          :final stopReason,
          :final stopDetails,
          :final title,
          :final usage,
        ):
        this.stopReason = stopReason;
        this.stopDetails = stopDetails;
        if (title != null) this.title = title;
        if (usage != null) this.usage = usage;

      case MessageStop():
        messageStopped = true;
    }
  }

  ReplyBlock _applyDelta(ReplyBlock block, BlockDelta delta) {
    if (block is TextBlock) {
      if (delta is TextDelta) return block.copyWith(text: block.text + delta.text);
      if (delta is CitationsDelta) {
        return block.copyWith(citations: [...block.citations, delta.citation]);
      }
    }
    if (block is ThinkingBlock) {
      if (delta is ThinkingDelta) {
        return block.copyWith(thinking: block.thinking + delta.thinking);
      }
      if (delta is SignatureDelta) {
        return block.copyWith(signature: block.signature + delta.signature);
      }
    }
    return block;
  }

  /// ZH
  /// 收尾回复：给未结束的思考块补结束时间；安全拒绝时丢弃已收到的思考与
  /// 正文，只保留工具块。
  ///
  /// EN
  /// Settle the reply by closing unfinished thinking blocks with an end time.
  /// On safety refusal, discard received thinking and text, keeping only tool blocks.
  void settle(ReplyStatus status) {
    final refused = stopReason == StopReason.refusal;
    final now = _clock();
    final settled = <ReplyBlock>[];
    for (final block in blocks) {
      if (refused && (block is TextBlock || block is ThinkingBlock)) continue;
      settled.add(
        block is ThinkingBlock &&
                block.startedAt != null &&
                block.endedAt == null
            ? block.copyWith(endedAt: now)
            : block,
      );
    }
    blocks
      ..clear()
      ..addAll(settled);
    _indexes.clear();
    this.status = status;
  }
}
