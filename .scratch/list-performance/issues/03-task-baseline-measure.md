# 列表基线测量

Type: task
Status: open

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
