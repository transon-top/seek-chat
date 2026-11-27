import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:gpt_markdown/custom_widgets/code_field.dart';
import 'package:gpt_markdown/custom_widgets/unordered_ordered_list.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mermaid_core/mermaid_core.dart' as mermaid_core;
import 'package:mermaid_flutter/mermaid_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/markdown_theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/horizontal_fade_scroll.dart';
import '../../shared/widgets/push_menu.dart';
import 'reply_view.dart';

/// ZH
/// 渲染回复中的 Markdown 文本。
///
/// 数学默认只认 `\(...\)` / `\[...\]`；单 `$` 会误伤价格文本（票 02）。
/// `mermaid` 围栏交给 `mermaid_flutter`，其余围栏走代码高亮与复制。
///
/// 流式期间按上次渲染耗时的两倍节流，把连续 token 合并成一次更新；
/// 区间限制在 50ms 到 2s（票 08）。
///
/// EN
/// Render Markdown text inside replies.
///
/// Math accepts only `\(...\)` / `\[...\]` by default; a lone `$` would mangle
/// price text (ticket 02). Fences named `mermaid` go to `mermaid_flutter`; other
/// fences get code highlighting and copy.
///
/// While streaming, throttle at twice the last render cost, merging tokens into
/// one update. The interval is clamped from 50ms to 2s (ticket 08).
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.text,
    this.streaming = false,
    this.sources,
    this.dense = false,
    this.disableLinks = false,
    this.textStyle,
  });

  final String text;

  /// ZH
  /// 回复仍在流式生成时为 true；流结束后立即显示全文。
  ///
  /// EN
  /// True while the reply is still streaming; show the full text immediately after it ends.
  final bool streaming;

  /// ZH
  /// 传入时把 `[citation:N]` 渲染为可点击的来源角标；不传则保留原文。
  ///
  /// EN
  /// When set, render `[citation:N]` as a tappable source badge; otherwise keep the raw text.
  final List<Source>? sources;

  /// ZH
  /// 思考与过程性正文使用小号文本。
  ///
  /// EN
  /// Thinking and preamble text use the small text style.
  final bool dense;

  /// ZH
  /// 思考内容只保留链接文字，不渲染成可点击链接。
  ///
  /// EN
  /// Thinking content keeps link text but does not render tappable links.
  final bool disableLinks;

  /// ZH
  /// 正文样式；为空时按 [dense] 取 Material 的 bodySmall / bodyMedium。
  ///
  /// EN
  /// Body style; when null, use Material bodySmall / bodyMedium based on [dense].
  final TextStyle? textStyle;

  /// ZH
  /// 单块超过此长度时不再解析 Markdown，按纯文本展示（票 08 的降级上限）。
  ///
  /// EN
  /// Blocks longer than this skip Markdown parsing and render as plain text (ticket 08 degradation cap).
  static const int plainTextLimit = 200000;

  static const Duration minInterval = Duration(milliseconds: 50);
  static const Duration maxInterval = Duration(milliseconds: 2000);

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  String _shown = '';
  Timer? _windowTimer;
  DateTime? _renderStartedAt;
  Duration _lastCost = Duration.zero;

  // ZH
  // 正文、来源与样式都不变时复用同一个 widget 实例：新实例会让
  // GptMarkdown 整棵子树重建，复用则被 Flutter 的 identical 短路跳过。
  //
  // EN
  // Reuse the same widget instance while body, sources and style stay unchanged.
  // A new instance rebuilds the GptMarkdown subtree; reuse is skipped by Flutter's
  // identical check.
  (String, String, bool, TextStyle?, bool, bool)? _bodyKey;
  Widget? _body;

  // ZH
  // 引用角标模式按来源内容缓存；来源内容变化时重建。
  //
  // EN
  // Cache the citation badge pattern by source content; rebuild when sources change.
  String _patternSources = '';
  InlinePattern? _pattern;

  @override
  void initState() {
    super.initState();
    _shown = widget.text;
  }

  @override
  void didUpdateWidget(MarkdownView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _shown) {
      if (!widget.streaming) _windowTimer?.cancel();
      return;
    }
    // ZH
    // 新回复、切换版本或流结束：不做节流等待，直接显示最新全文。
    //
    // EN
    // New reply, version switch or stream end: show the latest full text without throttling.
    if (!widget.streaming || !widget.text.startsWith(_shown)) {
      _showLatest();
      return;
    }
    if (_windowTimer?.isActive ?? false) return; // Window output merges at window end.
    _showLatest();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    super.dispose();
  }

  /// ZH
  /// 立即显示最新文本；节流窗口在该帧结束后才开始计时（票 08）。
  ///
  /// EN
  /// Show the latest text immediately; the throttle window starts timing after this frame (ticket 08).
  void _showLatest({bool rebuild = false}) {
    _windowTimer?.cancel();
    _shown = widget.text;
    _renderStartedAt = DateTime.now();
    if (rebuild && mounted) setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) => _afterRender());
  }

  /// ZH
  /// 记录本帧耗时并开启下一个更新窗口；窗口结束时有积压才再渲染。
  ///
  /// EN
  /// Record frame cost and start the next update window; re-render only if content is pending at its end.
  void _afterRender() {
    final started = _renderStartedAt;
    if (!mounted || started == null) return;
    _renderStartedAt = null;
    _lastCost = DateTime.now().difference(started);
    _windowTimer = Timer(_interval(), () {
      if (!mounted) return;
      if (widget.streaming && widget.text != _shown) {
        _showLatest(rebuild: true);
      }
    });
  }

  Duration _interval() {
    final doubled = _lastCost * 2;
    if (doubled < MarkdownView.minInterval) return MarkdownView.minInterval;
    if (doubled > MarkdownView.maxInterval) return MarkdownView.maxInterval;
    return doubled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final style =
        widget.textStyle ?? (widget.dense ? theme.bodySmall : theme.bodyMedium);
    // ZH
    // 识别器必须放在 SelectionArea 内层：Android 上文本选择会抢横向拖拽，
    // 内层先注册才能赢；表格等内层横向滚动仍在更深层，优先于抽屉。
    //
    // EN
    // The detector must sit inside SelectionArea: on Android text selection steals
    // horizontal drags. The inner detector registers first and wins; deeper inner
    // scrolls such as tables beat the drawer.
    return SelectionArea(
      child: PushMenuSwipeDetector(child: _buildBody(style)),
    );
  }

  Widget _buildBody(TextStyle? style) {
    final sources = widget.sources;
    final sourcesKey = _sourcesKey(sources);
    final key = (
      _shown,
      sourcesKey,
      widget.streaming,
      style,
      widget.dense,
      widget.disableLinks,
    );
    if (_bodyKey == key && _body != null) return _body!;
    if (_patternSources != sourcesKey) {
      _patternSources = sourcesKey;
      _pattern = sourcesKey.isEmpty ? null : _citationPattern(sources!);
    }
    final body = _shown.length > MarkdownView.plainTextLimit
        ? Text(_shown, style: style)
        : GptMarkdown(
            _detachedTaskItems(_shown),
            style: style,
            useDollarSignsForLatex: false,
            isStreaming: widget.streaming,
            // ZH
            // 流式期间逐字浮现并淡入；结束后回到静态文档，避免残留 ticker。
            //
            // EN
            // Fade in characters while streaming; return to a static document after to avoid a lingering ticker.
            animation: widget.streaming
                ? GptMarkdownAnimation.fade
                : GptMarkdownAnimation.none,
            charactersPerSecond: 25,
            revealFadeSeconds: 0.3,
            blockAnimation: widget.streaming
                ? GptMarkdownBlockAnimation.fadeIn
                : GptMarkdownBlockAnimation.none,
            onLinkTap: widget.disableLinks ? null : openExternalLink,
            inlineLinkBuilder: widget.disableLinks
                ? (details) =>
                      TextSpan(text: details.label, style: details.style)
                : null,
            inlinePatterns: _pattern == null ? null : [_pattern!],
            // ZH
            // 与 chat-demo 一致：图片不加载，只显示可点击的地址（票 08）。
            //
            // EN
            // Same as chat-demo: images are not loaded, only a tappable URL is shown (ticket 08).
            imageBuilder: _imageAsLink,
            // ZH
            // chat-demo 的 h1-h3 上方留 32，h4-h6 保持段间距。
            //
            // EN
            // Match chat-demo: h1-h3 get 32 above; h4-h6 keep paragraph spacing.
            headingBuilder: widget.dense ? null : _headingBuilder,
            // ZH
            // chat-demo 的表格只保留行分隔线，表头无底色。
            //
            // EN
            // Match chat-demo: tables keep only row dividers; headers have no fill.
            tableBuilder: _tableBuilder,
            // ZH
            // chat-demo 不识别 GitHub Alert，按普通引用块渲染。
            //
            // EN
            // Match chat-demo: GitHub Alerts are not recognized; render them as ordinary block quotes.
            alertBuilder: (context, details) => details.asBlockQuote(),
            // ZH
            // chat-demo 的任务项画成 `☑`/`□` 文本，不用 Material 复选框。
            //
            // EN
            // Match chat-demo: task items are drawn as `☑`/`□` text, not Material checkboxes.
            checkboxBuilder: (context, checked, content, checkboxStyle) =>
                _taskCheckbox(
                  context,
                  checked,
                  content,
                  style ?? DefaultTextStyle.of(context).style,
                ),
            orderedListBuilder: _orderedListItem,
            unOrderedListBuilder: _unorderedListItem,
            // ZH
            // 思考内容比正文更紧凑。
            //
            // EN
            // Thinking content is denser than body text.
            styleSheet: widget.dense
                ? const GptMarkdownStyleSheet(blockSpacing: 12)
                : null,
            codeBuilder: (context, name, code, closed) {
              // ZH
              // mermaid 围栏闭合后才渲染图表；流式半成品按普通代码展示。
              //
              // EN
              // Render a diagram only after the mermaid fence closes; show streaming drafts as ordinary code.
              if (closed && name.trim().toLowerCase() == 'mermaid') {
                return _MermaidBlock(source: code);
              }
              return CodeField(name: name, codes: code);
            },
          );
    _bodyKey = key;
    _body = body;
    return body;
  }

  /// ZH
  /// 只取角标渲染用到的字段；无来源与空来源等价，都表示不装 pattern。
  ///
  /// EN
  /// Use only fields needed for badge rendering; null and empty sources both mean no pattern.
  static String _sourcesKey(List<Source>? sources) {
    if (sources == null || sources.isEmpty) return '';
    return sources
        .map(
          (source) => '${source.index}\u0000${source.url}\u0000${source.title}',
        )
        .join('\u0001');
  }
}

Widget _imageAsLink(
  BuildContext context,
  String url,
  double? width,
  double? height,
) {
  final colors = AppMarkdownColors.of(context);
  final uri = webUri(url);
  return GestureDetector(
    onTap: uri == null ? null : () => openExternalLink(uri.toString(), ''),
    child: Text(
      uri?.toString() ?? url,
      style: TextStyle(color: colors.brandText),
    ),
  );
}

/// ZH
/// 任务列表去掉列表符号：`[x]` 行成为无圆点的 checkbox 块，
/// 与 chat-demo 的 `list-style: none` 一致。
/// shortcut: 只处理顶层的 `-`/`*`/`+` 任务行，嵌套任务列表保持原样。
///
/// EN
/// Task lists drop list markers: `[x]` lines become checkbox blocks without
/// bullets. This matches chat-demo's `list-style: none`.
/// Only handles top-level `-`/`*`/`+` task lines; nested task lists stay unchanged.
String _detachedTaskItems(String text) => text.replaceAllMapped(
  RegExp(r'^[-*+] (?=\[[ xX]\] )', multiLine: true),
  (match) => '',
);

/// ZH
/// 列表项间距 6（官方 app `li` 的 margin-top）。
///
/// `gpt_markdown` 没有项间距样式，项目靠 `WidgetSpan` 的基线放置：给内容加
/// 底部留白只把行盒向下撑 6，文字基线不动。
///
/// EN
/// List item gap 6 (margin-top of `li` in the official app).
///
/// The `gpt_markdown` package has no item-gap style; items are placed by
/// `WidgetSpan` baseline. Adding bottom padding only stretches the line box by 6,
/// leaving the text baseline unchanged.
const double _listItemGap = 6;

/// ZH
/// 有序列表项：序号 `labelTertiary` 常规字重、左缩进 4、与正文间距 7
/// （官方 app 实测）。
///
/// EN
/// Ordered list item: marker `labelTertiary` regular weight, left indent 4,
/// body gap 7 (measured on the official app).
Widget _orderedListItem(
  BuildContext context,
  String no,
  Widget child,
  GptMarkdownConfig config,
) {
  final colors = AppMarkdownColors.of(context);
  final marker = (config.style ?? const TextStyle()).copyWith(
    color: colors.labelTertiary,
    fontWeight: FontWeight.w400,
  );
  return MarkdownTextScaling.wrap(
    Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, end: 7),
          child: Text('$no.', style: marker),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(bottom: _listItemGap),
            child: child,
          ),
        ),
      ],
    ),
    enabled: config.blocksRenderDirectly,
  );
}

/// ZH
/// 无序列表项：项目符号沿用包内的悬挂缩进，仅补项间距与符号颜色。
///
/// EN
/// Unordered list item: keep the package's hanging indent; only add item gap and marker color.
Widget _unorderedListItem(
  BuildContext context,
  Widget child,
  GptMarkdownConfig config,
) {
  final colors = AppMarkdownColors.of(context);
  final fontSize =
      config.style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize;
  return UnorderedListView(
    scalesItsOwnText: config.blocksRenderDirectly,
    padding: 6,
    spacing: 10,
    bulletSize: 0.3 * (fontSize ?? 14),
    bulletColor: colors.labelTertiary,
    textDirection: config.textDirection,
    child: Padding(
      padding: const EdgeInsets.only(bottom: _listItemGap),
      child: child,
    ),
  );
}

/// ZH
/// 任务复选框：选中与未选中都自绘同一方框（`☑` 在 Android 会回退成彩色
/// emoji，`□` 字形又与自绘盒尺寸对不上），按字号与系统文字缩放推导尺寸。
/// 方框右侧留 5 与文案分开，垂直位置由方框上报的基线决定（见 [_TaskBox]）。
///
/// EN
/// Task checkbox: both states use the same drawn square (`☑` falls back to
/// color emoji on Android and the `□` glyph does not match a drawn box), sized
/// from the font size and text scaler. A 5px gap separates it from the label;
/// its vertical position comes from the baseline the box reports (see [_TaskBox]).
Widget _taskCheckbox(
  BuildContext context,
  bool checked,
  Widget content,
  TextStyle style,
) {
  final colors = AppMarkdownColors.of(context);
  final fontSize =
      style.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
  // 13 at the 16px body size, so the box keeps the previous visual weight.
  final boxSize = MediaQuery.textScalerOf(context).scale(fontSize) * 13 / 16;
  return Padding(
    padding: const EdgeInsets.only(bottom: _listItemGap),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 5),
          child: _TaskBox(
            checked: checked,
            size: boxSize,
            color: colors.labelPrimary,
          ),
        ),
        Flexible(child: content),
      ],
    ),
  );
}

/// ZH
/// 13×13 直角方框，选中时加勾；尺寸由外部按字号推导后等比缩放。
///
/// 自绘 RenderBox 把底边报告为基线，由 `Row` 的基线对齐钉在首行文字
/// 基线上。位置不依赖字体的 ascent/descent（Android 与 iOS 不同），
/// 否则方框在两端的垂直位置不一致。
///
/// EN
/// 13×13 square box with a check when selected; the caller scales it from the font size.
///
/// The drawn RenderBox reports its bottom edge as the baseline, so the Row's
/// baseline alignment pins it to the first line's text baseline. The position
/// then does not depend on font ascent/descent, which differs between Android
/// and iOS.
class _TaskBox extends LeafRenderObjectWidget {
  const _TaskBox({
    required this.checked,
    required this.size,
    required this.color,
  });

  final bool checked;
  final double size;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTaskBox(checked, size, color);

  @override
  void updateRenderObject(BuildContext context, _RenderTaskBox renderObject) {
    renderObject
      ..checked = checked
      ..side = size
      ..color = color;
  }
}

class _RenderTaskBox extends RenderBox {
  _RenderTaskBox(this._checked, this._side, this._color);

  bool _checked;
  double _side;
  Color _color;

  set checked(bool value) {
    if (value == _checked) return;
    _checked = value;
    markNeedsPaint();
  }

  set side(double value) {
    if (value == _side) return;
    _side = value;
    markNeedsLayout();
  }

  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size.square(_side));
  }

  /// ZH
  /// 底边即基线：方框像 `□` 字形一样坐在文字基线上。
  ///
  /// EN
  /// The bottom edge is the baseline, so the box sits on the text baseline like a `□` glyph.
  @override
  double computeDistanceToActualBaseline(TextBaseline baseline) => size.height;

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    // Draw in the original 13px space, then scale to the requested size.
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(size.width / 13);
    final stroke = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(
      const Rect.fromLTWH(0.55, 0.55, 11.9, 11.9),
      stroke..strokeWidth = 1.1,
    );
    if (_checked) {
      final check = Path()
        ..moveTo(2.8, 6.9)
        ..lineTo(5.4, 9.4)
        ..lineTo(10.4, 3.6);
      canvas.drawPath(check, stroke..strokeWidth = 1.5);
    }
    canvas.restore();
  }
}

/// ZH
/// 标题间距：`h1`-`h3` 上方 32，`h4`-`h6` 只保留块间距 16。
///
/// EN
/// Heading spacing: 32 above `h1`-`h3`; `h4`-`h6` keep only the 16 block gap.
Widget _headingBuilder(
  BuildContext context,
  int level,
  Widget content,
  HeadingStyle style,
) => Padding(
  padding: EdgeInsets.only(top: level <= 3 ? 16 : 0),
  child: content,
);

/// ZH
/// 表格：只有行分隔线、无表头底色；首列与末列贴边（chat-demo `markdown.css`）。
///
/// 列宽按可视宽度均分（每列至少 100），固定后跳过固有尺寸测量；单元格内容
/// 已是纯文本，直接显示，不再每格嵌套 `GptMarkdown`。
///
/// EN
/// Table: row dividers only, no header fill; first and last columns flush (chat-demo `markdown.css`).
///
/// Columns share the visible width evenly (min 100 each) and stay fixed to skip
/// measurement. Cell content is plain text shown directly, with no nested
/// `GptMarkdown` per cell.
Widget _tableBuilder(
  BuildContext context,
  List<CustomTableRow> rows,
  TextStyle style,
  GptMarkdownConfig config,
) {
  final colors = AppMarkdownColors.of(context);
  final dense = (style.fontSize ?? 16) < 16;
  final cellSize = dense ? 14.0 : 15.0;
  final bodyStyle = style.copyWith(
    fontSize: cellSize,
    height: (cellSize + 10) / cellSize,
    color: colors.labelPrimary,
  );
  final headerStyle = bodyStyle.copyWith(fontWeight: FontWeight.w500);
  final border = BorderSide(color: colors.borderL2);
  final columns = rows.fold<int>(
    1,
    (count, row) => math.max(count, row.fields.length),
  );
  return LayoutBuilder(
    builder: (context, constraints) {
      final available = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      // ZH
      // chat-demo：单元格最少 100，超出换行，超过视口宽度后横向滚动。
      //
      // EN
      // Match chat-demo: cells at least 100, wrap when longer, scroll horizontally past the viewport width.
      final cellWidth = math.max(available / columns, 100.0);
      return HorizontalFadeScroll(
        child: Table(
          defaultColumnWidth: FixedColumnWidth(cellWidth),
          border: TableBorder(horizontalInside: border, bottom: border),
          children: [
            for (final row in rows)
              TableRow(
                children: [
                  for (var index = 0; index < row.fields.length; index++)
                    Padding(
                      padding: EdgeInsets.only(
                        left: index == 0 ? 0 : 16,
                        right: index == row.fields.length - 1 ? 0 : 16,
                        top: 10,
                        bottom: 10,
                      ),
                      child: Text(
                        row.fields[index].data,
                        style: row.isHeader ? headerStyle : bodyStyle,
                        textAlign: row.fields[index].alignment,
                      ),
                    ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

/// ZH
/// 无协议地址补 `https://`（对齐 chat-demo）；只放行 http(s)。
///
/// EN
/// Prepend `https://` to schemeless URLs (matching chat-demo); allow only http(s).
Uri? webUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('mailto:')) return null;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
  final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// ZH
/// 只打开 http(s)，避免模型输出触发任意 URI scheme。
///
/// EN
/// Open only http(s) so model output cannot trigger arbitrary URI schemes.
Future<void> openExternalLink(String url, String title) async {
  final uri = webUri(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // ZH
    // 链接打不开时保持内容可读，不中断渲染。
    //
    // EN
    // Keep content readable when a link fails to open; do not interrupt rendering.
  }
}

/// ZH
/// `[citation:N]` 行内模式：找到来源时渲染数字角标，找不到时整个移除。
///
/// EN
/// Inline `[citation:N]` renders a badge when the source matches, or removes it otherwise.
InlinePattern _citationPattern(List<Source> sources) => InlinePattern(
  pattern: RegExp(r'\[citation:(\d+)\]'),
  builder: (context, match, style) {
    final index = int.tryParse(match.group(1) ?? '');
    Source? matchSource;
    for (final candidate in sources) {
      if (candidate.index == index) {
        matchSource = candidate;
        break;
      }
    }
    if (matchSource == null) return const TextSpan(text: '');
    final source = matchSource;
    final colors = AppMarkdownColors.of(context);
    final l10n = AppLocalizations.of(context);
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Semantics(
        button: true,
        label: l10n == null
            ? null
            : '${l10n.sourceNumber(source.index)}: ${source.title}',
        child: GestureDetector(
          key: Key('citation-${source.index}'),
          onTap: () => openExternalLink(source.url, source.title),
          // ZH
          // chat-demo 的角标上移 5px、右下角不圆角、9px 等宽数字。
          //
          // EN
          // Match chat-demo: badge shifts up 5px, square bottom-right corner, 9px monospace digits.
          child: Transform.translate(
            offset: const Offset(0, -5),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: colors.placeholderFill,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                  bottomLeft: Radius.circular(6),
                ),
                border: Border.all(color: colors.borderL1, width: 0.5),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        '${source.index}',
                        style: TextStyle(
                          fontFamily: kGptMarkdownMonoFontFamily,
                          package: kGptMarkdownFontPackage,
                          fontSize: 9,
                          height: 14 / 9,
                          fontWeight: FontWeight.w500,
                          color: colors.labelTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  },
);

class _MermaidBlock extends StatefulWidget {
  const _MermaidBlock({required this.source});

  final String source;

  @override
  State<_MermaidBlock> createState() => _MermaidBlockState();
}

class _MermaidBlockState extends State<_MermaidBlock> {
  bool _failed = false;

  /// ZH
  /// 当前 source 的解析结果，按 source 缓存。
  ///
  /// EN
  /// Parse result for the current source, cached by source.
  String? _checkedSource;
  bool _parses = true;

  @override
  void didUpdateWidget(_MermaidBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.source != oldWidget.source) {
      _failed = false;
      _checkedSource = null;
    }
  }

  /// ZH
  /// 在 build 中同步试解析一次：失败时当帧就换成代码块。
  ///
  /// 若等 errorBuilder 回调再换，块会先按图表容器撑高、下一帧才缩回，
  /// 滚动中视口上方的高度突变会让列表跳位。
  /// 校验与图表绘制各解析一次，只有首次构建该 source 时付这份成本。
  ///
  /// EN
  /// Try parsing synchronously in build: on failure switch to a code block in the same frame.
  ///
  /// Waiting for errorBuilder would first stretch the block to the chart container,
  /// then shrink it next frame; a height jump above the viewport while scrolling
  /// makes the list jump. Validation and chart drawing parse once each, paid only on
  /// the first build of a source.
  bool _sourceParses() {
    if (_checkedSource == widget.source) return _parses;
    _checkedSource = widget.source;
    try {
      mermaid_core.Mermaid(measurer: const FlutterTextMeasurer())
          .render(widget.source);
      _parses = true;
    } catch (_) {
      _parses = false;
    }
    return _parses;
  }

  /// ZH
  /// 兜底：校验通过但绘制仍出错时，下一帧换成代码块。
  ///
  /// EN
  /// Fallback: if drawing still fails after validation passes, switch to a code block next frame.
  void _markFailed() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // ZH
    // 无可用图时按普通代码块展示源码，不用图表容器里的纯文本降级。
    //
    // EN
    // Without a diagram, show source as a normal code block, not the chart container's text fallback.
    if (_failed || !_sourceParses()) {
      return CodeField(name: 'mermaid', codes: widget.source);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16),
      // ZH
      // 关闭缩放/平移控件并吞掉手势：图表固定按适配比例展示，
      // 手势交还给外层消息列表滚动。
      //
      // EN
      // Disable zoom/pan controls and swallow gestures: the diagram is shown scaled
      // to fit; gestures are returned to the outer message list scroll.
      child: IgnorePointer(
        child: SizedBox(
          height: 320,
          child: MermaidView(
            source: widget.source,
            showControls: false,
            theme: dark
                ? mermaid_core.MermaidTheme.darkTheme
                : mermaid_core.MermaidTheme.defaultTheme,
            keepLastGoodSceneOnError: true,
            errorBuilder: (context, error) {
              _markFailed();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }
}
