import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../shared/api/client.dart';
import '../../../shared/api/errors.dart';
import '../../../shared/models/types.dart';
import '../../../shared/prefs/speech_store.dart';

/// 本地录音为空，未发出请求（`speech.md` §3.3）。
final class EmptyRecordingException implements Exception {
  const EmptyRecordingException();
}

/// 语音工具端点：ASR 一次性转写与 TTS PCM 流。
///
/// 两者都是 `/v1/tools/*`，用 `Authorization: Bearer`，与 Messages 端点
/// 分开（`speech.md` §3.3、§4.2）。请求可随 [abortTrigger] 取消。
abstract interface class SpeechApi {
  Future<String> transcribe({
    required String path,
    required String apiKey,
    Future<void>? abortTrigger,
  });

  Stream<Uint8List> synthesize({
    required String text,
    required TtsVoice voice,
    required String apiKey,
    Future<void>? abortTrigger,
  });

  void close();
}

class DeepSeekSpeechApi implements SpeechApi {
  DeepSeekSpeechApi({http.Client? httpClient, Uri? origin})
    : _http = httpClient ?? http.Client(),
      _origin = (origin ?? DeepSeekApiClient.defaultOrigin)
          .toString()
          .replaceFirst(RegExp(r'/+$'), '');

  /// 上传前的大小闸门；120 秒录音远小于此值。
  static const int maxRecordingBytes = 8 * 1024 * 1024;

  final http.Client _http;
  final String _origin;

  @override
  void close() => _http.close();

  /// `POST /v1/tools/asr`：整段 WAV 转成文本。只读取响应中的 `text`。
  @override
  Future<String> transcribe({
    required String path,
    required String apiKey,
    Future<void>? abortTrigger,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (error) {
      throw ApiException(ApiErrorKind.protocol, error.message);
    } finally {
      // 临时录音用后即删，无论上传是否继续（speech.md §3.2）。
      unawaited(_deleteQuietly(path));
    }
    if (bytes.isEmpty) throw const EmptyRecordingException();
    if (bytes.length > maxRecordingBytes) {
      throw ApiException(ApiErrorKind.http, 'Recording too large', status: 413);
    }

    final uri = Uri.parse('$_origin/v1/tools/asr');
    final multipart = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: 'recording.wav'),
      );
    // 先 finalize 成字节，才能交给 AbortableRequest 取消（§3.3）。
    final body = await multipart.finalize().toBytes();
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          ..headers.addAll(multipart.headers)
          ..bodyBytes = body;

    final response = await _send(request);
    final responseBytes = await _guard(() => response.stream.toBytes());
    if (!_ok(response.statusCode)) {
      throw ApiException(
        ApiErrorKind.http,
        _errorMessage(responseBytes, response),
        status: response.statusCode,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(responseBytes));
      final text = decoded is Map ? decoded['text'] : null;
      if (text is String) return text;
    } on FormatException {
      // 落空到协议错误。
    }
    throw ApiException(ApiErrorKind.protocol, 'Missing text in response');
  }

  /// `POST /v1/tools/tts`：按块产出裸 PCM（s16le、24 kHz、单声道）。
  @override
  Stream<Uint8List> synthesize({
    required String text,
    required TtsVoice voice,
    required String apiKey,
    Future<void>? abortTrigger,
  }) async* {
    final uri = Uri.parse('$_origin/v1/tools/tts');
    final request =
        http.AbortableRequest('POST', uri, abortTrigger: abortTrigger)
          ..headers.addAll({
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          })
          ..body = jsonEncode({
            'text': text,
            'voice_id': voice.name,
            'format': 'pcm',
            'filter_markdown': true,
          });

    final response = await _send(request);
    if (!_ok(response.statusCode)) {
      final body = await _guard(() => response.stream.bytesToString());
      throw ApiException(
        ApiErrorKind.http,
        _errorMessage(utf8.encode(body), response),
        status: response.statusCode,
      );
    }
    yield* response.stream.map(Uint8List.fromList);
  }

  bool _ok(int status) => status >= 200 && status < 300;

  Future<http.StreamedResponse> _send(http.BaseRequest request) =>
      _guard(() => _http.send(request));

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

  Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // 文件可能已被平台清理。
    }
  }

  String _errorMessage(List<int> body, http.BaseResponse response) {
    if (body.isEmpty) {
      return response.reasonPhrase ?? 'HTTP ${response.statusCode}';
    }
    final text = utf8.decode(body, allowMalformed: true);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
      }
    } on FormatException {
      // 解析失败时回退到响应原文。
    }
    return text;
  }
}
