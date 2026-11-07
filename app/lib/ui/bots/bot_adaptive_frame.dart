// A Bot's or a group's chat on a tablet, a foldable or a phone on its side.
//
// The page keeps its own column — the header, the transcript, the composer —
// and only its frame changes: the conversation list becomes a sidebar when it
// fits (otherwise ≡ still pulls the drawer over the chat), and 对话详情 becomes
// a column beside the chat instead of a page pushed over it. The plan comes
// from the same [AdaptiveLayout] the home screen uses, so one App has one set
// of breakpoints.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/adaptive_layout_state.dart';
import '../session/session_detail_page.dart';
import '../shell/session_search_page.dart' show showSessionSearch;
import '../theme/backdrop.dart' show AppBackdrop;
import '../shell/adaptive/adaptive_layout.dart';
import '../shell/adaptive/adaptive_scaffold.dart';
import '../shell/adaptive/open_detail.dart';
import '../shell/adaptive/adaptive_rail.dart';
import '../shell/drawer/drawer_destination.dart';
import '../shell/session_drawer_host.dart';
import '../shell/sessions_drawer.dart';

/// The frame around a Bot's or a group's chat: the chat column, the list beside
/// it when the window has room, 对话详情 beside it when the window has room.
class BotAdaptiveFrame extends ConsumerWidget {
  const BotAdaptiveFrame({super.key, required this.drawer, required this.panel, required this.builder});

  /// The page's own pull-over drawer, the one it has on a phone.
  final SessionDrawerConfig drawer;

  /// What the right column shows; null when there is no conversation to
  /// describe (a member with no conversation in this group yet).
  final Widget? panel;

  /// The page's own frame, given the plan its header keys follow.
  final Widget Function(BuildContext context, AdaptiveLayout layout) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(layoutPrefsProvider);
    final layout = AdaptiveLayout.resolve(
      window: MediaQuery.sizeOf(context),
      padding: MediaQuery.paddingOf(context),
      hasSession: true,
      sidebarOpen: prefs.sidebarOpen,
      panelOpen: prefs.panelOpen,
    );
    final sidebar = layout.sidebarFits && prefs.sidebarOpen;
    // The columns this shell draws sit outside the page's own frame: without
    // the app's backdrop they fall back to the default (dark) surfaces while
    // the chat in the middle is drawn on the page's. One backdrop for all three.
    return AppBackdrop(
      child: AdaptiveChrome(
      layout: layout,
      child: AdaptiveScaffold(
        layout: layout,
        // Stored choices arriving at launch snap into place.
        animate: prefs.loaded,
        body: builder(context, layout),
        sidebar: sidebar
            ? SessionsDrawer(
                key: const ValueKey('bot-sidebar'),
                // It stays: picking a conversation just shows it.
                onClose: () {},
                onOpen: drawer.onDestination,
                onChosen: drawer.onChosen,
              )
            : null,
        // Without a widget here the layout still reserves the rail's width and
        // the page shows an empty strip; the rail is the list's folded form.
        rail: AdaptiveRail(
          onMenu: () {
            final notifier = ref.read(layoutPrefsProvider.notifier);
            switch (layout.menuAction) {
              case MenuAction.overlay:
                drawer.controller.open(context);
              case MenuAction.expand:
                unawaited(notifier.setSidebarOpen(true));
              case MenuAction.collapse:
                unawaited(notifier.setSidebarOpen(false));
            }
          },
          menuTooltip: AdaptiveChrome.menuTooltipFor(layout),
          onSearch: () async {
            final sessionId = await showSessionSearch(context);
            if (sessionId != null) drawer.onChosen();
          },
          onHost: () => drawer.onDestination(DrawerDestination.remote),
          onWeb: () => drawer.onDestination(DrawerDestination.web),
          onSettings: () => drawer.onDestination(DrawerDestination.settings),
        ),
        // As home does: the panel is handed over whenever there is room, and the
        // scaffold plays its slide-away; gating it on the pref would cut that.
        panel: layout.panelAvailable ? panel : null,
      ),
      ),
    );
  }
}

/// Where 对话详情 of [sessionId] opens on this window, from a page of its own
/// (a Bot's chat, a group's): the column beside the chat on a wide window that
/// has room, the wide sheet on a medium one, a page otherwise.
///
/// Unlike [SessionDetailPage.open] this does not ask whether the session is the
/// home screen's: a Bot's chat shows its own details beside itself.
void openBotDetail(
  BuildContext context,
  WidgetRef ref, {
  required AdaptiveLayout layout,
  required String sessionId,
  String? scopeLabel,
}) {
  // One way in for every form: the same helper the home screen uses, told that
  // this page is showing the session, so a wide window gives the column rather
  // than a sheet.
  openAdaptiveDetail(
    context,
    sessionId: sessionId,
    toggle: true,
    assumeCurrent: true,
    page: (_) => SessionDetailPage(sessionId: sessionId, scopeLabel: scopeLabel),
    sheet: (_) => SessionDetailPage(
      sessionId: sessionId,
      mode: SessionDetailMode.sheet,
      scopeLabel: scopeLabel,
    ),
  );
}

/// What the ≡ key does, and what it says: folds or unfolds the sidebar when the
/// window has room for one, pulls the drawer over the chat otherwise.
String botMenuTooltip(BuildContext context, AdaptiveLayout layout) => !layout.sidebarFits
    ? context.l10n.shellChatList
    : layout.left == LeftPane.sidebar
    ? context.l10n.shellCollapseChatList
    : context.l10n.shellExpandChatList;

void onBotMenu(BuildContext context, WidgetRef ref, AdaptiveLayout layout, VoidCallback overlay) {
  if (!layout.sidebarFits) {
    overlay();
    return;
  }
  // The write is a preference; the store keeps it for this run if it cannot.
  unawaited(ref.read(layoutPrefsProvider.notifier).setSidebarOpen(layout.left != LeftPane.sidebar));
}
