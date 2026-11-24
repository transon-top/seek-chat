import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../shared/error_text.dart';
import '../../shared/models/types.dart';
import '../../shared/toast.dart';
import '../../shared/widgets/app_dialogs.dart';
import 'history_files.dart';
import 'history_service.dart';
import 'history_zip.dart';

/// ZH
/// 设置页的「数据管理」：导入会覆盖全部本地对话与附件（`history.md` §8）。
///
/// EN
/// Settings "Data Management": import replaces all local chats and attachments (`history.md` §8).
class HistorySection extends ConsumerStatefulWidget {
  const HistorySection({
    super.key,
    required this.stopGeneration,
    this.onImported,
  });

  /// ZH
  /// 导入校验通过后、写库之前停止全部活动会话的生成。
  ///
  /// EN
  /// Stop generation in all active sessions after validation passes and before writing.
  final void Function() stopGeneration;

  /// ZH
  /// 导入成功、数据库已替换后调用；宿主据此清空旧页面状态。
  ///
  /// EN
  /// Called after a successful import and DB swap; the host clears old page state.
  final VoidCallback? onImported;

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

    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.historyImportConfirmTitle,
      description: l10n.historyImportConfirmDescription,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.historyImportConfirm,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    _showProgress(l10n.historyImporting);
    try {
      final count = await ref
          .read(historyServiceProvider)
          .importArchive(bytes, stopGeneration: widget.stopGeneration);
      widget.onImported?.call();
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

  /// ZH
  /// 错误与拒答回复在导出时写入导出语言的模板文案（`history.md` §3.1）。
  ///
  /// EN
  /// Error and refusal replies get template text in the export language (`history.md` §3.1).
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
    unawaited(showAppProgressDialog(context, message: text));
  }

  void _closeProgress() {
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showMessage(String message, {bool destructive = false}) {
    showAppToast(context, message, destructive: destructive);
  }

  Future<void> _deleteAll() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.historyDeleteConfirmTitle,
      description: l10n.historyDeleteConfirmDescription,
      cancelLabel: l10n.cancel,
      confirmLabel: l10n.delete,
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(historyServiceProvider)
          .deleteAll(stopGeneration: widget.stopGeneration);
      if (!mounted) return;
      _showMessage(l10n.historyDeleted);
    } on Object {
      if (!mounted) return;
      _showMessage(l10n.historyDeleteFailed, destructive: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = ShadTheme.of(context).colorScheme;
    final divider = Divider(height: 1, thickness: 1, color: colors.border);
    Widget pillButton({
      required String label,
      required VoidCallback? onPressed,
      required bool destructive,
    }) => ShadTheme(
      data: ShadTheme.of(context).copyWith(
        radius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: ShadButton.outline(
        onPressed: onPressed,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        foregroundColor: destructive ? colors.destructive : colors.foreground,
        textStyle: const TextStyle(fontSize: 14, height: 20 / 14),
        decoration: ShadDecoration(
          border: ShadBorder.fromBorderSide(
            ShadBorderSide(
              width: 1,
              color: destructive ? colors.destructive : colors.border,
            ),
            radius: const BorderRadius.all(Radius.circular(999)),
          ),
        ),
        child: Text(label),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistoryRow(
          title: l10n.historyImport,
          description: l10n.historyImportDescription,
          trailing: pillButton(
            label: l10n.historyImportAction,
            onPressed: _busy ? null : _import,
            destructive: false,
          ),
        ),
        divider,
        _HistoryRow(
          title: l10n.historyExport,
          description: l10n.historyExportDescription,
          trailing: pillButton(
            label: l10n.historyExportAction,
            onPressed: _busy ? null : _export,
            destructive: false,
          ),
        ),
        divider,
        _HistoryRow(
          title: l10n.historyDelete,
          trailing: pillButton(
            label: l10n.delete,
            onPressed: _busy ? null : _deleteAll,
            destructive: true,
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.trailing,
    this.description,
  });

  final String title;
  final String? description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = ShadTheme.of(context).colorScheme;
    final description = this.description;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    height: 20 / 15,
                    color: colors.foreground,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: colors.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}
