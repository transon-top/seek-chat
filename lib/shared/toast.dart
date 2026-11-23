import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// ZH
/// 聊天页顶栏高度；toast 顶部锚点据此让出顶栏。
///
/// EN
/// Chat header height; the top toast anchor offsets by this to clear the header.
const double chatHeaderHeight = 46;

/// ZH
/// 未识别到语音内容：官方式屏幕居中深色胶囊，2 s 自动消失（参照 DeepSeek）。
///
/// EN
/// No speech recognized: dark centered pill, auto-dismissed in 2 s (official DeepSeek style).
void showVoiceEmptyToast(BuildContext context, String message) {
  ShadToaster.of(context).show(
    ShadToast.raw(
      variant: ShadToastVariant.primary,
      alignment: Alignment.center,
      offset: const Offset(16, 0),
      constraints: const BoxConstraints(maxWidth: 320),
      mainAxisSize: MainAxisSize.min,
      backgroundColor: const Color(0xFF333333),
      border: const ShadBorder(),
      shadows: const [],
      radius: BorderRadius.circular(14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      duration: const Duration(seconds: 2),
      description: Text(message, textAlign: TextAlign.center),
      descriptionStyle: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w400,
      ),
    ),
  );
}

/// ZH
/// 全应用提示：`ShadToast`，顶部、聊天顶栏下方 8、最大宽 480，
/// 默认 4 s、错误 5 s，同屏只显示一条（ui.md §1.6）。
///
/// EN
/// App-wide toast: `ShadToast` at top, 8 below the chat header, max width 480;
/// defaults to 4 s, errors 5 s, one on screen at a time (`ui.md` §1.6).
void showAppToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool destructive = true,
}) {
  final hasAction = actionLabel != null && onAction != null;
  ShadToaster.of(context).show(
    ShadToast.raw(
      variant: destructive
          ? ShadToastVariant.destructive
          : ShadToastVariant.primary,
      alignment: Alignment.topCenter,
      offset: Offset(
        16,
        MediaQuery.paddingOf(context).top + chatHeaderHeight + 8,
      ),
      constraints: const BoxConstraints(maxWidth: 480),
      duration: Duration(seconds: destructive ? 5 : 4),
      description: Text(message),
      action: hasAction
          ? ShadButton.link(onPressed: onAction, child: Text(actionLabel))
          : null,
    ),
  );
}
