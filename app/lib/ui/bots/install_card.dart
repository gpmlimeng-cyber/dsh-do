// Explains the required mobile capability and offers the authenticated Web UI
// when the host has no usable mobile API. Missing plugins can also be installed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../../state/plugins_state.dart';
import '../common/empty_view.dart';
import '../plugins/plugin_actions.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../common/brief_notice.dart';
import '../web/dsh_web_launcher.dart';
import '../web/web_target.dart';

/// The command that adds DS Bot to a `dsh web` profile on a computer.
const dsBotInstallCommand = 'dsh plugin --profile web add ds-bot';

/// Uses the existing authenticated DSH Web launcher. Tests replace only this edge.
final dsBotWebOpenerProvider = Provider<void Function(BuildContext context, WidgetRef ref)>(
  (ref) =>
      (context, ref) => openDshWeb(context, ref, target: const DshWebTarget(sidebar: true)),
);

class DsBotInstallCard extends ConsumerStatefulWidget {
  const DsBotInstallCard({super.key, required this.status});

  final DsBotStatus status;

  @override
  ConsumerState<DsBotInstallCard> createState() => _DsBotInstallCardState();
}

class _DsBotInstallCardState extends ConsumerState<DsBotInstallCard> {
  /// 内置：安装包由运行时随包发放，进到这一页就自己装上，不用先去点一遍。
  bool _autoTried = false;

  bool get _update => widget.status.availability == DsBotAvailability.outdated;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoInstall());
  }

  /// 只在主机能自己装、且没有正在进行的安装时跑一次。
  Future<void> _autoInstall() async {
    if (_autoTried || !mounted) return;
    final host = ref.read(pluginHostProvider);
    final job = ref.read(pluginInstallsProvider.select((jobs) => jobs[dsBotPackage]));
    if (host?.canInstall != true || (job?.isActive ?? false)) return;
    _autoTried = true;
    await _install(context, ref);
  }

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final hub = ref.read(dsBotProvider.notifier);
    // The runtime carries the package; only when that copy is not there (an
    // older environment, a remote host) fall back to the repository.
    var job = await runPluginInstall(
      context,
      PluginInstallRequest(
        name: dsBotPackage,
        spec: dsBotBundledSpec,
        title: 'DS Bot',
        replaceInstalled: _update,
      ),
    );
    if (job.phase == PluginInstallPhase.failed) {
      if (!context.mounted) return;
      job = await runPluginInstall(
        context,
        PluginInstallRequest(name: dsBotPackage, spec: dsBotSpec, title: 'DS Bot', replaceInstalled: _update),
      );
    }
    if (job.phase == PluginInstallPhase.succeeded && !job.needsRestart) hub.retry();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = ref.watch(pluginHostProvider);
    final job = ref.watch(pluginInstallsProvider.select((jobs) => jobs[dsBotPackage]));
    final busy = job?.isActive ?? false;
    final canInstall = host?.canInstall ?? false;
    final title = _update ? l10n.botsMobileUnsupportedTitle : l10n.botsInstall;
    final message = _update ? l10n.botsMobileApiRequired : l10n.botsMobileApiMissing;
    return EmptyView(
      icon: AppIcons.bot,
      title: title,
      message: busy ? job!.phaseLabel : message,
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 24),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            key: const ValueKey('dsbot-open-web'),
            onPressed: () => ref.read(dsBotWebOpenerProvider)(context, ref),
            icon: const Icon(AppIcons.webApp, size: 18),
            label: Text(l10n.commonOpenInWeb),
          ),
          const SizedBox(height: 8),
          if (_update)
            TextButton(
              key: const ValueKey('dsbot-recheck-mobile'),
              onPressed: () => ref.read(dsBotProvider.notifier).retry(),
              child: Text(l10n.commonRetry),
            )
          else if (canInstall)
            FilledButton.tonal(
              onPressed: busy ? null : () => _install(context, ref),
              child: Text(busy ? l10n.botsInstalling : l10n.commonInstall),
            )
          else
            const _CommandWell(command: dsBotInstallCommand),
        ],
      ),
    );
  }
}

/// A monospace command with a copy key, as the plugin page shows it.
class _CommandWell extends StatelessWidget {
  const _CommandWell({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dsh = DshColors.of(context);
    return GlassSurface(
      tier: GlassTier.card,
      borderRadius: AppShape.radiusMd,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SelectableText(command, maxLines: 1, style: AppType.monoSmall(color: dsh.codeWellFg)),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.commonCopy,
              icon: const Icon(AppIcons.copy, size: 18),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: command));
                showBriefNotice(context, l10n.commonCopied);
              },
            ),
          ],
        ),
      ),
    );
  }
}
