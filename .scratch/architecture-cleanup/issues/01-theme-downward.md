# 01: 把主题 token 下沉到 shared

**What to build:** 目前 5 个 feature 文件向上 import `app/theme.dart` 或 `app/markdown_theme.dart`，违反 `main → app → features → shared` 的依赖方向。把 feature 实际使用的主题 token、Markdown 样式与颜色常量移到 `shared/theme/`；app 与 features 都向下依赖。行为与视觉不变。

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] feature 不再 import `app/theme.dart` 或 `app/markdown_theme.dart`
- [ ] Markdown 样式、颜色与字体 token 的对外接口保持等价
- [ ] 视觉无变化，现有 widget 测试通过
- [ ] `flutter analyze` 与 `flutter test` 通过
