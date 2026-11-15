// 轻松模式的「发现」：把现有页面当入口，只做跳转，不新做功能。
//
// 排版用 App 原生的「全部功能」那套：`FeatureGroupLabel` + `TileGrid`（2 列）
// + `FeatureCard`（圆底图标、标题 + 一句说明）。取舍按产品《轻松模式-需求》D 组：
// 砍收藏/星标、更新、外观、会话搜索；社区一格（论坛在社区页里）；文件页需要会话，
// 换成工作区页。这一张表是唯一数据源，产品调顺序/增删只改这里。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/sessions_state.dart';
import '../bots/bots_page.dart';
import '../common/tile_grid.dart';
import '../community/community_page.dart';
import '../features/all_features_page.dart' show FeatureGroupLabel;
import '../features/jobs_page.dart';
import '../features/skills_page.dart';
import '../forum/forum_home_page.dart';
import '../phone/phone_control_screen.dart';
import '../plugins/plugins_screen.dart';
import '../remote/remote_screen.dart';
import '../settings/index/settings_pages.dart';
import '../settings/settings_screen.dart';
import '../share_code/profile_share_sheet.dart' show showShareProfileSheet;
import '../terminal/terminal_page.dart';
import '../theme/app_icons.dart';
import '../workspace/workspaces_page.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

/// 发现页的一格：图标、标题、一句话，需要会话的格子会变淡并在点击时给提示。
class _Cell {
  const _Cell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool enabled;
}

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

    final groups = <(String, List<_Cell>)>[
      (
        ImStrings.groupChats,
        [
          _Cell(icon: AppIcons.groupChat, title: l10n.botsGroupChat, subtitle: ImStrings.discoverBotsSub, onTap: () => push(const BotsPage())),
          _Cell(
            icon: AppIcons.inProgress,
            title: l10n.catalogJobs,
            subtitle: ImStrings.discoverJobsSub,
            enabled: hasSession,
            onTap: () => push(JobsPage(sessionId: sessionId)),
          ),
        ],
      ),
      (
        ImStrings.groupContents,
        [
          _Cell(icon: AppIcons.workspace, title: l10n.catalogWorkspaces, subtitle: ImStrings.discoverWorkspacesSub, onTap: () => push(const WorkspacesPage())),
          _Cell(icon: AppIcons.share, title: l10n.catalogShareProfile, subtitle: ImStrings.discoverShareSub, onTap: () => unawaited(showShareProfileSheet(context))),
        ],
      ),
      (
        ImStrings.groupTools,
        [
          _Cell(
            icon: AppIcons.terminal,
            title: l10n.catalogTerminal,
            subtitle: ImStrings.discoverTerminalSub,
            enabled: hasSession,
            onTap: () => push(TerminalPage(sessionId: sessionId)),
          ),
          _Cell(icon: AppIcons.phoneControl, title: l10n.catalogPhoneControl, subtitle: ImStrings.discoverPhoneSub, onTap: () => push(const PhoneControlScreen())),
          _Cell(icon: AppIcons.voice, title: l10n.catalogVoiceInput, subtitle: ImStrings.discoverVoiceSub, onTap: () => settings(SettingsPageId.voice)),
          _Cell(icon: AppIcons.pet, title: ImStrings.pets, subtitle: ImStrings.discoverPetsSub, onTap: () => settings(SettingsPageId.pets)),
        ],
      ),
      (
        ImStrings.groupExtensions,
        [
          _Cell(icon: AppIcons.plugin, title: l10n.catalogPlugins, subtitle: ImStrings.discoverPluginsSub, onTap: () => push(const PluginsScreen())),
          _Cell(
            icon: AppIcons.skill,
            title: l10n.catalogSkills,
            subtitle: ImStrings.discoverSkillsSub,
            enabled: hasSession,
            onTap: () => push(SkillsPage(sessionId: sessionId)),
          ),
          _Cell(
            icon: AppIcons.community,
            title: l10n.catalogCommunity,
            subtitle: ImStrings.discoverCommunitySub,
            // 社区页里的论坛入口用同一个 Navigator。
            onTap: () => push(CommunityPage(onOpenForum: () => Navigator.of(context).push(ForumHomePage.route()))),
          ),
        ],
      ),
      (
        ImStrings.groupHost,
        [
          _Cell(icon: AppIcons.remoteHost, title: ImStrings.remote, subtitle: ImStrings.discoverRemoteSub, onTap: () => push(const RemoteScreen())),
          _Cell(icon: AppIcons.engine, title: l10n.catalogEngine, subtitle: ImStrings.discoverEngineSub, onTap: () => settings(SettingsPageId.engine)),
        ],
      ),
      (
        ImStrings.groupSettings,
        [
          _Cell(icon: AppIcons.model, title: l10n.catalogModels, subtitle: ImStrings.discoverModelsSub, onTap: () => settings(SettingsPageId.models)),
          // 更新按产品裁决并进「全部设置 → 关于」，这里不另设入口。
          _Cell(icon: AppIcons.settings, title: l10n.catalogAllSettings, subtitle: ImStrings.discoverAllSettingsSub, onTap: () => push(const SettingsScreen())),
        ],
      ),
    ];

    Widget card(_Cell cell) {
      final tile = FeatureCard(
        icon: cell.icon,
        title: cell.title,
        subtitle: cell.subtitle,
        enabled: cell.enabled,
        onTap: cell.onTap,
      );
      if (cell.enabled) return tile;
      // 禁用态的卡不吞点击：外面包一层，点一下给出「先聊一句」的提示。
      return GestureDetector(onTap: needsChat, behavior: HitTestBehavior.opaque, child: tile);
    }

    return ImPageScaffold(
      backdrop: false,
      title: ImStrings.discoverTitle,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final (title, cells) in groups) ...[
            FeatureGroupLabel(title),
            TileGrid(children: [for (final cell in cells) card(cell)]),
          ],
        ],
      ),
    );
  }
}
