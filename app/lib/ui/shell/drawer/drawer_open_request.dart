import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bumped when a page pushed over the shell wants the drawer opened there.
///
/// A Bot or group chat is its own route, so its header has no drawer of its
/// own to open: it asks the shell underneath, then steps back to it.
final drawerOpenRequestProvider = StateProvider<int>((ref) => 0);

/// From a page pushed over the shell: go back to the shell, drawer open.
void openDrawerOverShell(BuildContext context, WidgetRef ref) {
  ref.read(drawerOpenRequestProvider.notifier).state++;
  Navigator.of(context).popUntil((route) => route.isFirst);
}
