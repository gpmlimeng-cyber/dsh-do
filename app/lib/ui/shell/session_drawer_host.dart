// The sessions drawer and the pull it follows. The shell leans it over the
// chat screen; a Bot's or a group's chat — a route of its own — pulls the same
// panel over itself instead of stepping back to the shell, so opening the
// drawer never leaves the conversation (or drops its draft and scroll).
//
// One controller, one overlay, one drag: the two callers cannot drift apart.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../engine/engine_screen.dart';
import '../features/all_features_page.dart';
import '../plugins/plugins_screen.dart';
import '../remote/remote_screen.dart';
import '../settings/search/settings_search_page.dart';
import '../settings/settings_screen.dart';
import '../theme/theme.dart';
import '../web/local_web_screen.dart';
import 'adaptive/adaptive_layout.dart';
import 'drawer_drag.dart';
import 'sessions_drawer.dart';

/// One drawer's state: the animation a swipe and a header's ≡ move, the width
/// of the panel, and the "is it open" the back key reads.
///
/// The owner keeps it for the page's lifetime (`vsync` is the page's), so an
/// open and closed drawer leaves the page it covers untouched.
class SessionDrawerController {
  SessionDrawerController({required TickerProvider vsync, double initialValue = 0})
    : animation = AnimationController(vsync: vsync, duration: AppMotion.emphasized, value: initialValue);

  final AnimationController animation;

  bool _disposed = false;

  bool get isOpen => !_disposed && animation.value > 0;

  /// 320 of list, plus the cutout or navigation bar it covers on a phone on
  /// its side (the drawer's content keeps clear of it), like the sidebar.
  double widthOf(BuildContext context) => math.min(
    AdaptiveMetrics.sidebarWidth + MediaQuery.paddingOf(context).left,
    MediaQuery.sizeOf(context).width - 56,
  );

  /// Pulls the panel over (moving, not snapping): the curve a tap uses.
  void open(BuildContext context) {
    if (_disposed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    animation.animateTo(1, curve: AppMotion.glide, duration: AppMotion.of(context, AppMotion.emphasized));
  }

  void close(BuildContext context) {
    if (_disposed) return;
    FocusManager.instance.primaryFocus?.unfocus();
    animation.animateBack(0, curve: AppMotion.glide, duration: AppMotion.of(context, AppMotion.standard));
  }

  void toggle(BuildContext context) => isOpen ? close(context) : open(context);

  /// Puts the panel away at once: nothing the person sees should move while
  /// the window or the layout changes under it.
  void snapClosed() {
    if (_disposed) return;
    animation.value = 0;
  }

  /// The drag handlers the panel's swipe shares: follow the finger, then settle
  /// to the nearer edge with the fling's own velocity.
  Map<Type, GestureRecognizerFactory> gestures(BuildContext context) => {
    DrawerDragRecognizer: GestureRecognizerFactoryWithHandlers<DrawerDragRecognizer>(
      () => DrawerDragRecognizer(
        isOpen: () => isOpen,
        onStart: () {
          if (_disposed) return;
          animation.stop();
          FocusManager.instance.primaryFocus?.unfocus();
        },
        onDelta: (dx) {
          if (_disposed) return;
          final width = widthOf(context);
          if (width <= 0) return;
          animation.value = (animation.value + dx / width).clamp(0.0, 1.0);
        },
        onEnd: (velocity) => _settle(context, velocity),
        debugOwner: this,
      ),
      (_) {},
    ),
  };

  void _settle(BuildContext context, double velocity) {
    if (_disposed) return;
    final width = widthOf(context);
    if (velocity.abs() >= kMinFlingVelocity && width > 0) {
      final target = velocity > 0 ? 1.0 : 0.0;
      if (AppMotion.reduced(context)) {
        animation.value = target;
        return;
      }
      // Not `fling`, which refuses a spring with any bounce. The controller's
      // bounds clip it: the bounce shapes the arrival, nothing goes past the edge.
      final spring = AppMotion.settle(AppMotion.flingSpring, animation.value, target, velocity / width, landing: false);
      if (velocity > 0) {
        animation.animateWith(spring);
      } else {
        animation.animateBackWith(spring);
      }
      return;
    }
    if (animation.value >= 0.5) {
      open(context);
    } else {
      close(context);
    }
  }

  void dispose() {
    _disposed = true;
    animation.dispose();
  }
}

/// What a pushed page (a Bot's or a group's chat) hands its own drawer.
class SessionDrawerConfig {
  const SessionDrawerConfig({required this.controller, required this.onDestination, required this.onChosen});

  final SessionDrawerController controller;

  /// A settings-like destination: pushed above this page, which stays under it.
  final ValueChanged<DrawerDestination> onDestination;

  /// A conversation or a new chat was chosen: this page leaves for the shell
  /// (the selection is already made — close, then pop back to the shell).
  final VoidCallback onChosen;
}

/// The drawer as a pushed page shows it: the same panel, scrim, swipe and back
/// handling the shell has, without the shell's quick panel and sidebar.
class SessionDrawerHost extends StatefulWidget {
  const SessionDrawerHost({super.key, required this.config, required this.child});

  final SessionDrawerConfig config;
  final Widget child;

  @override
  State<SessionDrawerHost> createState() => _SessionDrawerHostState();
}

class _SessionDrawerHostState extends State<SessionDrawerHost> {
  /// The pulled-over drawer's identity bar height: its notices stand above it.
  final _identityBar = ValueNotifier<double>(0);

  /// Mirrors "drawer at all open" so the page's PopScope rebuilds only on the
  /// 0 ↔ >0 edge, never per drag frame.
  late bool _open = widget.config.controller.isOpen;

  @override
  void initState() {
    super.initState();
    widget.config.controller.animation.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.config.controller.animation.removeListener(_onTick);
    _identityBar.dispose();
    super.dispose();
  }

  void _onTick() {
    final open = widget.config.controller.isOpen;
    if (open != _open) setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.config.controller;
    return PopScope(
      // Back closes the drawer first; the page itself stays.
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.close(context);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          RawGestureDetector(
            behavior: HitTestBehavior.translucent,
            gestures: controller.gestures(context),
            child: widget.child,
          ),
          Positioned.fill(
            // Open, the panel and its scrim take the swipe that pushes them
            // back; closed, nothing here is hit.
            child: RawGestureDetector(
              behavior: HitTestBehavior.deferToChild,
              gestures: controller.gestures(context),
              child: SessionDrawerOverlay(
                animation: controller.animation,
                width: controller.widthOf(context),
                drawer: SessionsDrawer(
                  onClose: () => controller.close(context),
                  onOpen: widget.config.onDestination,
                  onChosen: widget.config.onChosen,
                  identityBarHeight: _identityBar,
                  drawerMotion: controller.animation,
                ),
                onClose: () => controller.close(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The settings-like page a drawer destination opens, pushed above whatever
/// page the drawer was opened from.
void openDrawerDestination(BuildContext context, DrawerDestination destination) {
  final page = switch (destination) {
    DrawerDestination.web => const LocalWebScreen(),
    DrawerDestination.remote => const RemoteScreen(),
    DrawerDestination.plugins => const PluginsScreen(),
    DrawerDestination.engine => const EngineScreen(),
    DrawerDestination.settings => const SettingsScreen(),
    DrawerDestination.settingsSearch => const SettingsSearchPage(),
    DrawerDestination.features => const AllFeaturesPage(),
  };
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// Scrim + drawer panel; the only part that rebuilds while the drawer moves. The
/// panel keeps its state when closed, while Visibility suppresses painting,
/// semantics and tickers until the first drag frame reveals it. [QuickPanel]
/// comes the same way, [fromRight].
class SessionDrawerOverlay extends StatelessWidget {
  const SessionDrawerOverlay({
    super.key,
    required this.animation,
    required this.width,
    required this.drawer,
    required this.onClose,
    this.fromRight = false,
  });

  final Animation<double> animation;
  final double width;
  final Widget drawer;
  final VoidCallback onClose;
  final bool fromRight;

  @override
  Widget build(BuildContext context) {
    final scrim = DshSurfaces.of(context).scrim;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: drawer),
      builder: (context, drawer) {
        final progress = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: progress == 0,
                child: GestureDetector(
                  onTap: onClose,
                  child: ColoredBox(color: scrim.withValues(alpha: scrim.a * progress)),
                ),
              ),
            ),
            // 面板位置用 Transform 走(paint-only):每帧改 Positioned.left 会让
            // Stack 和整块抽屉重新布局,拖动时白白多一层成本。
            Positioned(
              left: fromRight ? null : 0,
              right: fromRight ? 0 : null,
              top: 0,
              bottom: 0,
              width: width,
              child: Visibility(
                visible: progress > 0,
                maintainState: true,
                child: Transform.translate(
                  offset: Offset((progress - 1) * (width + 24) * (fromRight ? -1 : 1), 0),
                  child: drawer!,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
