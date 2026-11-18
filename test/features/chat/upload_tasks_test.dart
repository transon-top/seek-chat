import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_chat/shared/api/client.dart';
import 'package:open_chat/shared/models/types.dart';
import 'package:open_chat/shared/providers.dart';
import 'package:open_chat/shared/security/api_key_store.dart';
import 'package:open_chat/features/chat/upload_tasks.dart';

import '../../support/fake_api_key_store.dart';

const origin = 'https://api.test';

void main() {
  late Directory temp;
  late File sample;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('upload-tasks-test');
    sample = File('${temp.path}/sample.txt')..writeAsStringSync('hello');
  });

  tearDown(() => temp.delete(recursive: true));

  http.StreamedResponse jsonResponse(Object body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );

  ProviderContainer containerWith(
    DeepSeekApiClient client, {
    ApiKeyStore? apiKeyStore,
  }) =>
      ProviderContainer.test(
        overrides: [
          apiClientProvider.overrideWithValue(client),
          apiKeyStoreProvider.overrideWithValue(
            apiKeyStore ?? FakeApiKeyStore('secret'),
          ),
        ],
      );

  UploadTasks tasksOf(ProviderContainer container) =>
      container.read(uploadTasksProvider.notifier);

  test('uploads, exposes progress and keeps the server id', () async {
    final gate = Completer<http.StreamedResponse>();
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) => gate.future),
      ),
    );
    final tasks = tasksOf(container);

    final pending = tasks.upload(
      id: 'att-1',
      path: sample.path,
      name: 'a.txt',
      isImage: false,
    );

    expect(container.read(uploadTasksProvider)['att-1']?.status,
        UploadStatus.uploading);
    gate.complete(jsonResponse({'id': 'file-1'}));
    expect(await pending, 'file-1');
    final task = container.read(uploadTasksProvider)['att-1']!;
    expect(task.status, UploadStatus.done);
    expect(task.serverId, 'file-1');
  });

  test('failed uploads record a retryable reason and can be retried', () async {
    var call = 0;
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          call++;
          if (call == 1) {
            return jsonResponse(
              {
                'error': {'message': 'server exploded'},
              },
              status: 500,
            );
          }
          return jsonResponse({'id': 'file-2'});
        }),
      ),
    );
    final tasks = tasksOf(container);

    await expectLater(
      tasks.upload(
        id: 'att-1',
        path: sample.path,
        name: 'a.txt',
        isImage: false,
      ),
      throwsA(isA<Exception>()),
    );
    final failed = container.read(uploadTasksProvider)['att-1']!;
    expect(failed.status, UploadStatus.error);
    expect(failed.retryable, isTrue);
    expect(failed.error?.key, LocalMessageKeys.uploadServerBusy);

    final id = await tasks.upload(
      id: 'att-1',
      path: sample.path,
      name: 'a.txt',
      isImage: false,
    );
    expect(id, 'file-2');
    expect(
      container.read(uploadTasksProvider)['att-1']?.status,
      UploadStatus.done,
    );
  });

  test('non-retryable parse failures are recorded as such', () async {
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, body) async => jsonResponse(
            {
              'error': {
                'message': 'Failed to recognize the file content',
              },
            },
            status: 400,
          ),
        ),
      ),
    );
    final tasks = tasksOf(container);

    await expectLater(
      tasks.upload(
        id: 'att-1',
        path: sample.path,
        name: 'a.pdf',
        isImage: false,
      ),
      throwsA(isA<Exception>()),
    );
    final task = container.read(uploadTasksProvider)['att-1']!;
    expect(task.status, UploadStatus.error);
    expect(task.retryable, isFalse);
    expect(task.error?.key, LocalMessageKeys.uploadParseFailed);
  });

  test('removing a queued upload never sends it', () async {
    final gates = <Completer<http.StreamedResponse>>[];
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) {
          final gate = Completer<http.StreamedResponse>();
          gates.add(gate);
          return gate.future;
        }),
      ),
    );
    final tasks = tasksOf(container);

    for (var i = 0; i < 4; i++) {
      unawaited(
        tasks
            .upload(
              id: 'att-$i',
              path: sample.path,
              name: 'f$i.txt',
              isImage: false,
            )
            .catchError((_) => null),
      );
    }
    await pumpEventQueue();

    // 并发上限 3：第四个还在排队。
    expect(gates, hasLength(3));

    tasks.remove('att-3');
    expect(container.read(uploadTasksProvider).containsKey('att-3'), isFalse);

    gates.first.complete(jsonResponse({'id': 'file-0'}));
    await pumpEventQueue();
    expect(gates, hasLength(3), reason: '被移除的排队任务不应发出请求');
  });

  test('a server 401 is a plain upload failure, not a missing key', () async {
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming(
          (request, body) async => jsonResponse(
            {
              'error': {'message': 'invalid api key'},
            },
            status: 401,
          ),
        ),
      ),
    );
    final tasks = tasksOf(container);

    await expectLater(
      tasks.upload(
        id: 'att-1',
        path: sample.path,
        name: 'a.txt',
        isImage: false,
      ),
      throwsA(isA<Exception>()),
    );
    final task = container.read(uploadTasksProvider)['att-1']!;
    expect(task.error?.key, LocalMessageKeys.uploadFileStatusFailed);
    expect(task.retryable, isFalse);
  });

  test('missing key fails without calling the API', () async {
    var requests = 0;
    final container = containerWith(
      DeepSeekApiClient(
        origin: Uri.parse(origin),
        httpClient: MockClient.streaming((request, body) async {
          requests++;
          return jsonResponse({'id': 'file-1'});
        }),
      ),
      apiKeyStore: FakeApiKeyStore(),
    );
    final tasks = tasksOf(container);

    await expectLater(
      tasks.upload(
        id: 'att-1',
        path: sample.path,
        name: 'a.txt',
        isImage: false,
      ),
      throwsA(isA<Exception>()),
    );

    expect(requests, 0);
    final task = container.read(uploadTasksProvider)['att-1']!;
    expect(task.error?.key, LocalMessageKeys.errorNoApiKey);
    expect(task.retryable, isFalse);
  });
}
