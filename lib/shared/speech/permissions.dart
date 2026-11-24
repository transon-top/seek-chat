import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../prefs/speech_store.dart';

/// ZH
/// 设置页展示的三态；`permission_handler` 没有「未请求」，用
/// [SpeechStore.micRequested] 区分（`speech.md` §5.1）。
///
/// EN
/// Three states shown in settings. `permission_handler` has no "not requested" state;
/// [SpeechStore.micRequested] distinguishes it (`speech.md` §5.1).
enum MicrophoneStatus { notRequested, granted, denied }

/// ZH
/// 麦克风权限：请求、读取三态与跳系统设置。朗读不需要权限。
///
/// EN
/// Microphone permission: request, read three states, open system settings. Speech needs none.
abstract interface class MicrophonePermissions {
  Future<bool> isGranted();

  /// ZH
  /// 发起系统请求；首次请求后记录 `speech.micRequested`。
  ///
  /// EN
  /// Trigger the system request; record `speech.micRequested` after the first request.
  Future<bool> request();

  Future<MicrophoneStatus> status();

  Future<void> openSettings();
}

class DeviceMicrophonePermissions implements MicrophonePermissions {
  DeviceMicrophonePermissions(this._store);

  final SpeechStore _store;

  @override
  Future<bool> isGranted() async =>
      (await Permission.microphone.status).isGranted;

  @override
  Future<bool> request() async {
    await _store.setMicRequested(true);
    return (await Permission.microphone.request()).isGranted;
  }

  @override
  Future<MicrophoneStatus> status() async {
    if (await isGranted()) return MicrophoneStatus.granted;
    return _store.micRequested
        ? MicrophoneStatus.denied
        : MicrophoneStatus.notRequested;
  }

  @override
  Future<void> openSettings() => openAppSettings();
}

final microphonePermissionsProvider = Provider<MicrophonePermissions>(
  (ref) => DeviceMicrophonePermissions(ref.watch(speechStoreProvider)),
);
