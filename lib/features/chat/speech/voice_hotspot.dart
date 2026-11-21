import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 按住麦克风的全局 pointer 坐标；浮层据此锚定高光。
///
/// 由 `VoiceButton` 写入、`RecordingOverlay` 消费，松开或取消时置空；
/// 读屏的语义 tap 没有 pointer，浮层用默认位置。
class VoiceHotspot extends Notifier<Offset?> {
  @override
  Offset? build() => null;

  void set(Offset? value) {
    if (state != value) state = value;
  }
}

final voiceHotspotProvider = NotifierProvider<VoiceHotspot, Offset?>(
  VoiceHotspot.new,
);
