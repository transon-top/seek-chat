# 04: Contract，删除 controller 旧编排

**What to build:** 五条意图全部经 Reply Run 后，删除 controller 中不再使用的流合并、请求构造、附件补齐、终态落盘与标题写库代码。controller 只剩意图路由、busy、API Key 门禁、keepAlive、stop/flush 转发与 ChatState 镜像。后台补写与启动兜底继续工作，公共接口与注释同步收紧。`docs/features/` 的行为规格不改。

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] controller 内不再存在流合并、请求构造、附件补齐或终态落盘逻辑
- [ ] 后台 flush 经当前 Reply Run 完成，失败仍不阻塞
- [ ] 五条意图全部经新模块，无旧路径残留
- [ ] spec 列出的 seam 测试全部落地，新增测试只走 Reply Run 公共接口
- [ ] 现有测试无需删除；仅允许必要的 import 与类型调整
- [ ] `flutter analyze` 与 `flutter test` 通过
