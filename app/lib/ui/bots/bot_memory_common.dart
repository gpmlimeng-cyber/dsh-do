// A Bot's or a group's memory, shared by the details card and the full page:
// the entry editor, the scope wording, and how a change reaches the host.

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/bots_state.dart';
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../theme/app_icons.dart';
import 'bot_action_scope.dart';
import 'bot_sheets.dart';

/// Entries longer than DS Bot keeps are refused there; the field stops here.
const memoryEntryMax = 300;

/// How many entries the details card shows; the rest live on the full page.
const memoryCardLimit = 8;

IconData memoryScopeIcon(String scope) => switch (scope) {
  'team' => AppIcons.team,
  'group' => AppIcons.groupChat,
  _ => AppIcons.bookmark,
};

/// Whether the person wrote this: the host says so with `by: user`, or with a
/// source only the person's own tools have (the memory panel).
bool _byYou(DsBotMemoryEntry entry) => entry.by == 'user' || entry.source == 'memory panel';

/// 「团队 · 你写的 · 2026-10-24」.
String memoryEntryMeta(DsBotMemoryEntry entry) => [
  switch (entry.scope) {
    'team' => appL10n.botsTeam,
    'group' => appL10n.botsGroupChat,
    _ => appL10n.botsSelf,
  },
  if (_byYou(entry)) appL10n.botsWrittenByYou else if (entry.by case final by? when by.isNotEmpty) by,
  ?entry.added,
].join(' · ');

/// 「你写的 · 2026-10-24 · 对话#12」: no scope, the section header already says it.
String memoryEntryDetail(DsBotMemoryEntry entry) => [
  if (_byYou(entry)) appL10n.botsWrittenByYou else if (entry.by case final by? when by.isNotEmpty) by,
  ?entry.added,
  // 「你写的」 already covers the panel's own source.
  if (entry.source case final source? when source.isNotEmpty && source != 'memory panel') source,
].join(' · ');

/// Runs a memory change and reloads the entries on both surfaces.
Future<void> runMemoryChange(
  BuildContext context,
  WidgetRef ref,
  BotActionScope scope,
  Future<void> Function(DsBotApi api) call, {
  required String? botId,
  required String? roomId,
}) async {
  if (!context.mounted || !scope.current(context, ref)) return;
  final api = scope.api!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await call(api);
  } catch (error) {
    if (context.mounted && scope.current(context, ref)) {
      messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
    }
  }
  if (context.mounted && scope.current(context, ref)) {
    ref.invalidate(dsBotMemoryProvider((botId: botId, roomId: roomId)));
  }
}

/// Opens one entry: edit or delete, then runs the change.
Future<void> openMemoryEntry(
  BuildContext context,
  WidgetRef ref, {
  required String? botId,
  required String? roomId,
  required DsBotMemoryEntry entry,
  required bool canEdit,
}) async {
  final scope = BotActionScope(ref, botId: botId, roomId: roomId);
  final action = await showAppSheet<String>(
    context,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitleBar(context.l10n.botsMemory),
          Padding(
            padding: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
            child: Text(entry.text, style: Theme.of(sheet).textTheme.bodyLarge),
          ),
          SheetGroup(
            children: [
              if (canEdit)
                ListPageRow(
                  icon: AppIcons.edit,
                  title: context.l10n.commonEdit,
                  onTap: () => Navigator.pop(sheet, 'edit'),
                ),
              ListPageRow(
                icon: AppIcons.delete,
                title: context.l10n.commonDelete,
                danger: true,
                chevron: false,
                onTap: () => Navigator.pop(sheet, 'delete'),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    ),
  );
  if (!context.mounted || !scope.current(context, ref) || action == null) return;
  if (action == 'delete') {
    await runMemoryChange(
      context,
      ref,
      scope,
      (api) => api.forgetMemory(entry, botId: botId, roomId: roomId),
      botId: botId,
      roomId: roomId,
    );
    return;
  }
  final next = await showTextEditSheet(
    context,
    title: context.l10n.botsEditMemory,
    initial: entry.text,
    maxLength: memoryEntryMax,
    multiline: true,
  );
  if (next == null || next == entry.text || !context.mounted) return;
  await runMemoryChange(
    context,
    ref,
    scope,
    (api) => api.editMemory(entry, next, botId: botId, roomId: roomId),
    botId: botId,
    roomId: roomId,
  );
}

/// 「添加记忆」.
Future<void> addMemoryEntry(
  BuildContext context,
  WidgetRef ref, {
  required String? botId,
  required String? roomId,
}) async {
  final scope = BotActionScope(ref, botId: botId, roomId: roomId);
  final text = await showTextEditSheet(
    context,
    title: context.l10n.botsAddMemory,
    hint: roomId == null ? context.l10n.botsMemoryReplyExample : context.l10n.botsMemoryDraftExample,
    maxLength: memoryEntryMax,
    multiline: true,
    action: context.l10n.commonAdd,
  );
  if (text == null || !context.mounted) return;
  await runMemoryChange(
    context,
    ref,
    scope,
    (api) => api.addMemory(text, botId: botId, roomId: roomId),
    botId: botId,
    roomId: roomId,
  );
}
