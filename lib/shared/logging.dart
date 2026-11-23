import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// ZH
/// 调试日志，只在 debug 构建输出（architecture.md §5）。
///
/// 禁止传入 API Key、请求头、完整请求体与附件内容。
///
/// EN
/// Debug logging, output only in debug builds (architecture.md §5).
///
/// Never pass API Keys, request headers, full request bodies, or attachment contents.
void debugLog(String message, [Object? error]) {
  if (!kDebugMode) return;
  developer.log(message, name: 'open_chat', error: error);
}
