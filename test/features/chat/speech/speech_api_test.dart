import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:seek_chat/features/chat/speech/speech_api.dart';
import 'package:seek_chat/shared/api/errors.dart';
import 'package:seek_chat/shared/models/types.dart';
import 'package:seek_chat/shared/prefs/speech_store.dart';

const origin = 'https://api.test';

void main() {
  late Directory temp;
  late File wav;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('speech_api_test');
    wav = File('${temp.path}/recording.wav')
      ..writeAsBytesSync(List<int>.generate(32, (index) => index));
  });

  tearDown(() => temp.deleteSync(recursive: true));

  test('ASR posts the wav as multipart with a bearer token', () async {
    late http.Request captured;
    final api = DeepSeekSpeechApi(
      origin: Uri.parse(origin),
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'text': ' hello '}), 200);
      }),
    );

    final text = await api.transcribe(path: wav.path, apiKey: 'sk-test');

    expect(text, ' hello ');
    expect(captured.method, 'POST');
    expect(captured.url.toString(), '$origin/v1/tools/asr');
    expect(captured.headers['authorization'], 'Bearer sk-test');
    expect(captured.headers['content-type'], startsWith('multipart/form-data'));
    final body = utf8.decode(captured.bodyBytes, allowMalformed: true);
    expect(body, contains('name="file"; filename="recording.wav"'));
    expect(body.codeUnits, contains(0));
    expect(captured.headers.containsKey('x-api-key'), isFalse);
  });

  test('ASR keeps the server status on http errors', () async {
    final api = DeepSeekSpeechApi(
      origin: Uri.parse(origin),
      httpClient: MockClient(
        (request) async => http.Response('{"error":{"message":"nope"}}', 429),
      ),
    );

    await expectLater(
      api.transcribe(path: wav.path, apiKey: 'sk-test'),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 429)),
    );
  });

  test(
    'ASR rejects a non-JSON or missing text response as a protocol error',
    () async {
      for (final body in ['not json', '{"request_id":"r1"}', '{"text":1}']) {
        final api = DeepSeekSpeechApi(
          origin: Uri.parse(origin),
          httpClient: MockClient((request) async => http.Response(body, 200)),
        );
        await expectLater(
          api.transcribe(path: wav.path, apiKey: 'sk-test'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.kind,
              'kind',
              ApiErrorKind.protocol,
            ),
          ),
        );
      }
    },
  );

  test('ASR does not upload an empty recording', () async {
    final empty = File('${temp.path}/empty.wav')..writeAsBytesSync([]);
    var called = false;
    final api = DeepSeekSpeechApi(
      origin: Uri.parse(origin),
      httpClient: MockClient((request) async {
        called = true;
        return http.Response('{"text":"x"}', 200);
      }),
    );

    await expectLater(
      api.transcribe(path: empty.path, apiKey: 'sk-test'),
      throwsA(isA<EmptyRecordingException>()),
    );
    expect(called, isFalse);
  });

  test('TTS posts the documented JSON and streams pcm chunks', () async {
    late http.BaseRequest captured;
    late String capturedBody;
    final api = DeepSeekSpeechApi(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming((request, bodyStream) async {
        captured = request;
        capturedBody = await bodyStream.bytesToString();
        return http.StreamedResponse(
          Stream.fromIterable([
            Uint8List.fromList([1, 2]),
            Uint8List.fromList([3, 4]),
          ]),
          200,
        );
      }),
    );

    final chunks = await api
        .synthesize(text: 'hello', voice: TtsVoice.tide, apiKey: 'sk-test')
        .expand((chunk) => chunk)
        .toList();

    expect(chunks, [1, 2, 3, 4]);
    expect(captured.method, 'POST');
    expect(captured.url.toString(), '$origin/v1/tools/tts');
    expect(captured.headers['authorization'], 'Bearer sk-test');
    expect(jsonDecode(capturedBody), {
      'text': 'hello',
      'voice_id': 'tide',
      'format': 'pcm',
      'filter_markdown': true,
    });
  });

  test('TTS keeps the server status on http errors', () async {
    final api = DeepSeekSpeechApi(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming(
        (request, bodyStream) async =>
            http.StreamedResponse(Stream.value(Uint8List(0)), 400),
      ),
    );

    await expectLater(
      api
          .synthesize(text: 'hello', voice: TtsVoice.stella, apiKey: 'k')
          .toList(),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
    );
  });
}
