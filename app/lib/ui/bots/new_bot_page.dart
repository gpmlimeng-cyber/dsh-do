// 新建 Bot = 新建伙伴：先看脸，再起名。
//
// 从上到下：预览（大头像 + 「角色 · 颜色 · 动作」标签 + 换个样子/随机换一个）
// → 叫什么 → 一句话它是做什么的 → 它是什么样的（性格多选）→ 还想补充什么
// → 模型（仅专业模式）→ 完成。
//
// 外观存本机（`state/bot_avatar_state.dart`），不动宿主协议；颜色另按宿主认的
// 色名写进 `bot.color`。性格标签不新增宿主字段，拼进 `instructions`。
import 'dart:convert';
import 'dart:math' as math;

import 'package:dsh_client/dsh_client.dart' hide SettingsSection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bot_avatar_state.dart';
import '../../state/bots_state.dart';
import '../../state/im_mode_state.dart' show interfaceModeProvider;
import '../../state/settings_state.dart' show settingsProvider;
import '../chat/model_sheet.dart';
import '../common/discard_guard.dart';
import '../common/list_page_row.dart';
import '../mascots/mascot_avatar.dart';
import '../mascots/mascot_customizer.dart' show openMascotCustomizer;
import '../im/im_partner_templates.dart' show PartnerTemplate;
import '../providers/provider_widgets.dart' show FormBottomBar, FormFieldBlock, FormFieldGroup;
import '../settings/settings_widgets.dart' show SettingsSection;
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_chat_page.dart';
import 'bot_details_page.dart' show effortName, shortModel;
import 'bot_format.dart';
import 'bot_creation_scope.dart';

/// 8 个性格标签（产品口径，照 Miffan 原文的八条；不预选）。
const botTraitsZh = ['温柔耐心', '直接高效', '幽默', '爱追问', '专业严谨', '话少', '鼓励型', '有点毒舌'];
const botTraitsEn = ['Patient', 'Direct', 'Humorous', 'Curious', 'Rigorous', 'Quiet', 'Encouraging', 'A bit sharp'];

String _t(String zh, String en) => AppLocale.current.languageCode == 'zh' ? zh : en;

class NewBotPage extends ConsumerStatefulWidget {
  const NewBotPage({super.key, this.initialName, this.template});

  /// A name typed in 新建's search field: the page opens with it filled in.
  final String? initialName;

  /// 模板：进页时把名字/角色/说明/形象预填好；`instructions` 原样透传，
  /// 不走「性格 + 补充」合成（模板自带完整 prompt）。
  final PartnerTemplate? template;

  static Route<void> route({String? initialName, PartnerTemplate? template}) =>
      MaterialPageRoute<void>(builder: (_) => NewBotPage(initialName: initialName, template: template));

  @override
  ConsumerState<NewBotPage> createState() => _NewBotPageState();
}

/// What a new Bot is told about 可视化回复, when that setting is on.
String? newBotInstructions(String typed, {required bool visualReplies}) {
  final text = typed.trim();
  if (!visualReplies || text.toLowerCase().contains('dsh-ui')) return text.isEmpty ? null : text;
  final hint = AppLocale.isEnglish
      ? 'When a chart or card explains it better, answer with a ```dsh-ui fence '
            '(JSON following the dsh-ui spec) instead of a plain paragraph.'
      : '适合用图表或卡片说明时，用 ```dsh-ui 围栏呈现（JSON 按 dsh-ui 规范），不要只写一段文字。';
  return text.isEmpty ? hint : '$text\n\n$hint';
}

class _NewBotPageState extends ConsumerState<NewBotPage> {
  late final _name = TextEditingController(text: _templateName ?? widget.initialName ?? '');

  /// 模板名跟随界面语言；英文名缺失（即将支持的条目）时用中文名。
  String? get _templateName {
    final template = widget.template;
    if (template == null) return null;
    return AppLocale.isEnglish && template.nameEn.isNotEmpty ? template.nameEn : template.nameZh;
  }
  late final _role = TextEditingController(text: widget.template?.role ?? '');
  late final _instructions = TextEditingController(text: widget.template?.instructions ?? '');
  final _random = math.Random();

  /// 外观：模板带自己的形象；手填就随机一个。
  late MascotSpec _spec = widget.template?.mascot ?? MascotSpec.random(_random);

  /// 选中的性格（不预选）。
  final _traits = <int>{};

  ModelSelection? _model;
  bool _saving = false;
  BotCreationScope? _scope;

  late final Listenable _edits = Listenable.merge([_name, _role, _instructions]);
  late String _clean;

  String get _hostColor => hostColorOf(_spec);

  String _signature() => jsonEncode([
    _name.text,
    _role.text,
    _instructions.text,
    _spec.toJson(),
    _traits.toList()..sort(),
    _model?.provider,
    _model?.model,
    _model?.reasoningEffort,
  ]);

  @override
  void initState() {
    super.initState();
    _clean = _signature();
  }

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _instructions.dispose();
    super.dispose();
  }

  bool _visualRepliesOn() {
    final settings = ref.read(settingsProvider);
    return settings.loaded && settings.visualReplies;
  }

  ModelSelection? _effectiveModel(DsBotTeam? team) {
    if (_model != null) return _model;
    final ref = team?.defaultModel;
    final slash = ref?.indexOf('/') ?? -1;
    if (ref == null || slash <= 0) return null;
    return ModelSelection(provider: ref.substring(0, slash), model: ref.substring(slash + 1));
  }

  /// 性格 + 补充合成 instructions（性格不新增宿主字段；原有 dsh-ui 提示照旧最后追加）。
  /// 模板模式例外：模板的 prompt 原样发出，不合成、不追加。
  String? _instructionsText() {
    if (widget.template != null) {
      final typed = _instructions.text.trim();
      return typed.isEmpty ? null : typed;
    }
    final traits = [for (final i in _traits.toList()..sort()) (AppLocale.isEnglish ? botTraitsEn : botTraitsZh)[i]];
    final typed = _instructions.text.trim();
    final parts = [
      if (traits.isNotEmpty) '${_t('你的性格', 'Your personality')}：${traits.join('、')}。',
      if (typed.isNotEmpty) typed,
    ];
    return newBotInstructions(parts.join('\n'), visualReplies: _visualRepliesOn());
  }

  Future<void> _customize() async {
    final choice = await openMascotCustomizer(context, initial: _spec);
    if (choice == null || !mounted) return;
    setState(() => _spec = choice.spec);
  }

  void _randomize() {
    // Miffan 规则：角色和颜色必换、动作随机；五官不动。
    setState(() => _spec = MascotSpec.randomDifferent(_spec, _random));
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final scope = _scope;
    if (_saving || scope == null || !scope.writable(ref)) return;
    final hub = ref.read(dsBotProvider.notifier);
    final api = scope.api;
    final model = _effectiveModel(ref.read(dsBotProvider).team);
    setState(() => _saving = true);
    try {
      final bot = await api.createBot(
        name: name,
        role: _role.text.trim().isEmpty ? null : _role.text.trim(),
        instructions: _instructionsText(),
        color: _hostColor,
        model: model == null ? null : '${model.provider}/${model.model}',
        effort: model?.reasoningEffort,
      );
      // 头像只存本机：创建成功拿到 id 再写。
      await ref
          .read(botAvatarProvider.notifier)
          .set(bot.id, BotAvatarConfig.mascot(_spec));
      if (!mounted || !scope.connected(ref)) return;
      await hub.refresh();
      if (!mounted || !scope.connected(ref)) return;
      await Navigator.of(context).pushReplacement(BotChatPage.route(bot.id));
    } catch (error) {
      if (!mounted || !scope.connected(ref)) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final light = ref.watch(interfaceModeProvider.select((mode) => mode.light));
    _scope ??= BotCreationScope.capture(ref);
    final changed = _scope != null && !_scope!.connected(ref);
    final saving = _saving && !changed;
    final model = _effectiveModel(status.team);
    final scheme = Theme.of(context).colorScheme;
    final name = _name.text.trim();
    final canCreate = name.isNotEmpty && !saving && _scope != null && _scope!.writable(ref);
    final traits = AppLocale.isEnglish ? botTraitsEn : botTraitsZh;

    final page = AppPage.list(
      title: l10n.botsNewBot,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              child: Column(
                children: [
                  GestureDetector(
                    key: const ValueKey('bot-avatar-preview'),
                    onTap: _customize,
                    child: MascotAvatar(spec: _spec, size: 112, animate: true),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _spec.caption,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        key: const ValueKey('bot-avatar-customize'),
                        onPressed: _customize,
                        child: Text(_t('换个样子', 'Change')),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        key: const ValueKey('bot-avatar-random'),
                        onPressed: _randomize,
                        icon: const Icon(AppIcons.refresh, size: 18),
                        label: Text(_t('随机换一个', 'Random')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SettingsSection(
              title: _t('它是谁', 'Who it is'),
              children: [
                FormFieldGroup(
                  children: [
                    FormFieldBlock(
                      label: _t('叫什么', 'Name'),
                      child: TextField(
                        key: const ValueKey('bot-name'),
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [LengthLimitingTextInputFormatter(40)],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(hintText: l10n.botsWriterExample),
                      ),
                    ),
                    FormFieldBlock(
                      label: _t('一句话它是做什么的', 'What it does, in one line'),
                      child: TextField(
                        key: const ValueKey('bot-role'),
                        controller: _role,
                        textInputAction: TextInputAction.next,
                        inputFormatters: [LengthLimitingTextInputFormatter(24)],
                        decoration: InputDecoration(hintText: l10n.botsRoleHint),
                      ),
                    ),
                    FormFieldBlock(
                      label: _t('它是什么样的？可以多选', 'What is it like? Pick any'),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (var i = 0; i < traits.length; i++)
                              FilterChip(
                                key: ValueKey('bot-trait-$i'),
                                label: Text(traits[i]),
                                selected: _traits.contains(i),
                                onSelected: (on) => setState(() => on ? _traits.add(i) : _traits.remove(i)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    FormFieldBlock(
                      label: _t('还想补充什么（选填）', 'Anything else? (optional)'),
                      child: TextField(
                        key: const ValueKey('bot-instructions'),
                        controller: _instructions,
                        minLines: 3,
                        maxLines: 8,
                        decoration: InputDecoration(hintText: l10n.botsNewInstructionsHint),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // 模型只在专业模式出现：轻松模式用宿主默认，不露模型名。
            if (!light)
              SettingsSection(
                title: l10n.botsModel,
                children: [
                  ListPageRow(
                    icon: AppIcons.model,
                    title: l10n.botsModel,
                    value: model == null
                        ? l10n.botsChooseModel
                        : [
                            shortModel(modelLabel('${model.provider}/${model.model}', status.team?.models ?? const [])),
                            if (model.reasoningEffort case final e?) effortName(e),
                          ].join(' · '),
                    onTap: () => showModelSheet(
                      context,
                      current: model,
                      onSelected: (selection) => setState(() => _model = selection),
                    ),
                  ),
                ],
              ),
            if (changed) Text(l10n.botsCreationConnectionChanged, style: TextStyle(color: scheme.error)),
            const SizedBox(height: FormBottomBar.height),
          ],
        ),
      ],
    );
    return DiscardGuard(
      listenable: _edits,
      isDirty: () => !saving && _signature() != _clean,
      child: Stack(
        children: [
          page,
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.viewInsetsOf(context).bottom,
            child: FormBottomBar(
              child: FilledButton(
                key: const ValueKey('bot-create'),
                onPressed: canCreate ? _create : null,
                child: saving
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                          ),
                          const SizedBox(width: 10),
                          Text(l10n.botsCreating),
                        ],
                      )
                    : Text(_t('完成', 'Done')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// l10n:keep-end
