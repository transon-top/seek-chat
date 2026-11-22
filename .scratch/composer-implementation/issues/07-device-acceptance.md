# 07: 真机验收与集成测试

**What to build:** 在真机上完成输入区改版的端到端验收：补齐权限、系统选择器、
按住说话与生命周期相关的集成测试，并按原型截图逐状态对图。发现缺陷回到对应票
修复，本票只记录验收结果与证据。

**Blocked by:** 03, 04, 06
**Status:** claimed
**Type:** task

- [ ] 集成测试覆盖：照片权限允许 / 受限 / 拒绝；相机；系统相册；系统文件选择器；
      按住 / 上滑 / 松手；来电中断；进后台取消；浮层与输入法切换。
- [ ] iPhone 与 Android 各 10 个状态、深浅两套对图通过：空态、有文本、草稿、
      面板、面板权限、录音、取消、识别中、生成中、深浅色 402pt / 411pt 无溢出。
- [ ] 深 / 浅色下照片权限拒绝、受限「管理」、空图库、读取失败四种横条降级
      均按规格呈现。
- [x] 双语（中 / 英）× 320 宽 × 动态字体 2.0 无文本溢出。
- [ ] 人工确认：Android 预测性返回「先收面板、再退页面」；输入法与面板同时收起
      的空窗；iOS 受限授权后「管理」返回重载；HEIC 转码成功率与方向正常。
- [ ] 确认无数据库迁移、无新增持久化字段；`OPEN_CHAT_PHOTO_STRIP=false` 构建
      在 Android 上只剩三宫格且不申请照片权限。
- [ ] 验收证据（截图、设备与系统版本、失败项）记录在本票 Answer 中。

## Comments

自动化部分（2026-11-22）：新增 `integration_test/composer_test.dart`，用 fake
录音器 / ASR / 照片库注入完整应用，覆盖可在设备上自动驱动的交互：

- 按住说话：上滑 80dp 进入取消态、回拉恢复、松手丢弃且不转写。
- 按住松手：转写后插入输入框并自动发送，流式回复落库（断言仓储里的回复块）。
- 录音中进后台：取消录音、不转写。
- 录音中系统中断：fake 会话发出中断事件，丢弃录音并提示「录音已中断」；
  真实来电 / 路由变化走同一条 `interruptions` 通道，留真机验证。
- 面板：`+` 展开；返回键先收面板、页面不退出；点输入框收起面板。
- 输入法聚焦时按住麦克风：输入框失焦、显示浮层。
- 面板展开时按住麦克风：面板收起、显示浮层。

运行与结果：

```bash
flutter test integration_test/composer_test.dart -d <device>
```

- iOS 26.3 模拟器（iPhone 17 Pro）：7 项通过。
- Android 17（API 37）模拟器：7 项通过（收尾 `adb uninstall` 超时警告，
  不影响测试结果）。
- `flutter analyze` 无问题；`flutter test` 477 通过。

仍待人工：照片权限允许 / 受限 / 拒绝、相机、系统相册、系统文件选择器；
真实来电中断；双端真机 10 状态 × 深浅色对图；双语 × 320 宽 × 动态字体 2.0；
四种横条降级；预测性返回；输入法与面板同时收起的空窗；iOS 受限授权后
「管理」返回重载；HEIC 转码成功率与方向；确认无数据库迁移、无新增持久化
字段；`OPEN_CHAT_PHOTO_STRIP=false` 构建只剩三宫格且不申请照片权限；
截图、设备与系统版本证据。

自动化补充（2026-11-22）：

- 新增 `test/features/chat/composer_text_scale_test.dart`：中 / 英 × 深 / 浅共 4 组，
  320×720、系统字号 2.0，覆盖空态、有文本、生成中、草稿（图片 + 长文件名 + 失败
  原因）、面板（横条就绪 / 拒绝 / 受限 / 空图库 / 读取失败 + 三宫格）与浮层三态
  （录音 / 取消 / 识别中），断言无溢出异常。
- 测试先红：文件卡固定 64 高，两行文字在 2.0 下溢出 22px。为守住 210×64 规格，
  仅卡内文字封顶 1.3 倍（`attachments_view.dart` 的
  `_draftDocumentTextScaleMax`），并断言封顶值生效；取舍记录在票 08，行高、卡片
  尺寸与图标不变。
- `photo_strip_test.dart` 增加按 `OPEN_CHAT_PHOTO_STRIP` 互斥的两条：默认构建断言
  双端启用；关闭构建断言 Android 关闭、iOS 仍启用。验证：
  `flutter test test/features/chat/photo_strip_test.dart --dart-define=OPEN_CHAT_PHOTO_STRIP=false`
  → 12 通过、1 跳过；默认全量套件 → 481 通过、1 跳过。
- `flutter build apk --debug --dart-define=OPEN_CHAT_PHOTO_STRIP=false` 成功
  （51.6s，`build/app/outputs/flutter-apk/app-debug.apk`）。无横条时面板只剩三宫格
  由 `attachment_panel_test.dart` 覆盖；真机运行时权限申请仍需人工确认。
- 数据层：`git diff 6ff2d1c..HEAD -- lib/shared/data` 为空；`types.dart` 只新增
  内存字段 `DraftAttachment.sourceAssetId`，未落库、未进导出。
- `flutter analyze` 无问题。

真机 / 人工项（照片权限弹窗、相机、系统相册 / 文件选择器、来电中断、10 状态对图、
预测性返回、HEIC 转码、横条关闭后的 Android 运行时表现与截图证据）仍待人工完成。
