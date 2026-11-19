import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// 聊天页顶部栏：菜单、左对齐标题、新建对话（ui.md §1.3）。
///
/// 首屏（空对话）不展示标题与新建按钮，进入对话后才展示。
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
      height: 46,
      child: Row(
        children: [
          Semantics(
            button: true,
            label: l10n.openSessionList,
            child: ShadIconButton.ghost(
              key: const Key('chat-open-drawer'),
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(LucideIcons.menu),
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
                    // 与 chat-demo 移动端顶栏一致：标题左右各 12。
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
