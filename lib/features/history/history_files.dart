import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 系统文件选择与保存；测试用 override 替换。
final historyFilesProvider = Provider<HistoryFiles>(
  (ref) => const SystemHistoryFiles(),
);

abstract interface class HistoryFiles {
  /// 选择一个 ZIP；取消时返回 null。
  Future<Uint8List?> pickZip();

  /// 交给系统文档提供器保存；返回是否保存成功（用户取消为 false）。
  Future<bool> saveZip({
    required String fileName,
    required Uint8List bytes,
  });
}

final class SystemHistoryFiles implements HistoryFiles {
  const SystemHistoryFiles();

  @override
  Future<Uint8List?> pickZip() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    if (files.isEmpty) return null;
    return files.first.readAsBytes();
  }

  @override
  Future<bool> saveZip({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/zip',
    );
    return uri != null;
  }
}
