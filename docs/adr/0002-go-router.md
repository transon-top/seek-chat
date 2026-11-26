# go_router 承载设置等独立页面路由

设置从底部 Sheet 改为独立页面，需要可深链的页面栈：根页、账户、数据管理、
字体大小、位置信息都是真实路由，返回键与深链（无 Key 提示条直达账户页）
必须一致。Flutter 的 `Navigator` 1.0 也能 push 页面，但路径与参数只能靠
手写 `MaterialPageRoute` 约定，深链与测试都要另建一套解析。

因此引入 `go_router`，由 `lib/app/router.dart` 统一注册路由树，`ShadApp.router`
接管 `routerConfig`。路由地址常量放在所属功能内（`SettingsRoutes`），`app/`
只做组装。

## Considered Options

- 保持 `Navigator.push` + `MaterialPageRoute`：零新依赖，但设置子页与深链参数
  （`/settings/account?focus=1`）没有统一地址，返回栈与测试难以表达。
- `auto_route` + 代码生成：同样解决路由，但引入生成步骤与注解，超出本仓库
  「手写 Provider、生成物只用于 drift 与 ARB」的既有约定。
- `go_router`：官方维护，`RouterConfig` 可直接交给 `ShadApp.router`；路径即地址，
  深链、返回与测试共用同一棵树。

## Consequences

- `lib/app/app.dart` 从 `ShadApp` 改为 `ShadApp.router`；`ChatHome` 拆到
  `lib/app/chat_home.dart`，避免与路由表循环依赖。
- 设置页不再需要 `showShadSheet`；语言与外观仍是弹窗，朗读音色仍是底部 Sheet，
  它们不占路由，只提交时才写入。
- 数据管理页的历史区仍由 `app/router.dart` 注入，`features/settings` 不 import
  其他功能目录。
- 历史导入完成后通过 `historyReloadProvider` 通知聊天页重置界面状态，
  不再依赖设置入口传入回调。
- 测试用 `GoRouter(initialLocation: ...)` 直接渲染设置子树；新增页面须同时在
  `router.dart` 与设置页测试的路由表登记。
