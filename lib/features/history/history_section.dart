import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/models/types.dart';
import '../../shared/toast.dart';
import 'history_files.dart';
import 'history_service.dart';
import 'history_zip.dart';

/// 设置页的「数据管理」：导入会覆盖全部本地对话与附件（`history.md` §8）。
class HistorySection extends ConsumerStatefulWidget {
  const HistorySection({super.key, required this.stopGeneration});

  /// 导入校验通过后、写库之前停止全部活动会话的生成。
  final void Function() stopGeneration;

  @override
  ConsumerState<HistorySection> createState() => _HistorySectionState();
}

class _HistorySectionState extends ConsumerState<HistorySection> {
  bool _busy = false;

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context)!;
    final Uint8List? bytes;
    try {
      bytes = await ref.read(historyFilesProvider).pickZip();
    } on Object {
      if (mounted) _showMessage(l10n.historyImportFailed, destructive: true);
      return;
    }
    if (!mounted || bytes == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.historyImportConfirmTitle),
        content: Text(l10n.historyImportConfirmDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.historyImportConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    _showProgress(l10n.historyImporting);
    try {
      final count = await ref
          .read(historyServiceProvider)
          .importArchive(bytes, stopGeneration: widget.stopGeneration);
      if (!mounted) return;
      _closeProgress();
      _showMessage(
        count == 1 ? l10n.historyImportedOne : l10n.historyImported(count),
      );
    } on HistoryException catch (error) {
      if (!mounted) return;
      _closeProgress();
      _showMessage(_errorText(l10n, error.code), destructive: true);
    } on Object {
      if (!mounted) return;
      _closeProgress();
      _showMessage(l10n.historyImportFailed, destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    _showProgress(l10n.historyExporting);
    try {
      final exported = await ref
          .read(historyServiceProvider)
          .exportArchive(notice: (reply) => _notice(l10n, reply));
      final saved = await ref
          .read(historyFilesProvider)
          .saveZip(fileName: exported.fileName, bytes: exported.bytes);
      if (!mounted) return;
      _closeProgress();
      if (saved) _showMessage(l10n.historyExported);
    } on HistoryException catch (error) {
      if (!mounted) return;
      _closeProgress();
      _showMessage(
        error.code == HistoryError.tooLarge
            ? l10n.historyErrorExportTooLarge
            : _errorText(l10n, error.code),
        destructive: true,
      );
    } on Object {
      if (!mounted) return;
      _closeProgress();
      _showMessage(l10n.historyExportFailed, destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 错误与拒答回复在导出时写入导出语言的模板文案（`history.md` §3.1）。
  String? _notice(AppLocalizations l10n, AssistantMessage reply) {
    if (reply.stopReason == StopReason.refusal) return l10n.replyRefused;
    if (reply.status == ReplyStatus.error && reply.error != null) {
      return replyErrorText(l10n, reply.error!);
    }
    return null;
  }

  String _errorText(AppLocalizations l10n, HistoryError error) =>
      switch (error) {
        HistoryError.tooLarge => l10n.historyErrorTooLarge,
        HistoryError.unrecognized => l10n.historyErrorUnrecognized,
        HistoryError.newerVersion => l10n.historyErrorNewerVersion,
        HistoryError.invalidVersion => l10n.historyErrorInvalidVersion,
        HistoryError.invalidJson => l10n.historyErrorInvalidJson,
        HistoryError.incomplete => l10n.historyErrorIncomplete,
        HistoryError.invalidBranches => l10n.historyErrorInvalidBranches,
        HistoryError.invalidFiles => l10n.historyErrorInvalidFiles,
      };

  void _showProgress(String text) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(text)),
            ],
          ),
        ),
      ),
    );
  }

  void _closeProgress() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showMessage(String message, {bool destructive = false}) {
    showAppToast(context, message, destructive: destructive);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.settingsData, style: titleStyle),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.historyImport),
          subtitle: Text(l10n.historyImportDescription),
          trailing: OutlinedButton(
            onPressed: _busy ? null : _import,
            child: Text(l10n.historyImportAction),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.historyExport),
          subtitle: Text(l10n.historyExportDescription),
          trailing: OutlinedButton(
            onPressed: _busy ? null : _export,
            child: Text(l10n.historyExportAction),
          ),
        ),
      ],
    );
  }
}
