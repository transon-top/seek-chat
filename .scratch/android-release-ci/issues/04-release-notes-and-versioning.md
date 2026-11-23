# 版本说明形态与版本号流程

Type: grilling
Status: open
Blocked by: 02

## Question

基于票 02 的调研，敲定版本说明与版本号流程：

1. 版本说明的生成方式：GitHub 自动 notes、仓库内 `CHANGELOG.md`、git-cliff 等工具，还是「自动 notes 初稿 + 手动润色」。
2. 版本说明的读者与语言：面向最终用户还是开发者；中文、英文或双语；分类与长度。
3. tag 命名与版本号来源：`vX.Y.Z` 与 `pubspec.yaml` 的 `x.y.z+n` 如何对应；是否恢复「tag 与 pubspec 版本一致」的 CI 校验（此前预留）。
4. 发版前版本 bump 由谁、在哪一步完成；是否允许直接以 tag 覆盖 `--build-name` / `--build-number` 而不改 `pubspec`。
5. 预发布（rc / beta）是否需要单独的 tag 规则与 Release 标记。
6. `v1-dev` → `main` 的合并与 tag 时机：PR、直接 merge 还是 fast-forward；tag 打在 `main` 的哪个提交上。
7. 公开仓库后的分支保护、tag 保护与 Release 权限；是否需要 draft Release（当前决定为自动 published，若调研有反例再改）。
8. `CHANGELOG.md` 是否保留；若保留，由人写还是工具生成。

产出一份决策：notes 来源与格式、版本号 / tag 流程、发布前检查清单、分支与 tag 保护。
