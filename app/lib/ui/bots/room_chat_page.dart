// A group chat: every message with its speaker's face and name, the round's
// events, who speaks now, members waiting for approval, the `@` member
// picker over the chat's composer.

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
import '../chat/widgets/chat_card.dart';
import '../features/feature_kit.dart';
import '../shell/page_frame.dart';
import 'bot_stop_guard.dart';
import 'bot_action_scope.dart';
import '../shell/drawer/drawer_open_request.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_attachment_open.dart';
import 'bot_attachments.dart';
import 'bot_composer_deck.dart';
import 'bot_draft_send.dart';
import 'bot_avatar.dart';
import 'unavailable_message.dart';
import '../../state/artifacts.dart' show TurnArtifacts, sessionArtifactsProvider;
import '../chat/widgets/artifact_card.dart';
import 'bot_chat_kit.dart';
import 'bot_links.dart' show openLinkedFile;
import 'bot_chat_page.dart';
import 'bot_format.dart';
import 'bot_mention.dart';
import 'room_approval_action.dart';
import 'room_activity_strip.dart' show roomStatusOf;
import 'room_aggregate_details_page.dart';
import 'room_details_page.dart';
import 'room_full_text_sheet.dart';

class RoomChatPage extends ConsumerStatefulWidget {
  const RoomChatPage({super.key, required this.roomId});

  final String roomId;

  static Route<void> route(String roomId) => MaterialPageRoute<void>(builder: (_) => RoomChatPage(roomId: roomId));

  @override
  ConsumerState<RoomChatPage> createState() => _RoomChatPageState();
}

class _RoomChatPageState extends ConsumerState<RoomChatPage> {
  Object? _continueScope;
  int _continueRequest = 0;
  bool _continuing = false;
  String? _continuedPause;
  late final BotStopGuard _stopGuard;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scrolled = ValueNotifier(0.0);
  late final DsBotViewingController _viewing;
  late final BotMentionController _mentions = BotMentionController(input: _input);
  /// Picked but unsent: shown above the composer, cleared when the send lands.
  List<DraftAttachment> _drafts = const [];
  /// 引用 for the next message only; the host builds the quoted body.
  String? _quote;
  /// The running round's progress, read once a second while the page is up.
  DsBotRoomProgress? _progress;
  Timer? _progressTimer;
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
      if (mounted) _viewing.set(widget.roomId);
    });
    // A read, and only while a round runs: nothing here starts a turn.
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_readProgress()));
  }

  void _reportVoice() => _voiceFlag.set(_voice.active);

  /// Reads the round's progress. Silent on failure: the last one stands.
  Future<void> _readProgress() async {
    if (!mounted) return;
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    if (!ref.read(roomChatProvider(widget.roomId)).running) {
      if (_progress != null) setState(() => _progress = null);
      return;
    }
    final api = ref.read(dsBotProvider.notifier).api;
    if (api == null) return;
    try {
      final fresh = await api.roomProgress(widget.roomId);
      if (mounted) setState(() => _progress = fresh);
    } catch (_) {
      // A read that fails changes nothing on screen.
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _voice.removeListener(_reportVoice);
    _voice.dispose();
    // The page is gone, and its dictation with it.
    final flag = _voiceFlag;
    scheduleMicrotask(() => flag.set(false));
    _stopGuard.dispose();
    _viewing.leave(widget.roomId);
    _mentions.dispose();
    _input.dispose();
    _focus.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  Future<void> _send(BotActionScope target, {SendMode mode = SendMode.queue}) async {
    if (!mounted || target.roomId != widget.roomId || !target.current(context, ref)) return;
    if (!ref.read(dsBotProvider).ready) return;
    final attachments = _drafts;
    final quote = _quote;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await sendBotDraft(
      context,
      ref,
      _input,
      roomId: widget.roomId,
      hasAttachments: attachments.isNotEmpty,
      send: (text) async {
        final controller = ref.read(roomChatProvider(widget.roomId).notifier);
        if (attachments.isEmpty) {
          final sent = await controller.send(withQuote(text, quote), mode: botSendMode(mode));
          if (sent && mounted) setState(() => _quote = null);
          return sent;
        }
        final client = ref.read(activeConnectionProvider).value?.client;
        if (client == null) return false;
        try {
          // The line reaches the round through the group's current Session; a
          // group that moved on has a newer one than its id.
          final staged = await stageBotAttachments(client, _roomSession(), attachments);
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

  /// The Session the round runs in now, not the group's first part.
  String _roomSession() => ref.read(dsBotProvider).team?.room(widget.roomId)?.sessionId ?? widget.roomId;

  /// 长按发送键: while the round runs, choose how the message reaches it;
  /// otherwise send at once.
  Future<void> _sendOptions(BotActionScope target, DsBotRoom room, {required bool running}) async {
    if (!running) return _send(target);
    // 插话 steers the group's relay Session, not the member turns that are
    // actually working; unverified, so a group offers 排队 and 打断 only.
    final mode = await showBotSendOptions(context, steer: false);
    if (!mounted || mode == null) return;
    await runBotSend(
      mode,
      stop: () => _stopGuard.action(roomId: room.id)(),
      send: (mode) => _send(target, mode: mode),
    );
  }

  void _setQuote(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    setState(() => _quote = trimmed.length > 2000 ? trimmed.substring(0, 2000) : trimmed);
  }

  /// Opens the ＋ panel; the pick joins the tray above the composer.
  Future<void> _attach() async {
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
    );
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() => _drafts = [..._drafts, ...picked]);
  }

  Future<void> _continue(DsBotRoom room, BotActionScope target) async {
    // The rendered button belongs to this connection and these parked calls.
    // A click may arrive after a host/boot change but before the next frame.
    if (!mounted || !target.current(context, ref)) return;
    final hub = ref.read(dsBotProvider.notifier);
    final api = target.api;
    if (api == null || _continuing) return;
    final status = ref.read(dsBotProvider);
    final pause = room.pausedCallIds.join('\u0000');
    if (_continuedPause == pause) return;
    if (!status.ready || status.team?.room(room.id)?.pausedCallIds.join('\u0000') != pause) return;
    final scope = _continueScope;
    final request = ++_continueRequest;
    bool current() =>
        mounted &&
        scope == _continueScope &&
        request == _continueRequest &&
        ref.read(dsBotProvider.notifier).api == api &&
        ref.read(dsBotProvider).host == status.host &&
        ref.read(dsBotProvider).hello?.boot == status.hello?.boot;
    setState(() => _continuing = true);
    try {
      await api.continueRoom(room.id);
      if (!current()) return;
      // The queued round clears these calls asynchronously. Do not enqueue
      // another Continue while the same parked calls remain in state.
      setState(() => _continuedPause = pause);
      await hub.refresh();
    } catch (error) {
      if (mounted && current()) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
      }
    } finally {
      if (current()) setState(() => _continuing = false);
    }
  }

  bool _fullTextOpen = false;

  Future<void> _showAll(DsBotItem item, BotActionScope scope) async {
    if (_fullTextOpen) return;
    _fullTextOpen = true;
    try {
      await showRoomFullText(context, ref, widget.roomId, item, scope: scope);
    } finally {
      _fullTextOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = ref.watch(dsBotProvider);
    final api = ref.read(dsBotProvider.notifier).api;
    final scope = (status.host, status.hello?.boot, widget.roomId, api);
    if (_continueScope != scope) {
      _continueScope = scope;
      _continueRequest++;
      _continuing = false;
      _continuedPause = null;
    }
    final team = status.team;
    final room = team?.room(widget.roomId);
    // Everything Session-scoped here (the deck's capsules and strips, the
    // attachments' image fetches) follows the group's current Session.
    final roomSession = room?.sessionId ?? widget.roomId;
    final continueTarget = BotActionScope(ref, roomId: widget.roomId);
    final fullTextScope = BotActionScope(ref, roomId: widget.roomId);
    final sendTarget = BotActionScope(ref, roomId: widget.roomId);
    final mobileUnavailable =
        status.availability == DsBotAvailability.missing || status.availability == DsBotAvailability.outdated;
    if (team == null || room == null || mobileUnavailable) {
      return AppPage.list(
        title: l10n.botsGroupChat,
        children: [
          DsBotUnavailableMessage(status: status, goneIcon: AppIcons.groupChat, goneTitle: l10n.botsRoomGone),
        ],
      );
    }
    final members = [for (final id in room.members) ?team.bot(id)];
    _mentions.setMembers(members, room.admin);
    final chat = ref.watch(roomChatProvider(widget.roomId));
    final approvals = [
      for (final a in status.live.approvals)
        if (a.roomId == room.id && a.answerable) a,
    ];
    // The header's line and the deck's line are worked out once, so the two
    // cannot say different things about the same round.
    final statusLine = roomStatusOf(
      l10n: l10n,
      team: team,
      room: room,
      live: status.live,
      running: chat.running,
      speaking: chat.speaking,
      progress: _progress,
    );
    final speaker = statusLine.bot;

    final typing = speaker == null
        ? null
        : BotTypingRow(
            speaker,
            l10n.botsNamedActivity(speaker.name, workPhrase(status.live.bots[speaker.id]) ?? l10n.botsTyping),
          );
    // What each member delivered in this group, from their Session here; the card
    // goes under their last line. The group Session's own delivery keeps the
    // single-conversation placement by turn.
    final deliveredByBot = <String, ({String sessionId, TurnArtifacts group})>{};
    for (final id in room.members) {
      final bot = team.bot(id);
      if (bot == null) continue;
      final memberSession = room.sessions[bot.id] ?? bot.sessionId;
      if (memberSession.isEmpty) continue;
      final artifacts = ref.watch(sessionArtifactsProvider(memberSession));
      if (artifacts.isEmpty) continue;
      deliveredByBot[id] = (sessionId: memberSession, group: artifacts.last);
    }
    final groupArtifacts = room.sessionId == null ? null : ref.watch(sessionArtifactsProvider(room.sessionId!));
    final rows = attachMemberArtifacts(
      attachArtifacts(
        transcriptRows(chat.items, pending: chat.pending, typing: typing),
        groupArtifacts == null || groupArtifacts.isEmpty ? null : groupArtifacts.last,
        atOldestEnd: !chat.hasEarlier,
      ),
      deliveredByBot,
    );
    final topInset = BotChatHeader.heightOf(context);
    final readOnly = status.readOnly != null;

    return BotChatFrame(
      header: BotChatHeader(
        face: RoomAvatar(room: room, team: team, size: BotChatHeader.faceSize),
        title: room.name,
        status: statusLine.spoken == 0
            ? statusLine.label
            : '${statusLine.label} · ${l10n.botsAlreadySpoke} ${statusLine.spoken}',
        tone: statusLine.tone,
        scrolledUnder: _scrolled,
        onLeading: () => openDrawerOverShell(context, ref),
        // The title capsule is the group's own details; the key on the right is
        // this conversation's — trajectory, files, progress, context — the same
        // page a Bot's chat shows, read from the Session the group runs in.
        onDetails: () => Navigator.of(context).push(RoomDetailsPage.route(room.id)),
        onInfo: () => Navigator.of(context).push(RoomAggregateDetailsPage.route(room.id)),
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
              onEarlier: () => ref.read(roomChatProvider(widget.roomId).notifier).loadEarlier(),
              empty: _Members(room: room, team: team),
              rowBuilder: (context, row) => Padding(
                padding: rowPadding(row),
                child: switch (row) {
                  BotTimeRow(:final time) => BotTimeLine(time),
                  BotPendingRow(:final pending) => BotUserMessage(text: pending.text, pending: true, pendingSince: pending.at),
                  BotStreamingRow() => const SizedBox.shrink(),
                  BotTypingRow(:final bot, :final label) => BotTypingLine(bot: bot, label: label),
                  // A group has no tool events to show; the row exists so the
                  // switch stays exhaustive, and the same widget keeps it honest.
                  // A group's delivered cards come from each member's Session for
                  // this group (see attachMemberArtifacts), not from the group's
                  // own turns — a group line carries no DSH turn to place them by.
                  BotArtifactsRow(:final group, :final sessionId) =>
                    ArtifactCard(sessionId: sessionId ?? roomSession, group: group),
                  BotToolGroupRow(:final items) => BotToolGroup(items: items),
                  BotItemRow(:final item, :final continued) => switch (item.kind) {
                    DsBotItemKind.user => BotUserMessage(
                      text: botLineText(item),
                      images: item.images,
                      attachments: botLineAttachments(
                        item,
                        roomSession,
                        onOpenFile: (file) => openBotAttachmentFile(
                          context,
                          ref,
                          file: file,
                          roomId: room.id,
                        ),
                      ),
                      onQuote: _setQuote,
                    ),
                    DsBotItemKind.bot => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (botLineAttachments(
                        item,
                        roomSession,
                        onOpenFile: (file) => openBotAttachmentFile(
                          context,
                          ref,
                          file: file,
                          roomId: room.id,
                        ),
                      ) case final shown?) ...[
                          shown,
                          const SizedBox(height: 6),
                        ],
                        GroupMessage(
                      item: item,
                      bot: team.bot(item.botId),
                      continued: continued,
                      admin: item.botId != null && item.botId == room.admin,
                      onOpenBot: team.bot(item.botId) == null
                          ? null
                          : () => Navigator.of(context).push(BotChatPage.route(item.botId!)),
                      onShowAll: item.whole == null ? null : () => _showAll(item, fullTextScope),
                      // A path is a file in the speaker's Session here; fall back
                      // to the group Session when the speaker is unknown.
                      onLinkTap: (href) => openLinkedFile(
                        context,
                        sessionId: item.botId == null
                            ? roomSession
                            : (room.sessions[item.botId!] ?? team.bot(item.botId!)?.sessionId ?? roomSession),
                        href: href,
                      ),
                          onQuote: _setQuote,
                        ),
                      ],
                    ),
                    DsBotItemKind.event => BotEventLine(
                      text: roomEventText(item),
                      danger: item.event == 'failed',
                      icon: switch (item.event) {
                        'done' => AppIcons.completed,
                        'working' => AppIcons.working,
                        'approval' => AppIcons.approval,
                        'failed' => AppIcons.error,
                        'schedule' => AppIcons.scheduled,
                        _ => null,
                      },
                    ),
                    DsBotItemKind.tool => BotToolRow(name: item.toolName ?? '', status: item.toolStatus),
                    // A group's relay Session runs no model, so a thinking
                    // step should never reach here; it says nothing if it does.
                    DsBotItemKind.thinking => const SizedBox.shrink(),
                    _ => const SizedBox.shrink(),
                  },
                },
              ),
            ),
      bottom: [
        if (room.paused)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChatCard(
              key: const ValueKey('room-paused'),
              icon: AppIcons.paused,
              title: l10n.commonPaused,
              tone: ChatCardTone.attention,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, ChatCard.inset),
                  child: FilledButton.icon(
                    key: const ValueKey('room-continue'),
                    onPressed:
                        api == null || readOnly || _continuing || _continuedPause == room.pausedCallIds.join('\u0000')
                        ? null
                        : () => _continue(room, continueTarget),
                    icon: const Icon(AppIcons.play, size: 18),
                    label: Text(l10n.commonContinue),
                  ),
                ),
              ],
            ),
          ),
        for (final approval in approvals)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: api == null
                ? GroupApprovalCard(approval: approval, bot: team.bot(approval.botId), onAnswer: null)
                : RoomApprovalAction(
                    key: ValueKey((
                      status.host,
                      status.hello?.boot,
                      api,
                      approval.id,
                      approval.sessionId,
                      approval.botId,
                      approval.roomId,
                    )),
                    api: api,
                    origin: status,
                    approval: approval,
                    builder: (answer) =>
                        GroupApprovalCard(approval: approval, bot: team.bot(approval.botId), onAnswer: answer),
                  ),
          ),
        ListenableBuilder(
          listenable: _mentions,
          builder: (context, _) => AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.quick),
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            child: _mentions.isOpen
                ? Padding(
                    key: const ValueKey('mentions'),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: BotMentionPicker(controller: _mentions),
                  )
                : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
        ),
        BotErrorSlot(
          error: chat.error,
          onDismiss: () => ref.read(roomChatProvider(widget.roomId).notifier).dismissError(),
        ),
        // A group has no single conversation behind it: the todo, goal and
        // permission parts stay off; the activity and plugin strips still apply.
        BotComposerDeck(
          sessionId: roomSession,
          running: chat.running,
          showSessionBars: false,
          roomActivity: statusLine,
        ),
        Composer(
          hardwareEnterSends: ref.watch(settingsProvider.select((s) => s.hardwareEnterSends)),
          voice: _voice,
          controller: _input,
          placeholder: l10n.botsGroupComposerHint,
          focusNode: _focus,
          connected: api != null && !readOnly,
          running: chat.running,
          onSend: () => _send(sendTarget),
          onSendOptions: () => _sendOptions(sendTarget, room, running: chat.running),
          onStop: _stopGuard.action(roomId: room.id),
          onKeyEvent: _mentions.handleKey,
          // 写 `@` 仍会按光标弹出成员候选；＋ 占住左边那颗键，附件优先。
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
        ),
      ],
    );
  }
}

/// A member waiting for the user's approval inside the group.
class GroupApprovalCard extends StatefulWidget {
  const GroupApprovalCard({super.key, required this.approval, required this.bot, required this.onAnswer});

  final DsBotApproval approval;
  final DsBot? bot;

  /// Null on a read-only team: both keys disabled.
  final Future<void> Function(bool allow)? onAnswer;

  @override
  State<GroupApprovalCard> createState() => _GroupApprovalCardState();
}

class _GroupApprovalCardState extends State<GroupApprovalCard> {
  bool _busy = false;

  Future<void> _answer(bool allow) async {
    final answer = widget.onAnswer;
    // A second tap can land before the rebuild that disables the keys.
    if (_busy || answer == null) return;
    setState(() => _busy = true);
    try {
      await answer(allow);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    final name = widget.bot?.name ?? 'Bot';
    final reason = widget.approval.reason.trim();
    return ChatCard(
      icon: AppIcons.approval,
      title: approvalPhrase(name, widget.approval.tool),
      tone: ChatCardTone.attention,
      children: [
        if (reason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(ChatCard.inset, 0, ChatCard.inset, 4),
            child: Text(
              reason,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(ChatCard.inset, 8, ChatCard.inset, ChatCard.inset),
          child: Row(
            spacing: 12,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy || widget.onAnswer == null ? null : () => _answer(false),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.5)),
                  ),
                  child: Text(l10n.botsDecline),
                ),
              ),
              Expanded(
                child: FilledButton(
                  onPressed: _busy || widget.onAnswer == null ? null : () => _answer(true),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(l10n.botsAllowOnce),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The empty group: who is in it.
class _Members extends StatelessWidget {
  const _Members({required this.room, required this.team});

  final DsBotRoom room;
  final DsBotTeam team;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final names = [for (final id in room.members) ?team.bot(id)?.name];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RoomAvatar(room: room, team: team, size: 64),
        const SizedBox(height: 12),
        Text(room.name, style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          names.join(l10n.botsNameSeparator),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary),
        ),
      ],
    );
  }
}
