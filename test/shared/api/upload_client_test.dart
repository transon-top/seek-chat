import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/api/errors.dart';
import 'package:open_chat/shared/models/types.dart';

const origin = 'https://api.test';

void main() {
  late Directory temp;
  late File sample;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('upload-test');
    sample = File('${temp.path}/report.pdf')
      ..writeAsBytesSync(List.filled(10, 7));
  });

  tearDown(() => temp.delete(recursive: true));

  DeepSeekApiClient clientWith(
    http.StreamedResponse Function(http.BaseRequest) handler,
  ) =>
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          expect(request, isA<http.MultipartRequest>());
          return handler(request);
        }),
      );

  http.StreamedResponse jsonResponse(Object body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  test('uploads a multipart file with purpose and returns the file id',
      () async {
    late http.MultipartRequest captured;
    final client = clientWith((request) {
      captured = request as http.MultipartRequest;
      return jsonResponse({'id': 'file-1'});
    });

    final id = await client.uploadFile(
      apiKey: 'secret',
      path: sample.path,
      filename: 'report.pdf',
      purpose: 'rich_layout_recognition',
    );

    expect(id, 'file-1');
    expect(
      captured.url.toString(),
      '$origin/anthropic/v1/files',
    );
    expect(captured.method, 'POST');
    expect(captured.headers['x-api-key'], 'secret');
    expect(
      captured.headers['anthropic-beta'],
      DeepSeekApiClient.filesApiBeta,
    );
    expect(captured.fields, {'purpose': 'rich_layout_recognition'});
    expect(captured.files.single.field, 'file');
    expect(captured.files.single.filename, 'report.pdf');
    expect(captured.files.single.length, 10);
  });

  test('omits purpose for images', () async {
    late http.MultipartRequest captured;
    final client = clientWith((request) {
      captured = request as http.MultipartRequest;
      return jsonResponse({'id': 'file-2'});
    });

    await client.uploadFile(
      apiKey: 'secret',
      path: sample.path,
      filename: 'photo.png',
    );

    expect(captured.fields, isEmpty);
  });

  test('maps non-2xx responses to http errors with the server message',
      () async {
    final client = clientWith(
      (_) => jsonResponse(
        {
          'error': {'message': 'User file count limit exceeded, limit 100'},
        },
        status: 400,
      ),
    );

    await expectLater(
      client.uploadFile(
        apiKey: 'secret',
        path: sample.path,
        filename: 'a.txt',
        purpose: 'user_data',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.http)
            .having((e) => e.status, 'status', 400)
            .having(
              (e) => e.message,
              'message',
              'User file count limit exceeded, limit 100',
            ),
      ),
    );
  });

  test('missing id in a 2xx response is a protocol error', () async {
    final client = clientWith((_) => jsonResponse({'ok': true}));

    await expectLater(
      client.uploadFile(
        apiKey: 'secret',
        path: sample.path,
        filename: 'a.txt',
        purpose: 'user_data',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.protocol),
      ),
    );
  });

  test('maps connection failures to network errors', () async {
    final client = DeepSeekApiClient(
      origin: Uri.parse(origin),
      httpClient: MockClient.streaming((request, body) async {
        throw http.ClientException('offline');
      }),
    );

    await expectLater(
      client.uploadFile(
        apiKey: 'secret',
        path: sample.path,
        filename: 'a.txt',
        purpose: 'user_data',
      ),
      throwsA(
        isA<ApiException>()
            .having((e) => e.kind, 'kind', ApiErrorKind.network),
      ),
    );
  });
}
