import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_provider.dart';

/// 字号档位：七档，第 4 档为「标准」（1.0）。
abstract final class FontScaleLevels {
  static const standard = 3;
  static const values = <double>[0.82, 0.88, 0.94, 1, 1.12, 1.24, 1.35];

  /// 与 [scale] 距离最近的档位，用于跟随系统时展示 thumb。
  static int nearest(double scale) {
    var best = 0;
    for (var i = 1; i < values.length; i++) {
      if ((values[i] - scale).abs() < (values[best] - scale).abs()) best = i;
    }
    return best;
  }
}

/// 字号设置：是否跟随系统，以及手动档位。
class FontScaleSettings {
  const FontScaleSettings({required this.followSystem, required this.level});

  static const defaults = FontScaleSettings(
    followSystem: true,
    level: FontScaleLevels.standard,
  );

  final bool followSystem;
  final int level;

  double get scale => FontScaleLevels.values[level];

  /// 跟随系统时夹到规格支持的 0.8–2.0；手动档位使用固定倍率。
  TextScaler textScaler(TextScaler system) => followSystem
      ? system.clamp(minScaleFactor: 0.8, maxScaleFactor: 2)
      : TextScaler.linear(scale);

  FontScaleSettings copyWith({bool? followSystem, int? level}) =>
      FontScaleSettings(
        followSystem: followSystem ?? this.followSystem,
        level: level ?? this.level,
      );
}

/// 字号偏好：默认跟随系统；手动档位在关闭跟随后保留。
class FontScaleStore {
  FontScaleStore(this._preferences);

  static const followKey = 'ui.fontScaleFollow';
  static const levelKey = 'ui.fontScaleLevel';

  final SharedPreferences _preferences;

  FontScaleSettings get settings {
    final stored = _preferences.getInt(levelKey);
    final level =
        stored != null && stored >= 0 && stored < FontScaleLevels.values.length
        ? stored
        : FontScaleLevels.standard;
    return FontScaleSettings(
      followSystem: _preferences.getBool(followKey) ?? true,
      level: level,
    );
  }

  Future<void> write(FontScaleSettings settings) async {
    await _preferences.setBool(followKey, settings.followSystem);
    await _preferences.setInt(levelKey, settings.level);
  }
}

final fontScaleStoreProvider = Provider<FontScaleStore>(
  (ref) => FontScaleStore(ref.watch(sharedPreferencesProvider)),
);

final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, FontScaleSettings>(
      FontScaleNotifier.new,
    );

class FontScaleNotifier extends Notifier<FontScaleSettings> {
  @override
  FontScaleSettings build() => ref.read(fontScaleStoreProvider).settings;

  Future<void> setFollowSystem(bool value) =>
      _persist(state.copyWith(followSystem: value));

  /// 手动选档即退出跟随系统。
  Future<void> selectLevel(int level) =>
      _persist(FontScaleSettings(followSystem: false, level: level));

  Future<void> _persist(FontScaleSettings next) async {
    state = next;
    await ref.read(fontScaleStoreProvider).write(next);
  }
}
