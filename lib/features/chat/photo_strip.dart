import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import 'photo_import.dart';

/// 构建开关只关闭 Android 横条；iOS 不受影响（`attachments.md` §9.1）。
const bool _photoStripBuildEnabled = bool.fromEnvironment(
  'OPEN_CHAT_PHOTO_STRIP',
  defaultValue: true,
);

bool photoStripEnabledFor(TargetPlatform platform) =>
    platform != TargetPlatform.android || _photoStripBuildEnabled;

enum PhotoAccessStatus { authorized, limited, denied, notDetermined }

/// 照片权限、最近图片与系统「管理」入口；测试注入 fake。
abstract interface class PhotoLibrary {
  Future<PhotoAccessStatus> access({required bool request});

  Future<List<PhotoAsset>> recentImages({int limit = 30});

  Future<void> presentLimited();

  Future<void> openSettings();
}

final photoLibraryProvider = Provider<PhotoLibrary>(
  (ref) => PhotoManagerLibrary(),
);

class PhotoManagerLibrary implements PhotoLibrary {
  static const _requestOption = PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.image,
      mediaLocation: false,
    ),
  );

  @override
  Future<PhotoAccessStatus> access({required bool request}) async {
    final state = request
        ? await PhotoManager.requestPermissionExtend(
            requestOption: _requestOption,
          )
        : await PhotoManager.getPermissionState(requestOption: _requestOption);
    return switch (state) {
      PermissionState.authorized => PhotoAccessStatus.authorized,
      PermissionState.limited => PhotoAccessStatus.limited,
      PermissionState.notDetermined => PhotoAccessStatus.notDetermined,
      PermissionState.denied ||
      PermissionState.restricted => PhotoAccessStatus.denied,
    };
  }

  /// 每次展开只取第一页 30 张，显式按 `createDate` 倒序（`attachments.md` §9.1）。
  @override
  Future<List<PhotoAsset>> recentImages({int limit = 30}) async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      onlyAll: true,
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    );
    if (paths.isEmpty) return const [];
    final entities = await paths.first.getAssetListPaged(page: 0, size: limit);
    return [for (final entity in entities) _ManagerPhotoAsset(entity)];
  }

  @override
  Future<void> presentLimited() =>
      PhotoManager.presentLimited(type: RequestType.image);

  @override
  Future<void> openSettings() => openAppSettings();
}

class _ManagerPhotoAsset implements PhotoAsset {
  const _ManagerPhotoAsset(this._entity);

  final AssetEntity _entity;

  @override
  String get id => _entity.id;

  @override
  Future<Uint8List?> thumbnail() =>
      _entity.thumbnailDataWithSize(const ThumbnailSize.square(200));

  @override
  Future<File?> originalFile() => _entity.file;

  /// iOS 用 `ThumbnailOption.ios` 的 fit 模式，默认的 AspectFill 会裁成方图。
  @override
  Future<Uint8List?> transcodedJpeg() {
    const size = ThumbnailSize.square(2560);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return _entity.thumbnailDataWithOption(
        ThumbnailOption.ios(size: size, quality: 90),
      );
    }
    return _entity.thumbnailDataWithSize(size, quality: 90);
  }
}

const double _tileSize = 80;
const double _stripHeight = 96;

enum _StripStatus { loading, ready, denied, empty, failed }

/// 面板顶部照片横条：最近 30 张、勾选与四种权限 / 数据降级（`attachments.md` §9）。
///
/// 每次插入树（面板展开）重新查询；展开期间不自动刷新，回到前台或「管理」
/// 返回时才重载。
class PhotoStrip extends StatefulWidget {
  const PhotoStrip({
    super.key,
    required this.library,
    required this.selectedAssetIds,
    required this.full,
    required this.onToggle,
    required this.onLimitReached,
    this.reloadOnResume = true,
  });

  final PhotoLibrary library;

  /// 选中态由草稿附件的 `sourceAssetId` 派生。
  final Set<String> selectedAssetIds;
  final bool full;
  final ValueChanged<PhotoAsset> onToggle;
  final VoidCallback onLimitReached;

  /// 相机 / 相册 / 文件选择器返回时页面保持展开且横条不刷新（ui.md §5.7）。
  final bool reloadOnResume;

  @override
  State<PhotoStrip> createState() => _PhotoStripState();
}

class _PhotoStripState extends State<PhotoStrip> with WidgetsBindingObserver {
  _StripStatus _status = _StripStatus.loading;
  List<PhotoAsset> _assets = const [];
  bool _limited = false;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从后台、系统设置或「管理」返回时重新检查并重载；系统选择器返回除外。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.reloadOnResume) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final loadId = ++_loadId;
    setState(() => _status = _StripStatus.loading);
    try {
      var access = await widget.library.access(request: false);
      if (access == PhotoAccessStatus.notDetermined) {
        access = await widget.library.access(request: true);
      }
      if (!mounted || loadId != _loadId) return;
      if (access == PhotoAccessStatus.denied) {
        setState(() {
          _status = _StripStatus.denied;
          _assets = const [];
        });
        return;
      }
      _limited = access == PhotoAccessStatus.limited;
      final assets = await widget.library.recentImages();
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _assets = assets;
        // 受限且可访问资产为 0 时只显示「管理」格，不显示空态。
        _status = assets.isEmpty && !_limited
            ? _StripStatus.empty
            : _StripStatus.ready;
      });
    } on Object {
      if (!mounted || loadId != _loadId) return;
      setState(() => _status = _StripStatus.failed);
    }
  }

  Future<void> _manage() async {
    try {
      await widget.library.presentLimited();
    } on Object {
      // 选择器不可用时按原资产重载。
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: _stripHeight,
      child: switch (_status) {
        _StripStatus.loading => _skeleton(context),
        _StripStatus.denied => _message(
          l10n.photoPermissionDenied,
          key: const Key('photo-strip-denied'),
          action: ShadButton.link(
            key: const Key('photo-strip-settings'),
            onPressed: () => unawaited(widget.library.openSettings()),
            child: Text(l10n.settingsOpenSystemSettings),
          ),
        ),
        _StripStatus.empty => _message(
          l10n.photoStripEmpty,
          key: const Key('photo-strip-empty'),
        ),
        _StripStatus.failed => _message(
          l10n.photoStripLoadFailed,
          key: const Key('photo-strip-error'),
          action: ShadButton.link(
            key: const Key('photo-strip-retry'),
            onPressed: () => unawaited(_load()),
            child: Text(l10n.retry),
          ),
        ),
        _StripStatus.ready => _assetsView(l10n),
      },
    );
  }

  Widget _skeleton(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    return ListView.separated(
      key: const Key('photo-strip-skeleton'),
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 6,
      separatorBuilder: (context, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) => Container(
        width: _tileSize,
        height: _tileSize,
        decoration: BoxDecoration(
          color: colors.muted,
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _assetsView(AppLocalizations l10n) {
    final manageTileOffset = _limited ? 1 : 0;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _assets.length + manageTileOffset,
      separatorBuilder: (context, index) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        if (_limited && index == 0) {
          return _ManageTile(label: l10n.photoLimitedManage, onTap: _manage);
        }
        final assetIndex = index - manageTileOffset;
        final asset = _assets[assetIndex];
        final selected = widget.selectedAssetIds.contains(asset.id);
        return _PhotoTile(
          asset: asset,
          index: assetIndex + 1,
          selected: selected,
          enabled: selected || !widget.full,
          onToggle: () => widget.onToggle(asset),
          onLimitReached: widget.onLimitReached,
        );
      },
    );
  }

  Widget _message(String text, {required Key key, Widget? action}) {
    final colors = ShadTheme.of(context).colorScheme;
    return Center(
      key: key,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: colors.mutedForeground),
              ),
            ),
            if (action != null) ...[const SizedBox(width: 4), action],
          ],
        ),
      ),
    );
  }
}

class _PhotoTile extends StatefulWidget {
  const _PhotoTile({
    required this.asset,
    required this.index,
    required this.selected,
    required this.enabled,
    required this.onToggle,
    required this.onLimitReached,
  });

  final PhotoAsset asset;

  /// 从 1 起的照片序号，用于无障碍文案。
  final int index;
  final bool selected;

  /// 草稿已满时未选中的照片格不可添加，但仍可取消已有选择。
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onLimitReached;

  @override
  State<_PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<_PhotoTile> {
  late final Future<Uint8List?> _image = widget.asset.thumbnail();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final label = widget.selected
        ? l10n.photoTileSelected(widget.index)
        : l10n.photoTileUnselected(widget.index);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: GestureDetector(
          key: Key('photo-tile-${widget.asset.id}'),
          onTap: widget.enabled ? widget.onToggle : widget.onLimitReached,
          child: SizedBox(
            width: _tileSize,
            height: _tileSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<Uint8List?>(
                    future: _image,
                    builder: (context, snapshot) => snapshot.data == null
                        ? ColoredBox(
                            color: colors.muted,
                            child: Icon(
                              LucideIcons.image,
                              size: 20,
                              color: colors.mutedForeground,
                            ),
                          )
                        : Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stackTrace) =>
                                ColoredBox(
                                  color: colors.muted,
                                  child: Icon(
                                    LucideIcons.image,
                                    size: 20,
                                    color: colors.mutedForeground,
                                  ),
                                ),
                          ),
                  ),
                  if (widget.selected) ...[
                    const ColoredBox(color: Colors.black26),
                    Center(
                      child: Container(
                        key: Key('photo-check-${widget.asset.id}'),
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.check,
                          size: 14,
                          color: colors.primaryForeground,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  const _ManageTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.photoLimitedManageSemantics,
      child: GestureDetector(
        key: const Key('photo-strip-manage'),
        onTap: onTap,
        child: Container(
          width: _tileSize,
          height: _tileSize,
          decoration: BoxDecoration(
            color: colors.muted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.image, size: 20, color: colors.mutedForeground),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: colors.foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
