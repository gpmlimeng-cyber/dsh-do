// 侧栏底部的一条更新行: appears only when there is something to do, and takes
// no space at all otherwise (no empty gap above 本机引擎/设置).
//
// One row for all three states — a new version, a download running, an APK
// ready to install — the way the settings tile words them. Tapping opens the
// update sheet; it never jumps to 设置.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/update_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'update_sheet.dart';
import 'update_tiles.dart' show UpdateBadge;

class DrawerUpdateRow extends ConsumerWidget {
  const DrawerUpdateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final update = ref.watch(appUpdateProvider);
    // A version the person skipped stays skipped: no row, no reminder.
    if (!update.hasUpdate || update.isSkipped) return const SizedBox.shrink();
    final colors = DshColors.of(context);
    final Widget trailing = switch (update.task) {
      UpdateTaskPhase.downloading => Text(
        update.progress == null
            ? l10n.updateTileDownloading
            : l10n.updateTileDownloadingPercent((update.progress! * 100).floor()),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
      ),
      UpdateTaskPhase.verifying => Text(
        l10n.updateTileVerifying,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
      ),
      UpdateTaskPhase.ready || UpdateTaskPhase.needsPermission => UpdateBadge(l10n.updateTileReady),
      UpdateTaskPhase.installing => Text(
        l10n.updateTileInstalling,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.textTertiary),
      ),
      _ => UpdateBadge(l10n.updateTileNewVersion(update.latest!.version.name)),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: const ValueKey('drawer-update-row'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => showUpdateSheet(context),
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 10),
                Icon(AppIcons.download, size: 18, color: colors.textTertiary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.updateCheck,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                trailing,
                const SizedBox(width: 4),
                Icon(AppIcons.forward, size: 16, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
