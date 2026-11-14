// 轻松模式的「我」：账号、AI 对我的了解、外观、AI 服务、高级、关于。
//
// 这里只做入口，设置页本身原样复用（`settingsPage`）；「高级」进的就是
// `InterfacePage`，架构加的「聊天界面」两选一在那里。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/account_state.dart';
import '../../state/bots_state.dart';
import '../account/account_page.dart';
import '../account/account_widgets.dart';
import '../common/list_page_row.dart';
import '../settings/index/settings_pages.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_page_scaffold.dart';
import 'im_strings.dart';

class ImMePage extends ConsumerWidget {
  const ImMePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final account = ref.watch(accountProvider);
    final host = ref.watch(dsBotProvider.select((s) => s.hostLabel));
    final profile = account.profile;
    final name = (profile?.displayName ?? '').trim();
    void open(SettingsPageId id) {
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => settingsPage(id)));
    }

    return ImPageScaffold(
      title: ImStrings.meTitle,
      child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        children: [
          Semantics(
            button: true,
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountPage())),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Row(
                  children: [
                    AccountAvatar(profile: profile, size: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? context.l10n.engineAccountDeepSeek : name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            host,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                          ),
                        ],
                      ),
                    ),
                    Icon(AppIcons.disclosure, size: 18, color: colors.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          ListPageRow(
            icon: AppIcons.companionInvite,
            title: ImStrings.meAboutAi,
            onTap: () => open(SettingsPageId.personalization),
          ),
          ListPageRow(
            icon: AppIcons.theme,
            title: ImStrings.meAppearance,
            onTap: () => open(SettingsPageId.appearance),
          ),
          ListPageRow(
            icon: AppIcons.providers,
            title: ImStrings.meServices,
            onTap: () => open(SettingsPageId.models),
          ),
          ListPageRow(
            icon: AppIcons.settings,
            title: ImStrings.meAdvanced,
            onTap: () => open(SettingsPageId.interface),
          ),
          ListPageRow(
            icon: AppIcons.info,
            title: ImStrings.meAbout,
            onTap: () => open(SettingsPageId.about),
          ),
          const SizedBox(height: 22),
          Text(
            ImStrings.meFooter,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
          ),
        ],
      ),
    );
  }
}
