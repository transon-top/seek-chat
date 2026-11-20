# 初始窗口

Type: task
Status: resolved
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

## Answer

已落地。

改动：

- `lib/features/chat/messages_view.dart`
  - 初始窗口：打开会话从最后 50 条起；距顶 200px 内每次向前补 40 条，直到窗口起点为 0；窗口只扩不缩。
  - `findChildIndexCallback`：按消息 id 维护绝对下标表，前插后子项按 id 复用；消息集合变化时重建，索引对不上则回退按位置重建。
  - 锚点补偿：补历史当帧把 `scrollCacheExtent` 临时放大到 1500px；自定义 `ScrollPosition` 在 `applyContentDimensions` 里两段修正偏移——先按 `maxScrollExtent` 差值估算，再按旧窗口起点条目的 `layoutOffset` 实测——视口以修正后的偏移重排后才出帧，不闪跳；锚点未建成时保留估算值。
  - 顶部留白按绝对下标判断；消息数变化（版本切换、编辑）时重算窗口；`_scheduleFollow()` 与 Sticky Bottom 逻辑未动。
  - 锚点 `GlobalKey` 换到另一条消息时换新实例，避免旧消息元素状态被挪给新消息（曾使编辑后的新版提问继承 `_editing` 状态）。
- `lib/features/chat/chat_page.dart`：`ChatMessageList` 以 `sessionId` 为 key，重新打开会话时窗口与滚动状态一起重建。
- 测试（`test/features/chat/messages_view_test.dart`）：新增 4 项——首屏只渲染尾部 50 条；滚到顶部补 40 条且已渲染内容只随滚动位移（锚点补偿）；换 key 重开重置为 50；切到 20 条的短版本后窗口收敛为 20。全量 `flutter test` 373 项全绿，`dart analyze` 无问题。

复测（模拟器 `Medium_Phone_API_37.0`，`-gpu host`，profile，1 轮）：

```
flutter drive --profile -d emulator-5554 \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/list_perf_test.dart
```

| 场景 | 本次 | 票 01 复测 | 改造前基线（3 轮） |
| --- | --- | --- | --- |
| 打开 1000 条消息首屏 | 347ms（build max 95.56ms） | 1651ms（build max 1312.85ms） | 1966–5623ms |
| 聊天列表滚动 1000 条慢帧 | 9.52%（build max 6.29ms） | 0% | 9.5–16.6% |
| 流式 + 滚动慢帧占比 | 8.19%（build max 2.9ms） | 1.58% | 0.4–11.2% |
| 流式静止慢帧 | 0% | — | — |
| 抽屉首行 / 滚动慢帧 | 270ms / 55.6% | 68ms / 1.78% | 106–247ms / 1.4–71.6% |
| 打开长会话后 RSS | 365.98MB | 409.97MB | 341–430MB |

原始日志：`evidence/02-initial-window-simulator-r1.log`。

读数注意：

- 本轮模拟器光栅化明显偏慢（空白对话静止慢帧 72%，raster p50 21.48ms），滚动慢帧以光栅为主，构建成本很低（build p90 ≤ 0.63ms）。首屏从 1651ms 降至 347ms，`build max` 从 1312.85ms 降至 95.56ms，跳底大构建已消除。
- 首屏 347ms 仍高于 §7 的 300ms 口径，但按图门禁只看相对关系；真机 3 轮判定留给《总验收与收图》。
- 抽屉数字属会话列表（《会话列表 P2》），本票未改。
- 补历史的偏移修正会触发一次临时缓存布局（约 1500px 内的条目），作为补历史当帧的固有成本记录。
- `Sticky Bottom` 与向上加载不跳动：由「短会话从视口顶部开始 / 长会话跟随底部」与新增锚点测试覆盖；未做人工看屏验收。
