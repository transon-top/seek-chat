import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

AppSidebarColors _colors(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? AppSidebarColors.dark
    : AppSidebarColors.light;

class _Bone extends StatelessWidget {
  const _Bone({this.width, this.height = 12, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _colors(context).activeItemFill,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// ZH
/// 抽屉首次加载：6 行会话行形状的静态骨架。
///
/// EN
/// First drawer load: static skeleton of six session-row shapes.
class SessionListSkeleton extends StatelessWidget {
  const SessionListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    key: const Key('session-skeleton'),
    padding: const EdgeInsets.only(top: 16),
    children: [
      for (var index = 0; index < 6; index++)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 44,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _Bone(width: 180),
              ),
            ),
          ),
        ),
    ],
  );
}

/// ZH
/// 搜索页加载：6 行搜索结果形状的静态骨架。
///
/// EN
/// Search page load: static skeleton of six search-result shapes.
class SearchListSkeleton extends StatelessWidget {
  const SearchListSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('search-skeleton'),
    children: [
      for (var index = 0; index < 6; index++)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                _Bone(width: 44, height: 44, radius: 22),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Bone(width: 140),
                      SizedBox(height: 10),
                      _Bone(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}
