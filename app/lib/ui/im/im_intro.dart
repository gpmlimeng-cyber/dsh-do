// 轻松模式的空态：Bot 头像 + 一句自我介绍 + 三个可点的建议。
//
// 专业页的 `_Intro` 只有头像/名字/角色；这里只多三颗建议，点了直接把这句话
// 发出去（`onSay` 由 `bot_chat_page` 接到它自己的发送流程）。
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';

import '../bots/bot_avatar.dart';
import '../theme/theme.dart';
import 'im_strings.dart';

class ImIntro extends StatelessWidget {
  const ImIntro({super.key, required this.bot, required this.onSay});

  final DsBot bot;
  final ValueChanged<String> onSay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final role = bot.role.trim();
    final hints = [ImStrings.introWhatCanYouDo, ImStrings.introPlanMyDay, ImStrings.introJustChat];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BotAvatar(bot: bot, size: 72),
          const SizedBox(height: 14),
          Text(bot.name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (role.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              role,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hint in hints)
                ActionChip(
                  label: Text(hint),
                  onPressed: () => onSay(hint),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
