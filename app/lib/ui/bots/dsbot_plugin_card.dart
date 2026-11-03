import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/dsbot_plugin_update.dart';
import '../../state/plugins_state.dart';
import '../common/list_page_row.dart';
import '../plugins/plugin_actions.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';

/// The DS Bot plugin itself: which copy this host has, what the fork publishes,
/// and a way to install it.
///
/// The Bot pages need the mobile API this fork's plugin carries; the copy in the
/// plugin market is the official one, which does not have it, and the market's
/// update button therefore never offers this fork's builds. This row is the
/// update path: it asks the fork once a day on its own, again whenever the
/// person taps 检查更新, and installs what it finds over the installed copy.
class DsBotPluginCard extends ConsumerWidget {
  const DsBotPluginCard({super.key});

  static PluginBundle? _installed(List<PluginBundle>? bundles) {
    for (final bundle in bundles ?? const <PluginBundle>[]) {
      if (bundle.name == dsBotPackage) return bundle;
    }
    return null;
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.pluginsUpdateNamed('DS Bot')),
        content: Text(l10n.pluginsUpdateCurrentWarning(dsBotSpec)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialog).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.of(dialog).pop(true), child: Text(l10n.commonConfirm)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final job = await runPluginInstall(
      context,
      const PluginInstallRequest(
        name: dsBotPackage,
        spec: dsBotSpec,
        title: 'DS Bot',
        replaceInstalled: true,
      ),
    );
    if (job.phase == PluginInstallPhase.succeeded) {
      ref.read(dsBotProvider.notifier).retry();
      unawaited(ref.read(dsBotPluginUpdateProvider.notifier).check());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    final installed = _installed(ref.watch(installedPluginsProvider).value)?.version;
    final update = ref.watch(dsBotPluginUpdateProvider);
    final checking = update.isLoading;
    final known = update.value;
    final newer = known?.isNewerThan(installed) ?? false;

    final String? subtitle;
    if (installed == null) {
      subtitle = null;
    } else if (checking) {
      subtitle = '${l10n.pluginsInstalledVersion} $installed · ${l10n.updateCheck}…';
    } else if (newer) {
      subtitle = '${l10n.pluginsInstalledVersion} $installed · ${l10n.marketUpdateAvailable} ${known?.latest ?? ''}';
    } else if (known?.failed == true) {
      subtitle = '${l10n.pluginsInstalledVersion} $installed · ${l10n.updateCheckUnavailable}';
    } else if (known?.latest != null) {
      subtitle = '${l10n.pluginsInstalledVersion} $installed · ${l10n.updateTileUpToDate}';
    } else {
      subtitle = '${l10n.pluginsInstalledVersion} $installed';
    }

    return ListPageCard(
      title: 'DS Bot',
      children: [
        ListPageRow(
          key: const ValueKey('dsbot-plugin'),
          icon: AppIcons.plugin,
          title: l10n.pluginsTitle,
          subtitle: subtitle,
          subtitleColor: newer ? dsh.info : null,
          chevron: false,
          trailing: checking
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : TextButton(
                  key: const ValueKey('dsbot-plugin-check'),
                  onPressed: () => unawaited(
                    newer ? _install(context, ref) : ref.read(dsBotPluginUpdateProvider.notifier).check(),
                  ),
                  child: Text(newer ? l10n.commonUpdate : l10n.updateCheck),
                ),
          onTap: newer ? () => unawaited(_install(context, ref)) : null,
        ),
      ],
    );
  }
}
