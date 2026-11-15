// 轻松模式的 Bot 资料卡：头像、名字、角色、它记得几件事、现在能做什么、发消息、删除。
//
// 这是专业 `BotDetailsPage` 的轻量替代：那页会露 token 用量和原始记录
// （`bot_details_page.dart`），light 不看这些。字段清单见
// `轻松模式-组件树.md` §4。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bot_avatar_state.dart';
import '../../state/bots_state.dart';
import '../../state/features_state.dart' show permissionStateProvider;
import '../bots/bot_avatar.dart';
import '../bots/bot_memory_page.dart';
import '../bots/bot_sheets.dart' show confirmDelete, showTextEditSheet;
import '../common/list_page_row.dart';
import '../features/feature_format.dart' show permissionName;
import '../mascots/mascot_customizer.dart' show openMascotCustomizer;
import '../settings/index/settings_pages.dart' show settingsPage;
import '../settings/index/spots.dart' show SettingsPageId;
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImBotProfilePage extends ConsumerWidget {
  const ImBotProfilePage({super.key, required this.botId});

  final String botId;

  static Route<void> route(String botId) => MaterialPageRoute<void>(builder: (_) => ImBotProfilePage(botId: botId));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final status = ref.watch(dsBotProvider);
    final bot = status.team?.bot(botId);
    if (bot == null) {
      return const ImPageScaffold(title: 'Bot', back: true, child: SizedBox.shrink());
    }
    final look = ref.watch(botAvatarProvider.select((byBot) => byBot[botId]));
    final lookKind = switch (look) {
      BotAvatarConfig(kind: BotAvatarKind.mascot) => ImStrings.lookKindMascot,
      BotAvatarConfig(kind: BotAvatarKind.text) => ImStrings.lookKindLetter,
      BotAvatarConfig(kind: BotAvatarKind.emoji) => ImStrings.lookKindEmoji,
      BotAvatarConfig(kind: BotAvatarKind.photo) => ImStrings.lookKindPhoto,
      _ => ImStrings.lookKindDefault,
    };
    final memory = ref.watch(dsBotMemoryProvider((botId: botId, roomId: null))).value;
    final permission = ref.watch(permissionStateProvider(bot.sessionId)).value;
    final api = ref.read(dsBotProvider.notifier).api;
    final preset = permission?.current;
    final ability = preset == null ? null : permissionName(preset);

    Future<void> editLook() async {
      final initial = look?.mascot ?? letterMascotOf(look, bot.id);
      final choice = await openMascotCustomizer(
        context,
        initial: initial,
        text: look?.kind == BotAvatarKind.text,
        name: bot.name,
      );
      if (choice == null || !context.mounted) return;
      await ref.read(botAvatarProvider.notifier).set(
        bot.id,
        choice.text ? BotAvatarConfig.text(choice.spec) : BotAvatarConfig.mascot(choice.spec),
      );
    }

    Future<void> editText({required String title, required String initial, required bool multiline, required Future<void> Function(String) save}) async {
      final text = await showTextEditSheet(context, title: title, initial: initial, multiline: multiline);
      if (text == null || text == initial || !context.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await save(text);
        await ref.read(dsBotProvider.notifier).refresh();
      } catch (error) {
        // 撞名、空名、超长等都由宿主拒绝，这里给出提示而不是未捕获异常。
        messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
      }
    }

    return ImPageScaffold(
      title: bot.name,
      back: true,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 28),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              children: [
                BotAvatar(bot: bot, size: 96, emotion: '02', animate: true),
                const SizedBox(height: 12),
                Text(bot.name, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                if (bot.role.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    bot.role.trim(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.textTertiary),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  icon: const Icon(AppIcons.chat, size: 18),
                  label: Text(ImStrings.profileSend),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          if (api != null) ...[
            ListPageRow(
              icon: AppIcons.rename,
              title: ImStrings.renameBot,
              subtitle: bot.name,
              onTap: () => editText(
                title: ImStrings.renameBot,
                initial: bot.name,
                multiline: false,
                save: (text) => api.updateBot(bot.id, name: text),
              ),
            ),
            ListPageRow(
              icon: AppIcons.edit,
              title: ImStrings.renameRole,
              subtitle: bot.role.trim().isEmpty ? ImStrings.roleEmpty : bot.role.trim(),
              onTap: () => editText(
                title: ImStrings.renameRole,
                initial: bot.role,
                multiline: false,
                save: (text) => api.updateBot(bot.id, role: text),
              ),
            ),
            ListPageRow(
              icon: AppIcons.instructions,
              title: ImStrings.profileSettings,
              subtitle: ImStrings.profileSettingsHint,
              onTap: () => editText(
                title: ImStrings.profileSettings,
                initial: bot.instructions,
                multiline: true,
                save: (text) => api.updateBot(bot.id, instructions: text),
              ),
            ),
            ListPageRow(
              icon: AppIcons.pet,
              title: ImStrings.profileLook,
              subtitle: lookKind,
              onTap: editLook,
            ),
            if (bot.imageRef != null)
              ListPageRow(
                icon: AppIcons.gallery,
                title: ImStrings.profileLookPhoto,
                onTap: () => ref.read(botAvatarProvider.notifier).set(bot.id, const BotAvatarConfig.photo()),
              ),
            if (look != null)
              ListPageRow(
                icon: AppIcons.restart,
                title: ImStrings.profileLookReset,
                onTap: () => ref.read(botAvatarProvider.notifier).clear(bot.id),
              ),
            ListPageRow(
              icon: AppIcons.goal,
              title: ImStrings.profileMemory,
              meta: memory == null ? null : ImStrings.memoryCount(memory.entries.length),
              onTap: () => Navigator.of(context).push(BotMemoryPage.route(botId: bot.id)),
            ),
            ListPageRow(
              icon: AppIcons.permissions,
              title: ImStrings.profileAbilities,
              meta: ability,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => settingsPage(SettingsPageId.permission, sessionId: bot.sessionId),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Center(
              child: TextButton(
                onPressed: () async {
                  final gone = await confirmDelete(context, title: bot.name, body: ImStrings.deleteBotBody(bot.name));
                  if (!gone || !context.mounted) return;
                  await api.deleteBot(bot.id);
                  await ref.read(dsBotProvider.notifier).refresh();
                  if (context.mounted) Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Text(
                  ImStrings.profileDelete,
                  style: TextStyle(color: colors.danger),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
