# 08: 固定高度文件卡的动态字体封顶

**What to build:** 票 07 验收时发现：文件卡固定 210×64，两行文字在系统字号 2.0 下
溢出 22px；规格同时要求字号 0.8–2.0 与固定卡片尺寸，二者冲突。本票记录取舍，
实现卡内文字封顶，并补自动化验证。

**Blocked by:** 04
**Status:** resolved
**Type:** task

- [x] 记录冲突：`GLOSSARY.md` Font Scale 要求文字随系统字号（0.8–2.0），
      `attachments.md` / 票 04 要求文件卡固定 210×64 且行高 76。
- [x] 仅文件卡内两行文字封顶 1.3 倍（`MediaQuery.withClampedTextScaling`），
      卡片尺寸、行高、图标、间距与其余文字不变。
- [x] 双语 × 深浅 × 320 宽 × 2.0 的验收测试同时断言无溢出与封顶值生效，
      防止退化成「整体压小」而静默通过。
- [x] `GLOSSARY.md` Font Scale 段补一句固定高度控件的封顶例外，文档与实现一致。

## Answer

- 冲突无法同时满足：1.3 倍时两行文字（12 / 11，行高 1.4）加 3px 间距为 44.9px，
  恰好放进 46px 卡片内容高；2.0 倍需要约 67px。选择遵守固定几何规格，卡内封顶
  1.3，避免撑高卡片或截断信息。
- 实现：`attachments_view.dart` 的 `_draftDocumentTextScaleMax = 1.3`，只包裹
  文件名 / 状态两行，不影响扩展名色块、图片卡与消息附件。
- 测试：`composer_text_scale_test.dart` 在草稿态断言
  `MediaQuery.textScalerOf(...).scale(10) == 13`，固定封顶而非无限压缩；四种
  语言 / 主题组合均无溢出。
- 文档：`GLOSSARY.md` Font Scale 增加固定高度控件例外说明；票 07 的验收注释
  指向本票。
- 验证：`flutter analyze` 无问题；相关测试通过。
