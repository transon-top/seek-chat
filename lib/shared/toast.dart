import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// ZH
/// 聊天页顶栏高度；toast 顶部锚点据此让出顶栏。
///
/// EN
/// Chat header height; the top toast anchor offsets by this to clear the header.
const double chatHeaderHeight = 46;

/// ZH
/// Toast 语义。颜色只由语义推导，调用方不自己挑颜色：
/// [info] 中性说明、[success] 操作成功、[warning] 达到限制或需要留意、
/// [error] 操作失败。
///
/// EN
/// Toast semantics. Colors derive from the tone alone; callers never pick colors:
/// [info] neutral note, [success] completed action, [warning] a limit or attention
/// needed, [error] failed action.
enum AppToastTone { info, success, warning, error }

/// ZH
/// 每种语义在浅色 / 深色下的背景与前景；描边取前景色降低透明度。
///
/// EN
/// Background and foreground per tone in light / dark; the border is the
/// foreground at reduced opacity.
class _ToastPalette {
  const _ToastPalette(this.background, this.foreground);

  final Color background;
  final Color foreground;

  Color get border => foreground.withValues(alpha: 0.28);

  static _ToastPalette of(Brightness brightness, AppToastTone tone) {
    if (brightness == Brightness.dark) {
      return switch (tone) {
        AppToastTone.info => const _ToastPalette(
          Color(0xFF14203F),
          Color(0xFFA4BDFF),
        ),
        AppToastTone.success => const _ToastPalette(
          Color(0xFF10261B),
          Color(0xFF75E0A7),
        ),
        AppToastTone.warning => const _ToastPalette(
          Color(0xFF2A2010),
          Color(0xFFFEC84B),
        ),
        AppToastTone.error => const _ToastPalette(
          Color(0xFF2E1615),
          Color(0xFFFDA29B),
        ),
      };
    }
    return switch (tone) {
      AppToastTone.info => const _ToastPalette(
        Color(0xFFEFF4FF),
        Color(0xFF1D4ED8),
      ),
      AppToastTone.success => const _ToastPalette(
        Color(0xFFECFDF3),
        Color(0xFF067647),
      ),
      AppToastTone.warning => const _ToastPalette(
        Color(0xFFFFFAEB),
        Color(0xFFB54708),
      ),
      AppToastTone.error => const _ToastPalette(
        Color(0xFFFEF3F2),
        Color(0xFFB42318),
      ),
    };
  }
}

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
/// 同屏只显示一条。色调决定颜色：error 5 s，其余 4 s。
///
/// EN
/// App-wide toast: `ShadToast` at top, 8 below the chat header, max width 480,
/// one on screen at a time. The tone picks the colors: error 5 s, others 4 s.
void showAppToast(
  BuildContext context,
  String message, {
  AppToastTone tone = AppToastTone.info,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final hasAction = actionLabel != null && onAction != null;
  final theme = ShadTheme.of(context);
  final palette = _ToastPalette.of(theme.brightness, tone);
  ShadToaster.of(context).show(
    ShadToast.raw(
      variant: ShadToastVariant.primary,
      alignment: Alignment.topCenter,
      offset: Offset(
        16,
        MediaQuery.paddingOf(context).top + chatHeaderHeight + 8,
      ),
      constraints: const BoxConstraints(maxWidth: 480),
      duration: Duration(seconds: tone == AppToastTone.error ? 5 : 4),
      backgroundColor: palette.background,
      border: ShadBorder.all(color: palette.border),
      description: Text(message),
      descriptionStyle: theme.textTheme.muted.copyWith(
        color: palette.foreground,
      ),
      action: hasAction
          ? ShadButton.link(
              onPressed: onAction,
              foregroundColor: palette.foreground,
              hoverForegroundColor: palette.foreground,
              child: Text(actionLabel),
            )
          : null,
    ),
  );
}
