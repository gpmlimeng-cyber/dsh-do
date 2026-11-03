import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/plugins_state.dart';
import '../common/list_page_row.dart';
import '../plugins/plugin_actions.dart';
import '../theme/app_icons.dart';

/// The DS Bot plugin itself: the copy this host has, and a way to reinstall it
/// from the fork the app talks to.
///
/// The Bot pages need the mobile API this fork's plugin carries; the copy in the
/// plugin market is the official one, which does not have it, and the market's
/// update button therefore never offers this fork's builds. This row is that
/// update path: it installs the fork's latest over the installed copy.
class DsBotPluginCard extends ConsumerWidget {
  const DsBotPluginCard({super.key});

  static PluginBundle? _installed(List<PluginBundle>? bundles) {
    for (final bundle in bundles ?? const <PluginBundle>[]) {
      if (bundle.name == dsBotPackage) return bundle;
    }
    return null;
  }

  Future<void> _reinstall(BuildContext context, WidgetRef ref) async {
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
      unawaited(ref.read(dsBotProvider.notifier).retry());
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bundle = _installed(ref.watch(installedPluginsProvider).value);
    final version = bundle?.version;
    return ListPageCard(
      title: 'DS Bot',
      children: [
        ListPageRow(
          key: const ValueKey('dsbot-plugin'),
          icon: AppIcons.plugin,
          title: l10n.pluginsTitle,
          subtitle: version == null || version.isEmpty ? null : '${l10n.pluginsInstalledVersion} $version',
          chevron: false,
          onTap: () => unawaited(_reinstall(context, ref)),
        ),
      ],
    );
  }
}
