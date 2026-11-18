# 票 09：shadcn_ui 聊天界面原型

一次性粗原型，回答「长什么样、怎么动」。数据全部是假的，没有数据库、网络或真实
状态机；生产实现按票 10 的界面规格另做。视觉按参考截图收敛为极简黑白灰、大圆角
输入框、胶囊开关与底部免责声明。

## 运行

```sh
flutter run -t prototype/main.dart -d <设备 id>
```

主界面只保留菜单、会话标题、消息区与输入区。会话抽屉里放会话增删改、模型切换、
原型场景切换与深浅主题开关。原型场景覆盖：完整、流式、空会话、加载中、错误、
已停止、断流、内容拒答、超长消息。

可选的启动参数（截图与演示用）：

```sh
flutter run -t prototype/main.dart \
  --dart-define=PROTOTYPE_SCENARIO=streaming \
  --dart-define=PROTOTYPE_DARK=true
```

## 覆盖的交互

- 会话抽屉：新建、打开、重命名、删除、模型切换、原型场景、主题开关。
- 消息流：用户气泡与附件、助手思考块折叠与实时计时、行内引用角标、来源卡片、
  分支切换、复制 / 重新生成 / 朗读入口、编辑入口。
- 流式：光标、搜索进度卡、行内停止、停止后「继续生成」、断流后的重试、完成后的操作条。
- 输入区：多行输入、深度思考 / 智能搜索胶囊开关、附件条（上传进度、失败重试、
  删除）、语音录音态、朗读入口、发送 / 停止、底部免责声明。
- 状态：空会话首屏、加载、连接错误、用户停止、断流、内容拒答、超长消息折叠。

## 明确不做

- 真实 Markdown / 数学 / Mermaid 渲染（生产实现已由 `lib/features/chat/markdown_view.dart` 负责）。
- 真实上传、语音、复制、朗读与网络请求；按钮只给视觉与状态反馈。
- 设置页与数据管理页见[票 20 原型](settings/README.md)，本原型只保留抽屉里的设置入口占位。
- 小屏适配、无障碍、国际化与像素级对齐；这些留给票 10 / 18 / 20。
- 测试只覆盖一条冒烟路径（发送、停止、场景切换、展开长消息），见
  `test/prototype/prototype_test.dart`。

## 截图

由 iPhone 17 Pro 模拟器直接采集：

| 文件 | 状态 |
| --- | --- |
| `screenshots/01-demo-light.png` | 完整会话（浅色） |
| `screenshots/02-streaming-light.png` | 流式中：思考计时、搜索进度、停止 |
| `screenshots/03-empty-light.png` | 空会话首屏 |
| `screenshots/04-error-light.png` | 连接错误与重试 |
| `screenshots/05-dropped-light.png` | 断流与重试 |
| `screenshots/06-long-light.png` | 超长消息折叠 |
| `screenshots/07-demo-dark.png` | 完整会话（深色） |
