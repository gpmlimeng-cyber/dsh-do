// 伙伴模板：首页推荐 6 个 + 「全部模板」页（分类 + 搜索 + 详情）。
//
// 数据来自构建期生成的常量（`im_partner_templates.g.dart`，源自 grok-bot-cn,
// MIT）；`available:false` 的条目只展示元数据，创建按钮禁用。模板只做「新建页
// 预填」，真正创建仍在 `NewBotPage` 里由用户点「完成」。

import 'package:dsh_client/dsh_client.dart' show DsBot;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart' show dsBotProvider;
import '../bots/new_bot_page.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../mascots/mascot_avatar.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'im_page_scaffold.dart';
import 'im_partner_templates.dart';
import 'im_strings.dart';

String templateName(PartnerTemplate template) =>
    AppLocale.isEnglish && template.nameEn.isNotEmpty ? template.nameEn : template.nameZh;

String categoryName(PartnerTemplate template) {
  final category = categoryOf(template);
  return AppLocale.isEnglish ? category.en : category.zh;
}

/// 「+」和空态的入口：Miffan 那种高抽屉——自己捏一个 + 推荐模板 + 查看全部。
///
/// 「已添加」按团队里已有同名 Bot（中文名或英文名，忽略大小写）判断，不新增字段。
Future<void> startPartnerFromTemplate(BuildContext context, WidgetRef ref) async {
  final choice = await showAppSheet<PartnerTemplateChoice>(
    context,
    heightFactor: 0.86,
    builder: (sheet) => SafeArea(
      top: false,
      child: Consumer(
        builder: (context, ref, _) {
          final theme = Theme.of(context);
          final colors = DshColors.of(context);
          final bots = ref.watch(dsBotProvider).team?.bots ?? const <DsBot>[];
          final names = {for (final bot in bots) bot.name.trim().toLowerCase()};
          bool added(PartnerTemplate template) =>
              names.contains(template.nameZh.toLowerCase()) ||
              (template.nameEn.isNotEmpty && names.contains(template.nameEn.toLowerCase()));
          return Column(
            children: [
              SheetTitleBar(ImStrings.addCompanion),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                  children: [
                    _BlankCard(onTap: () => Navigator.pop(sheet, const PartnerTemplateBlank())),
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        ImStrings.templateStart,
                        style: theme.textTheme.labelLarge?.copyWith(color: colors.textTertiary),
                      ),
                    ),
                    SheetGroup(
                      children: [
                        for (final template in featuredPartnerTemplates)
                          ListPageRow(
                            key: ValueKey('template-add-${template.id}'),
                            leading: MascotAvatar(spec: template.mascot, size: 40),
                            leadingWidth: 48,
                            title: templateName(template),
                            subtitle: template.tagline,
                            chevron: false,
                            trailing: added(template)
                                ? Text(
                                    ImStrings.templateAdded,
                                    style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                                  )
                                : FilledButton.tonal(
                                    onPressed: () => Navigator.pop(sheet, PartnerTemplateSelected(template)),
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      minimumSize: const Size(0, 34),
                                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(ImStrings.templateAdd, style: theme.textTheme.labelLarge),
                                  ),
                            onTap: added(template)
                                ? null
                                : () => Navigator.pop(sheet, PartnerTemplateSelected(template)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SheetGroup(
                      children: [
                        ListPageRow(
                          key: const ValueKey('template-see-all'),
                          icon: AppIcons.allFeatures,
                          title: ImStrings.templateSeeAll,
                          onTap: () => Navigator.pop(sheet, const PartnerTemplateBrowseAll()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case PartnerTemplateBlank():
      await Navigator.of(context).push(NewBotPage.route());
    case PartnerTemplateSelected(:final template):
      await Navigator.of(context).push(NewBotPage.route(template: template));
    case PartnerTemplateBrowseAll():
      await Navigator.of(context).push(ImPartnerTemplatesPage.route());
  }
  if (context.mounted) await ref.read(dsBotProvider.notifier).refresh();
}

/// 抽屉顶部的主色大卡：「自己捏一个伙伴」。
class _BlankCard extends StatelessWidget {
  const _BlankCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimary = theme.colorScheme.onPrimary;
    return Material(
      color: theme.colorScheme.primary,
      shape: RoundedSuperellipseBorder(borderRadius: AppShape.radiusLg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 16, 12, 16),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.18),
                ),
                child: Icon(AppIcons.add, color: onPrimary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ImStrings.blankCompanion,
                      style: theme.textTheme.titleMedium?.copyWith(color: onPrimary, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ImStrings.blankCompanionHint,
                      style: theme.textTheme.bodySmall?.copyWith(color: onPrimary.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Icon(AppIcons.disclosure, color: onPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// 选择结果：自己做 / 指定模板 / 去看全部。
sealed class PartnerTemplateChoice {
  const PartnerTemplateChoice();
}

class PartnerTemplateBlank extends PartnerTemplateChoice {
  const PartnerTemplateBlank();
}

class PartnerTemplateSelected extends PartnerTemplateChoice {
  const PartnerTemplateSelected(this.template);

  final PartnerTemplate template;
}

class PartnerTemplateBrowseAll extends PartnerTemplateChoice {
  const PartnerTemplateBrowseAll();
}

/// 全部模板：分类 Tab + 搜索 + 行，点行看详情。
class ImPartnerTemplatesPage extends StatefulWidget {
  const ImPartnerTemplatesPage({super.key});

  static Route<void> route() => MaterialPageRoute<void>(builder: (_) => const ImPartnerTemplatesPage());

  @override
  State<ImPartnerTemplatesPage> createState() => _ImPartnerTemplatesPageState();
}

class _ImPartnerTemplatesPageState extends State<ImPartnerTemplatesPage> {
  final _search = TextEditingController();
  String? _category;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final query = _search.text.trim().toLowerCase();
    final visible = [
      for (final template in partnerTemplates)
        if ((_category == null || template.category == _category) &&
            (query.isEmpty ||
                templateName(template).toLowerCase().contains(query) ||
                template.nameZh.contains(query) ||
                template.tagline.toLowerCase().contains(query)))
          template,
    ];
    return ImPageScaffold(
      title: ImStrings.templatesTitle,
      back: true,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('template-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: ImStrings.templateSearch,
                prefixIcon: const Icon(AppIcons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.onSurface.withValues(alpha: 0.05),
                border: const OutlineInputBorder(
                  borderRadius: AppShape.radiusLg,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Chip(label: ImStrings.templateAllCategory, selected: _category == null, onTap: () => setState(() => _category = null)),
                for (final category in partnerTemplateCategories)
                  _Chip(
                    label: AppLocale.isEnglish ? category.en : category.zh,
                    selected: _category == category.id,
                    onTap: () => setState(() => _category = category.id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: visible.isEmpty
                ? Center(child: Text(ImStrings.templateSearch, style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final template = visible[i];
                      return _TemplateRow(
                        template: template,
                        onTap: () => Navigator.of(context).push(ImPartnerTemplateDetailPage.route(template)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.of(context, AppMotion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: ShapeDecoration(
            color: selected ? theme.colorScheme.primary.withValues(alpha: 0.12) : theme.colorScheme.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: selected ? 1.4 : 0.8,
              ),
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: selected ? theme.colorScheme.primary : DshColors.of(context).textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateRow extends StatelessWidget {
  const _TemplateRow({required this.template, required this.onTap});

  final PartnerTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedSuperellipseBorder(borderRadius: AppShape.radiusMd),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              SizedBox.square(dimension: 40, child: MascotAvatar(spec: template.mascot, size: 40)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            templateName(template),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (!template.available) ...[
                          const SizedBox(width: 6),
                          Text(
                            ImStrings.templateComingSoon,
                            style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(categoryName(template), style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary)),
              const SizedBox(width: 2),
              Icon(AppIcons.disclosure, size: 16, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模板详情：它负责什么、工作方式与边界、来源，以及「用这个模板创建」。
class ImPartnerTemplateDetailPage extends StatelessWidget {
  const ImPartnerTemplateDetailPage({super.key, required this.template});

  final PartnerTemplate template;

  static Route<void> route(PartnerTemplate template) =>
      MaterialPageRoute<void>(builder: (_) => ImPartnerTemplateDetailPage(template: template));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    final source = template.source;
    return ImPageScaffold(
      title: templateName(template),
      back: true,
      child: Column(
        children: [
          Expanded(
            child: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                SizedBox.square(dimension: 64, child: MascotAvatar(spec: template.mascot, size: 64)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(template.tagline, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 4),
                      Text(
                        categoryName(template),
                        style: theme.textTheme.labelSmall?.copyWith(color: colors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Section(
            title: ImStrings.templateResponsible,
            body: template.role.isEmpty ? template.tagline : template.role,
          ),
          if (template.instructions.isNotEmpty) _Section(title: ImStrings.templateHow, body: template.instructions),
          _Section(
            title: ImStrings.templateSource,
            body: '${source.name} · ${source.license}\n${source.url}',
          ),
        ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('template-create'),
                onPressed: template.available
                    ? () => Navigator.of(context).push(NewBotPage.route(template: template))
                    : null,
                child: Text(template.available ? ImStrings.templateUse : ImStrings.templateComingSoon),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = DshColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: colors.textTertiary, height: 1.45)),
        ],
      ),
    );
  }
}
