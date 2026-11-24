import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../shared/widgets/push_menu.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/toast.dart';

/// ZH
/// 聊天页顶部栏：菜单、左对齐标题、新建对话（ui.md §1.3）。
///
/// 首屏（空对话）不展示标题与新建按钮，进入对话后才展示。
///
/// EN
/// Chat page header: menu, left-aligned title, new chat (ui.md §1.3).
///
/// First screen (empty conversation) hides title and new-chat; both appear inside a conversation.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.title,
    this.onNewChat,
    this.inConversation = true,
  });

  final String title;
  final VoidCallback? onNewChat;
  final bool inConversation;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = ShadTheme.of(context);
    return SizedBox(
      height: chatHeaderHeight,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.openSessionList,
            child: ShadIconButton.ghost(
              key: const Key('chat-open-drawer'),
              onPressed: () => PushMenuScope.maybeOf(context)?.toggle(),
              icon: _MenuIcon(color: theme.colorScheme.foreground),
              iconSize: 18,
              width: 44,
              height: 44,
              padding: EdgeInsets.zero,
              foregroundColor: theme.colorScheme.foreground,
            ),
          ),
          Expanded(
            child: inConversation
                ? Padding(
                    // ZH
                    // 与 chat-demo 移动端顶栏一致：标题左右各 12。
                    //
                    // EN
                    // Match the chat-demo mobile header: 12 horizontal padding around the title.
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 15,
                        height: 20 / 15,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (inConversation)
            Semantics(
              button: true,
              label: l10n.newChat,
              child: ShadIconButton.ghost(
                key: const Key('chat-new'),
                onPressed: onNewChat,
                icon: const Icon(LucideIcons.circlePlus),
                iconSize: 18,
                width: 44,
                height: 44,
                padding: EdgeInsets.zero,
                foregroundColor: theme.colorScheme.foreground,
              ),
            ),
        ],
      ),
    );
  }
}

/// ZH
/// 照抄 chat-demo 的 IconMenuOutline20：上长下短两条左对齐横杠。
///
/// EN
/// Copy chat-demo's IconMenuOutline20: two left-aligned bars, long on top and short below.
class _MenuIcon extends StatelessWidget {
  const _MenuIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final size = IconTheme.of(context).size ?? 20;
    return CustomPaint(
      size: Size.square(size),
      painter: _MenuIconPainter(color),
    );
  }
}

class _MenuIconPainter extends CustomPainter {
  const _MenuIconPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 20;
    final paint = Paint()..color = color;
    canvas.drawRect(
      Rect.fromLTRB(2.79724 * s, 4.90034 * s, 17.2027 * s, 6.43655 * s),
      paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(2.79724 * s, 13.0634 * s, 10.9603 * s, 14.5996 * s),
      paint,
    );
  }

  @override
  bool shouldRepaint(_MenuIconPainter oldDelegate) =>
      oldDelegate.color != color;
}
