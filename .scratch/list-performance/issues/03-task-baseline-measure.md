# 列表基线测量

Type: task
Status: resolved

## Question

在目标规模下，两列表现在的真实表现是什么？没有基线就无法判断「是否适合用虚拟滚动」。必须完成：

1. 构造测量数据：debug mock 场景加入单会话 1000 条消息（混合 Markdown / 代码块 / 表格 / mermaid / LaTeX / 图片）与 1000 个会话；保留现有 50 会话场景不动。
2. 在可运行环境（模拟器或桌面优先，注明环境与设备）测量三条验收标准：
   - 打开长会话：首屏时间（可感知即开，约 <300ms）
   - 滚动 1000 条消息：帧耗时 / 掉帧（DevTools timeline）
   - 流式输出期间滚动：是否阻塞
   - 附：内存占用（DevTools memory）
3. 同时测历史会话列表：1000 个会话的打开、滚动成本。
4. 记录测量方法（命令、设备、Flutter 版本），使他人可复现。

产出测量报告 `.scratch/list-performance/evidence/baseline.md`（含原始数据/截图链接）。产品代码不改；mock 场景可加 debug 入口。

## Deliverable

报告 + 复现步骤；Answer 记录结论数字（打开耗时、帧耗时分布、内存峰值）与环境。

## Answer

完成：压测样本（`lib/dev/mock_seed.dart` 的 `seedStressSamples`，1 个 1000 条消息的长会话 + 1000 条会话，覆盖 Markdown/代码/表格/mermaid/LaTeX/图片链接）与测量入口（`integration_test/list_perf_test.dart` + `test_driver/integration_test.dart`）已落地，产品代码未改。测量在 `flutter drive --profile`、Android 模拟器 `Medium_Phone_API_37.0`（API 37）+ 宿主 Metal（`-gpu host`）、Flutter 3.50.0 / Dart 3.14.0 下跑三轮全通过。报告：`.scratch/list-performance/evidence/baseline.md`；原始日志：`evidence/baseline-run-host-{1,2,3}.log`。

结论数字（三轮范围）：

- 打开 1000 条消息的会话：首屏 **1966–5623ms**，其中单个 build 帧 **1578–4461ms**（build p50 仅 0.12–0.44ms）。对照的 2 条消息会话：首屏 89–555ms。打开成本集中在首屏跳到底部时的一次性大量构建。
- 滚动 1000 条消息：build p90 0.71–0.93ms / max 4.5–15ms；raster p90 16.4–17.5ms；合计 >16.7ms 的帧占 **9.5–16.6%**。
- 流式期间（mock 约 13 增量/秒、200 个增量）：静止与滚动均未出现明显阻塞；滚动窗口慢帧占 0.4–11.2%，偶发单帧 raster 233–241ms。
- 1000 个会话的抽屉：打开首行可见 106–247ms（完整 529–706ms）；滚动慢帧占比 1.4–71.6%（波动大）。
- 内存 RSS：冷启动峰值 531–561MB；打开长会话后 341–430MB；滚动/流式后 326–427MB，未见随滚动单调增长。

环境限制：模拟器而非真机，绝对值波动大，决策只看相对关系与形状；默认 `hw.gpu.mode=auto` 会回退 SwiftShader（raster 142–860ms/帧），那批数据已作废；`flutter drive` 每轮清空应用数据，播种 30–35s 不计入首屏。流式为本地 mock，未覆盖真实服务端速率与长回复。
