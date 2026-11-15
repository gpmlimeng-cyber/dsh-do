// 「想多久再回」的展示层：四档人话 + 原生高抽屉。
//
// 档位与映射在状态层（`state/bot_effort.dart` 的 `ReplyPace` /
// `wireEffortFor` / `paceOf`）；这里只放文案和抽屉。

import 'package:flutter/material.dart';

import '../../state/bot_effort.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_strings.dart';

String replyPaceLabel(ReplyPace pace) => switch (pace) {
  ReplyPace.instant => ImStrings.replyPaceInstant,
  ReplyPace.adaptive => ImStrings.replyPaceAuto,
  ReplyPace.thoughtful => ImStrings.replyPaceThink,
  ReplyPace.deep => ImStrings.replyPaceDeep,
};

String replyPaceHint(ReplyPace pace) => switch (pace) {
  ReplyPace.instant => ImStrings.replyPaceInstantHint,
  ReplyPace.adaptive => ImStrings.replyPaceAutoHint,
  ReplyPace.thoughtful => ImStrings.replyPaceThinkHint,
  ReplyPace.deep => ImStrings.replyPaceDeepHint,
};

bool replyPaceRecommended(ReplyPace pace) => pace == ReplyPace.adaptive;

/// 原生高抽屉：四档 + 单选。
///
/// 选中后先跑 [onSelect]：返回 true 才关抽屉，失败（false）停在原地可重试。
Future<void> showReplyPaceSheet(
  BuildContext context, {
  required ReplyPace current,
  required String botName,
  required Future<bool> Function(ReplyPace) onSelect,
}) {
  final choices = [
    (ReplyPace.instant, AppIcons.stopGenerating),
    (ReplyPace.adaptive, AppIcons.askAi),
    (ReplyPace.thoughtful, AppIcons.generating),
    (ReplyPace.deep, AppIcons.providers),
  ];
  return showAppSheet<void>(
    context,
    heightFactor: 0.72,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        children: [
          SheetTitleBar(ImStrings.replyPace),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    ImStrings.replyPaceHintFor(botName),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
                  ),
                ),
                SheetGroup(
                  children: [
                    for (final (pace, icon) in choices)
                      ListPageRow(
                        key: ValueKey('reply-pace-${pace.name}'),
                        icon: icon,
                        title: replyPaceLabel(pace),
                        titleNote: replyPaceRecommended(pace) ? ImStrings.replyPaceRecommended : null,
                        subtitle: replyPaceHint(pace),
                        chevron: false,
                        badge: pace == current
                            ? Icon(AppIcons.radioOn, size: 18, color: Theme.of(context).colorScheme.primary)
                            : Icon(AppIcons.radioOff, size: 18, color: Theme.of(context).colorScheme.outline),
                        onTap: () async {
                          final saved = await onSelect(pace);
                          if (saved && context.mounted) Navigator.pop(sheet);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
