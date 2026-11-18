# 用户元信息：语言与所在地

Type: grilling
Status: resolved
Blocked by: 05

## Question

1. chat-demo 的 `latest_reminder` 角色与 `src/services/chat/latestReminder.ts`、`locationData.ts` 的行为。
2. 设置页：语言（中文 / 英文）与所在地（国家 / 城市）的选择与持久化。
3. 传递格式：`latest_reminder` 的 content 模板；每轮请求的位置；回答版本快照。
4. 与界面语言的关系：界面语言是否独立于传给模型的语言；默认值。
5. 未设置时的默认行为；修改后对后续请求的影响。
6. 隐私说明与清除入口。

产出：`user-metadata.md` 章节 + 模板样例。

## Comments

- 2026-11-18：`latest_reminder` 的插入位置（对应 user 前、快照变化才插）与回答版本快照语义已由票 05 锁定，见 [`../api.md`](../api.md) §3.3。本票只需锁定 content 的取值模板与样例。

## Answer

结论写入 [`user-metadata.md`](../user-metadata.md)。要点：

1. **模板**：`日期,星期,所在地,平台,语言` 逗号连接；日期为本地时区 `YYYY-MM-DD`，星期取应用语言长名称；所在地在中文界面下按市 → 省 → `中国` 回退，其他界面只发本地化国家名，未设置为空字段；平台为 `iOS` / `Android`；语言为 `中文` / `English`。
2. **设置**：语言存 `user.locale`（`zh` / `en`），首次跟随系统语言，之后持久化；同一设置同时驱动界面与元信息，不设第二语言。所在地存 `user.location` JSON，按 chat-demo `normalizeLocation` 校验。
3. **位置选择器**：形态跟随**系统语言**而非应用语言；中文系统为省 / 市两级，其他系统为全量国家 / 地区列表。补「不指定」作为清除入口（chat-demo 无清除项）。
4. **快照**：附件补齐成功、请求发出前生成并写入 assistant 行；重新生成与编辑产生独立快照，续写沿用原快照，历史缺快照不插；插入与去重规则沿用 `api.md` §3.3。
5. **隐私**：只随同一条消息请求发给用户配置的 DeepSeek API，不申请定位权限、不新增接收方；v1 不单列隐私说明，清除入口即「不指定」。
6. **测试**：纯函数模板、设置默认与持久化、控制器快照时机、设置页两种选择器；明细见 `user-metadata.md` §6。
