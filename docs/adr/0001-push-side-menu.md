# 推入式侧栏替代 Material Drawer

聊天页需要“侧栏内容从左侧滑入、对话内容缩小右移”的推入效果，Material `Scaffold.drawer` 只能以浮层覆盖内容，无法驱动内容层变换。因此用 `lib/shared/widgets/push_menu.dart` 自研 `PushMenu`（`AnimationController` + `Transform`）替代 `Scaffold.drawer`，`SessionDrawer` 只作为侧栏内容。手势仲裁保持“内层横向滚动优先”；Android 上 `MarkdownView` 在 `SelectionArea` 内层注册识别器，避免横拖被文本选择吞掉。

## Considered Options

- `flutter_zoom_drawer`：2024-02 后未更新，依赖 Flutter 3.50 起废弃的 `package:flutter/material.dart`；与 `material_ui` 是两套 widget 类型，主题与手势排除都不可控。
- 加宽 `drawerEdgeDragWidth`：全宽会抢光水平手势（flutter/flutter#142234），且仍是浮层，无法实现内容缩放。
- 只在左边缘保留原生抽屉：零代码，但不满足“界面任意位置右滑”的需求。

## Consequences

- 返回键、焦点、Semantics 与点击关闭由 `PushMenu` 接管，不再复用 `DrawerController`。
- 侧栏关闭不再通过 `Navigator.pop()`，改由 `PushMenuScope` 驱动。
- 现有 `find.byType(Drawer)` 测试改为查找 `SessionDrawer`；新增手势竞技场测试。
- 内层识别器依赖 Flutter 手势竞技场的注册顺序，需真机复核 Android `SelectionArea` 与表格行为。
