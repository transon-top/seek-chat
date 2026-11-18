import '../../l10n/generated/app_localizations.dart';
import '../../shared/models/types.dart';

/// 工具调用的界面状态，只由已持久化的块推导（`search.md` §3.1）。
enum ToolStatus { wip, done, failed }

bool isDeepSearchKind(ServerToolKind kind) =>
    kind == ServerToolKind.deepSearch || kind == ServerToolKind.deepImageSearch;

bool isImageSearchKind(ServerToolKind kind) =>
    kind == ServerToolKind.imageSearch ||
    kind == ServerToolKind.deepImageSearch;

/// 正文引用可指向的来源；编号按首次登记顺序，从 1 开始。
final class Source {
  Source({
    required this.index,
    required this.url,
    required this.title,
    required this.siteName,
    required this.publishedAt,
    required this.snippet,
    required this.siteIcon,
  });

  final int index;
  final String url;
  String title;
  String siteName;
  String? publishedAt;
  String? snippet;
  String? siteIcon;
}

final class PageItem {
  const PageItem({
    required this.id,
    required this.url,
    required this.title,
    required this.status,
  });

  final String id;
  final String url;
  final String title;
  final ToolStatus status;
}

final class FindItem {
  const FindItem({
    required this.id,
    required this.pattern,
    required this.status,
  });

  final String id;
  final String pattern;
  final ToolStatus status;
}

sealed class ReplyStep {
  const ReplyStep();
}

final class ThinkingStep extends ReplyStep {
  ThinkingStep({required this.key, required this.blocks});

  final String key;
  final List<ThinkingBlock> blocks;
}

final class PreambleStep extends ReplyStep {
  const PreambleStep({required this.key, required this.markdown});

  final String key;
  final String markdown;
}

final class SearchStep extends ReplyStep {
  SearchStep({
    required this.key,
    required this.kind,
    required this.queries,
    required this.results,
    required this.status,
  });

  /// 该步骤首次调用的 `tool_use` id。
  final String key;
  final ServerToolKind kind;
  final List<String> queries;
  final List<Source> results;
  ToolStatus status;
}

final class OpenStep extends ReplyStep {
  OpenStep(this.pages);

  final List<PageItem> pages;
}

final class FindStep extends ReplyStep {
  FindStep(this.patterns);

  final List<FindItem> patterns;
}

final class ReadLinkStep extends ReplyStep {
  ReadLinkStep(this.links);

  final List<PageItem> links;
}

/// 回复的界面结构：步骤时间线、带引用角标的正文与来源列表。
///
/// 纯函数，不修改 [AssistantMessage.blocks]；每次块变化时重算
/// （`search.md` §3）。
final class ReplyView {
  const ReplyView({
    required this.steps,
    required this.answer,
    required this.sources,
    required this.searchResults,
  });

  final List<ReplyStep> steps;
  final ({String markdown, String text})? answer;

  /// 全部可引用来源，按编号排列。
  final List<Source> sources;

  /// 去重后的网页搜索结果，供胶囊与抽屉使用。
  final List<Source> searchResults;
}

ReplyView buildReplyView(
  AssistantMessage reply, {
  required bool streaming,
}) {
  final results = <String, ReplyBlock>{};
  for (final block in reply.blocks) {
    final toolUseId = switch (block) {
      WebSearchToolResultBlock(:final toolUseId) => toolUseId,
      WebFetchToolResultBlock(:final toolUseId) => toolUseId,
      _ => null,
    };
    if (toolUseId != null) results[toolUseId] = block;
  }

  final registry = _SourceRegistry();
  final searchResults = <Source>[];
  final steps = <ReplyStep>[];
  final mergedSearch = <ServerToolKind, SearchStep>{};
  ThinkingStep? mergedThinking;
  final pending = <_PendingText>[];

  Source registerSearchResult(WebSearchResult item) => registry.add(
    item.url,
    item.title,
    item.pageAge,
    snippet: item.snippet,
    siteName: item.siteName,
    siteIcon: item.siteIcon,
  );

  void flushPreamble() {
    if (pending.isEmpty) return;
    final joined = _joinTextBlocks(pending, registry);
    if (joined.markdown.trim().isNotEmpty) {
      steps.add(
        PreambleStep(key: 'text-${pending.first.index}', markdown: joined.markdown),
      );
    }
    pending.clear();
  }

  // 先登记搜索结果与深度搜索抓取结果，保证它们先于正文引用获得编号。
  for (final block in reply.blocks) {
    if (block is! ServerToolUseBlock) continue;
    final result = results[block.id];
    if (result is WebSearchToolResultBlock) {
      for (final item in result.content) {
        if (item is WebSearchResult) {
          final source = registerSearchResult(item);
          if (!searchResults.contains(source)) searchResults.add(source);
        }
      }
    } else if (result is WebFetchToolResultBlock &&
        block.kind == ServerToolKind.deepSearch) {
      final content = result.content;
      if (content is WebFetchResult) {
        registry.add(content.url, content.title, content.publishedAt);
      }
    }
  }

  for (var index = 0; index < reply.blocks.length; index++) {
    final block = reply.blocks[index];
    // 任何非思考块都断开相邻思考块的合并，包括被跳过的模板块。
    if (block is! ThinkingBlock) mergedThinking = null;

    if (block is TextBlock) {
      // 模板统一由外层展示，不混入正文或过程性文字。
      if (block.isTemplate) continue;
      pending.add(_PendingText(index, block));
      continue;
    }
    if (block is ThinkingBlock) {
      if (mergedThinking != null) {
        mergedThinking.blocks.add(block);
      } else {
        // 首个思考块出现前先结算待定正文；空思考块也按块边界结算。
        flushPreamble();
        if (block.thinking.isNotEmpty) {
          mergedThinking = ThinkingStep(
            key: 'thinking-$index',
            blocks: [block],
          );
          steps.add(mergedThinking);
        }
      }
      continue;
    }
    if (block is! ServerToolUseBlock) continue;

    final result = results[block.id];
    final input = block.input;
    if (input is ReadLinkInput && input.url.isEmpty) {
      final content = result is WebFetchToolResultBlock ? result.content : null;
      if (content is! WebFetchResult || content.url.isEmpty) continue;
    }

    flushPreamble();
    final status = _statusFor(result, streaming);
    final last = steps.isEmpty ? null : steps.last;

    if (input is SearchInput) {
      final found = <Source>[
        if (result is WebSearchToolResultBlock)
          for (final item in result.content)
            if (item is WebSearchResult) registerSearchResult(item),
      ];
      // 普通搜索按种类合并到首次出现的位置；深度搜索只合并相邻同类调用。
      final target = isDeepSearchKind(block.kind)
          ? (last is SearchStep && last.kind == block.kind ? last : null)
          : mergedSearch[block.kind];
      if (target != null) {
        target.queries.addAll(input.queries);
        for (final source in found) {
          if (!target.results.contains(source)) target.results.add(source);
        }
        target.status = _mergeStatus([target.status, status]);
      } else {
        final step = SearchStep(
          key: block.id,
          kind: block.kind,
          queries: [...input.queries],
          results: found,
          status: status,
        );
        steps.add(step);
        if (!isDeepSearchKind(block.kind)) mergedSearch[block.kind] = step;
      }
      continue;
    }

    final content = result is WebFetchToolResultBlock ? result.content : null;
    final fetched = content is WebFetchResult ? content : null;
    final inputUrl = switch (input) {
      OpenPageInput(:final url) => url,
      FindInPageInput(:final url) => url,
      ReadLinkInput(:final url) => url,
      _ => '',
    };
    final url = inputUrl.isNotEmpty ? inputUrl : (fetched?.url ?? '');
    final fetchedTitle = fetched?.title;
    final page = PageItem(
      id: block.id,
      url: url,
      title: (fetchedTitle == null || fetchedTitle.isEmpty)
          ? url
          : fetchedTitle,
      status: status,
    );

    if (input is ReadLinkInput) {
      // 阅读链接只展示进行态；结束后行消失，原始块仍保留用于请求。
      if (status != ToolStatus.wip) continue;
      if (last is ReadLinkStep) {
        last.links.add(page);
      } else {
        steps.add(ReadLinkStep([page]));
      }
    } else if (input is OpenPageInput) {
      if (last is OpenStep) {
        last.pages.add(page);
      } else {
        steps.add(OpenStep([page]));
      }
    } else if (input is FindInPageInput) {
      final item = FindItem(id: block.id, pattern: input.pattern, status: status);
      if (last is FindStep) {
        last.patterns.add(item);
      } else {
        steps.add(FindStep([item]));
      }
    }
  }

  final answer = pending.isEmpty ? null : _joinTextBlocks(pending, registry);
  return ReplyView(
    steps: steps,
    answer: answer != null && answer.text.isNotEmpty ? answer : null,
    sources: registry.list,
    searchResults: searchResults,
  );
}

/// 拒答回复展示的文案：模板文本优先，其次图片审核文案，最后通用拒答文案
/// （`safety.md` §3）。非拒答回复返回 null。
String? refusalText(AppLocalizations l10n, AssistantMessage reply) {
  if (reply.stopReason != StopReason.refusal) return null;
  final template = reply.blocks
      .whereType<TextBlock>()
      .where((block) => block.isTemplate)
      .map((block) => block.text)
      .join()
      .trim();
  if (template.isNotEmpty) return template;
  final explanation = reply.stopDetails?.explanation?.trim() ?? '';
  return explanation.isEmpty ? l10n.replyRefused : l10n.replyImageBlocked;
}

final class _PendingText {
  const _PendingText(this.index, this.block);

  final int index;
  final TextBlock block;
}

/// 拼接正文块，并把每个块的引用登记后插入块尾（尾部空白之前）。
({String markdown, String text}) _joinTextBlocks(
  List<_PendingText> pending,
  _SourceRegistry registry,
) {
  var markdown = '';
  var text = '';
  for (final pendingBlock in pending) {
    final block = pendingBlock.block;
    text += block.text;
    final indexes = <int>{};
    for (final citation in block.citations) {
      indexes.add(registry.add(citation.url, citation.title, null).index);
    }
    final body = indexes.isEmpty ? block.text : block.text.trimRight();
    markdown += body;
    for (final index in indexes) {
      markdown += '[citation:$index]';
    }
    markdown += block.text.substring(body.length);
  }
  return (markdown: markdown, text: text);
}

ToolStatus _statusFor(ReplyBlock? result, bool streaming) {
  if (result == null) return streaming ? ToolStatus.wip : ToolStatus.failed;
  if (result is WebSearchToolResultBlock) {
    return result.content.any((item) => item is WebSearchResultError)
        ? ToolStatus.failed
        : ToolStatus.done;
  }
  if (result is WebFetchToolResultBlock) {
    return result.content is WebFetchResult ? ToolStatus.done : ToolStatus.failed;
  }
  return ToolStatus.failed;
}

ToolStatus _mergeStatus(Iterable<ToolStatus> statuses) {
  if (statuses.contains(ToolStatus.wip)) return ToolStatus.wip;
  if (statuses.every((status) => status == ToolStatus.failed)) {
    return ToolStatus.failed;
  }
  return ToolStatus.done;
}

/// 来源登记：同一 URL 只编号一次，后到的元数据只补空、不覆盖。
final class _SourceRegistry {
  final List<Source> list = [];
  final Map<String, Source> _byUrl = {};

  Source add(
    String url,
    String? title,
    String? publishedAt, {
    String? snippet,
    String? siteName,
    String? siteIcon,
  }) {
    final trimmedTitle = title?.trim() ?? '';
    final trimmedSiteName = siteName?.trim() ?? '';
    final trimmedSnippet = snippet?.trim() ?? '';
    final trimmedIcon = siteIcon?.trim() ?? '';
    final domain = _domainOf(url);
    final resolvedSiteName =
        trimmedSiteName.isEmpty ? domain : trimmedSiteName;
    final existing = _byUrl[url];
    if (existing != null) {
      if (existing.title == url && trimmedTitle.isNotEmpty) {
        existing.title = trimmedTitle;
      }
      if (trimmedSiteName.isNotEmpty && existing.siteName == domain) {
        existing.siteName = trimmedSiteName;
      }
      if ((existing.publishedAt ?? '').isEmpty &&
          (publishedAt ?? '').isNotEmpty) {
        existing.publishedAt = publishedAt;
      }
      if (existing.snippet == null && trimmedSnippet.isNotEmpty) {
        existing.snippet = trimmedSnippet;
      }
      if (existing.siteIcon == null && trimmedIcon.isNotEmpty) {
        existing.siteIcon = trimmedIcon;
      }
      return existing;
    }
    final source = Source(
      index: list.length + 1,
      url: url,
      title: trimmedTitle.isEmpty ? url : trimmedTitle,
      siteName: resolvedSiteName,
      publishedAt: publishedAt,
      snippet: trimmedSnippet.isEmpty ? null : trimmedSnippet,
      siteIcon: trimmedIcon.isEmpty ? null : trimmedIcon,
    );
    list.add(source);
    _byUrl[url] = source;
    return source;
  }
}

String _domainOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host.isEmpty) return '';
  return uri.host.replaceFirst(RegExp(r'^www\.'), '');
}
