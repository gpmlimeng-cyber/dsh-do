// 轻松模式的「发现」：把现有页面当入口，只做跳转，不新做功能。
//
// 取舍按产品《轻松模式-需求》D 组：砍收藏/星标、更新、外观、会话搜索；
// 社区一格（论坛在社区页里）；文件页需要会话，换成工作区页。
// 这一张表是唯一数据源，产品调顺序/增删只改这里。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/sessions_state.dart';
import '../bots/bots_page.dart';
import '../community/community_page.dart';
import '../features/jobs_page.dart';
import '../features/schedules_page.dart';
import '../features/skills_page.dart';
import '../forum/forum_home_page.dart';
import '../phone/phone_control_screen.dart';
import '../plugins/plugins_screen.dart';
import '../remote/remote_screen.dart';
import '../settings/index/settings_pages.dart';
import '../settings/settings_screen.dart';
import '../share_hosted/hosted_links_page.dart';
import '../terminal/terminal_page.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../workspace/workspaces_page.dart';
import 'im_feature_grid.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImDiscoverPage extends ConsumerWidget {
  const ImDiscoverPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessionId = ref.watch(currentSessionProvider) ?? '';
    final hasSession = sessionId.isNotEmpty;
    void needsChat() {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(ImStrings.needsConversation)));
    }

    void push(Widget page) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    }

    void settings(SettingsPageId id) => push(settingsPage(id));

    final groups = <(String, List<ImFeatureCell>)>[
      (
        ImStrings.groupChats,
        [
          ImFeatureCell(icon: AppIcons.groupChat, label: l10n.botsGroupChat, onTap: () => push(const BotsPage())),
          ImFeatureCell(
            icon: AppIcons.inProgress,
            label: l10n.catalogJobs,
            enabled: hasSession,
            onTap: () => push(JobsPage(sessionId: sessionId)),
            onDisabledTap: needsChat,
          ),
          ImFeatureCell(icon: AppIcons.scheduled, label: l10n.catalogSchedules, onTap: () => push(const SchedulesPage())),
        ],
      ),
      (
        ImStrings.groupContents,
        [
          ImFeatureCell(icon: AppIcons.workspace, label: l10n.catalogWorkspaces, onTap: () => push(const WorkspacesPage())),
          ImFeatureCell(icon: AppIcons.share, label: l10n.catalogShareProfile, onTap: () => push(const HostedLinksPage())),
        ],
      ),
      (
        ImStrings.groupTools,
        [
          ImFeatureCell(
            icon: AppIcons.terminal,
            label: l10n.catalogTerminal,
            enabled: hasSession,
            onTap: () => push(TerminalPage(sessionId: sessionId)),
            onDisabledTap: needsChat,
          ),
          ImFeatureCell(icon: AppIcons.phoneControl, label: l10n.catalogPhoneControl, onTap: () => push(const PhoneControlScreen())),
          ImFeatureCell(icon: AppIcons.voice, label: l10n.catalogVoiceInput, onTap: () => settings(SettingsPageId.voice)),
          ImFeatureCell(icon: AppIcons.pet, label: ImStrings.pets, onTap: () => settings(SettingsPageId.pets)),
        ],
      ),
      (
        ImStrings.groupExtensions,
        [
          ImFeatureCell(icon: AppIcons.plugin, label: l10n.catalogPlugins, onTap: () => push(const PluginsScreen())),
          ImFeatureCell(
            icon: AppIcons.skill,
            label: l10n.catalogSkills,
            enabled: hasSession,
            onTap: () => push(SkillsPage(sessionId: sessionId)),
            onDisabledTap: needsChat,
          ),
          ImFeatureCell(
            icon: AppIcons.community,
            label: l10n.catalogCommunity,
            // 社区页里的论坛入口用同一个 Navigator。
            onTap: () => push(CommunityPage(onOpenForum: () => Navigator.of(context).push(ForumHomePage.route()))),
          ),
        ],
      ),
      (
        ImStrings.groupHost,
        [
          ImFeatureCell(icon: AppIcons.remoteHost, label: ImStrings.remote, onTap: () => push(const RemoteScreen())),
          ImFeatureCell(icon: AppIcons.engine, label: l10n.catalogEngine, onTap: () => settings(SettingsPageId.engine)),
        ],
      ),
      (
        ImStrings.groupSettings,
        [
          ImFeatureCell(icon: AppIcons.model, label: l10n.catalogModels, onTap: () => settings(SettingsPageId.models)),
          // 更新按产品裁决并进「全部设置 → 关于」，这里不另设入口。
          ImFeatureCell(icon: AppIcons.settings, label: l10n.catalogAllSettings, onTap: () => push(const SettingsScreen())),
        ],
      ),
    ];

    return ImPageScaffold(
      title: ImStrings.discoverTitle,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          for (final (title, cells) in groups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DshColors.of(context).textTertiary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ImFeatureGrid(cells: cells),
            ),
          ],
        ],
      ),
    );
  }
}
