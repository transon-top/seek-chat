import 'dart:convert';

import 'types.dart';

Map<String, dynamic>? asJsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return null;
}

String? asString(Object? value) => value is String ? value : null;

int? asInt(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

bool? asBool(Object? value) => value is bool ? value : null;

List<String> asStringList(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

/// 解码 JSON 列；数据损坏时返回 null 而不抛异常。
Object? decodeJsonSource(String? source) {
  if (source == null || source.isEmpty) return null;
  try {
    return jsonDecode(source);
  } on FormatException {
    return null;
  }
}

// ------------------------------------------------------------------- 引用

TextCitation? parseCitation(Object? value) {
  final json = asJsonMap(value);
  if (json == null) return null;
  final url = asString(json['url']);
  if (url == null) return null;
  return TextCitation(
    url: url,
    title: asString(json['title']),
    citedText: asString(json['cited_text']) ?? '',
    encryptedIndex: asString(json['encrypted_index']) ?? '',
  );
}

Map<String, dynamic> encodeCitation(TextCitation citation) => {
      'type': 'web_search_result_location',
      'url': citation.url,
      'title': citation.title,
      'cited_text': citation.citedText,
      'encrypted_index': citation.encryptedIndex,
    };

// ------------------------------------------------------------- 工具输入

ServerToolInput parseToolInput(Object? value) {
  final json = asJsonMap(value);
  if (json == null) return UnknownToolInput(const {});
  switch (asString(json['action'])) {
    case 'search':
      return SearchInput(
        query: asString(json['query']),
        queries: asStringList(json['queries']),
      );
    case 'open_page':
      return OpenPageInput(asString(json['url']) ?? '');
    case 'find_in_page':
      return FindInPageInput(
        url: asString(json['url']) ?? '',
        pattern: asString(json['pattern']) ?? '',
      );
    case 'read_link':
      return ReadLinkInput(asString(json['url']) ?? '');
    default:
      return UnknownToolInput(json);
  }
}

Map<String, dynamic> encodeToolInput(ServerToolInput input) => switch (input) {
      SearchInput(:final query, :final queries) => {
          'action': 'search',
          'query': ?query,
          'queries': queries,
        },
      OpenPageInput(:final url) => {'action': 'open_page', 'url': url},
      FindInPageInput(:final url, :final pattern) => {
          'action': 'find_in_page',
          'url': url,
          'pattern': pattern,
        },
      ReadLinkInput(:final url) => {'action': 'read_link', 'url': url},
      UnknownToolInput(:final json) => json,
    };

// ------------------------------------------------------------- 回复块

/// 解析一个协议内容块。未知块类型返回 null，调用方可跳过且不占下标。
///
/// [thinkingStartedAt] 是实时流块的接收时间；持久化的块自带
/// [ThinkingBlock.startedAt]。
ReplyBlock? parseReplyBlock(Map<String, dynamic> json, {int? thinkingStartedAt}) {
  switch (asString(json['type'])) {
    case 'text':
      final citations = <TextCitation>[];
      final raw = json['citations'];
      if (raw is List) {
        for (final item in raw) {
          final citation = parseCitation(item);
          if (citation != null) citations.add(citation);
        }
      }
      return TextBlock(
        text: asString(json['text']) ?? '',
        citations: citations,
        isTemplate: asBool(json['isTemplate']) ?? false,
      );

    case 'thinking':
      return ThinkingBlock(
        thinking: asString(json['thinking']) ?? '',
        signature: asString(json['signature']) ?? '',
        startedAt: asInt(json['startedAt']) ?? thinkingStartedAt,
        endedAt: asInt(json['endedAt']),
        elapsedSeconds: asInt(json['elapsedSeconds']),
      );

    case 'server_tool_use':
      final id = asString(json['id']);
      final kind = ServerToolKind.fromWire(asString(json['kind']));
      if (id == null || kind == null) return null;
      return ServerToolUseBlock(
        id: id,
        name: asString(json['name']) ?? '',
        input: parseToolInput(json['input']),
        kind: kind,
        caller: asJsonMap(json['caller']) ?? const {'type': 'direct'},
      );

    case 'web_search_tool_result':
      final toolUseId = asString(json['tool_use_id']);
      final kind = ServerToolKind.fromWire(asString(json['kind']));
      if (toolUseId == null || kind == null) return null;
      final items = <WebSearchResultItem>[];
      final raw = json['content'];
      if (raw is List) {
        for (final item in raw) {
          final parsed = _parseSearchItem(asJsonMap(item));
          if (parsed != null) items.add(parsed);
        }
      }
      return WebSearchToolResultBlock(
        toolUseId: toolUseId,
        content: items,
        kind: kind,
      );

    case 'web_fetch_tool_result':
      final toolUseId = asString(json['tool_use_id']);
      final kind = ServerToolKind.fromWire(asString(json['kind']));
      final content = _parseFetchContent(asJsonMap(json['content']));
      if (toolUseId == null || kind == null || content == null) return null;
      return WebFetchToolResultBlock(
        toolUseId: toolUseId,
        content: content,
        kind: kind,
        signature: asString(json['signature']),
      );

    default:
      return null;
  }
}

WebSearchResultItem? _parseSearchItem(Map<String, dynamic>? json) {
  if (json == null) return null;
  switch (asString(json['type'])) {
    case 'web_search_result':
      return WebSearchResult(
        title: asString(json['title']) ?? '',
        url: asString(json['url']) ?? '',
        snippet: asString(json['snippet']) ?? '',
        imageUrl: asString(json['image_url']),
        siteIcon: asString(json['site_icon']),
        siteName: asString(json['site_name']),
        encryptedContent: asString(json['encrypted_content']) ?? '',
        pageAge: asString(json['page_age']),
      );
    case 'web_search_tool_result_error':
      return WebSearchResultError(asString(json['error_code']) ?? 'unavailable');
    default:
      return null;
  }
}

WebFetchContent? _parseFetchContent(Map<String, dynamic>? json) {
  if (json == null) return null;
  switch (asString(json['type'])) {
    case 'web_fetch_result':
      return WebFetchResult(
        url: asString(json['url']) ?? '',
        content: asJsonMap(json['content']) ?? const {},
        publishedAt: asString(json['published_at']),
      );
    case 'web_fetch_tool_result_error':
      return WebFetchResultError(asString(json['error_code']) ?? 'unavailable');
    default:
      return null;
  }
}

Map<String, dynamic> encodeReplyBlock(ReplyBlock block) => switch (block) {
      TextBlock(:final text, :final citations, :final isTemplate) => {
          'type': 'text',
          'text': text,
          'citations': citations.map(encodeCitation).toList(),
          'isTemplate': isTemplate,
        },
      ThinkingBlock(
        :final thinking,
        :final signature,
        :final startedAt,
        :final endedAt,
        :final elapsedSeconds,
      ) =>
        {
          'type': 'thinking',
          'thinking': thinking,
          'signature': signature,
          'startedAt': startedAt,
          'endedAt': endedAt,
          'elapsedSeconds': elapsedSeconds,
        },
      ServerToolUseBlock(
        :final id,
        :final name,
        :final input,
        :final kind,
        :final caller,
      ) =>
        {
          'type': 'server_tool_use',
          'id': id,
          'name': name,
          'input': encodeToolInput(input),
          'kind': kind.wire,
          'caller': caller,
        },
      WebSearchToolResultBlock(
        :final toolUseId,
        :final content,
        :final kind,
      ) =>
        {
          'type': 'web_search_tool_result',
          'tool_use_id': toolUseId,
          'kind': kind.wire,
          'content': content.map(_encodeSearchItem).toList(),
        },
      WebFetchToolResultBlock(
        :final toolUseId,
        :final content,
        :final kind,
        :final signature,
      ) =>
        {
          'type': 'web_fetch_tool_result',
          'tool_use_id': toolUseId,
          'kind': kind.wire,
          'content': _encodeFetchContent(content),
          'signature': ?signature,
        },
    };

Map<String, dynamic> _encodeSearchItem(WebSearchResultItem item) =>
    switch (item) {
      WebSearchResult(
        :final title,
        :final url,
        :final snippet,
        :final imageUrl,
        :final siteIcon,
        :final siteName,
        :final encryptedContent,
        :final pageAge,
      ) =>
        {
          'type': 'web_search_result',
          'title': title,
          'url': url,
          'snippet': snippet,
          'image_url': ?imageUrl,
          'site_icon': siteIcon,
          'site_name': siteName,
          'encrypted_content': encryptedContent,
          'page_age': pageAge,
        },
      WebSearchResultError(:final errorCode) => {
          'type': 'web_search_tool_result_error',
          'error_code': errorCode,
        },
    };

Map<String, dynamic> _encodeFetchContent(WebFetchContent content) =>
    switch (content) {
      WebFetchResult(:final url, :final content, :final publishedAt) => {
          'type': 'web_fetch_result',
          'url': url,
          'content': content,
          'published_at': publishedAt,
        },
      WebFetchResultError(:final errorCode) => {
          'type': 'web_fetch_tool_result_error',
          'error_code': errorCode,
        },
    };

List<ReplyBlock> decodeReplyBlocks(String? source) {
  if (source == null || source.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return const [];
  }
  if (decoded is! List) return const [];
  final blocks = <ReplyBlock>[];
  for (final item in decoded) {
    final json = asJsonMap(item);
    if (json == null) continue;
    final block = parseReplyBlock(json);
    if (block != null) blocks.add(block);
  }
  return blocks;
}

String encodeReplyBlocks(List<ReplyBlock> blocks) =>
    jsonEncode(blocks.map(encodeReplyBlock).toList());

// ------------------------------------------------------------------- 用量

Usage? parseUsage(Object? value) {
  final json = asJsonMap(value);
  if (json == null) return null;
  final serverToolUse = asJsonMap(json['server_tool_use']);
  return Usage(
    inputTokens: asInt(json['input_tokens']) ?? 0,
    cacheCreationInputTokens: asInt(json['cache_creation_input_tokens']) ?? 0,
    cacheReadInputTokens: asInt(json['cache_read_input_tokens']) ?? 0,
    outputTokens: asInt(json['output_tokens']) ?? 0,
    webSearchRequests: asInt(serverToolUse?['web_search_requests']),
    toolSearch: asInt(serverToolUse?['tool_search']),
  );
}

Map<String, dynamic> encodeUsage(Usage usage) => {
      'input_tokens': usage.inputTokens,
      'cache_creation_input_tokens': usage.cacheCreationInputTokens,
      'cache_read_input_tokens': usage.cacheReadInputTokens,
      'output_tokens': usage.outputTokens,
      if (usage.webSearchRequests != null || usage.toolSearch != null)
        'server_tool_use': {
          if (usage.webSearchRequests != null)
            'web_search_requests': usage.webSearchRequests,
          if (usage.toolSearch != null) 'tool_search': usage.toolSearch,
        },
    };

StopDetails? parseStopDetails(Object? value) {
  final json = asJsonMap(value);
  if (json == null) return null;
  return StopDetails(
    type: asString(json['type']) ?? 'refusal',
    category: asString(json['category']),
    explanation: asString(json['explanation']),
  );
}

Map<String, dynamic> encodeStopDetails(StopDetails details) => {
      'type': details.type,
      'category': details.category,
      'explanation': details.explanation,
    };

// ------------------------------------------------------------------- 错误

ApiErrorKind? apiErrorKindFromWire(String? value) {
  for (final kind in ApiErrorKind.values) {
    if (kind.name == value) return kind;
  }
  return null;
}

ReplyError? parseReplyError(String? source) {
  if (source == null || source.isEmpty) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    return null;
  }
  final json = asJsonMap(decoded);
  if (json == null) return null;
  final kind = apiErrorKindFromWire(asString(json['kind']));
  final message = asString(json['message']);
  if (kind == null || message == null) return null;
  final local = asJsonMap(json['localMessage']);
  return ReplyError(
    kind: kind,
    message: message,
    status: asInt(json['status']),
    localMessage: local == null
        ? null
        : LocalMessage(
            key: asString(local['key']) ?? '',
            params: asJsonMap(local['params']) ?? const {},
          ),
    retryable: asBool(json['retryable']),
  );
}

String encodeReplyError(ReplyError error) => jsonEncode({
      'kind': error.kind.name,
      'message': error.message,
      'status': error.status,
      if (error.localMessage != null)
        'localMessage': {
          'key': error.localMessage!.key,
          'params': error.localMessage!.params,
        },
      if (error.retryable != null) 'retryable': error.retryable,
    });
