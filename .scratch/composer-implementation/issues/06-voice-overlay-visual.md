# 06: 蓝色动态浮层视觉

**What to build:** 把按住说话的浮层做成原型确认的视觉：贴底蓝色动态区域、漂移
团块上缘、跟随按住位置的高光与 32 根电平波形；录音、取消、识别共用同一效果，
减少动画时冻结为静态帧。

**Blocked by:** 05
**Status:** resolved
**Type:** task

- [x] 浮层贴底覆盖输入卡与草稿行，约 60% 屏高，不盖顶部栏、不遮消息区、不加
      全屏遮罩、不响应点击。
- [x] 蓝区由 6 枚缓慢漂移、互相重叠的径向椭圆构成动态不规则上缘（周期约 4–6s），
      顶部全透明、底部渐到实色；不引入渐变 / 动效库，用 `CustomPainter` 自绘。
- [x] 高光锚定按下 / 移动的真实 pointer 坐标，并随电平脉动；取消态不变红，
      只把文案换成「松开取消」。
- [x] 波形 32 根（高 28、宽 2.4、间距 1.6），电平平滑后约 30fps 插值；录音未开始
      为静止低幅骨架，识别中保持低幅波形；只重建浮层，不触发整页重建。
- [x] 文案：录音「松手发送，上滑取消」、取消「松开取消」、识别「识别中」；
      15 / w500 白色，底部留白 44。
- [x] `MediaQuery.disableAnimations` 为 true 时漂移、高光脉动与波形全部冻结为
      静态帧；进退场过渡归零。
- [x] 删除旧录音状态胶囊组件；删除废弃 ARB `voiceInput`、`voiceInputRecording`、
      `voiceInputStop`、`voiceInputTranscribing`、`voiceInputCancel`，重跑
      `flutter gen-l10n`。
- [x] 测试覆盖：三文案、波形骨架、语义播报、减少动画冻结、浮层不拦截点击。

## Answer

- `recording_overlay.dart`：`CustomPainter` 自绘 6 枚径向椭圆漂移团块（漂移周期
  按 4–6s 调整，顶部全透明、底部渐到实色）、按住位置高光与 32 根波形；文案 15 /
  w500、底部 44。取消态复用同一蓝色只换文案。
- 高光位置经 `voice_hotspot.dart` 的 `NotifierProvider` 由 `VoiceButton` 的
  pointer down / move 写入、up / cancel 置空，浮层换算到本地坐标；读屏语义 tap
  用默认位置。电平取 `SpeechState.level`，浮层内按约 30fps 指数平滑。
- 录音 / 取消使用电平驱动的波形；`starting` 为静止低幅骨架，`transcribing` 为
  低幅波形。`disableAnimations` 时停 ticker，漂移、高光脉动与波形全部冻结。
- 颜色全部由 `ShadColorScheme.primary` / `primaryForeground` 派生，不写死十六进制
  （`ui.md` §3.1）；浮层包 `SafeArea(top: false)`，蓝色止于底部安全区。
- 60% 屏高与点击穿透沿用票 05 的插槽；槽只 `select` phase + level，不触发整页
  重建。旧状态胶囊与废弃 `voiceInput*` ARB 键在 HEAD 已不存在，无需再删。
- 波形条间距照搬原型：每根左右各 1.6（条间 3.2），与截图一致。
- 测试新增：32 根骨架静止、识别低幅、减少动画冻结（无待调度帧）、既有三文案 /
  liveRegion / 点击穿透回归。`flutter analyze` 无问题；`flutter test` 477 通过。
- 遗留：真机对图、安全区与浮层 / 输入法切换行为在票 07 验收。
