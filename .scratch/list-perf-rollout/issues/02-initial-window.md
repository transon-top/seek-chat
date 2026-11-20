# 初始窗口

Type: task
Status: open
Blocked by: 01

## Question（实施切片）

按 `decision.md` §3 实现 UI 层初始窗口（`Initial Window`，见 `GLOSSARY.md`）：

- 打开会话只渲染可见路径末尾最近 50 条；向上滚动接近已渲染范围起点时每次补 40 条，直到全部消息进入范围。
- 窗口只扩不缩；重新打开会话时重置；保留现有非反向 `ListView.builder` 与 `_scheduleFollow()` 的 `jumpTo(maxScrollExtent)` 跟随逻辑。
- 前插历史补 `findChildIndexCallback`，否则按键复用会错位。
- 顶部补历史后按插入高度补偿滚动位置，避免视口跳动。
- 版本切换或编辑导致消息数变化时重算窗口，保证当前视口消息仍在范围内。
- 内容不足一屏时保持 `Sticky Bottom` 的「提问从视口顶部开始」。

## 验收

- widget 测试：窗口计算与扩展；重新打开重置；版本切换后窗口有效；顶部补历史后的滚动锚点补偿。
- 手动验证 `Sticky Bottom` 与向上加载不跳动。
- 模拟器 1 轮复测打开 1000 条消息会话首屏；数字与命令回填票内。
- 一次提交。
