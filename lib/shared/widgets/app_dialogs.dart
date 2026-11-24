import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// ZH
/// 浮层阴影：菜单与弹窗共用，照搬 chat-demo。
///
/// EN
/// Overlay shadow shared by menus and dialogs, copied from chat-demo.
const appOverlayShadows = [
  BoxShadow(color: Color(0x33000000), blurRadius: 1),
  BoxShadow(color: Color(0x05000000), blurRadius: 4),
  BoxShadow(color: Color(0x14000000), offset: Offset(0, 12), blurRadius: 32),
];

const _pillRadius = BorderRadius.all(Radius.circular(999));
const _dialogRadius = BorderRadius.all(Radius.circular(24));

/// ZH
/// 遮罩：浅色 36%、深色 60%，照搬 chat-demo。
///
/// EN
/// Scrim: 36% in light, 60% in dark, copied from chat-demo.
Color appDialogBarrierColor(BuildContext context) =>
    ShadTheme.of(context).brightness == Brightness.dark
    ? const Color(0x99000000)
    : const Color(0x5C000000);

/// ZH
/// 统一确认弹窗：24 圆角、卡片底色、胶囊按钮。
///
/// EN
/// Unified confirm dialog: 24 radius, card background, pill buttons.
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String description,
  required String cancelLabel,
  required String confirmLabel,
  bool destructive = false,
}) {
  // ZH
  // 对话框路由挂在 Navigator 上，可能高于调用处的 ShadTheme；先取好主题再传进去。
  //
  // EN
  // Dialog routes sit on the Navigator, possibly above the caller's ShadTheme; capture it first.
  final theme = ShadTheme.of(context);
  final colors = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final width = math.min(380.0, MediaQuery.sizeOf(context).width - 32);
  return showShadDialog<bool>(
    context: context,
    barrierColor: appDialogBarrierColor(context),
    builder: (context) {
      return ShadTheme(
        // ZH
        // 只把弹窗内按钮改成 chat-demo 的胶囊形。
        //
        // EN
        // Only dialog buttons become chat-demo pill shapes.
        data: theme.copyWith(radius: _pillRadius),
        child: ShadDialog.alert(
          title: Text(title),
          description: Padding(
            // ZH
            // chat-demo 标题与描述间距 12、描述与按钮间距 20。
            //
            // EN
            // chat-demo gaps: 12 between title and description, 20 between description and buttons.
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(description),
          ),
          actions: [
            ShadButton.outline(
              onPressed: () => Navigator.of(context).pop(false),
              foregroundColor: colors.foreground,
              child: Text(cancelLabel),
            ),
            if (destructive)
              ShadButton.destructive(
                onPressed: () => Navigator.of(context).pop(true),
                backgroundColor: colors.destructive,
                foregroundColor: colors.destructiveForeground,
                child: Text(confirmLabel),
              )
            else
              ShadButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(confirmLabel),
              ),
          ],
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          radius: _dialogRadius,
          removeBorderRadiusWhenTiny: false,
          backgroundColor: colors.card,
          border: Border.all(
            color: dark ? const Color(0x0FFFFFFF) : const Color(0x00000000),
          ),
          shadows: appOverlayShadows,
          gap: 12,
          titleStyle: TextStyle(
            fontSize: 16,
            height: 24 / 16,
            fontWeight: FontWeight.w500,
            color: colors.foreground,
          ),
          descriptionStyle: TextStyle(
            fontSize: 14,
            height: 22 / 14,
            color: colors.mutedForeground,
          ),
          titleTextAlign: TextAlign.start,
          descriptionTextAlign: TextAlign.start,
          actionsAxis: Axis.horizontal,
          actionsMainAxisSize: MainAxisSize.max,
          actionsMainAxisAlignment: MainAxisAlignment.end,
          actionsGap: 8,
          expandActionsWhenTiny: false,
        ),
      );
    },
  );
}

/// ZH
/// 统一阻塞式进度弹窗；调用方用 `Navigator.of(context, rootNavigator: true).pop()` 关闭。
///
/// EN
/// Unified blocking progress dialog; callers close it with
/// `Navigator.of(context, rootNavigator: true).pop()`.
Future<void> showAppProgressDialog(
  BuildContext context, {
  required String message,
}) {
  final theme = ShadTheme.of(context);
  final colors = theme.colorScheme;
  final dark = theme.brightness == Brightness.dark;
  final width = math.min(320.0, MediaQuery.sizeOf(context).width - 64);
  return showShadDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: appDialogBarrierColor(context),
    builder: (context) => ShadTheme(
      data: theme,
      child: PopScope(
        canPop: false,
        child: ShadDialog(
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          radius: _dialogRadius,
          removeBorderRadiusWhenTiny: false,
          backgroundColor: colors.card,
          border: Border.all(
            color: dark ? const Color(0x0FFFFFFF) : const Color(0x00000000),
          ),
          shadows: appOverlayShadows,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Flexible(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 14,
                    height: 22 / 14,
                    color: colors.foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
