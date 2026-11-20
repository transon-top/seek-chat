import 'package:shared_preferences/shared_preferences.dart';

import '../shared/data/chat_repository.dart';
import '../shared/models/types.dart';
import 'markdown_samples.dart';

/// 样本会话标题；改名会让旧会话留在列表里，直到下次哈希变化被清理。
const String markdownSampleSessionTitle = 'Markdown 渲染测试';
const String longTextSampleSessionTitle = 'Markdown 超长文本降级';

const String _sampleHashKey = 'dev.markdownSampleHash';

/// debug 构建启动时写入 Markdown 样本会话。
///
/// 样本内容哈希与上次一致时跳过；变化时删除两个样本会话后重建，
/// 改样本只需热重启，不必手动删除会话。
Future<void> seedMarkdownSamples(
  ChatRepository repository,
  SharedPreferences prefs,
) async {
  final hash = _samplesHash();
  if (prefs.getInt(_sampleHashKey) == hash) return;

  for (final session in await repository.listSessions()) {
    if (session.title == markdownSampleSessionTitle ||
        session.title == longTextSampleSessionTitle) {
      await repository.deleteSession(session.id);
    }
  }
  // 先写超长文本会话，让主样本会话更新、冷启动自动打开。
  await _seedSession(repository, longTextSampleSessionTitle, [longTextSample]);
  await _seedSession(repository, markdownSampleSessionTitle, markdownSamples);
  await prefs.setInt(_sampleHashKey, hash);
}

Future<void> _seedSession(
  ChatRepository repository,
  String title,
  List<MarkdownSample> samples,
) async {
  final session = await repository.createSession();
  await repository.renameSession(session.id, title);
  for (final sample in samples) {
    final user = await repository.addUserMessage(
      sessionId: session.id,
      text: sample.prompt,
    );
    final reply = await repository.createReply(
      sessionId: session.id,
      userMessageId: user.id,
      model: ChatModel.deepseekFlash,
      thinking: sample.thinking,
      search: false,
    );
    await repository.updateReply(
      messageId: reply.id,
      status: ReplyStatus.done,
      blocks: sample.blocks,
    );
  }
}

/// FNV-1a 32 位：跨进程稳定，用于判断样本是否被编辑过。
int _samplesHash() {
  var hash = 0x811c9dc5;
  void add(String value) {
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
  }

  for (final sample in [...markdownSamples, longTextSample]) {
    add(sample.label);
    add(sample.prompt);
    add('${sample.thinking}');
    for (final block in sample.blocks) {
      switch (block) {
        case TextBlock():
          add(block.text);
          for (final citation in block.citations) {
            add(citation.url);
            add(citation.title ?? '');
            add(citation.citedText);
          }
        case ThinkingBlock():
          add(block.thinking);
        default:
          break;
      }
    }
  }
  return hash;
}
