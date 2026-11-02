// A Bot's own chat: the whole conversation across its parts as DS Bot lays
// it out, the reply it is writing, its cards (a question, a view, a model to
// pick, a DSH approval) and the chat's composer.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/settings_state.dart';
import '../../state/attachments.dart';
import '../../state/bots_state.dart';
import '../../state/connection_state.dart';
import '../chat/composer.dart';
import '../../state/voice_model_state.dart';
import '../../state/voice_state.dart';
import '../../state/chat_state.dart' show SendMode;
import '../chat/voice/voice_controller.dart';
import '../chat/widgets/attachments.dart';
import '../chat/widgets/quote_chip.dart' show ComposerTrayStack, QuoteChip;
import '../chat/model_sheet.dart';
import '../chat/widgets/approval_card.dart';
import '../common/status_dot.dart';
import '../session/session_detail_page.dart';
import '../common/typing_indicator.dart';
import '../features/feature_kit.dart';
import '../shell/page_frame.dart';
import 'bot_stop_guard.dart';
import 'bot_action_scope.dart';
import '../shell/drawer/drawer_open_request.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_attachments.dart';
import 'bot_composer_deck.dart';
import 'bot_draft_send.dart';
import 'bot_avatar.dart';
import 'unavailable_message.dart';
import 'bot_chat_kit.dart';
import 'bot_details_page.dart';
import 'bot_format.dart';
import 'bot_pending_card.dart';

class BotChatPage extends ConsumerStatefulWidget {
  const BotChatPage({super.key, required this.botId});

  final String botId;

  static Route<void> route(String botId) => MaterialPageRoute<void>(builder: (_) => BotChatPage(botId: botId));

  @override
  ConsumerState<BotChatPage> createState() => _BotChatPageState();
}

class _BotChatPageState extends ConsumerState<BotChatPage> {
  late final BotStopGuard _stopGuard;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scrolled = ValueNotifier(0.0);
  late final DsBotViewingController _viewing;
  /// Picked but unsent: shown above the composer, cleared when the send lands.
  List<DraftAttachment> _drafts = const [];
  /// 引用 for the next message only; the host builds the quoted body.
  String? _quote;
  late final VoiceInputController _voice;
  late final VoiceInputActiveController _voiceFlag;

  @override
  void initState() {
    super.initState();
    _stopGuard = BotStopGuard(ref);
    _voice = createBotVoice(ref, _input, alive: () => mounted);
    // Other surfaces read this flag to keep dictation and speech apart.
    _voiceFlag = ref.read(voiceInputActiveProvider.notifier);
    _voice.addListener(_reportVoice);
    // A download or deletion changes capabilities without replacing the host.
    ref.listenManual(voiceModelProvider.select((s) => s.status == VoiceModelStatus.ready), (_, _) {
      if (mounted && (ref.read(activeConnectionProvider).value?.isLocal ?? false)) {
        unawaited(_voice.refreshAfterModelChange());
      }
    });
    _viewing = ref.read(dsBotViewingProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewing.set(widget.botId);
    });
  }

  void _reportVoice() => _voiceFlag.set(_voice.active);

  @override
  void dispose() {
    _voice.removeListener(_reportVoice);
    _voice.dispose();
    // The page is gone, and its dictation with it.
    final flag = _voiceFlag;
    scheduleMicrotask(() => flag.set(false));
    _stopGuard.dispose();
    _viewing.leave(widget.botId);
    _input.dispose();
    _focus.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  Future<void> _send(BotActionScope target, String part, {SendMode mode = SendMode.queue}) async {
    if (!mounted || target.botId != widget.botId || !target.current(context, ref)) return;
    final status = ref.read(dsBotProvider);
    if (!status.ready || status.team?.bot(widget.botId)?.sessionId != part) return;
    final attachments = _drafts;
    final quote = _quote;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await sendBotDraft(
      context,
      ref,
      _input,
      botId: widget.botId,
      hasAttachments: attachments.isNotEmpty,
      send: (text) async {
        final controller = ref.read(botChatProvider(widget.botId).notifier);
        if (attachments.isEmpty) {
          final sent = await controller.send(text, mode: botSendMode(mode), quote: quote);
          if (sent && mounted) setState(() => _quote = null);
          return sent;
        }
        final client = ref.read(activeConnectionProvider).value?.client;
        if (client == null) return false;
        try {
          final staged = await stageBotAttachments(client, part, attachments);
          final sent = await controller.send(
            text,
            images: staged.images,
            fileReceiptIds: staged.receipts,
            mode: botSendMode(mode),
            quote: quote,
          );
          if (sent && mounted) {
            setState(() {
              _drafts = const [];
              _quote = null;
            });
          }
          return sent;
        } catch (error) {
          if (mounted) messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
          return false;
        }
      },
    );
  }

  /// 长按发送键: while a turn runs, choose how the message reaches it; otherwise
  /// send at once.
  Future<void> _sendOptions(BotActionScope target, DsBot bot, {required bool running}) async {
    if (!running) return _send(target, bot.sessionId);
    final mode = await showBotSendOptions(context);
    if (!mounted || mode == null) return;
    await runBotSend(
      mode,
      stop: () => _stopGuard.action(botId: bot.id)(),
      send: (mode) => _send(target, bot.sessionId, mode: mode),
    );
  }

  void _setQuote(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() => _quote = trimmed.length > 2000 ? trimmed.substring(0, 2000) : trimmed);
  }

  /// Opens the ＋ panel; the pick joins the tray above the composer.
  Future<void> _attach() async {
    final sessionId = ref.read(dsBotProvider).team?.bot(widget.botId)?.sessionId;
    if (sessionId == null) return;
    final room = maxAttachments - _drafts.length;
    if (room <= 0) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.chatAttachmentLimit(maxAttachments))),
      );
      return;
    }
    final client = ref.read(activeConnectionProvider).value?.client;
    final picked = await pickBotAttachments(
      context,
      ref,
      files: client?.supportsEndpoint('fileUploads/upload') ?? true,
      limit: room,
      // 本对话 (permissions, plan mode) acts on the session behind this Bot.
      sessionId: sessionId,
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() => _drafts = [..._drafts, ...picked]);
  }

  Future<void> _pickModel(DsBot bot, BotActionScope scope) => pickBotModel(context, ref, bot, scope: scope);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final team = status.team;
    final bot = team?.bot(widget.botId);
    final mobileUnavailable =
        status.availability == DsBotAvailability.missing || status.availability == DsBotAvailability.outdated;
    if (team == null || bot == null || mobileUnavailable) {
      return AppPage.list(
        title: 'Bot',
        children: [
          DsBotUnavailableMessage(status: status, goneIcon: AppIcons.bot, goneTitle: l10n.botsBotGone),
        ],
      );
    }
    final chat = ref.watch(botChatProvider(widget.botId));
    final work = status.live.bots[bot.id];
    final ownTurn = work != null && work.roomId == null;
    final question = team.questionOf(bot);
    final view = team.viewOf(bot);
    final api = ref.read(dsBotProvider.notifier).api;
    final (String label, StatusTone tone) = switch (()) {
      _ when question != null || view != null => (l10n.commonWaitingAnswer, StatusTone.warn),
      _ when bot.waiting => (l10n.botsWaitingModel, StatusTone.warn),
      _ when work != null => (
        [
          workPhrase(work, activity: status.live.activity[bot.id]) ?? l10n.botsThinking,
          ?team.room(work.roomId)?.name,
        ].join(' · '),
        StatusTone.busy,
      ),
      _ => (bot.role.isEmpty ? (team.isMain(bot.id) ? l10n.botsMainBot : l10n.botsIdle) : bot.role, StatusTone.ok),
    };
    // Consecutive tool calls fold into one row, so a busy turn does not fill
    // the transcript with them.
    final rows = groupToolRows(
      transcriptRows(chat.items, pending: chat.pending, streaming: ownTurn ? chat.streaming : null),
    );
    final topInset = BotChatHeader.heightOf(context);
    final rooms = {for (final room in team.rooms) room.id: room.name};
    final readOnly = status.readOnly != null;
    final modelScope = BotActionScope(ref, botId: bot.id);
    final sendTarget = BotActionScope(ref, botId: bot.id);

    return BotChatFrame(
      header: BotChatHeader(
        face: BotAvatar(bot: bot, size: BotChatHeader.faceSize),
        title: bot.name,
        status: label,
        tone: tone,
        scrolledUnder: _scrolled,
        onLeading: () => openDrawerOverShell(context, ref),
        // The title capsule opens the Bot's own details; the key on the right
        // opens the conversation's (trajectory, files, progress).
        onDetails: () => Navigator.of(context).push(BotDetailsPage.route(bot.id)),
        onInfo: () => SessionDetailPage.open(context, bot.sessionId),
        // The chat page's own chip: same height, padding, chevron and type.
        chip: ModelChip(
          selection: botModelSelection(bot),
          grouped: true,
          onSelected: (selection) => applyBotModel(context, ref, bot, selection, scope: modelScope),
        ),
      ),
      body: chat.loading && chat.items.isEmpty
          ? Padding(
              padding: EdgeInsets.only(top: topInset),
              child: const QuietSpinner(),
            )
          : BotTranscript(
              rows: rows,
              topInset: topInset,
              scrolledUnder: _scrolled,
              hasEarlier: chat.hasEarlier,
              loadingEarlier: chat.loadingEarlier,
              onEarlier: () => ref.read(botChatProvider(widget.botId).notifier).loadEarlier(),
              empty: _Intro(bot: bot),
              rowBuilder: (context, row) => Padding(
                padding: rowPadding(row),
                child: switch (row) {
                  BotTimeRow(:final time) => BotTimeLine(time),
                  BotPendingRow(:final pending) => BotUserMessage(text: pending.text, pending: true),
                  BotStreamingRow(:final text) =>
                    text.isEmpty
                        ? const Align(alignment: Alignment.centerLeft, child: _Thinking())
                        : BotReplyText(text: text, streaming: true),
                  BotTypingRow() => const SizedBox.shrink(),
                  BotToolGroupRow(:final items) => BotToolGroup(
                    // A stable key: paging in older rows must not hand this
                    // group's open state to the one that lands on its index.
                    key: ValueKey('tool-group-${items.first.callId ?? items.first.toolName}'),
                    items: items,
                  ),
                  BotItemRow(:final item) => switch (item.kind) {
                    DsBotItemKind.user => BotUserMessage(
                      text: item.text,
                      images: item.images,
                      attachments: botLineAttachments(item, chat.sessionId),
                      onQuote: _setQuote,
                    ),
                    DsBotItemKind.bot => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // A Bot's own attachments draw like the person's do;
                        // the pictures among them open full screen already.
                        if (botLineAttachments(item, chat.sessionId) case final shown?) ...[
                          shown,
                          const SizedBox(height: 6),
                        ],
                        BotReplyText(text: item.text, onQuote: _setQuote),
                      ],
                    ),
                    DsBotItemKind.event => BotEventLine(
                      text: chatEventText(item, roomName: rooms[item.roomId]),
                      icon: AppIcons.swap,
                    ),
                    DsBotItemKind.answer => BotEventLine(text: l10n.botsAnsweredQuestion, icon: AppIcons.done),
                    DsBotItemKind.divider => BotEventLine(text: l10n.botsEarlierMessages, icon: AppIcons.history),
                    DsBotItemKind.tool => BotToolRow(name: item.toolName ?? '', status: item.toolStatus),
                    DsBotItemKind.unknown => const SizedBox.shrink(),
                  },
                },
              ),
            ),
      bottom: [
        if (bot.waiting && !readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BotModelCard(name: bot.name, onPick: () => _pickModel(bot, modelScope)),
          ),
        if ((question != null || view != null) && api != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BotPendingCard(
              key: ValueKey((
                status.host,
                status.hello?.boot,
                api,
                bot.id,
                bot.sessionId,
                question != null,
                question?.id ?? view?.id,
              )),
              api: api,
              origin: status,
              bot: bot,
              question: question,
              view: view,
            ),
          ),
        _OwnApprovals(sessionId: bot.sessionId),
        BotErrorSlot(
          error: chat.error,
          onDismiss: () => ref.read(botChatProvider(widget.botId).notifier).dismissError(),
        ),
        BotComposerDeck(sessionId: bot.sessionId, running: ownTurn),
        Composer(
          hardwareEnterSends: ref.watch(settingsProvider.select((s) => s.hardwareEnterSends)),
          controller: _input,
          focusNode: _focus,
          connected: api != null && !readOnly,
          voice: _voice,
          accessory: BotContextRing(sessionId: bot.sessionId, model: botModelSelection(bot)),
          waiting: question != null || view != null,
          waitHint: question != null ? l10n.commonWaitingAnswer : null,
          // A host that speaks API 2 is the one that takes attachments on `send`.
          leading: (status.hello?.api ?? 0) >= 2
              ? AttachButton(key: const ValueKey('attach-key'), onPressed: api == null || readOnly ? null : _attach)
              : null,
          tray: ComposerTrayStack.maybe(
            quote: _quote == null ? null : QuoteChip(quote: _quote!, onRemove: () => setState(() => _quote = null)),
            attachments: _drafts.isEmpty
                ? null
                : ComposerTray(
                    items: _drafts,
                    onRemove: (gone) => setState(() => _drafts = [for (final draft in _drafts) if (draft != gone) draft]),
                  ),
          ),
          hasAttachments: _drafts.isNotEmpty,
          running: ownTurn,
          onSend: () => _send(sendTarget, bot.sessionId),
          onSendOptions: () => _sendOptions(sendTarget, bot, running: ownTurn),
          onStop: _stopGuard.action(botId: bot.id),
          placeholder: l10n.botsComposerHint(bot.name),
        ),
      ],
    );
  }
}

/// Picks [bot]'s model in the chat's model sheet and saves it.
Future<void> pickBotModel(BuildContext context, WidgetRef ref, DsBot bot, {BotActionScope? scope}) {
  final target = scope ?? BotActionScope(ref, botId: bot.id);
  if (!target.current(context, ref)) return Future.value();
  final hub = ref.read(dsBotProvider.notifier);
  final api = target.api;
  bool current() => target.current(context, ref);

  if (!current()) return Future.value();
  return showModelSheet(
    context,
    current: botModelSelection(bot),
    onSelected: (selection) => applyBotModel(context, ref, bot, selection, scope: scope),
  );
}

/// Saves [selection] on [bot]. The header's model chip opens the same sheet
/// itself, so the write lives here rather than inside the sheet's callback.
Future<void> applyBotModel(
  BuildContext context,
  WidgetRef ref,
  DsBot bot,
  ModelSelection selection, {
  BotActionScope? scope,
}) async {
  final target = scope ?? BotActionScope(ref, botId: bot.id);
  if (!target.current(context, ref)) return;
  final hub = ref.read(dsBotProvider.notifier);
  final api = target.api;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // A sheet can outlive a host switch, reconnect, or removal of this Bot.
  // Check before any write; never redirect an old choice through hub.api.
  if (!target.current(context, ref)) return;
  try {
    await api!.updateBot(
      bot.id,
      model: '${selection.provider}/${selection.model}',
      // A model without levels clears the previous Bot override.
      // Omission means "keep" to DS Bot, not "use the default".
      effort: selection.reasoningEffort ?? '',
    );
    if (target.current(context, ref)) await hub.refresh();
  } catch (error) {
    if (target.current(context, ref)) messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
  }
}

/// A Bot's model as the model sheet names it.
ModelSelection? botModelSelection(DsBot bot) {
  final ref = bot.modelRef;
  if (ref == null) return null;
  final slash = ref.indexOf('/');
  if (slash <= 0) return null;
  return ModelSelection(
    provider: ref.substring(0, slash),
    model: ref.substring(slash + 1),
    reasoningEffort: bot.effort,
  );
}

class _Thinking extends StatelessWidget {
  const _Thinking();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: SizedBox(height: 14, child: TypingIndicator(color: DshColors.of(context).textTertiary)),
  );
}

/// The empty chat: the Bot's face, name and role.
class _Intro extends StatelessWidget {
  const _Intro({required this.bot});

  final DsBot bot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BotAvatar(bot: bot, size: 64),
        const SizedBox(height: 12),
        Text(bot.name, style: theme.textTheme.titleLarge),
        if (bot.role.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(bot.role, style: theme.textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary)),
        ],
      ],
    );
  }
}

/// DSH's own approval requests in the Bot's chat (a member's in a group are
/// answered in the group's details).
class _OwnApprovals extends ConsumerStatefulWidget {
  const _OwnApprovals({required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<_OwnApprovals> createState() => _OwnApprovalsState();
}

class _OwnApprovalsState extends ConsumerState<_OwnApprovals> {
  StreamSubscription<HostEvent>? _sub;
  DshClient? _client;
  List<ApprovalRequest> _requests = const [];

  void _attach(DshClient? client) {
    if (identical(client, _client)) return;
    unawaited(_sub?.cancel());
    _client = client;
    _sub = client?.hostEvents.listen((_) => _read());
    _read();
  }

  void _read() {
    final client = _client;
    final next = [
      for (final event in client?.mux.pendingRequests ?? const <HostEvent>[])
        if (event is ApprovalRequestedEvent && event.request.sessionId == widget.sessionId) event.request,
    ];
    if (!mounted) return;
    if (next.length != _requests.length || !next.every((r) => _requests.any((o) => o.eventId == r.eventId))) {
      setState(() => _requests = next);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _attach(ref.watch(activeConnectionProvider.select((c) => c.value?.client)));
    final client = _client;
    if (_requests.isEmpty || client == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final request in _requests)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ApprovalCard(
              key: ValueKey(request.eventId),
              request: request,
              onRespond: (request, decision) async {
                await client.respondApproval(request, decision);
                _read();
              },
            ),
          ),
      ],
    );
  }
}
