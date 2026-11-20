# Map: 列表性能落地实施

## Destination

按 `.scratch/list-performance/decision.md` 第 8 节的顺序，把第 1–3、5 步落地为代码：P0 稳定 `GptMarkdown` 输入、初始窗口、渲染降级、会话列表 P2；第 4 步（P1 `select` 收窄）为条件实施。全图完成 = 第 1–3、5 步合入并按其口径复测，P1 触发判定有数据结论，Android 真机 3 轮验收记录在案。实现进入本图，不只是规划。

## Notes

- 输入基线（已收图，不重开）：`.scratch/list-performance/decision.md`（决策与验收口径）、`.scratch/list-performance/evidence/baseline.md`（模拟器基线）、该图票 01–04 的 Answer。
- 执行进入地图：每票 = 实施切片，写码 + 测试 + 复测 + 一次提交。提交在 `v1-dev`，Conventional Commits 中文，scope `perf(list)`。
- 每票关票只需测试通过 + 复测数字回填票内，不强制该步达到 §7 阈值。硬门禁只有两处：第 1–2 步复测决定 P1 是否启动；《总验收与收图》按 §7 判定。
- 复测环境：日常用 Android 模拟器 `Medium_Phone_API_37.0 -gpu host` 跑 `integration_test/list_perf_test.dart`（每票 1 轮）；总验收用 Android 真机 profile，3 轮取波动范围。
- 真机接入：USB 调试 + `flutter devices` 取 device id，复测命令替换 `-d <id>`；手动查看可用 `flutter run --profile -d <id> --dart-define=OPEN_CHAT_STRESS_SEED=true`。
- 测试要求：窗口计算、缓存失效等逻辑必须有 widget/unit 测试；纯视觉项（表格列宽、mermaid 延迟渲染）以人工验收 + 压测为准。
- 视觉验收：表格列宽与 mermaid 延迟渲染需用户看模拟器截图/预览确认后才能关票。
- 每个会话先读 `GLOSSARY.md`（`Initial Window`、`Sticky Bottom` 已定义）与 `docs/agents/domain.md`；按需调用 grilling、domain-modeling。
- 同一时刻只跑一张票；先改 `Status: claimed` 再动代码。
- 压测数据入口：`OPEN_CHAT_STRESS_SEED`（`lib/dev/mock_seed.dart` 的 `seedStressSamples`）；`flutter drive` 每轮会清空数据并重新播种（30–35s，不计入首屏计时）。

## Decisions so far

<!-- 每个已关闭的票一行：票名 + 一句话结论。详细答案在票内。 -->

- [P0 稳定 GptMarkdown 输入](issues/01-p0-stable-markdown-input.md): 空来源不装 pattern，pattern 与正文 widget 按内容缓存，正文补 `isStreaming`；模拟器流式滚动慢帧 1.58%，首屏仍 1651ms（留给《初始窗口》）。
- [初始窗口](issues/02-initial-window.md): 只渲染末 50 条、向上距顶 200px 内每次补 40 条；补历史在布局阶段两段修正偏移（估算 + 锚点 `layoutOffset` 实测），视口不跳动；模拟器首屏 347ms、`build max` 95.56ms（改造前 1966–5623ms），build 侧大跳帧消除，慢帧余量受模拟器光栅化影响。

## Not yet specified

- 总验收不达标时的补强票：真机数据出来前无法切分（候选：数据层分页触发判定、进一步重建隔离）。只有 §7 未达标才毕业成票。
- 10000 条消息 / 10000 个会话压力场景是否进入本图：`decision.md` 明确未覆盖，等真机 1000 条数据后再判断是否需要专项。

## Out of scope

- 数据层分页加载（`decision.md` §6 仅建议，触发条件未满足）
- 引入第三方列表包（`super_sliver_list` 等）
- `reverse: true`、`SliverGptMarkdown`、全局 keep-alive、LaTeX 缓存调整
- 设置页、附件条、来源列表、Markdown 表格等本图外列表
- 重新论证方案或改验收口径（已由「列表性能与虚拟滚动」图锁定）
