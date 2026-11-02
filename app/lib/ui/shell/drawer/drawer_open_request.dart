import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped when a page pushed over the shell wants the drawer opened there.
///
/// A Bot or group chat is its own route, so its header has no drawer of its
/// own to open: it asks the shell underneath, then steps back to it.
class DrawerOpenRequest extends Notifier<int> {
  @override
  int build() => 0;

  /// One more request; the shell opens its drawer on every new value.
  void request() => state++;
}

final drawerOpenRequestProvider = NotifierProvider<DrawerOpenRequest, int>(DrawerOpenRequest.new);

/// From a page pushed over the shell: go back to the shell, drawer open.
void openDrawerOverShell(BuildContext context, WidgetRef ref) {
  ref.read(drawerOpenRequestProvider.notifier).request();
  Navigator.of(context).popUntil((route) => route.isFirst);
}
