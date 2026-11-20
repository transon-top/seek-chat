# 方案决策：两个列表的最终建议

Type: grilling
Status: open
Blocked by: 01, 02, 03

## Question

综合「Flutter 虚拟滚动与高性能列表方案调研」(01)、「每消息渲染成本与重建范围调研」(02) 与「列表基线测量」(03)，决定：

1. 聊天消息列表：保持 `ListView.builder` + 局部优化，还是引入第三方列表包？若引入，选哪个、版本、理由与回退路径。若保持，列出必须做的优化项与优先级。
2. 历史会话列表：同上；是否需要与消息列表统一方案。
3. 重建隔离：是否将流式 token 的重建范围从整页收敛到单条消息？落到哪个层级（provider 拆分 / Selector）。
4. 渲染降级与懒渲染：`SliverGptMarkdown`、图片 `cacheWidth`、mermaid/LaTeX 的视口策略，取哪些。
5. 分页加载是否进入建议；若是，只写数据层改造要点，不实施。
6. 每条建议的验收口径（对应三条验收标准）与风险。

产出 `.scratch/list-performance/decision.md`：方案对比、最终建议、实施顺序（未来 effort 的输入），不写代码。

## Deliverable

`decision.md` + 票内 Answer 摘要。结束后本图到达终点。
