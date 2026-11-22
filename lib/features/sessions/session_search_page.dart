import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/logging.dart';
import '../../shared/models/types.dart';
import '../../shared/providers.dart';
import '../../shared/widgets/push_menu.dart';
import 'session_skeleton.dart';

/// 会话搜索页；嵌在抽屉层里，由抽屉驱动展开与收起。
class SessionSearchPage extends ConsumerStatefulWidget {
  const SessionSearchPage({
    super.key,
    required this.focusNode,
    required this.onBack,
    required this.onOpen,
  });

  final FocusNode focusNode;
  final VoidCallback onBack;
  final ValueChanged<String> onOpen;

  @override
  ConsumerState<SessionSearchPage> createState() => _SessionSearchPageState();
}

class _SessionSearchPageState extends ConsumerState<SessionSearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SessionSearchHit> _hits = const [];
  bool _loading = false;
  int _token = 0;
  String _query = '';

  AppSidebarColors get _colors =>
      Theme.of(context).brightness == Brightness.dark
      ? AppSidebarColors.dark
      : AppSidebarColors.light;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final token = ++_token;
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _loading = false;
        _hits = const [];
      });
      return;
    }
    setState(() {
      _query = query;
      _loading = true;
    });
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      List<SessionSearchHit> hits;
      try {
        hits = await ref.read(chatRepositoryProvider).searchSessions(query);
      } on Object catch (error) {
        debugLog('session search failed', error);
        hits = const [];
      }
      if (!mounted || token != _token) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    });
  }

  void _clear() {
    _controller.clear();
    _onChanged('');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final controller = PushMenuScope.maybeOf(context);
    if (controller == null) return _build(context, 1);
    return AnimatedBuilder(
      animation: controller.searchAnimation,
      builder: (context, _) => _build(context, controller.searchProgress),
    );
  }

  /// [t] 为搜索展开进度：0 时搜索框与侧栏胶囊重合，1 时占满全屏。
  Widget _build(BuildContext context, double t) {
    final l10n = AppLocalizations.of(context)!;
    final colors = _colors;
    final width = MediaQuery.sizeOf(context).width;
    final travel = PushMenuScope.maybeOf(context)?.travel ?? width * 0.8;
    final left = _lerp(14, 4, t);
    final fieldRight = _lerp(travel - 14, width - 16, t);
    final backWidth = _lerp(0, 44, t);
    final backOpacity = Curves.easeIn.transform(
      ((t - 0.35) / 0.65).clamp(0.0, 1.0),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: colors.fill.withValues(alpha: t),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(left, 10, width - fieldRight, 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: backWidth,
                      child: Opacity(
                        opacity: backOpacity,
                        child: Semantics(
                          button: true,
                          label: l10n.searchBack,
                          child: IconButton(
                            key: const Key('search-back'),
                            onPressed: widget.onBack,
                            icon: Icon(
                              LucideIcons.chevronLeft,
                              size: 20,
                              color: colors.labelPrimary,
                            ),
                            constraints: const BoxConstraints.tightFor(
                              width: 44,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      // 与侧栏搜索胶囊同高，展开时只变宽不跳高。
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          key: const Key('search-field'),
                          controller: _controller,
                          focusNode: widget.focusNode,
                          autofocus: true,
                          onChanged: _onChanged,
                          style: TextStyle(
                            fontSize: 16,
                            height: 22 / 16,
                            color: colors.labelPrimary,
                          ),
                          cursorColor: colors.brand,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: l10n.searchChatsPlaceholder,
                            hintStyle: TextStyle(
                              fontSize: 16,
                              height: 22 / 16,
                              color: colors.labelTertiary,
                            ),
                            filled: true,
                            fillColor: colors.inputFill,
                            // 与侧栏搜索胶囊同高（44）。
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 11.5,
                            ),
                            prefixIcon: Icon(
                              LucideIcons.search,
                              size: 16,
                              color: colors.labelTertiary,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 36,
                            ),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    key: const Key('search-clear'),
                                    onPressed: _clear,
                                    tooltip: l10n.clearSearch,
                                    icon: Icon(
                                      LucideIcons.x,
                                      size: 14,
                                      color: colors.labelTertiary,
                                    ),
                                    constraints: const BoxConstraints.tightFor(
                                      width: 36,
                                      height: 36,
                                    ),
                                    padding: EdgeInsets.zero,
                                  ),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 36,
                            ),
                            // 官方搜索框为无描边灰底胶囊。
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(999),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: _body(l10n, colors)),
            ],
          ),
        ),
      ),
    );
  }

  static double _lerp(double begin, double end, double t) =>
      begin + (end - begin) * t;

  Widget _body(AppLocalizations l10n, AppSidebarColors colors) {
    if (_query.isEmpty) return const SizedBox.shrink();
    if (_loading) {
      return const SingleChildScrollView(child: SearchListSkeleton());
    }
    if (_hits.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomPaint(
              size: const Size.square(40),
              painter: _DashedSearchPainter(colors.labelTertiary),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.searchNoResults,
              style: TextStyle(fontSize: 14, color: colors.labelTertiary),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      itemCount: _hits.length,
      itemBuilder: (context, index) {
        final hit = _hits[index];
        final session = hit.session;
        final title = session.title.isEmpty ? l10n.untitledChat : session.title;
        return InkWell(
          key: ValueKey('search-hit-${session.id}'),
          onTap: () => widget.onOpen(session.id),
          child: SizedBox(
            height: 78,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                    child: Icon(
                      LucideIcons.messageCircle,
                      size: 20,
                      color: colors.labelTertiary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 22 / 16,
                                  fontWeight: FontWeight.w500,
                                  color: colors.labelPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _timeLabel(context, session.updatedAt),
                              style: TextStyle(
                                fontSize: 14,
                                height: 22 / 14,
                                color: colors.labelTertiary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hit.snippet,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            height: 22 / 14,
                            color: colors.labelTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _timeLabel(BuildContext context, DateTime date) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final local = date.toLocal();
    final now = DateTime.now();
    final day = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return DateFormat.Hm(locale).format(local);
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.sessionGroupYesterday;
    }
    if (local.year == now.year) return DateFormat.MMMd(locale).format(local);
    return DateFormat.yMMMd(locale).format(local);
  }
}

/// 无结果态：虚线圆放大镜。
class _DashedSearchPainter extends CustomPainter {
  const _DashedSearchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width * 0.42, size.height * 0.42);
    final rect = Rect.fromCircle(center: center, radius: size.width * 0.3);
    const segments = 10;
    const gap = 0.22;
    for (var i = 0; i < segments; i++) {
      final start = i * math.pi * 2 / segments + gap / 2;
      canvas.drawArc(rect, start, math.pi * 2 / segments - gap, false, paint);
    }
    canvas.drawLine(
      Offset(size.width * 0.62, size.height * 0.62),
      Offset(size.width * 0.84, size.height * 0.84),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DashedSearchPainter oldDelegate) =>
      oldDelegate.color != color;
}
