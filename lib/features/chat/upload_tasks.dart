import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/api/errors.dart';
import 'attachment_rules.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';

/// 一个附件的上传状态（`attachments.md` §5）。任务只在内存里；发送前失败的
/// 附件会在下一次请求前按本地原件补传。
enum UploadStatus { uploading, done, error }

final class UploadTask {
  const UploadTask.uploading()
      : status = UploadStatus.uploading,
        serverId = null,
        error = null,
        retryable = false,
        quota = null;

  const UploadTask.done(String this.serverId)
      : status = UploadStatus.done,
        error = null,
        retryable = false,
        quota = null;

  const UploadTask.failed({
    required LocalMessage this.error,
    required this.retryable,
    this.quota,
  })  : status = UploadStatus.error,
        serverId = null;

  final UploadStatus status;
  final String? serverId;

  /// 卡片上展示的失败原因。
  final LocalMessage? error;
  final bool retryable;

  /// 配额类失败的额外提示，由界面转成 SnackBar。
  final LocalMessage? quota;
}

/// 发送闸门：全部附件都已上传成功（`attachments.md` §5）。
bool allUploadsDone(
  Iterable<DraftAttachment> attachments,
  Map<String, UploadTask> tasks,
) =>
    attachments.every((item) => tasks[item.id]?.status == UploadStatus.done);

/// 附件上传统一队列：选中即上传，最多同时 3 个；同 id 复用进行中的任务。
final uploadTasksProvider =
    NotifierProvider<UploadTasks, Map<String, UploadTask>>(UploadTasks.new);

class UploadTasks extends Notifier<Map<String, UploadTask>> {
  static const int maxConcurrent = 3;

  final List<_UploadJob> _queue = [];
  final Map<String, _UploadJob> _jobs = {};
  int _running = 0;

  @override
  Map<String, UploadTask> build() => const {};

  /// 开始（或复用）上传，返回 Files API 的 file_id。
  ///
  /// 失败时任务记为 error 并抛出原错误；移除后结果只可能是 null。
  Future<String?> upload({
    required String id,
    required String path,
    required String name,
    required bool isImage,
  }) {
    final existing = _jobs[id];
    if (existing != null) return existing.completer.future;

    final job = _UploadJob(
      id: id,
      path: path,
      name: name,
      isImage: isImage,
    );
    _jobs[id] = job;
    _set(id, const UploadTask.uploading());
    _queue.add(job);
    // 调用方不一定等待任务；避免未监听的失败成为未处理异步错误。
    unawaited(job.completer.future.catchError((_) => null));
    _pump();
    return job.completer.future;
  }

  /// 移除附件时调用；排队中的任务不会再发出请求，进行中的结果被丢弃。
  void remove(String id) {
    final job = _jobs.remove(id);
    if (job != null) {
      job.cancelled = true;
      if (!job.completer.isCompleted) job.completer.complete(null);
    }
    if (!state.containsKey(id)) return;
    final next = Map<String, UploadTask>.of(state)..remove(id);
    state = next;
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      if (job.cancelled) continue;
      _running++;
      unawaited(
        _run(job).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _run(_UploadJob job) async {
    try {
      final apiKey = (await ref.read(apiKeyStoreProvider).read())?.trim();
      if (apiKey == null || apiKey.isEmpty) throw const _MissingApiKey();
      final serverId = await ref.read(apiClientProvider).uploadFile(
            apiKey: apiKey,
            path: job.path,
            filename: job.name,
            purpose: uploadPurposeFor(job.name, isImage: job.isImage)?.wire,
          );
      _jobs.remove(job.id);
      // 移除后迟到的成功只更新任务表，不再展示。
      _set(job.id, UploadTask.done(serverId));
      if (!job.cancelled && !job.completer.isCompleted) {
        job.completer.complete(serverId);
      }
    } on _MissingApiKey {
      _jobs.remove(job.id);
      if (!job.cancelled) {
        _set(
          job.id,
          const UploadTask.failed(
            error: LocalMessage(key: LocalMessageKeys.errorNoApiKey),
            retryable: false,
          ),
        );
      }
      if (!job.completer.isCompleted) {
        job.completer.completeError(
          ApiException(ApiErrorKind.http, 'Missing API key', status: 401),
        );
      }
    } on Object catch (error) {
      _jobs.remove(job.id);
      if (!job.cancelled) {
        _set(
          job.id,
          UploadTask.failed(
            error: uploadErrorMessage(error),
            retryable: isRetryable(error),
            quota: uploadQuotaMessage(error),
          ),
        );
      }
      if (!job.completer.isCompleted) job.completer.completeError(error);
    }
  }

  void _set(String id, UploadTask task) {
    state = {...state, id: task};
  }
}

final class _MissingApiKey implements Exception {
  const _MissingApiKey();
}

final class _UploadJob {
  _UploadJob({
    required this.id,
    required this.path,
    required this.name,
    required this.isImage,
  });

  final String id;
  final String path;
  final String name;
  final bool isImage;
  final Completer<String?> completer = Completer<String?>();
  bool cancelled = false;
}
