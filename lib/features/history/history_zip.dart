import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../shared/models/types.dart';

/// 历史归档（`history.md`）：chat-demo `export_format_version = 3` 的 ZIP。
///
/// 本文件只管格式、校验与领域对象转换，不做文件选择或数据库读写。
const int historyExportFormatVersion = 3;

const String historyManifestPath = 'manifest.json';
const String historyUserPath = 'user.json';
const String historyIndexPath = 'chat_session_index.json';

const int historyArchiveLimitBytes = 256 * 1024 * 1024;
const int historyJsonEntryLimitBytes = 32 * 1024 * 1024;
const int historyImageEntryLimitBytes = 64 * 1024 * 1024;
const int historyUncompressedLimitBytes = 512 * 1024 * 1024;

/// 导入导出失败的原因；界面按此显示文案。
enum HistoryError {
  tooLarge,
  unrecognized,
  newerVersion,
  invalidVersion,
  invalidJson,
  incomplete,
  invalidBranches,
  invalidFiles,
}

final class HistoryException implements Exception {
  const HistoryException(this.code);

  final HistoryError code;

  @override
  String toString() => 'HistoryException(${code.name})';
}

Never historyFail(HistoryError code) => throw HistoryException(code);

final class HistoryImage {
  const HistoryImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;
}

/// 解码后的归档：本地领域对象与按附件 id 去重的图片原件。
final class DecodedHistory {
  const DecodedHistory({required this.sessions, required this.images});

  final List<SessionHistory> sessions;
  final Map<String, HistoryImage> images;
}

String historySessionPath(String sessionId) => 'chat_sessions/$sessionId.json';

String historySessionFilesDir(String sessionId) =>
    'chat_sessions/${sessionId}_files/';

String? historyParseSessionPath(String path) {
  final match = RegExp(r'^chat_sessions/([^/]+)\.json$').firstMatch(path);
  return match?.group(1);
}

/// 安全路径片段：分隔符换下划线，空值、`.`、`..` 换 unnamed。
String historySafeName(String name) {
  final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
  return safe.isEmpty || safe == '.' || safe == '..' ? 'unnamed' : safe;
}

String historyImagePath(String sessionId, String fileId, String fileName) =>
    '${historySessionFilesDir(sessionId)}'
    '${historySafeName(fileId)}_${historySafeName(fileName)}';

/// 生成归档 ZIP。图片条目按会话各写一份；[imageBytes] 按附件 id 提供原件，
/// 缺失或非图片时只写元数据。[notice] 为错误 / 拒答回复补写导出时的模板文案。
Uint8List encodeHistoryZip(
  List<SessionHistory> sessions, {
  Map<String, Uint8List> imageBytes = const {},
  required String? Function(AssistantMessage reply) notice,
}) {
  final archive = Archive();
  final index = <Map<String, dynamic>>[];
  final images = <ArchiveFile>[];

  void addEntry(String name, List<int> bytes) {
    final file = ArchiveFile(name, bytes.length, bytes)..compress = false;
    archive.addFile(file);
  }

  void addJson(String name, Object? value, {bool jsonLimit = false}) {
    final bytes = utf8.encode(jsonEncode(value));
    if (jsonLimit && bytes.length > historyJsonEntryLimitBytes) {
      historyFail(HistoryError.tooLarge);
    }
    addEntry(name, bytes);
  }

  addJson(historyManifestPath, {
    'export_format_version': historyExportFormatVersion,
  });

  for (final tree in sessions) {
    final (file, sessionImages) = _encodeSession(
      tree,
      imageBytes: imageBytes,
      notice: notice,
    );
    addJson(historySessionPath(tree.session.id), file, jsonLimit: true);
    index.add({
      'id': file['id'],
      'title': file['title'],
      'pinned': tree.session.pinned,
      'message_count': (file['messages'] as List).length,
      'inserted_at': file['inserted_at'],
      'updated_at': file['updated_at'],
    });
    images.addAll(sessionImages);
  }

  addJson(historyIndexPath, index, jsonLimit: true);
  for (final file in images) {
    archive.addFile(file);
  }

  final bytes = ZipEncoder().encode(archive, level: 0);
  if (bytes == null || bytes.length > historyArchiveLimitBytes) {
    historyFail(HistoryError.tooLarge);
  }
  return Uint8List.fromList(bytes);
}

(Map<String, dynamic>, List<ArchiveFile>) _encodeSession(
  SessionHistory tree, {
  required Map<String, Uint8List> imageBytes,
  required String? Function(AssistantMessage reply) notice,
}) {
  final messages = tree.messages;
  final byId = {for (final message in messages) message.id: message};
  final ids = <String, int>{};
  final ordered = <Message>[];

  void visit(Message message) {
    if (ids.containsKey(message.id)) return;
    final parentId = message.parentId;
    if (parentId != null) {
      final parent = byId[parentId];
      if (parent == null) historyFail(HistoryError.invalidBranches);
      visit(parent);
    }
    ids[message.id] = ordered.length + 1;
    ordered.add(message);
  }

  for (final message in messages) {
    visit(message);
  }

  int idOf(Message message) =>
      ids[message.id] ?? historyFail(HistoryError.invalidBranches);

  Message? childById(String? id) => id == null ? null : byId[id];

  Message? current = childById(tree.session.rootMessageId);
  var guard = 0;
  while (current != null && current.selectedChildId != null) {
    final next = childById(current.selectedChildId);
    if (next == null || guard++ > messages.length) {
      historyFail(HistoryError.invalidBranches);
    }
    current = next;
  }

  final firstReply = <String, AssistantMessage>{};
  for (final message in ordered) {
    final parentId = message.parentId;
    if (message is AssistantMessage &&
        parentId != null &&
        !firstReply.containsKey(parentId)) {
      firstReply[parentId] = message;
    }
  }

  final images = <ArchiveFile>[];
  final jsonMessages = <Map<String, dynamic>>[];
  for (final message in ordered) {
    final base = {
      'id': idOf(message),
      'parent_id': message.parentId == null ? null : ids[message.parentId],
    };
    switch (message) {
      case UserMessage():
        final reply = firstReply[message.id];
        jsonMessages.add({
          ...base,
          'role': 'USER',
          'status': 'FINISHED',
          'thinking_enabled': reply?.thinking ?? false,
          'search_enabled': reply?.search ?? false,
          'accumulated_token_usage': 0,
          'inserted_at': _iso(message.createdAt),
          'fragments': _encodeUserFragments(
            message,
            sessionId: tree.session.id,
            imageBytes: imageBytes,
            images: images,
          ),
        });
      case AssistantMessage():
        jsonMessages.add({
          ...base,
          'role': 'ASSISTANT',
          'status': _archiveStatus(message),
          'thinking_enabled': message.thinking ?? false,
          'search_enabled': message.search ?? false,
          'accumulated_token_usage': _contextTokens(message),
          'inserted_at': _iso(message.createdAt),
          'fragments': _encodeAssistantFragments(message, notice: notice),
        });
    }
  }

  return (
    {
      'id': tree.session.id,
      'title': tree.session.title.isEmpty ? null : tree.session.title,
      'pinned': tree.session.pinned,
      'current_message_id': current == null ? 0 : idOf(current),
      'inserted_at': _iso(tree.session.createdAt),
      'updated_at': _iso(tree.session.updatedAt),
      'messages': jsonMessages,
    },
    images,
  );
}

List<Map<String, dynamic>> _encodeUserFragments(
  UserMessage message, {
  required String sessionId,
  required Map<String, Uint8List> imageBytes,
  required List<ArchiveFile> images,
}) {
  final files = [
    for (final attachment in message.attachments)
      {
        'id': attachment.id,
        'file_name': attachment.name,
        'file_size': attachment.size,
        'token_usage': null,
        'inserted_at': _iso(message.createdAt),
        'export_path': _exportImagePath(
          attachment,
          sessionId: sessionId,
          imageBytes: imageBytes,
          images: images,
        ),
        'is_image': attachment.isImage,
        'width': null,
        'height': null,
      },
  ];
  return [
    if (files.isNotEmpty) {'type': 'FILE', 'files': files},
    {'type': 'REQUEST', 'content': message.text},
  ];
}

String? _exportImagePath(
  Attachment attachment, {
  required String sessionId,
  required Map<String, Uint8List> imageBytes,
  required List<ArchiveFile> images,
}) {
  if (!attachment.isImage) return null;
  final bytes = imageBytes[attachment.id];
  if (bytes == null) return null;
  final path = historyImagePath(sessionId, attachment.id, attachment.name);
  images.add(
    ArchiveFile(path, bytes.length, bytes)..compress = false,
  );
  return path;
}

List<Map<String, dynamic>> _encodeAssistantFragments(
  AssistantMessage message, {
  required String? Function(AssistantMessage reply) notice,
}) {
  final fragments = <Map<String, dynamic>>[];
  final usedWeb = message.blocks.any((block) => block is ServerToolUseBlock);
  final results = <String, ReplyBlock>{};
  for (final block in message.blocks) {
    if (block is WebSearchToolResultBlock) {
      results[block.toolUseId] = block;
    } else if (block is WebFetchToolResultBlock) {
      results[block.toolUseId] = block;
    }
  }
  Map<String, dynamic>? response;
  var responseType = '';

  void flushResponse() {
    response = null;
    responseType = '';
  }

  for (final block in message.blocks) {
    if (block is TextBlock) {
      final type = block.isTemplate ? 'TEMPLATE_RESPONSE' : 'RESPONSE';
      if (response == null || responseType != type) {
        response = {'type': type, 'content': ''};
        responseType = type;
        fragments.add(response!);
      }
      final text = usedWeb
          ? block.text.replaceAll(RegExp(r'\[citation:\d+\]'), '')
          : block.text;
      response!['content'] = '${response!['content']}$text';
      continue;
    }
    if (block is ThinkingBlock) {
      if (block.thinking.isNotEmpty) {
        fragments.add({
          'type': 'THINK',
          'content': block.thinking,
          'elapsed_secs': _elapsedSeconds(block),
        });
      }
      flushResponse();
      continue;
    }
    if (block is ServerToolUseBlock) {
      final fragment = _toolFragment(block, results[block.id]);
      if (fragment != null) fragments.add(fragment);
      flushResponse();
    }
  }

  final hasTemplate =
      message.blocks.any((block) => block is TextBlock && block.isTemplate);
  final missingNotice = (message.status == ReplyStatus.error &&
          message.error != null) ||
      (!hasTemplate && message.stopReason == StopReason.refusal);
  if (missingNotice) {
    final text = notice(message);
    if (text != null) {
      fragments.add({'type': 'TEMPLATE_RESPONSE', 'content': text});
    }
  }
  return fragments;
}

int? _elapsedSeconds(ThinkingBlock block) {
  if (block.elapsedSeconds != null) return block.elapsedSeconds;
  if (block.startedAt == null || block.endedAt == null) return null;
  return (block.endedAt! - block.startedAt!) ~/ 1000;
}

Map<String, dynamic>? _toolFragment(
  ServerToolUseBlock tool,
  ReplyBlock? result,
) {
  final input = tool.input;
  if (input is SearchInput) {
    final queries = input.queries.isNotEmpty
        ? input.queries
        : [if (input.query != null) input.query!];
    final status = result is WebSearchToolResultBlock
        ? (result.content.any((item) => item is WebSearchResultError)
            ? 'FAILED'
            : 'FINISHED')
        : 'WIP';
    final items = result is WebSearchToolResultBlock
        ? result.content.whereType<WebSearchResult>()
        : const <WebSearchResult>[];
    return {
      'type': 'TOOL_SEARCH',
      'queries': queries,
      'status': status,
      'results': [
        for (final item in items)
          {
            'url': item.url,
            'title': item.title,
            'snippet': item.snippet,
            'published_at': _isoOrNull(item.pageAge),
            'site_name': item.siteName,
            'site_icon': item.siteIcon,
          },
      ],
    };
  }
  if (input is ReadLinkInput) {
    if (result is! WebFetchToolResultBlock ||
        result.kind != ServerToolKind.readLink ||
        result.content is! WebFetchResult ||
        (result.signature ?? '').trim().isEmpty) {
      return null;
    }
    final page = result.content as WebFetchResult;
    final url = page.url.isNotEmpty ? page.url : input.url;
    return {
      'type': 'READ_LINK',
      'results': [
        {
          if (url.isNotEmpty) 'url': url,
          'title': page.title,
          'signature': result.signature,
        },
      ],
    };
  }

  final fetch = result is WebFetchToolResultBlock ? result : null;
  final page = fetch?.content is WebFetchResult
      ? fetch!.content as WebFetchResult
      : null;
  final status = fetch == null ? 'WIP' : (page == null ? 'FAILED' : 'FINISHED');
  if (input is FindInPageInput) {
    return {'type': 'TOOL_FIND', 'status': status, 'pattern': input.pattern};
  }
  if (input is OpenPageInput) {
    final url = input.url.isNotEmpty ? input.url : page?.url;
    return {
      'type': 'TOOL_OPEN',
      'status': status,
      'url': url == null || url.isEmpty ? null : url,
      'title': page?.title,
      'snippet': page == null ? null : '',
      'site_name': null,
      'published_at': page == null ? null : _isoOrNull(page.publishedAt),
    };
  }
  return null;
}

String? _isoOrNull(String? value) {
  if (value == null) return null;
  final parsed = DateTime.tryParse(value);
  return parsed == null ? null : _iso(parsed);
}

String _archiveStatus(AssistantMessage message) {
  if (message.stopReason == StopReason.refusal) return 'CONTENT_FILTER';
  return switch (message.status) {
    ReplyStatus.done =>
      message.stopReason == StopReason.maxTokens ? 'INCOMPLETE' : 'FINISHED',
    ReplyStatus.stopped => 'INCOMPLETE',
    ReplyStatus.error => 'FAILED',
    ReplyStatus.pending || ReplyStatus.streaming => 'WIP',
  };
}

int _contextTokens(AssistantMessage message) {
  final usage = message.usage;
  if (usage == null) return 0;
  return usage.inputTokens +
      usage.cacheCreationInputTokens +
      usage.cacheReadInputTokens +
      usage.outputTokens;
}

String _iso(DateTime value) => value.toUtc().toIso8601String();

/// 解码并校验归档。消息 id 是会话内整数，这里统一换成 [newId] 生成的本地 id。
DecodedHistory decodeHistoryZip(
  Uint8List bytes, {
  required String Function() newId,
}) {
  if (bytes.length > historyArchiveLimitBytes) {
    historyFail(HistoryError.tooLarge);
  }
  _checkUncompressedSizes(bytes);
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: true);
  } on Object {
    historyFail(HistoryError.unrecognized);
  }

  final files = [
    for (final file in archive.files)
      if (file.isFile) file,
  ];
  if (files.isEmpty || files.first.name != historyManifestPath) {
    historyFail(HistoryError.unrecognized);
  }
  _checkManifest(_readJson(files.first));

  final sessionFiles = <String, _RawSession>{};
  Object? index;
  final imageEntries = <String, Uint8List>{};
  final entryNames = <String>{};
  var totalSize = 0;
  for (final file in files.skip(1)) {
    _checkEntryName(file.name);
    if (!entryNames.add(file.name)) historyFail(HistoryError.unrecognized);
    totalSize += file.size;
    if (totalSize > historyUncompressedLimitBytes) {
      historyFail(HistoryError.tooLarge);
    }
    final path = file.name;
    final sessionId = historyParseSessionPath(path);
    if (path == historyUserPath && index == null && sessionFiles.isEmpty) {
      continue;
    }
    if (sessionId != null && index == null) {
      if (sessionFiles.containsKey(sessionId)) {
        historyFail(HistoryError.incomplete);
      }
      sessionFiles[sessionId] = _parseSessionFile(
        _readJson(file, jsonLimit: true),
        sessionId: sessionId,
      );
      continue;
    }
    if (path == historyIndexPath && index == null) {
      index = _readJson(file, jsonLimit: true);
      continue;
    }
    if (_isImageEntry(path)) {
      if (file.size > historyImageEntryLimitBytes) {
        historyFail(HistoryError.tooLarge);
      }
      imageEntries[path] = Uint8List.fromList(file.content as List<int>);
      continue;
    }
    historyFail(HistoryError.incomplete);
  }

  if (index is! List) historyFail(HistoryError.incomplete);
  final indexIds = <String>{};
  for (final raw in index) {
    final entry = _record(raw);
    final id = _sessionId(entry['id']);
    if (!indexIds.add(id)) historyFail(HistoryError.incomplete);
    _nullableString(entry['title']);
    _count(entry['message_count']);
    _time(_string(entry['inserted_at']));
    _time(_string(entry['updated_at']));
  }
  if (indexIds.length != sessionFiles.length ||
      sessionFiles.keys.any((id) => !indexIds.contains(id))) {
    historyFail(HistoryError.incomplete);
  }

  final images = <String, HistoryImage>{};
  final sessions = <SessionHistory>[];
  for (final raw in sessionFiles.values) {
    final sessionImages = _resolveImages(raw, imageEntries);
    for (final entry in sessionImages.entries) {
      images.putIfAbsent(entry.key, () => entry.value);
    }
    sessions.add(_decodeSession(raw, images: sessionImages, newId: newId));
  }

  return DecodedHistory(sessions: sessions, images: images);
}

/// 只读中央目录，先按声明的大小拒绝超大条目与加密包，避免整包解压后才检查。
void _checkUncompressedSizes(Uint8List bytes) {
  final ZipDirectory directory;
  try {
    directory = ZipDirectory.read(InputStream(bytes));
  } on Object {
    historyFail(HistoryError.unrecognized);
  }
  var total = 0;
  for (final header in directory.fileHeaders) {
    // 加密条目不属于导出格式。
    if ((header.generalPurposeBitFlag & 1) != 0) {
      historyFail(HistoryError.unrecognized);
    }
    final size = header.uncompressedSize ?? 0;
    total += size;
    if (total > historyUncompressedLimitBytes) {
      historyFail(HistoryError.tooLarge);
    }
    final name = header.filename;
    final isJson = name == historyManifestPath ||
        name == historyIndexPath ||
        historyParseSessionPath(name) != null;
    if (isJson && size > historyJsonEntryLimitBytes) {
      historyFail(HistoryError.tooLarge);
    }
    if (_isImageEntry(name) && size > historyImageEntryLimitBytes) {
      historyFail(HistoryError.tooLarge);
    }
  }
}

bool _isImageEntry(String path) =>
    RegExp(r'^chat_sessions/[^/]+_files/.+$').hasMatch(path);

void _checkEntryName(String path) {
  if (path.isEmpty ||
      path.contains(r'\') ||
      path.contains('\u0000') ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    historyFail(HistoryError.unrecognized);
  }
  final parts = path.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    historyFail(HistoryError.unrecognized);
  }
}

Map<String, HistoryImage> _resolveImages(
  _RawSession session,
  Map<String, Uint8List> entries,
) {
  final images = <String, HistoryImage>{};
  final pathIds = <String, String>{};
  final directory = historySessionFilesDir(session.id);
  for (final message in session.messages) {
    for (final fragment in message.fragments.whereType<_RawFile>()) {
      for (final file in fragment.files) {
        // 图片身份来自归档；没有原件的图片只保留元数据。
        if (!file.isImage) continue;
        final path = file.exportPath;
        if (path == null) continue;
        final name = path.startsWith(directory)
            ? path.substring(directory.length)
            : '';
        if (name.isEmpty || name.contains('/')) {
          historyFail(HistoryError.invalidFiles);
        }
        final known = pathIds[path];
        if (known != null && known != file.id) {
          historyFail(HistoryError.invalidFiles);
        }
        pathIds[path] = file.id;
        final bytes = entries[path];
        if (bytes == null) continue;
        images.putIfAbsent(
          file.id,
          () => HistoryImage(bytes: bytes, mimeType: _imageMimeType(bytes)),
        );
      }
    }
  }
  return images;
}

String _imageMimeType(Uint8List bytes) {
  bool startsWith(List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  if (startsWith(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  final header = String.fromCharCodes(bytes.take(12));
  if (header.startsWith('GIF87a') || header.startsWith('GIF89a')) {
    return 'image/gif';
  }
  if (header.length >= 12 &&
      header.startsWith('RIFF') &&
      header.substring(8, 12) == 'WEBP') {
    return 'image/webp';
  }
  if (startsWith(const [0x42, 0x4d])) return 'image/bmp';
  if (startsWith(const [0x49, 0x49, 0x2a, 0x00]) ||
      startsWith(const [0x4d, 0x4d, 0x00, 0x2a])) {
    return 'image/tiff';
  }
  if (header.length >= 12 &&
      header.substring(4, 8) == 'ftyp' &&
      ['avif', 'avis'].contains(header.substring(8, 12))) {
    return 'image/avif';
  }
  return '';
}

void _checkManifest(Object? value) {
  final version = _record(value)['export_format_version'];
  if (version is! int) historyFail(HistoryError.invalidVersion);
  if (version > historyExportFormatVersion) {
    historyFail(HistoryError.newerVersion);
  }
  if (version != historyExportFormatVersion) {
    historyFail(HistoryError.invalidVersion);
  }
}

Object? _readJson(ArchiveFile file, {bool jsonLimit = false}) {
  if (jsonLimit && file.size > historyJsonEntryLimitBytes) {
    historyFail(HistoryError.tooLarge);
  }
  try {
    return jsonDecode(utf8.decode(file.content as List<int>));
  } on FormatException {
    historyFail(HistoryError.invalidJson);
  }
}

_RawSession _parseSessionFile(
  Object? value, {
  required String sessionId,
}) {
  final json = _record(value);
  if (_sessionId(json['id']) != sessionId) historyFail(HistoryError.incomplete);
  final rawMessages = [
    for (final raw in _list(json['messages'])) _parseMessage(_record(raw)),
  ]..sort((a, b) => a.id.compareTo(b.id));
  return _RawSession(
    id: sessionId,
    title: json['title'] == null ? '' : _string(json['title']),
    createdAt: _time(_string(json['inserted_at'])),
    updatedAt: _time(_string(json['updated_at'])),
    pinned: json['pinned'] == true,
    currentMessageId: _count(json['current_message_id']),
    messages: rawMessages,
  );
}

final class _RawSession {
  const _RawSession({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.pinned,
    required this.currentMessageId,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final int currentMessageId;
  final List<_RawMessage> messages;
}

SessionHistory _decodeSession(
  _RawSession raw, {
  required Map<String, HistoryImage> images,
  required String Function() newId,
}) {
  final sessionId = raw.id;
  final rawMessages = raw.messages;
  final currentId = raw.currentMessageId;

  final byId = <int, _RawMessage>{};
  for (final message in rawMessages) {
    if (byId.containsKey(message.id)) {
      historyFail(HistoryError.invalidBranches);
    }
    if (message.parentId != null) {
      final parent = byId[message.parentId];
      if (parent == null ||
          parent.id >= message.id ||
          parent.role == message.role) {
        historyFail(HistoryError.invalidBranches);
      }
    } else if (message.role != _Role.user) {
      historyFail(HistoryError.invalidBranches);
    }
    byId[message.id] = message;
  }

  final selected = <int, int>{};
  for (final message in rawMessages) {
    final parentId = message.parentId;
    if (parentId != null) selected[parentId] = message.id;
  }
  _RawMessage? current;
  if (rawMessages.isNotEmpty) {
    current = byId[currentId] ?? historyFail(HistoryError.invalidBranches);
    final currentRawId = current.id;
    while (current!.parentId != null) {
      final parent = byId[current.parentId]!;
      selected[parent.id] = current.id;
      current = parent;
    }
    // 当前停留的消息不再展开；它后面的节点也不在当前分支上。
    selected.remove(currentRawId);
  }

  final localIds = {
    for (final message in rawMessages) message.id: newId(),
  };

  final messages = <Message>[];
  for (final raw in rawMessages) {
    final id = localIds[raw.id]!;
    final parentId = raw.parentId == null ? null : localIds[raw.parentId]!;
    final selectedChildId = selected.containsKey(raw.id)
        ? localIds[selected[raw.id]]!
        : null;
    switch (raw.role) {
      case _Role.user:
        messages.add(UserMessage(
          id: id,
          parentId: parentId,
          selectedChildId: selectedChildId,
          createdAt: raw.createdAt,
          text: raw.text,
          attachments: raw.attachments(images),
        ));
      case _Role.assistant:
        messages.add(AssistantMessage(
          id: id,
          parentId: parentId,
          selectedChildId: selectedChildId,
          createdAt: raw.createdAt,
          status: raw.status,
          blocks: raw.blocks,
          thinking: raw.thinking,
          search: raw.search,
          prefix: false,
          stopReason: raw.stopReason,
        ));
    }
  }

  return SessionHistory(
    session: Session(
      id: sessionId,
      title: raw.title,
      createdAt: raw.createdAt,
      updatedAt: raw.updatedAt,
      rootMessageId: current == null ? null : localIds[current.id],
      pinned: raw.pinned,
    ),
    messages: messages,
  );
}

enum _Role { user, assistant }

final class _RawMessage {
  const _RawMessage({
    required this.id,
    required this.parentId,
    required this.role,
    required this.createdAt,
    required this.status,
    required this.thinking,
    required this.search,
    required this.fragments,
    required this.stopReason,
  });

  final int id;
  final int? parentId;
  final _Role role;
  final DateTime createdAt;
  final ReplyStatus status;
  final bool thinking;
  final bool search;
  final List<_RawFragment> fragments;
  final StopReason? stopReason;

  String get text => fragments
      .whereType<_RawRequest>()
      .map((item) => item.content)
      .join();

  List<ReplyBlock> get blocks {
    final searchKind = fragments.any(
      (fragment) => fragment is _RawToolOpen || fragment is _RawToolFind,
    )
        ? ServerToolKind.deepSearch
        : ServerToolKind.search;
    var blocks = <ReplyBlock>[
      for (var index = 0; index < fragments.length; index++)
        ...fragments[index].toBlocks(searchKind, 'history-$id-$index'),
    ];
    if (stopReason == StopReason.refusal) {
      blocks = [
        for (final block in blocks)
          if (block is! ThinkingBlock &&
              (block is! TextBlock || block.isTemplate))
            block,
      ];
    }
    return blocks;
  }

  List<Attachment> attachments(Map<String, HistoryImage> images) => [
        for (final fragment in fragments.whereType<_RawFile>())
          for (final file in fragment.files)
            Attachment(
              id: file.id,
              name: file.name,
              size: file.size,
              isImage: file.isImage,
              mimeType: images[file.id]?.mimeType ?? '',
            ),
      ];
}

_RawMessage _parseMessage(Map<String, dynamic> json) {
  final role = switch (_string(json['role'])) {
    'USER' => _Role.user,
    'ASSISTANT' => _Role.assistant,
    _ => historyFail(HistoryError.invalidBranches),
  };
  final archiveStatus = _string(json['status']);
  final localStatus = switch (archiveStatus) {
    'FINISHED' => ReplyStatus.done,
    'CONTENT_FILTER' => ReplyStatus.done,
    'FAILED' => ReplyStatus.error,
    'CONTEXT_LENGTH_EXCEEDED' => ReplyStatus.error,
    'INCOMPLETE' => ReplyStatus.stopped,
    'TIMEOUT' => ReplyStatus.error,
    'WIP' => ReplyStatus.stopped,
    _ => historyFail(HistoryError.incomplete),
  };
  final id = _count(json['id']);
  final fragments = <_RawFragment>[];
  for (final raw in _list(json['fragments'])) {
    final fragment = _tryFragment(raw);
    if (fragment != null) fragments.add(fragment);
  }
  final refused = archiveStatus == 'CONTENT_FILTER';
  _count(json['accumulated_token_usage']);
  return _RawMessage(
    id: id,
    parentId: json['parent_id'] == null ? null : _count(json['parent_id']),
    role: role,
    createdAt: _time(_string(json['inserted_at'])),
    status: localStatus,
    thinking: _boolean(json['thinking_enabled']),
    search: _boolean(json['search_enabled']),
    fragments: fragments,
    stopReason: refused ? StopReason.refusal : null,
  );
}

sealed class _RawFragment {
  const _RawFragment();

  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) =>
      const [];
}

final class _RawRequest extends _RawFragment {
  const _RawRequest(this.content);
  final String content;
}

final class _RawText extends _RawFragment {
  const _RawText(this.text, {this.isTemplate = false});
  final String text;
  final bool isTemplate;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) => [
        TextBlock(text: text, isTemplate: isTemplate),
      ];
}

final class _RawThink extends _RawFragment {
  const _RawThink(this.thinking, this.elapsedSeconds);
  final String thinking;
  final int? elapsedSeconds;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) => [
        ThinkingBlock(thinking: thinking, elapsedSeconds: elapsedSeconds),
      ];
}

final class _RawSearchResult {
  const _RawSearchResult({
    required this.url,
    required this.title,
    required this.snippet,
    required this.publishedAt,
    required this.siteName,
    required this.siteIcon,
  });

  final String url;
  final String title;
  final String snippet;
  final DateTime? publishedAt;
  final String? siteName;
  final String? siteIcon;
}

final class _RawToolSearch extends _RawFragment {
  const _RawToolSearch({
    required this.queries,
    required this.results,
    required this.status,
  });

  final List<String> queries;
  final List<_RawSearchResult> results;
  final String? status;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) {
    final input = SearchInput(
      query: queries.isEmpty ? null : queries.first,
      queries: queries,
    );
    final tool = ServerToolUseBlock(
      id: toolId,
      name: 'deepseek_web_search',
      input: input,
      kind: searchKind,
    );
    if (status == 'WIP') return [tool];
    final content = status == 'FAILED'
        ? const <WebSearchResultItem>[
            WebSearchResultError('unavailable'),
          ]
        : <WebSearchResultItem>[
            for (final result in results)
              if (_isWebUrl(result.url))
                WebSearchResult(
                  title: result.title,
                  url: result.url,
                  snippet: result.snippet,
                  encryptedContent: '',
                  siteIcon: result.siteIcon,
                  siteName: result.siteName,
                  pageAge: result.publishedAt?.toUtc().toIso8601String(),
                ),
          ];
    return [
      tool,
      WebSearchToolResultBlock(
        toolUseId: toolId,
        content: content,
        kind: searchKind,
      ),
    ];
  }
}

final class _RawToolOpen extends _RawFragment {
  const _RawToolOpen({
    required this.status,
    required this.url,
    required this.title,
    required this.publishedAt,
  });

  final String status;
  final String? url;
  final String? title;
  final DateTime? publishedAt;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) {
    final url = this.url;
    if (url == null || !_isWebUrl(url)) return const [];
    final tool = ServerToolUseBlock(
      id: toolId,
      name: 'deepseek_web_search',
      input: OpenPageInput(url),
      kind: ServerToolKind.deepSearch,
    );
    if (status == 'WIP') return [tool];
    final content = status == 'FINISHED'
        ? _fetchedPage(
            url,
            title,
            publishedAt?.toUtc().toIso8601String(),
          )
        : const WebFetchResultError('unavailable');
    return [
      tool,
      WebFetchToolResultBlock(
        toolUseId: toolId,
        kind: ServerToolKind.deepSearch,
        content: content,
      ),
    ];
  }
}

final class _RawToolFind extends _RawFragment {
  const _RawToolFind({required this.status, required this.pattern});

  final String status;
  final String? pattern;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) {
    final tool = ServerToolUseBlock(
      id: toolId,
      name: 'deepseek_web_search',
      input: FindInPageInput(url: '', pattern: pattern ?? ''),
      kind: ServerToolKind.deepSearch,
    );
    if (status == 'WIP') return [tool];
    final content = status == 'FINISHED'
        ? _fetchedPage('', null, null)
        : const WebFetchResultError('unavailable');
    return [
      tool,
      WebFetchToolResultBlock(
        toolUseId: toolId,
        kind: ServerToolKind.deepSearch,
        content: content,
      ),
    ];
  }
}

final class _RawReadLinkResult {
  const _RawReadLinkResult({
    required this.url,
    required this.title,
    required this.signature,
  });

  final String? url;
  final String? title;
  final String signature;
}

final class _RawReadLink extends _RawFragment {
  const _RawReadLink(this.results);
  final List<_RawReadLinkResult> results;

  @override
  List<ReplyBlock> toBlocks(ServerToolKind searchKind, String toolId) {
    final blocks = <ReplyBlock>[];
    for (var index = 0; index < results.length; index++) {
      final result = results[index];
      final url = result.url != null && _isWebUrl(result.url!) ? result.url! : '';
      if (url.isEmpty && result.signature.trim().isEmpty) continue;
      final id = '$toolId-$index';
      blocks.add(
        ServerToolUseBlock(
          id: id,
          name: 'deepseek_read_url',
          input: ReadLinkInput(url),
          kind: ServerToolKind.readLink,
        ),
      );
      blocks.add(
        WebFetchToolResultBlock(
          toolUseId: id,
          kind: ServerToolKind.readLink,
          content: _fetchedPage(url, result.title, null),
          signature: result.signature,
        ),
      );
    }
    return blocks;
  }
}

WebFetchResult _fetchedPage(
  String url,
  String? title,
  String? publishedAt,
) =>
    WebFetchResult(
      url: url,
      content: {
        'type': 'document',
        'source': {'type': 'text', 'media_type': 'text/plain', 'data': ''},
        'title': title,
      },
      publishedAt: publishedAt,
    );

bool _isWebUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

final class _RawFileEntry {
  const _RawFileEntry({
    required this.id,
    required this.name,
    required this.size,
    required this.isImage,
    required this.exportPath,
  });

  final String id;
  final String name;
  final int size;
  final bool isImage;
  final String? exportPath;
}

final class _RawFile extends _RawFragment {
  const _RawFile(this.files);
  final List<_RawFileEntry> files;
}

_RawFragment? _tryFragment(Object? value) {
  try {
    final json = _record(value);
    return switch (_string(json['type'])) {
      'REQUEST' => _RawRequest(_string(json['content'])),
      'RESPONSE' => _RawText(_string(json['content'])),
      'TEMPLATE_RESPONSE' => _RawText(
          _string(json['content']),
          isTemplate: true,
        ),
      'THINK' => _RawThink(
          _string(json['content']),
          json['elapsed_secs'] == null
              ? null
              : _duration(json['elapsed_secs']),
        ),
      'FILE' => _RawFile([
          for (final rawFile in _list(json['files']))
            _parseFileEntry(_record(rawFile)),
        ]),
      'TOOL_SEARCH' => _RawToolSearch(
          queries: [for (final query in _list(json['queries'])) _string(query)],
          results: [
            for (final result in _list(json['results']))
              _parseSearchResult(_record(result)),
          ],
          status: json['status'] == null
              ? null
              : _oneOf(json['status'], const ['WIP', 'FINISHED', 'FAILED']),
        ),
      'TOOL_OPEN' => _RawToolOpen(
          status: _oneOf(json['status'], const ['WIP', 'FINISHED', 'FAILED']),
          url: _nullableString(json['url']),
          title: _nullableString(json['title']),
          publishedAt: json['published_at'] == null
              ? null
              : _time(_string(json['published_at'])),
        ),
      'TOOL_FIND' => _RawToolFind(
          status: _oneOf(
            json['status'],
            const ['WIP', 'FINISHED', 'NO_RESULT', 'FAILED'],
          ),
          pattern: json['pattern'] == null ? null : _string(json['pattern']),
        ),
      'READ_LINK' => _RawReadLink([
          for (final result in _list(json['results']))
            _parseReadLinkResult(_record(result)),
        ]),
      _ => null,
    };
  } on HistoryException catch (error) {
    // 附件 id 会进入本地文件路径，不安全时整包失败，不能当作可丢弃片段。
    if (error.code == HistoryError.invalidFiles) rethrow;
    return null;
  }
}

_RawSearchResult _parseSearchResult(Map<String, dynamic> json) =>
    _RawSearchResult(
      url: _string(json['url']),
      title: _string(json['title']),
      snippet: _string(json['snippet']),
      publishedAt: json['published_at'] == null
          ? null
          : _time(_string(json['published_at'])),
      siteName: _nullableString(json['site_name']),
      siteIcon: json['site_icon'] == null
          ? null
          : _nullableString(json['site_icon']),
    );

_RawReadLinkResult _parseReadLinkResult(Map<String, dynamic> json) =>
    _RawReadLinkResult(
      url: json['url'] == null ? null : _string(json['url']),
      title: _nullableString(json['title']),
      signature: _string(json['signature']),
    );

int? _duration(Object? value) {
  if (value is num && value.isFinite && value >= 0) return value.round();
  historyFail(HistoryError.incomplete);
}

String _fileId(Object? value) {
  final id = _string(value);
  if (id.isEmpty ||
      id.contains('/') ||
      id.contains(r'\') ||
      id.contains('\u0000') ||
      id == '.' ||
      id == '..' ||
      RegExp(r'^[A-Za-z]:').hasMatch(id)) {
    historyFail(HistoryError.invalidFiles);
  }
  return id;
}

String _oneOf(Object? value, List<String> allowed) {
  final text = _string(value);
  return allowed.contains(text) ? text : historyFail(HistoryError.incomplete);
}

_RawFileEntry _parseFileEntry(Map<String, dynamic> json) {
  final id = _fileId(json['id']);
  _time(_string(json['inserted_at']));
  if (json['token_usage'] != null) _count(json['token_usage']);
  if (json['width'] != null) _count(json['width']);
  if (json['height'] != null) _count(json['height']);
  return _RawFileEntry(
    id: id,
    name: _string(json['file_name']),
    size: _count(json['file_size']),
    isImage: _boolean(json['is_image']),
    exportPath: _nullableString(json['export_path']),
  );
}

// ---------------------------------------------------------------- 校验助手

Map<String, dynamic> _record(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  historyFail(HistoryError.incomplete);
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  historyFail(HistoryError.incomplete);
}

String _string(Object? value) {
  if (value is String) return value;
  historyFail(HistoryError.incomplete);
}

String? _nullableString(Object? value) =>
    value == null ? null : _string(value);

bool _boolean(Object? value) {
  if (value is bool) return value;
  historyFail(HistoryError.incomplete);
}

int _count(Object? value) {
  if (value is int && value >= 0) return value;
  historyFail(HistoryError.incomplete);
}

String _sessionId(Object? value) {
  final id = _string(value);
  if (id.isEmpty || id.contains('/') || id.contains(r'\') || id == '.' || id == '..') {
    historyFail(HistoryError.incomplete);
  }
  return id;
}

DateTime _time(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$')
      .hasMatch(value)) {
    historyFail(HistoryError.incomplete);
  }
  try {
    return DateTime.parse(value);
  } on FormatException {
    historyFail(HistoryError.incomplete);
  }
}
