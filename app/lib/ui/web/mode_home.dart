// The home in the chosen 界面 (lib/state/ui_mode_state.dart) — the native shell
// or the official web page — and the quiet switch for the drawer. A switch
// cross-fades and lands on the same conversation on the same host: the web page
// opens the native conversation; the native shell opens what the page reported
// last (WebHome keeps currentSessionProvider current).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/sessions_state.dart';
import '../../state/ui_mode_state.dart';
import '../shell/home_shell.dart';
import '../shell/last_conversation_host.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'web_home.dart';
import 'web_target.dart';

/// The app's home in the chosen 界面.
class ModeHome extends ConsumerStatefulWidget {
  const ModeHome({super.key, this.native, this.web});

  /// Stand-ins for the two homes (tests).
  @visibleForTesting
  final Widget? native;
  @visibleForTesting
  final Widget Function(DshWebTarget? initial)? web;

  @override
  ConsumerState<ModeHome> createState() => _ModeHomeState();
}

class _ModeHomeState extends ConsumerState<ModeHome> {
  UiMode? _shown;
  DshWebTarget? _handoff;

  /// The drawer's ⇄ key posts a request instead of switching by itself: the
  /// home is the only thing that outlives every page, so it does the switch.
  Future<void> _becomeWeb() async {
    final container = ProviderScope.containerOf(context, listen: false);
    await container.read(uiModeProvider.notifier).set(UiMode.web);
    if (!mounted) return;
    Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(webModeRequestProvider, (_, _) => unawaited(_becomeWeb()));
    final mode = ref.watch(uiModeProvider);
    if (!mode.loaded) {
      // Read back with the rest of the settings: no frame of the other home.
      return const AppBackdrop(child: SizedBox.expand());
    }
    if (_shown == UiMode.native && mode.mode == UiMode.web) {
      // Switched from the native interface: its conversation (or its new
      // chat) opens in the page. A cold start in web mode lands where the
      // page itself left off.
      final id = ref.read(currentSessionProvider);
      _handoff = id == null ? const DshWebTarget(newSession: true) : DshWebTarget(sessionId: id);
      // A native page open over this home (a Bot chat, a group, a details
      // page) would otherwise stay on top of the web page: the switch would
      // look like it did nothing. The home is the first route; the page opens
      // under it, so the page has to go.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !ref.read(uiModeProvider).web) return;
        Navigator.maybeOf(context)?.popUntil((route) => route.isFirst);
      });
    }
    _shown = mode.mode;
    final Widget home = mode.web
        ? KeyedSubtree(
            key: const ValueKey(UiMode.web),
            child: widget.web?.call(_handoff) ?? WebHome(initial: _handoff),
          )
        : KeyedSubtree(
            key: const ValueKey(UiMode.native),
            // A cold start lands on the conversation this phone left open.
            child: LastConversationHost(child: widget.native ?? const HomeShell()),
          );
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.page),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: home,
    );
  }
}

/// The drawer's quiet switch to 网页模式: a round glass key the height of
/// 新对话 beside it, with 界面's own mark (the globe at the drawer's foot
/// opens the web page on top; this one makes it the home).
class WebModeKey extends ConsumerWidget {
  const WebModeKey({super.key, this.size = 36, this.tier = GlassTier.chrome, this.onSwitch});

  final double size;
  final GlassTier tier;

  /// The drawer puts itself away first: the key is its last act there, and the
  /// page that takes over should not open behind an open drawer.
  final VoidCallback? onSwitch;

  static String get tooltip => appL10n.webSwitchToWeb;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GlassIconButton(
      icon: AppIcons.swap,
      tooltip: context.l10n.webSwitchToWeb,
      size: size,
      tier: tier,
      onPressed: () => unawaited(_switch(context, ref)),
    );
  }

  Future<void> _switch(BuildContext context, WidgetRef ref) async {
    // Everything is taken before the drawer goes: its context is gone by the
    // time a failure arrives, and — in a Bot or group page, where closing the
    // drawer tears the page down with it — this widget's `ref` is gone too, so
    // reading the controller after [onSwitch] throws and the key looks dead on
    // that page only. (It did: the key worked on a conversation page and did
    // nothing at all on a group page.)
    final messenger = ScaffoldMessenger.maybeOf(context);
    final container = ProviderScope.containerOf(context, listen: false);
    // The intent goes first and synchronously: closing the drawer tears this
    // page (and this widget) down, and anything read or written after that
    // would be lost on a Bot or group page.
    container.read(webModeRequestProvider.notifier).request();
    onSwitch?.call();
    // If the state did not move, say what it is: a switch that quietly does
    // nothing is otherwise indistinguishable from a dead key.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final now = container.read(uiModeProvider).mode;
    if (now != UiMode.web) {
      messenger?.showSnackBar(SnackBar(content: Text('界面模式=${now.name}')));
    }
  }
}
