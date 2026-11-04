// 「消息模式」: which lines a group chat shows, picked the way the model sheet is
// (a title bar and a list of rows). A pick applies at once and closes.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../state/room_message_mode.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import 'bot_avatar.dart';

Future<void> showRoomMessageSheet(
  BuildContext context, {
  required DsBotRoom room,
  required DsBotTeam team,
  required RoomMessageMode current,
  required ValueChanged<RoomMessageMode> onSelected,
}) {
  return showAppSheet<void>(
    context,
    isScrollControlled: true,
    builder: (sheet) {
      final l10n = sheet.l10n;
      Widget row({
        required Key key,
        required String title,
        required bool selected,
        Widget? leading,
        IconData? icon,
        required RoomMessageMode mode,
      }) => ListPageRow(
        key: key,
        icon: icon,
        leading: leading,
        title: title,
        onTap: () {
          onSelected(mode);
          Navigator.of(sheet).pop();
        },
        trailing: selected ? Icon(AppIcons.done, size: 20, color: Theme.of(sheet).colorScheme.primary) : null,
      );

      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(l10n.botsMessageMode),
              SheetGroup(
                margin: const EdgeInsets.symmetric(horizontal: SheetTitleBar.inset),
                children: [
                  row(
                    key: const ValueKey('room-mode-all'),
                    title: l10n.shellAll,
                    icon: AppIcons.chat,
                    selected: current.isAll,
                    mode: RoomMessageMode.all,
                  ),
                  row(
                    key: const ValueKey('room-mode-relevant'),
                    title: l10n.botsMessageModeRelevant,
                    icon: AppIcons.mention,
                    selected: current.isRelevant,
                    mode: RoomMessageMode.relevant,
                  ),
                  for (final id in room.members)
                    if (team.bot(id) case final bot?)
                      row(
                        key: ValueKey('room-mode-${bot.id}'),
                        title: bot.name,
                        leading: BotAvatar(bot: bot, size: 24),
                        selected: current.memberId == bot.id,
                        mode: RoomMessageMode.member(bot.id),
                      ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
