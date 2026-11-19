import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/types.dart';
import 'errors.dart';
import 'request.dart';
import 'sse.dart';
import 'stream_events.dart';

/// DeepSeek 的 Anthropic 兼容 Messages 客户端（`api.md` §1、§8、§9）。
///
/// 应用共享一个实例与一个 [http.Client]。请求不设客户端超时：只有用户停止
/// 或服务端错误能提前结束流。
class DeepSeekApiClient {
  DeepSeekApiClient({
    http.Client? httpClient,
    Uri? origin,
    StreamEventParser? eventParser,
  })  : _http = httpClient ?? http.Client(),
        _origin = _normalizeOrigin(origin ?? _defaultOrigin),
        _eventParser = eventParser ?? StreamEventParser();

  static final Uri _defaultOrigin = Uri.parse(
    const String.fromEnvironment(
      'OPEN_CHAT_API_ORIGIN',
      defaultValue: 'https://api.deepseek.com',
    ),
  );

  /// Messages 之外的语音端点复用同一 API 源。
  static Uri get defaultOrigin => _defaultOrigin;

  static const String filesApiBeta = 'files-api-2025-04-14';

  final http.Client _http;
  final String _origin;
  final StreamEventParser _eventParser;

  void close() => _http.close();

  /// `GET /models`：任意 2xx 即视为 Key 有效。不解析响应体，也不产生费用。
  Future<void> validateApiKey(String apiKey) async {
    final response = await _guard(
      () => _http.get(
        Uri.parse('$_origin/models'),
        headers: {'Authorization': 'Bearer $apiKey'},
      ),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    throw ApiException(
      ApiErrorKind.http,
      _errorMessage(response.body, response),
      status: response.statusCode,
    );
  }

  /// `POST /anthropic/v1/files`：上传附件并返回 Files API 的 `file_id`。
  ///
  /// `purpose` 为 null 时不传该字段（图片）。Multipart 编码先写字段再写文件，
  /// 与 chat-demo 的 `purpose` 在前一致。上传本身不支持中止：移除附件后结果
  /// 直接丢弃（attachments.md §2）。
  Future<String> uploadFile({
    required String apiKey,
    required String path,
    required String filename,
    String? purpose,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_origin/anthropic/v1/files'),
    )
      ..headers.addAll({
        'x-api-key': apiKey,
        'anthropic-beta': filesApiBeta,
      });
    if (purpose != null) request.fields['purpose'] = purpose;
    request.files.add(
      await http.MultipartFile.fromPath('file', path, filename: filename),
    );

    final response = await _guard(() => _http.send(request));
    final body = await _guard(() => response.stream.bytesToString());
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        ApiErrorKind.http,
        _errorMessage(body, response),
        status: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(body);
      final id = decoded is Map ? decoded['id'] : null;
      if (id is String && id.isNotEmpty) return id;
    } on FormatException {
      // 落空到协议错误。
    }
    throw ApiException(ApiErrorKind.protocol, 'Missing file id in response');
  }

  /// 发送消息请求，按到达顺序产出解析后的事件。遇到 `message_stop` 或
  /// 已见 `stop_reason` 的 EOF 时结束。
  Stream<StreamEvent> streamMessage({
    required CreateMessageRequest request,
    required String apiKey,
    Future<void>? abortTrigger,
  }) async* {
    final messageRequest = http.AbortableRequest(
      'POST',
      Uri.parse('$_origin/anthropic/v1/messages'),
      abortTrigger: abortTrigger,
    )
      ..headers.addAll({
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream',
        'x-api-key': apiKey,
        if (request.hasFileBlocks) 'anthropic-beta': filesApiBeta,
      })
      ..body = jsonEncode(request.toJson());

    final response = await _guard(() => _http.send(messageRequest));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await _guard(() => response.stream.bytesToString());
      throw ApiException(
        ApiErrorKind.http,
        _errorMessage(body, response),
        status: response.statusCode,
      );
    }

    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (!contentType.contains('text/event-stream')) {
      final body = await _guard(() => response.stream.bytesToString());
      throw ApiException(
        ApiErrorKind.protocol,
        body.isNotEmpty
            ? body
            : response.reasonPhrase ?? 'Unexpected response',
      );
    }

    final decoder = SseDecoder();
    var sawBytes = false;
    var sawStopReason = false;
    var sawMessageStop = false;

    try {
      await for (final chunk in response.stream) {
        if (chunk.isEmpty) continue;
        sawBytes = true;
        for (final frame in decoder.add(chunk)) {
          final event = _parseFrame(frame);
          if (event == null) continue;
          if (event is MessageDelta) sawStopReason = true;
          yield event;
          if (event is MessageStop) {
            sawMessageStop = true;
            return;
          }
        }
      }
    } on http.RequestAbortedException {
      rethrow;
    } on ApiException {
      rethrow;
    } on http.ClientException catch (error) {
      throw ApiException(ApiErrorKind.network, error.message);
    } on SocketException catch (error) {
      throw ApiException(ApiErrorKind.network, error.message);
    } catch (error) {
      throw ApiException(ApiErrorKind.protocol, error.toString());
    } finally {
      decoder.close();
    }

    if (!sawBytes) {
      throw ApiException(
        ApiErrorKind.protocol,
        response.reasonPhrase ?? 'Empty response body',
      );
    }
    if (!sawMessageStop && !sawStopReason) {
      throw ApiException(ApiErrorKind.interrupted, 'Stream ended before completion');
    }
  }

  /// 传输层失败映射：本地取消原样抛出，连接/DNS 失败归为 network。
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on http.RequestAbortedException {
      rethrow;
    } on http.ClientException catch (error) {
      throw ApiException(ApiErrorKind.network, error.message);
    } on SocketException catch (error) {
      throw ApiException(ApiErrorKind.network, error.message);
    }
  }

  StreamEvent? _parseFrame(SseEvent frame) {
    try {
      return _eventParser.parse(frame);
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException(ApiErrorKind.protocol, error.toString());
    }
  }

  String _errorMessage(String body, http.BaseResponse response) {
    if (body.isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map) {
          final error = decoded['error'];
          if (error is Map && error['message'] is String) {
            return error['message'] as String;
          }
        }
      } on FormatException {
        // 解析失败时回退到响应原文。
      }
      return body;
    }
    return response.reasonPhrase ?? 'HTTP ${response.statusCode}';
  }

  static String _normalizeOrigin(Uri origin) =>
      origin.toString().replaceFirst(RegExp(r'/+$'), '');
}
