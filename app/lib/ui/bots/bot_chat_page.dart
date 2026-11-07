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
import '../../state/adaptive_layout_state.dart';
import '../../state/bots_state.dart';
import '../../state/last_conversation.dart';
import '../common/brief_notice.dart';
import 'bot_adaptive_frame.dart';
import '../../runtime/runtime_bridge.dart' show RuntimePhase;
import '../../runtime/runtime_state.dart' show localRuntimeProvider;
import '../../state/connection_state.dart';
import '../../state/artifacts.dart' show sessionArtifactsProvider;
import '../chat/chat_text_scale.dart';
import '../chat/composer.dart';
import '../chat/widgets/artifact_card.dart';
import '../../state/voice_model_state.dart';
import '../../state/voice_state.dart';
import '../../state/chat_state.dart' show SendMode, chatProvider;
import '../../state/room_message_mode.dart' show withoutDoneEchoes;
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
import '../shell/drawer/drawer_destination.dart';
import '../shell/session_drawer_host.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_attachment_open.dart';
import 'bot_attachments.dart';
import 'bot_composer_deck.dart';
import 'bot_draft_send.dart';
import 'bot_avatar.dart';
import 'unavailable_message.dart';
import 'bot_chat_kit.dart';
import 'bot_links.dart' show openLinkedFile;
import 'bot_details_page.dart';
import 'bot_memory_notice.dart';
import 'bot_memory_page.dart';
import 'bot_format.dart';
import 'bot_pending_card.dart';

class BotChatPage extends ConsumerStatefulWidget {
  const BotChatPage({super.key, required this.botId});

  final String botId;

  static Route<void> route(String botId) => MaterialPageRoute<void>(builder: (_) => BotChatPage(botId: botId));

  @override
  ConsumerState<BotChatPage> createState() => _BotChatPageState();
}

class _BotChatPageState extends ConsumerState<BotChatPage> with WidgetsBindingObserver, TickerProviderStateMixin {
  late final BotStopGuard _stopGuard;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scrolled = ValueNotifier(0.0);
  late final DsBotViewingController _viewing;
  /// This page's own drawer: it opens over the chat instead of leaving it.
  late final SessionDrawerController _drawer = SessionDrawerController(vsync: this);
  /// Picked but unsent: shown above the composer, cleared when the send lands.
  List<DraftAttachment> _drafts = const [];
  /// 引用 for the next message only; the host builds the quoted body.
  String? _quote;
  late final VoiceInputController _voice;
  late final VoiceInputActiveController _voiceFlag;

  /// The app is in front. The artifacts watch (which opens the Session's chat)
  /// waits for both this and a visible route.
  bool _resumed = true;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed != _resumed && mounted) setState(() => _resumed = resumed);
  }

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
    WidgetsBinding.instance.addObserver(this);
    _viewing = ref.read(dsBotViewingProvider.notifier);
    // The next cold start comes back here, not to the session behind it.
    unawaited(ref.read(lastConversationStoreProvider).rememberBot(widget.botId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewing.set(widget.botId);
    });
  }

  void _reportVoice() => _voiceFlag.set(_voice.active);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_reportVoice);
    _voice.dispose();
    // The page is gone, and its dictation with it.
    final flag = _voiceFlag;
    scheduleMicrotask(() => flag.set(false));
    _stopGuard.dispose();
    _viewing.leave(widget.botId);
    _drawer.dispose();
    _input.dispose();
    _focus.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  /// A settings-like destination opens above this page: the chat stays under it
  /// and "back" lands here again. The drawer closes once the page covers it.
  void _openDestination(DrawerDestination destination) {
    openDrawerDestination(context, destination);
    Future<void>.delayed(AppMotion.slow, () {
      if (mounted) _drawer.close(context);
    });
  }

  /// A conversation (or a new chat) was picked in the drawer: it is already
  /// selected, so close the drawer and step back to the shell showing it.
  void _chosen() {
    _drawer.close(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  SessionDrawerConfig get _drawerConfig => SessionDrawerConfig(
    controller: _drawer,
    onDestination: _openDestination,
    onChosen: _chosen,
  );

  /// One send bubble: the Host's queue words and actions when its inbox holds
  /// this message, otherwise the local 发送中 / 没能发送 note.
  Widget _pendingBubble(DsBotPending pending, DsBotQueue? inbox, {bool running = false}) {
    // The inbox answers first; before it arrives the send's own itemId/slot do.
    final item =
        inbox?.byRpc(pending.requestId) ??
        (pending.itemId == null
            ? null
            : DsBotQueueItem(
                itemId: pending.itemId!,
                rpcId: pending.requestId,
                text: pending.text,
                canSteer: pending.slot == 'next-turn' && running,
              ));
    final queueInbox = item == null
        ? null
        : (inbox ?? DsBotQueue(sessionId: ref.read(botChatProvider(widget.botId)).sessionId ?? ''));
    final inStep =
        item != null &&
        ((inbox != null && inbox.nextStep.any((e) => e.itemId == item.itemId)) || pending.slot == 'next-step');
    final queue = item == null
        ? null
        : (
            label: inStep ? context.l10n.chatSteerNextStep : context.l10n.chatQueuedAfterTurn,
            icon: inStep ? AppIcons.steer : AppIcons.queued,
          );
    return BotUserMessage(
      text: pending.text,
      pending: true,
      pendingSince: pending.at,
      pendingStatus: pending.status,
      onRetry: () => _retryPending(pending),
      onWithdraw: () => _withdrawPending(pending),
      queueLabel: queue?.label,
      queueIcon: queue?.icon,
      queueActions: [
        if (item != null)
          (
            running ? context.l10n.chatSendNow : context.l10n.commonSend,
            () => _sendNow(pending, queueInbox!, item, running),
          ),
        if (item != null && !inStep && item.canSteer)
          (context.l10n.chatSwitchToSteer, () => _queueAction(pending, queueInbox!, item)),
        if (item != null)
          (context.l10n.chatWithdraw, () => _queueAction(pending, queueInbox!, item, remove: true)),
      ],
    );
  }

  /// 「立即发送」: out of the inbox, stop the turn, send it again under the
  /// same request id, then the ones queued behind it — in their order.
  Future<void> _sendNow(DsBotPending pending, DsBotQueue inbox, DsBotQueueItem item, bool running) async {
    final client = ref.read(activeConnectionProvider).value?.client;
    final api = ref.read(dsBotProvider.notifier).api;
    if (client == null || api == null) return;
    final behind = _behind(inbox, item);
    final controller = ref.read(botChatProvider(widget.botId).notifier);
    try {
      await client.updateQueue(inbox.sessionId, item.itemId, remove: true);
      for (final b in behind) {
        await client.updateQueue(inbox.sessionId, b.itemId, remove: true);
      }
      if (running) await client.cancel(inbox.sessionId);
      final staged = await stageBotAttachments(client, inbox.sessionId, pending.drafts);
      await api.send(
        widget.botId,
        pending.text,
        images: staged.images,
        fileReceiptIds: staged.receipts,
        mode: 'queue',
        requestId: pending.requestId,
      );
      for (final b in behind) {
        await api.send(widget.botId, b.text, mode: 'queue', requestId: b.rpcId);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatQueueGone);
    }
    if (mounted) unawaited(controller.reload());
  }

  /// The next-turn entries waiting behind [item], in inbox order.
  List<DsBotQueueItem> _behind(DsBotQueue inbox, DsBotQueueItem item) {
    final at = inbox.nextTurn.indexWhere((e) => e.itemId == item.itemId);
    return at < 0 ? const [] : inbox.nextTurn.skip(at + 1).toList();
  }

  /// 改为插话 / 撤回 on a message the Host still holds: `session/updateQueue`.
  Future<void> _queueAction(
    DsBotPending pending,
    DsBotQueue inbox,
    DsBotQueueItem item, {
    bool remove = false,
  }) async {
    final client = ref.read(activeConnectionProvider).value?.client;
    if (client == null) return;
    try {
      await client.updateQueue(inbox.sessionId, item.itemId, steer: !remove, remove: remove);
      if (remove) ref.read(botChatProvider(widget.botId).notifier).dropPending(pending);
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatQueueGone);
    }
  }

  /// 重试 a failed send: the same request id, the staged attachments again.
  Future<void> _retryPending(DsBotPending pending) async {
    final client = ref.read(activeConnectionProvider).value?.client;
    final bot = ref.read(dsBotProvider).team?.bot(widget.botId);
    if (client == null || bot == null) return;
    try {
      final staged = await stageBotAttachments(client, bot.sessionId, pending.drafts);
      await ref.read(botChatProvider(widget.botId).notifier).send(
        pending.text,
        images: staged.images,
        fileReceiptIds: staged.receipts,
        pending: pending,
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showBriefNotice(describeDsBotError(error));
    }
  }

  /// 撤回 a failed send: the bubble goes, its words come back to be edited.
  void _withdrawPending(DsBotPending pending) {
    ref.read(botChatProvider(widget.botId).notifier).dropPending(pending);
    _input.text = pending.text;
    ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatWithdrawnEditable);
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
          final sent = await controller.send(withQuote(text, quote), mode: botSendMode(mode));
          if (sent && mounted) setState(() => _quote = null);
          return sent;
        }
        final client = ref.read(activeConnectionProvider).value?.client;
        if (client == null) return false;
        try {
          final staged = await stageBotAttachments(client, part, attachments);
          final sent = await controller.send(
            withQuote(text, quote),
            images: staged.images,
            fileReceiptIds: staged.receipts,
            mode: botSendMode(mode),
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
    // 等你回答 already shows on the pending card and in the composer's hint;
    // the header keeps the Bot's own state instead of saying it a third time.
    final (String label, StatusTone tone) = switch (()) {
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
    // the transcript with them; a turn's thinking is one line, and only while
    // it is the newest thing.
    // What the newest turn delivered, under its last row. A page read from
    // history never matches, because turn numbers restart per part.
    //
    // Watched only while this page is on top and the engine is connected: the
    // provider builds that Session's chat, and its connection, on first watch,
    // and a Bot page that only reads DS Bot's transcript must not open one.
    // 「引擎在线」is the local engine actually running, not merely a connection
    // object existing; 「页面可见」is this route on top *and* the app resumed.
    // 引擎在线 is per host: the local engine runs here, a remote host is up
    // while its connection is. Judging a remote Bot by the local engine would
    // hide every delivered card there.
    final engineUp = status.isLocal
        ? ref.watch(localRuntimeProvider.select((s) => s.status.phase == RuntimePhase.running))
        : ref.watch(activeConnectionProvider.select((c) => c.value != null));
    final visible = _resumed && (ModalRoute.of(context)?.isCurrent ?? true);
    // Watched on every build: the first watch builds this Session's chat and its
    // connection, and a delivered card is derived from that chat. The gate decides
    // only what is drawn, so a card that lands after the first frame is not lost by
    // a rebuild that happens to fall on an invisible moment.
    final artifacts = ref.watch(sessionArtifactsProvider(bot.sessionId));
    // Only the newest finished turn's own deliverables: a card from an earlier
    // turn must not reappear under a later one (turn numbers restart per part,
    // so "the last group" is not the same question as "this turn's group").
    final botTurns = ref.watch(chatProvider(bot.sessionId).select((s) => s.turns));
    final finished = [for (final trace in botTurns) if (!trace.running && trace.endSeq != null) trace];
    final newestEnd = finished.isEmpty ? null : finished.last.endSeq;
    final newest = artifacts.isEmpty ? null : artifacts.last;
    final delivered = !(visible && engineUp) || newest == null || newest.endSeq != newestEnd ? null : newest;
    // What its memory tools changed, one quiet line under the turn that did it.
    // 完成后收起过程: off leaves every step's thinking and every tool row out.
    final fold = ref.watch(settingsProvider.select((s) => s.foldCompletedTurns));
    final memoryNotices = visible && engineUp
        ? ref.watch(sessionMemoryNoticesProvider(bot.sessionId))
        : const <int, MemoryNotice>{};
    final rows = attachMemoryNotices(attachArtifacts(
      groupToolRows(
        fold: fold,
        transcriptRows(
          // 「{name} 完成了工作」 after every turn says what the reply already
          // said. The group chat has dropped that echo since it was written;
          // a Bot's own chat keeps the line only when it is the only trace.
          botTranscriptItems(withoutDoneEchoes(chat.items), running: ownTurn, fold: fold),
          pending: chat.pending,
          streaming: ownTurn ? chat.streaming : null,
        ),
      ),
      delivered,
      // A page that can still load older entries is a history page: the turn
      // numbers there restart per part, so a card must not be placed by sheer
      // "newest row" guessing.
      atOldestEnd: !chat.hasEarlier,
    ), memoryNotices, botId: bot.id);
    final topInset = BotChatHeader.heightOf(context);
    final rooms = {for (final room in team.rooms) room.id: room.name};
    final readOnly = status.readOnly != null;
    final modelScope = BotActionScope(ref, botId: bot.id);
    final sendTarget = BotActionScope(ref, botId: bot.id);

    return BotAdaptiveFrame(
      drawer: _drawerConfig,
      // The column beside the chat on a wide window; the key folds it away.
      panel: SessionDetailPage.panel(key: ValueKey('bot-detail-${bot.sessionId}'), sessionId: bot.sessionId),
      builder: (context, layout) => BotChatFrame(
      header: BotChatHeader(
        // Three columns: the rail owns the chats key, the header drops its own.
        showLeading: !layout.isExpanded,
        face: BotAvatar(bot: bot, size: BotChatHeader.faceSize),
        title: bot.name,
        status: label,
        tone: tone,
        scrolledUnder: _scrolled,
        onLeading: () => onBotMenu(context, ref, layout, () => _drawer.toggle(context)),
        leadingTooltip: botMenuTooltip(context, layout),
        // The title capsule opens the Bot's own details; the key on the right
        // opens the conversation's (trajectory, files, progress).
        onDetails: () => Navigator.of(context).push(BotDetailsPage.route(bot.id)),
        onInfo: () => openBotDetail(context, ref, layout: layout, sessionId: bot.sessionId),
        infoTooltip: layout.isExpanded && layout.panelAvailable
            ? (ref.watch(layoutPrefsProvider).panelOpen ? l10n.shellCollapseDetails : l10n.shellChatDetails)
            : null,
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
          // 对话字号 applies here too; the header and the composer keep the
          // system size, as they do in the native chat.
          : ChatTextScale(
              child: BotTranscript(
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
                  BotPendingRow(:final pending) => _pendingBubble(pending, chat.inbox, running: ownTurn),
                  BotStreamingRow(:final text) =>
                    text.isEmpty
                        ? const Align(alignment: Alignment.centerLeft, child: _Thinking())
                        : BotReplyText(text: text, streaming: true),
                  BotTypingRow() => const SizedBox.shrink(),
                  BotArtifactsRow(:final group, :final sessionId) =>
                    ArtifactCard(sessionId: sessionId ?? bot.sessionId, group: group),
                  BotMemoryNoticeRow(:final notice) => BotMemoryLine(
                    notice: notice,
                    onTap: () => Navigator.of(context).push(BotMemoryPage.route(botId: bot.id)),
                  ),
                  BotToolGroupRow(:final items) => BotToolGroup(
                    // A stable key: paging in older rows must not hand this
                    // group's open state to the one that lands on its index.
                    key: ValueKey('tool-group-${items.first.callId ?? items.first.toolName}'),
                    items: items,
                  ),
                  BotItemRow(:final item) => switch (item.kind) {
                    DsBotItemKind.user => BotUserMessage(
                      text: botLineText(item),
                      images: item.images,
                      onQuote: _setQuote,
                    ),
                    DsBotItemKind.bot => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // A Bot's own attachments draw like the person's do;
                        // the pictures among them open full screen already.
                        if (botLineAttachments(
                        item,
                        chat.sessionId,
                        onOpenFile: (file) => openBotAttachmentFile(
                          context,
                          ref,
                          file: file,
                          botId: bot.id,
                        ),
                      ) case final shown?) ...[
                          shown,
                          const SizedBox(height: 6),
                        ],
                        BotReplyText(
                          text: botLineText(item),
                          onQuote: _setQuote,
                          // A path in the reply is a file in this Bot's Session.
                          onLinkTap: (href) => openLinkedFile(context, sessionId: bot.sessionId, href: href),
                        ),
                      ],
                    ),
                    DsBotItemKind.event => BotEventLine(
                      text: chatEventText(item, roomName: rooms[item.roomId]),
                      icon: AppIcons.swap,
                    ),
                    DsBotItemKind.answer => BotEventLine(text: l10n.botsAnsweredQuestion, icon: AppIcons.done),
                    DsBotItemKind.divider => BotEventLine(text: l10n.botsEarlierMessages, icon: AppIcons.history),
                    DsBotItemKind.tool => BotToolRow(name: item.toolName ?? '', status: item.toolStatus),
                    // One line while a turn reasons, before its reply starts:
                    // no expand, no buttons, nothing else to read.
                    DsBotItemKind.thinking => BotTypingLine(
                      bot: bot,
                      label: '${bot.name} · ${l10n.botsThinking}',
                    ),
                    DsBotItemKind.unknown => const SizedBox.shrink(),
                  },
                },
              ),
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
          // The native chat's own line count for the same screen and text
          // size, so the field grows the same way here.
          maxLines: Composer.linesFor(context),
          busy: chat.loading,
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
      ),
    );
  }
}

/// Picks [bot]'s model in the chat's model sheet and saves it.
Future<void> pickBotModel(BuildContext context, WidgetRef ref, DsBot bot, {BotActionScope? scope}) {
  final target = scope ?? BotActionScope(ref, botId: bot.id);
  if (!target.current(context, ref)) return Future.value();
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
    if (context.mounted && target.current(context, ref)) await hub.refresh();
  } catch (error) {
    if (context.mounted && target.current(context, ref)) {
      messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
    }
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
