// 对话字号 (设置 › 外观 › 对话字号) applied to a conversation's content only:
// the header and the composer keep the system size, as the setting says.
//
// One widget for every conversation the app draws — the native one, a Bot's
// own chat, a group chat and a replay — so the setting means the same thing in
// all of them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings_state.dart';

class ChatTextScale extends ConsumerWidget {
  const ChatTextScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factor = ref.watch(settingsProvider.select((s) => s.chatTextScale));
    if (factor == 1.0) return child;
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: ChatScaler(media.textScaler, factor)),
      child: child,
    );
  }
}

/// The chat size on top of the system's: Android 14 scales large text less
/// than small, and that curve is kept.
class ChatScaler extends TextScaler {
  const ChatScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => scale(1);

  @override
  bool operator ==(Object other) => other is ChatScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
