import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';

/// Markdown 配色：照搬 chat-demo `theme.css` 的 markdown 令牌。
class AppMarkdownColors {
  const AppMarkdownColors({
    required this.labelPrimary,
    required this.labelSecondary,
    required this.labelTertiary,
    required this.labelCaption,
    required this.brandText,
    required this.borderL1,
    required this.borderL2,
    required this.borderL3,
    required this.inlineCodeFill,
    required this.codeBlockFill,
    required this.codeBlockBannerFill,
    required this.citationFill,
    required this.placeholderFill,
  });

  static AppMarkdownColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  static const light = AppMarkdownColors(
    labelPrimary: Color(0xFF0F1115),
    labelSecondary: Color(0xFF61666B),
    labelTertiary: Color(0xFF81858C),
    labelCaption: Color(0xFFADB2B8),
    brandText: Color(0xFF3964FE),
    borderL1: Color(0x0A000000),
    borderL2: Color(0x1A000000),
    borderL3: Color(0x1F000000),
    inlineCodeFill: Color(0xFFEBEEF2),
    codeBlockFill: Color(0xFFF9FAFB),
    codeBlockBannerFill: Color(0xFFF9FAFB),
    citationFill: Color(0xFFEBEEF2),
    placeholderFill: Color(0xFFF5F6F7),
  );

  static const dark = AppMarkdownColors(
    labelPrimary: Color(0xFFF9FAFB),
    labelSecondary: Color(0xFFCFD3D6),
    labelTertiary: Color(0xFFADB2B8),
    labelCaption: Color(0xFF81858C),
    brandText: Color(0xFF679EFE),
    borderL1: Color(0x0FFFFFFF),
    borderL2: Color(0x1FFFFFFF),
    borderL3: Color(0x29FFFFFF),
    inlineCodeFill: Color(0xFF2C2C2E),
    codeBlockFill: Color(0xFF1B1B1C),
    codeBlockBannerFill: Color(0xFF2C2C2E),
    citationFill: Color(0xFF353638),
    placeholderFill: Color(0xFF2C2C2E),
  );

  final Color labelPrimary;
  final Color labelSecondary;
  final Color labelTertiary;
  final Color labelCaption;
  final Color brandText;
  final Color borderL1;
  final Color borderL2;
  final Color borderL3;
  final Color inlineCodeFill;
  final Color codeBlockFill;
  final Color codeBlockBannerFill;
  final Color citationFill;
  final Color placeholderFill;
}

/// 正文：chat-demo `--dsw-font-markdown-base`（16/28）。
TextStyle markdownBodyStyle(BuildContext context) => TextStyle(
  fontSize: 16,
  height: 28 / 16,
  color: AppMarkdownColors.of(context).labelPrimary,
);

/// 思考与过程性正文：chat-demo `--dsw-font-markdown-small`（14/24）。
TextStyle markdownSmallStyle(BuildContext context) => TextStyle(
  fontSize: 14,
  height: 24 / 14,
  color: AppMarkdownColors.of(context).labelSecondary,
);

/// 全局 Markdown 主题：字号、链接色、代码块与引用块，取自 chat-demo `markdown.css`。
GptMarkdownThemeData buildMarkdownTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? AppMarkdownColors.dark
      : AppMarkdownColors.light;
  TextStyle heading(double size, double line, FontWeight weight) => TextStyle(
    fontSize: size,
    height: line / size,
    fontWeight: weight,
    color: colors.labelPrimary,
  );

  return GptMarkdownThemeData(
    brightness: brightness,
    h1: heading(24, 34, FontWeight.w700),
    h2: heading(22, 32, FontWeight.w700),
    h3: heading(20, 30, FontWeight.w700),
    h4: heading(16, 28, FontWeight.w600),
    h5: heading(16, 28, FontWeight.w600),
    h6: heading(16, 28, FontWeight.w600),
    linkColor: colors.brandText,
    linkHoverColor: colors.brandText,
    hrLineThickness: 1,
    hrLineColor: colors.borderL2,
    hrLinePadding: const EdgeInsets.symmetric(vertical: 16),
    // chat-demo 的 h1 下方没有分隔线。
    autoAddDividerLineAfterH1: false,
    inlineCode: InlineCodeStyle(
      fontSizeFactor: 0.875,
      color: colors.labelPrimary,
      backgroundColor: colors.inlineCodeFill,
      borderColor: Colors.transparent,
      borderWidth: 0,
      borderRadius: const Radius.circular(6),
      padding: const EdgeInsets.symmetric(horizontal: 5),
    ),
    styleSheet: GptMarkdownStyleSheet(
      // chat-demo 段落间距 16。
      blockSpacing: 16,
      link: const LinkStyle(decoration: TextDecoration.none),
      blockQuote: BlockQuoteStyle(
        barWidth: 2,
        barColor: colors.labelCaption,
        barRadius: Radius.zero,
        padding: const EdgeInsets.only(left: 14),
        margin: EdgeInsets.zero,
      ),
      list: ListStyle(
        bulletColor: colors.labelSecondary,
        markerTextStyle: TextStyle(color: colors.labelSecondary),
      ),
      codeBlock: CodeBlockStyle(
        backgroundColor: colors.codeBlockFill,
        borderRadius: const Radius.circular(12),
        padding: const EdgeInsets.all(16),
        headerPadding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
        fontSize: 13,
        textColor: colors.labelPrimary,
        languageStyle: const TextStyle(fontSize: 12, height: 18 / 12),
      ),
      hr: HrStyle(
        thickness: 1,
        color: colors.borderL2,
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      latex: const LatexStyle(
        padding: EdgeInsets.all(4),
        scrollBlockHorizontally: true,
      ),
    ),
  );
}
