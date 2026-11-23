# 05: 清除本地会话与附件

Status: ready-for-agent
Blocked by: 04

## What to build

启动失败页上的恢复入口：

- 危险按钮「清除本地会话与附件」；点击后二次确认，确认文案逐项写明删除与保留范围。
- 确认后先关闭数据库连接，再删除：主库及 `-journal` / `-wal` / `-shm`、旧库 `open_chat.sqlite` 及同套附属文件、附件目录整个删除。
- 保留 `SharedPreferences` 中的设置与安全存储中的 API Key。
- 删除成功后自动重试启动，成功进入应用。
- 删除失败留在错误页并显示 `startupClearDataFailed`；不自动重试、不自动再清库，用户可再次操作。
- 重置不承诺原子性：部分删除后再次执行应继续完成剩余删除。
- 不调用 Android `clearApplicationUserData()`。

## Acceptance criteria

- [ ] 错误页提供「清除本地会话与附件」危险按钮；点击打开二次确认，文案写明删除与保留范围。
- [ ] 取消不删除任何数据。
- [ ] 确认后数据库连接先关闭，文件删除其后发生。
- [ ] 主库、`-journal`、`-wal`、`-shm`、旧库及同套附属文件、附件目录全部删除。
- [ ] 设置与 API Key 保留。
- [ ] 删除成功后自动重试启动并进入应用。
- [ ] 删除失败显示 `startupClearDataFailed`，留在错误页，不自动重试，数据不再被自动改动。
- [ ] 部分删除后再次执行可继续完成剩余删除。
- [ ] 不调用 `clearApplicationUserData()`。
- [ ] ARB 新增 `startupClearData`、`startupClearDataConfirmTitle`、`startupClearDataConfirmBody`、`startupClearDataConfirm`、`startupClearDataFailed`；en/zh 与生成物同步。
- [ ] `flutter analyze` 与全量 `flutter test` 通过。
