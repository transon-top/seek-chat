/// 票 06「输入区视觉对图原型」入口。
///
/// 运行：`flutter run -t prototype/composer_redesign/main.dart -d <设备>`
///
/// 一次性粗原型：全部为假数据与假状态，没有输入、上传、录音或网络。目的只是
/// 让用户逐项确认视觉，生产实现按票 07 汇总的规格另做。
///
/// 截图模式：`--dart-define=PROTOTYPE_SHOTS=true`，自动把 10 个状态 × 深浅
/// 两套写入应用文档目录的 `composer_redesign_shots/`，文件名带设备与状态。
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:material_ui/material_ui.dart';
import 'package:seek_chat/app/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'stage.dart';

const _initialScenarioName = String.fromEnvironment(
  'PROTOTYPE_SCENARIO',
  defaultValue: 'empty',
);
const _initialDark = bool.fromEnvironment('PROTOTYPE_DARK');
const _shotMode = bool.fromEnvironment('PROTOTYPE_SHOTS');

void main() => runApp(const _PrototypeApp());

class _PrototypeApp extends StatefulWidget {
  const _PrototypeApp();

  @override
  State<_PrototypeApp> createState() => _PrototypeAppState();
}

class _PrototypeAppState extends State<_PrototypeApp> {
  final _shotKey = GlobalKey();
  late Scenario _scenario = Scenario.values.firstWhere(
    (scenario) => scenario.name == _initialScenarioName,
    orElse: () => Scenario.empty,
  );
  late bool _dark = _initialDark;
  bool _shooting = _shotMode;

  @override
  void initState() {
    super.initState();
    if (_shotMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runTour());
    }
  }

  Future<void> _runTour() async {
    final documents = await getApplicationDocumentsDirectory();
    final dir = Directory('${documents.path}/composer_redesign_shots');
    await dir.create(recursive: true);
    final device = Platform.isIOS ? 'iphone' : 'android';
    for (final dark in [false, true]) {
      for (final scenario in Scenario.values) {
        setState(() {
          _dark = dark;
          _scenario = scenario;
        });
        await Future<void>.delayed(const Duration(milliseconds: 450));
        await WidgetsBinding.instance.endOfFrame;
        final boundary =
            _shotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) continue;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (data == null) continue;
        final file = File(
          '${dir.path}/$device-${scenario.name}-${dark ? 'dark' : 'light'}.png',
        );
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      }
    }
    if (!mounted) return;
    setState(() => _shooting = false);
  }

  void _cycle(int delta) {
    final values = Scenario.values;
    final index = (values.indexOf(_scenario) + delta) % values.length;
    setState(() => _scenario = values[index]);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _shotKey,
      child: ShadApp(
        title: '输入区改版原型',
        debugShowCheckedModeBanner: false,
        theme: buildShadTheme(brightness: Brightness.light, chinese: true),
        darkTheme: buildShadTheme(brightness: Brightness.dark, chinese: true),
        themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
        home: Stack(
          children: [
            PrototypeStage(scenario: _scenario),
            if (!_shooting)
              Positioned(
                top: 6,
                left: 0,
                right: 0,
                child: Center(
                  child: _ControlBar(
                    scenario: _scenario,
                    dark: _dark,
                    onPrev: () => _cycle(-1),
                    onNext: () => _cycle(1),
                    onToggleTheme: () => setState(() => _dark = !_dark),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 原型自身的悬浮控制条，不属于被评估的视觉；截图模式不渲染。
class _ControlBar extends StatelessWidget {
  const _ControlBar({
    required this.scenario,
    required this.dark,
    required this.onPrev,
    required this.onNext,
    required this.onToggleTheme,
  });

  final Scenario scenario;
  final bool dark;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xE6101012),
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BarIcon(icon: LucideIcons.chevronLeft, onTap: onPrev),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '${scenario.label} · ${dark ? '深色' : '浅色'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          _BarIcon(icon: LucideIcons.chevronRight, onTap: onNext),
          Container(
            width: 1,
            height: 16,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: const Color(0x33FFFFFF),
          ),
          _BarIcon(
            icon: dark ? LucideIcons.sun : LucideIcons.moon,
            onTap: onToggleTheme,
          ),
        ],
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 28,
        child: Icon(icon, size: 15, color: const Color(0xFFE5E7EB)),
      ),
    );
  }
}
