# 内容安全与图片审核

Type: grilling
Status: open
Blocked by: 05, 13

## Question

1. `safety_check: { level: 'high' }` 的启用范围；是否所有请求都开启。
2. `stop_reason: refusal` 与 `stop_details` 的展示与后续操作。
3. 图片审核：上传图片触发审核的时机、审核失败的提示、是否阻止发送。
4. 错误码与用户文案；与 429 / 400 的区分。
5. 隐私：审核涉及的数据发送范围；设置页是否需要说明。
6. 测试样例：正常、拒答、图片被拒、网络失败。

产出：`safety.md` 章节 + 拒答状态表。
