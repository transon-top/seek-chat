import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// 全应用提示：`ShadToast`，底部居中、安全区上方 16、最大宽 480，
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
      alignment: Alignment.bottomCenter,
      constraints: const BoxConstraints(maxWidth: 480),
      duration: Duration(seconds: destructive ? 5 : 4),
      description: Text(message),
      action: hasAction
          ? ShadButton.link(onPressed: onAction, child: Text(actionLabel))
          : null,
    ),
  );
}
