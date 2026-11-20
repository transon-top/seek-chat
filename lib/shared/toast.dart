import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 聊天页顶栏高度；toast 顶部锚点据此让出顶栏。
const double chatHeaderHeight = 46;

/// 全应用提示：`ShadToast`，顶部、聊天顶栏下方 8、最大宽 480，
/// 默认 4 s、错误 5 s，同屏只显示一条（ui.md §1.6）。
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
