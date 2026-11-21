# Map: 输入区改版实现

## Destination

输入区改版在 iOS 与 Android 上落地：票 01–07 全部 resolved，`flutter analyze` 与
`flutter test` 全绿，真机验收证据（截图、设备与系统版本、失败项）记录在票 07。

## Notes

- **执行型地图**：本图 override wayfinder 的默认「只产决策」模式，票是执行切片，
  交付物是代码、测试与验收证据，不是决策。
- 权威规格：[`../composer-redesign/spec.md`](../composer-redesign/spec.md)。本目录
  `spec.md` 是执行拆分索引；冲突时以源规格为准。
- 验收口径：`../composer-redesign/spec.md` §7 与
  `prototype/composer_redesign/screenshots/`。
- 票格式：`Status:` 取 `open` / `claimed` / `resolved`；`Type:` 均为 `task`。
  票 01–06 为 AFK，可由 agent 独立完成；票 07 为 HITL，真机对图与人工确认必须由人参与。
- 每个会话最多 resolve 一张票。开工前先 claim（改 `Status: claimed`）。
- 每个会话先读根目录 `GLOSSARY.md` 与 `docs/agents/domain.md`；按需调用
  tdd、prototype、domain-modeling。
- 每张票完成前跑 `flutter analyze` 与相关 `flutter test`；改 ARB 或表结构后重跑
  代码生成。生成物入库。
- 执行中发现规格未覆盖、且影响后续票的决策，新开 child 票并接 blocking 边，
  不静默扩大当前票。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [01: 预置：依赖、平台权限与内存字段](issues/01-preset-deps-and-permissions.md):
  依赖与双端权限就位（`photo_manager 3.12.0` / `image_picker 1.2.4`），
  `DraftAttachment` 增内存字段 `sourceAssetId`；analyze、420 测试、双端 debug 构建通过。
- [02: 输入卡、空态与内联附件面板](issues/02-composer-empty-state-and-panel.md):
  输入卡单实例贴底、问候语居中并在首条消息后 150ms 淡出；`+` / `×` 与
  220/180ms 面板、三宫格、JPEG 嗅探与 50 上限；analyze、426 测试、双端 debug 构建通过。

## Not yet specified

- 无。实现路径已由票 01–07 固定；执行中暴露的新问题按 Notes 开新票。

## Out of scope

- 输入区改版规格之外的任何工作：推荐问句胶囊行、logo 与时段问候、图片生成、
  最近生成图与再编辑、拖拽 / 粘贴附件、桌面 / Web、流式语音识别与实时字幕。
- 实现票范围内的功能增补、顺手重构与依赖升级。
