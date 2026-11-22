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

/// 渲染回复中的 Markdown 文本。
///
/// 数学默认只认 `\(...\)` / `\[...\]`；单 `$` 会误伤价格文本（票 02）。
/// `mermaid` 围栏交给 `mermaid_flutter`，其余围栏走代码高亮与复制。
///
/// 流式期间按上次渲染耗时的两倍节流，把连续 token 合并成一次更新；
/// 区间限制在 50ms 到 2s（票 08）。
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

  /// 回复仍在流式生成时为 true；流结束后立即显示全文。
  final bool streaming;

  /// 传入时把 `[citation:N]` 渲染为可点击的来源角标；不传则保留原文。
  final List<Source>? sources;

  /// 思考与过程性正文使用小号文本。
  final bool dense;

  /// 思考内容只保留链接文字，不渲染成可点击链接。
  final bool disableLinks;

  /// 正文样式；为空时按 [dense] 取 Material 的 bodySmall / bodyMedium。
  final TextStyle? textStyle;

  /// 单块超过此长度时不再解析 Markdown，按纯文本展示（票 08 的降级上限）。
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

  // 正文、来源与样式都不变时复用同一个 widget 实例：新实例会让
  // GptMarkdown 整棵子树重建，复用则被 Flutter 的 identical 短路跳过。
  (String, String, bool, TextStyle?, bool, bool)? _bodyKey;
  Widget? _body;

  // 引用角标模式按来源内容缓存；来源内容变化时重建。
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
    // 新回复、切换版本或流结束：不做节流等待，直接显示最新全文。
    if (!widget.streaming || !widget.text.startsWith(_shown)) {
      _showLatest();
      return;
    }
    if (_windowTimer?.isActive ?? false) return; // 窗口内的输出合并到窗口结束
    _showLatest();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    super.dispose();
  }

  /// 立即显示最新文本；节流窗口在该帧结束后才开始计时（票 08）。
  void _showLatest({bool rebuild = false}) {
    _windowTimer?.cancel();
    _shown = widget.text;
    _renderStartedAt = DateTime.now();
    if (rebuild && mounted) setState(() {});
    SchedulerBinding.instance.addPostFrameCallback((_) => _afterRender());
  }

  /// 记录本帧耗时并开启下一个更新窗口；窗口结束时有积压才再渲染。
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
    // 识别器必须放在 SelectionArea 内层：Android 上文本选择会抢横向拖拽，
    // 内层先注册才能赢；表格等内层横向滚动仍在更深层，优先于抽屉。
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
            // 流式期间逐字浮现并淡入；结束后回到静态文档，避免残留 ticker。
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
            // 与 chat-demo 一致：图片不加载，只显示可点击的地址（票 08）。
            imageBuilder: _imageAsLink,
            // chat-demo 的 h1-h3 上方留 32，h4-h6 保持段间距。
            headingBuilder: widget.dense ? null : _headingBuilder,
            // chat-demo 的表格只保留行分隔线，表头无底色。
            tableBuilder: _tableBuilder,
            // chat-demo 不识别 GitHub Alert，按普通引用块渲染。
            alertBuilder: (context, details) => details.asBlockQuote(),
            // chat-demo 的任务项画成 `☑`/`□` 文本，不用 Material 复选框。
            checkboxBuilder: (context, checked, content, checkboxStyle) =>
                _taskCheckbox(
                  context,
                  checked,
                  content,
                  style ?? DefaultTextStyle.of(context).style,
                ),
            orderedListBuilder: _orderedListItem,
            unOrderedListBuilder: _unorderedListItem,
            // 思考内容比正文更紧凑。
            styleSheet: widget.dense
                ? const GptMarkdownStyleSheet(blockSpacing: 12)
                : null,
            codeBuilder: (context, name, code, closed) {
              // mermaid 围栏闭合后才渲染图表；流式半成品按普通代码展示。
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

  /// 只取角标渲染用到的字段；无来源与空来源等价，都表示不装 pattern。
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

/// 任务列表去掉列表符号：`[x]` 行成为无圆点的 checkbox 块，
/// 与 chat-demo 的 `list-style: none` 一致。
/// shortcut: 只处理顶层的 `-`/`*`/`+` 任务行，嵌套任务列表保持原样。
String _detachedTaskItems(String text) => text.replaceAllMapped(
  RegExp(r'^[-*+] (?=\[[ xX]\] )', multiLine: true),
  (match) => '',
);

/// 列表项间距 6（官方 app `li` 的 margin-top）。
///
/// `gpt_markdown` 没有项间距样式，项目靠 `WidgetSpan` 的基线放置：给内容加
/// 底部留白只把行盒向下撑 6，文字基线不动。
const double _listItemGap = 6;

/// 有序列表项：序号 `labelTertiary` 常规字重、左缩进 4、与正文间距 7
/// （官方 app 实测）。
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

/// 无序列表项：项目符号沿用包内的悬挂缩进，仅补项间距与符号颜色。
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

/// 任务复选框：官方 app 用的是 `☑`/`□` 字形，与正文同色、贴着文案。
Widget _taskCheckbox(
  BuildContext context,
  bool checked,
  Widget content,
  TextStyle style,
) {
  final colors = AppMarkdownColors.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: _listItemGap),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      textBaseline: TextBaseline.alphabetic,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      children: [
        // `□` 用字形；`☑` 在 Android 会回退成彩色 emoji（VS15 也拦不住），
        // 所以选中态自绘，保持与 `□` 同形的单色方框。
        checked
            ? Text.rich(
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: _CheckedBox(color: colors.labelPrimary),
                ),
              )
            : Text('□', style: style.copyWith(color: colors.labelPrimary)),
        Flexible(child: content),
      ],
    ),
  );
}

/// 已勾选任务项：13×13 直角方框 + 勾，笔触点与 `□` 字形相当。
class _CheckedBox extends StatelessWidget {
  const _CheckedBox({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(13, 13), painter: _CheckedBoxPainter(color));
}

class _CheckedBoxPainter extends CustomPainter {
  const _CheckedBoxPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRect(
      const Rect.fromLTWH(0.55, 0.55, 11.9, 11.9),
      stroke..strokeWidth = 1.1,
    );
    final check = Path()
      ..moveTo(2.8, 6.9)
      ..lineTo(5.4, 9.4)
      ..lineTo(10.4, 3.6);
    canvas.drawPath(check, stroke..strokeWidth = 1.5);
  }

  @override
  bool shouldRepaint(_CheckedBoxPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// 标题间距：`h1`-`h3` 上方 32，`h4`-`h6` 只保留块间距 16。
Widget _headingBuilder(
  BuildContext context,
  int level,
  Widget content,
  HeadingStyle style,
) => Padding(
  padding: EdgeInsets.only(top: level <= 3 ? 16 : 0),
  child: content,
);

/// 表格：只有行分隔线、无表头底色；首列与末列贴边（chat-demo `markdown.css`）。
///
/// 列宽按可视宽度均分（每列至少 100），固定后跳过固有尺寸测量；单元格内容
/// 已是纯文本，直接显示，不再每格嵌套 `GptMarkdown`。
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
      // chat-demo：单元格最少 100，超出换行，超过视口宽度后横向滚动。
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

/// 无协议地址补 `https://`（对齐 chat-demo）；只放行 http(s)。
Uri? webUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed.startsWith('mailto:')) return null;
  final hasScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed);
  final uri = Uri.tryParse(hasScheme ? trimmed : 'https://$trimmed');
  if (uri == null || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// 只打开 http(s)，避免模型输出触发任意 URI scheme。
Future<void> openExternalLink(String url, String title) async {
  final uri = webUri(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // 链接打不开时保持内容可读，不中断渲染。
  }
}

/// `[citation:N]` 行内模式：找到来源时渲染数字角标，找不到时整个移除。
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
          // chat-demo 的角标上移 5px、右下角不圆角、9px 等宽数字。
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

  /// 当前 source 的解析结果，按 source 缓存。
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

  /// 在 build 中同步试解析一次：失败时当帧就换成代码块。
  ///
  /// 若等 errorBuilder 回调再换，块会先按图表容器撑高、下一帧才缩回，
  /// 滚动中视口上方的高度突变会让列表跳位。
  /// 校验与图表绘制各解析一次，只有首次构建该 source 时付这份成本。
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

  /// 兜底：校验通过但绘制仍出错时，下一帧换成代码块。
  void _markFailed() {
    if (_failed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 无可用图时按普通代码块展示源码，不用图表容器里的纯文本降级。
    if (_failed || !_sourceParses()) {
      return CodeField(name: 'mermaid', codes: widget.source);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(16),
      // 关闭缩放/平移控件并吞掉手势：图表固定按适配比例展示，
      // 手势交还给外层消息列表滚动。
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
