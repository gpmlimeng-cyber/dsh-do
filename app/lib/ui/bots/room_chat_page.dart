// A group chat: every message with its speaker's face and name, the round's
// events, who speaks now, members waiting for approval, the `@` member
// picker over the chat's composer.

import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/route_observer.dart';
import '../../l10n/l10n.dart';
import '../../state/room_activity_state.dart' show roomMembersActivityProvider, roomUsageTotal;
import '../../state/room_chat_target.dart';
import '../../state/room_message_mode.dart';
import '../../state/room_speakers.dart';
import '../../state/settings_state.dart';
import '../../state/attachments.dart';
import '../../state/draft_store.dart';
import '../../state/adaptive_layout_state.dart';
import '../../state/bots_state.dart';
import '../../state/last_conversation.dart';
import '../../state/connection_state.dart';
import '../chat/chat_text_scale.dart';
import '../chat/trajectory_sheet.dart' show showTrajectorySheet;
import '../chat/usage_sheet.dart' show showUsageSheet;
import '../chat/composer.dart';
import '../chat/render/message_mentions.dart';
import '../../state/voice_model_state.dart';
import '../../state/voice_state.dart';
import '../../state/chat_state.dart' show SendMode, chatProvider;
import '../../state/usage_state.dart' show SessionUsage, sessionUsageProvider;
import '../chat/voice/voice_controller.dart';
import '../chat/widgets/attachments.dart';
import '../chat/widgets/quote_chip.dart' show ComposerTrayStack, QuoteChip;
import '../chat/widgets/chat_card.dart';
import '../common/status_dot.dart' show StatusTone;
import '../common/brief_notice.dart';
import '../features/feature_kit.dart';
import '../shell/adaptive/adaptive_scaffold.dart';
import '../shell/page_frame.dart';
import '../session/session_detail_page.dart';
import 'bot_stop_guard.dart';
import 'bot_action_scope.dart';
import '../shell/drawer/drawer_destination.dart';
import '../shell/session_drawer_host.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'bot_attachment_open.dart';
import 'bot_attachments.dart';
import 'bot_composer_deck.dart';
import 'group_goal.dart';
import 'bot_draft_send.dart';
import 'bot_adaptive_frame.dart';
import 'bot_avatar.dart';
import 'unavailable_message.dart';
import '../../state/artifacts.dart' show TurnArtifacts, sessionArtifactsProvider;
import '../chat/widgets/artifact_card.dart';
import 'bot_chat_kit.dart';
import 'bot_memory_notice.dart';
import 'bot_memory_page.dart';
import 'bot_links.dart' show openLinkedFile;
import 'bot_chat_page.dart';
import 'bot_format.dart';
import '../settings/settings_widgets.dart';
import 'bot_mention.dart';
import 'room_approval_action.dart';
import 'room_activity_strip.dart' show roomStatusOf;
import 'room_aggregate_details_page.dart';
import 'room_details_page.dart';
import 'room_session_sheet.dart' show showMessageScopeSheet;
import 'room_full_text_sheet.dart';

/// 各群目标胶囊的形态：默认完整；本轮内按群记住用户收起的选择，重启回到
/// 完整。按群记，别让 A 群收成小球串到 B 群。
final Map<String, bool> _goalExpandedByRoom = <String, bool>{};

class RoomChatPage extends ConsumerStatefulWidget {
  const RoomChatPage({super.key, required this.roomId, this.initialTarget = RoomChatTarget.all});

  final String roomId;

  /// The conversation to open on: the group chat (default) or one member's
  /// conversation in it. Later switches are page state, not routes.
  final RoomChatTarget initialTarget;

  static Route<void> route(String roomId, {RoomChatTarget initialTarget = RoomChatTarget.all}) =>
      MaterialPageRoute<void>(builder: (_) => RoomChatPage(roomId: roomId, initialTarget: initialTarget));

  @override
  ConsumerState<RoomChatPage> createState() => _RoomChatPageState();
}

class _RoomChatPageState extends ConsumerState<RoomChatPage> with WidgetsBindingObserver, RouteAware, TickerProviderStateMixin {
  Object? _continueScope;
  int _continueRequest = 0;
  bool _continuing = false;
  String? _continuedPause;
  late final BotStopGuard _stopGuard;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scrolled = ValueNotifier(0.0);
  late final DsBotViewingController _viewing;

  /// Which conversation this page shows now. Switching replaces it in place:
  /// no route is pushed, so one back still lands on the group's details.
  late RoomChatTarget _target = widget.initialTarget;

  /// 顶栏的目标：默认完整胶囊；点了「收起成小球」才收成小球。选择按群记、
  /// 只在本轮内有效（重启回到完整），不跨启动、也不由设置决定。
  late bool _goalExpanded = _goalExpandedByRoom[widget.roomId] ?? true;

  void _setGoalExpanded(bool value) {
    _goalExpandedByRoom[widget.roomId] = value;
    setState(() => _goalExpanded = value);
  }

  /// ⋯ 下拉菜单的开合：菜单锚在这颗键上，页面拿它管「返回先收菜单」。
  final MenuController _roomMenu = MenuController();

  late final DraftStore _draftStore = ref.read(draftStoreProvider.notifier);

  /// A draft per conversation: the group's, and each member's own.
  late String _draftKey = _draftKeyFor(_target);
  /// This page's own drawer: it opens over the chat instead of leaving it.
  late final SessionDrawerController _drawer = SessionDrawerController(vsync: this);
  late final BotMentionController _mentions = BotMentionController(input: _input);
  /// Picked but unsent: shown above the composer, cleared when the send lands.
  List<DraftAttachment> _drafts = const [];
  /// 引用 for the next message only; the host builds the quoted body.
  String? _quote;
  /// The running round's progress, read once a second while the page is up.
  DsBotRoomProgress? _progress;
  Timer? _progressTimer;
  /// The round that just finished, said once in the header for six seconds —
  /// the flow no longer draws a `done` line when the words already say it.
  String? _flash;
  StatusTone? _flashTone;
  Timer? _flashTimer;

  /// The last `done`/`failed` line seen, so only a new one flashes.
  String? _lastFlashKey;
  bool _flashPrimed = false;

  ({String key, String event, DsBotItem item})? _latestFlash(List<DsBotItem> items) {
    for (final item in items.reversed) {
      if (item.kind != DsBotItemKind.event) continue;
      if (item.event != 'done' && item.event != 'failed') continue;
      return (key: '${item.seq ?? item.id}', event: item.event!, item: item);
    }
    return null;
  }

  void _rememberFlash(DsBotRoom room, DsBotTeam team, RoomMessageMode mode, RoomChatTarget target) {
    final items = ref.read(roomChatProvider(widget.roomId)).items;
    final latest = _latestFlash(items);
    if (latest == null) return;
    if (!_flashPrimed) {
      // The first page of a conversation already has its history: only a new
      // line afterwards flashes.
      _flashPrimed = true;
      _lastFlashKey = latest.key;
      return;
    }
    if (latest.key == _lastFlashKey) return;
    _lastFlashKey = latest.key;
    // Another member's line is not this conversation's news.
    if (target.memberId != null && roomSpeakerOf(room, team, latest.item) != target.memberId) return;
    // A line the current mode filters out must not speak either.
    if (visibleRoomItems(
      [latest.item],
      mode,
      speakerOf: (item) => roomSpeakerOf(room, team, item),
    ).isEmpty) {
      return;
    }
    final name = team.bot(roomSpeakerOf(room, team, latest.item))?.name;
    if (name == null) return;
    final warn = latest.event == 'failed';
    setState(() {
      // One string for both: the tone says whether it finished or failed.
      _flash = appL10n.botsNamedDone(name);
      _flashTone = warn ? StatusTone.warn : StatusTone.busy;
      _flashTimer?.cancel();
      _flashTimer = null;
    });
  }
  late final VoiceInputController _voice;
  late final VoiceInputActiveController _voiceFlag;

  String _draftKeyFor(RoomChatTarget target) =>
      'room:${widget.roomId}${target.isAll ? '' : ':${target.memberId}'}';

  void _saveDraft() => _draftStore.save(_draftKey, _input.text, _drafts);

  void _showDraft(String key) {
    final draft = ref.read(draftStoreProvider).drafts[key];
    _drafts = draft?.attachments ?? const [];
    final text = draft?.text ?? '';
    _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }

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
    final queueInbox = item == null ? null : (inbox ?? DsBotQueue(sessionId: _roomSession()));
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
      attachments: pending.drafts.isEmpty ? null : SentAttachments.pending(pending.drafts),
      onRetry: () => _retryPending(pending),
      onWithdraw: () => _withdrawPending(pending),
      queueLabel: queue?.label,
      queueIcon: queue?.icon,
      queueActions: [
        if (item != null)
          (
            running ? context.l10n.chatSendNow : context.l10n.commonSend,
            () => _sendNow(pending, queueInbox!, item),
          ),
        if (item != null && !inStep && item.canSteer)
          (context.l10n.chatSwitchToSteer, () => _queueAction(pending, queueInbox!, item)),
        if (item != null) (context.l10n.chatWithdraw, () => _queueAction(pending, queueInbox!, item, remove: true)),
      ],
    );
  }

  /// 「立即发送」: take it out of the inbox, stop the running turn, send it
  /// again under the same request id, then the ones queued behind it — in
  /// their order, or they would overtake it.
  Future<void> _sendNow(DsBotPending pending, DsBotQueue inbox, DsBotQueueItem item) async {
    final client = ref.read(activeConnectionProvider).value?.client;
    final api = ref.read(dsBotProvider.notifier).api;
    if (client == null || api == null) return;
    final behind = _behind(inbox, item);
    final controller = ref.read(roomChatProvider(widget.roomId).notifier);
    try {
      await client.updateQueue(inbox.sessionId, item.itemId, remove: true);
      for (final b in behind) {
        await client.updateQueue(inbox.sessionId, b.itemId, remove: true);
      }
      if (ref.read(roomChatProvider(widget.roomId)).running) await client.cancel(inbox.sessionId);
      final staged = await stageBotAttachments(client, inbox.sessionId, pending.drafts);
      await api.send(
        widget.roomId,
        pending.text,
        images: staged.images,
        fileReceiptIds: staged.receipts,
        mode: 'queue',
        requestId: pending.requestId,
      );
      for (final b in behind) {
        await api.send(widget.roomId, b.text, mode: 'queue', requestId: b.rpcId);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatQueueGone);
    }
    if (mounted) unawaited(controller.refresh());
  }

  /// The next-turn entries waiting behind [item], in inbox order.
  List<DsBotQueueItem> _behind(DsBotQueue inbox, DsBotQueueItem item) {
    final at = inbox.nextTurn.indexWhere((e) => e.itemId == item.itemId);
    return at < 0 ? const [] : inbox.nextTurn.skip(at + 1).toList();
  }

  /// 改为插话 / 撤回 on a message the Host still holds: `session/updateQueue`,
  /// the same call the app's own chat uses. The inbox push is the truth after.
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
      if (remove) ref.read(roomChatProvider(widget.roomId).notifier).dropPending(pending);
    } catch (_) {
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatQueueGone);
    }
  }

  /// 重试 a failed send: the same request id, the staged attachments again.
  Future<void> _retryPending(DsBotPending pending) async {
    final client = ref.read(activeConnectionProvider).value?.client;
    final controller = ref.read(roomChatProvider(widget.roomId).notifier);
    if (client == null) return;
    try {
      final staged = await stageBotAttachments(client, _roomSession(), pending.drafts);
      await controller.send(
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
    ref.read(roomChatProvider(widget.roomId).notifier).dropPending(pending);
    _input.text = pending.text;
    ScaffoldMessenger.maybeOf(context)?.showBriefNotice(context.l10n.chatWithdrawnEditable);
  }

  /// Another conversation of the same group: same page, same data, same
  /// composer. Drafts go with their own conversation, so switching back brings
  /// the words back.
  void _switchTarget(RoomChatTarget next) {
    if (next == _target) return;
    _saveDraft();
    setState(() {
      _target = next;
      _draftKey = _draftKeyFor(next);
    });
    _showDraft(_draftKey);
    _mentions.dismiss();
    if (_voice.active) unawaited(_voice.cancel());
    _rememberConversation();
  }

  /// Which conversation of this group the next cold start reopens.
  void _rememberConversation() => unawaited(
    ref
        .read(lastConversationStoreProvider)
        .rememberRoom(widget.roomId, memberId: _target.memberId),
  );

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
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewing.set(widget.roomId);
    });
    _rememberConversation();
    _showDraft(_draftKey);
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

  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  /// 被别的页面（成员详情、群详情、图片、各种 sheet）盖住：把输入框的焦点
  /// 收掉。pop 回来时 Flutter 会把焦点还给输入框，Android 便又弹键盘。
  @override
  void didPushNext() => _focus.unfocus();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 退到后台、锁屏、切走：同样收掉焦点，回来不自动弹。
    if (state != AppLifecycleState.resumed) _focus.unfocus();
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _flashTimer?.cancel();
    _voice.removeListener(_reportVoice);
    _voice.dispose();
    // The page is gone, and its dictation with it.
    final flag = _voiceFlag;
    scheduleMicrotask(() => flag.set(false));
    _stopGuard.dispose();
    _viewing.leave(widget.roomId);
    _saveDraft();
    _drawer.dispose();
    _mentions.dispose();
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

  /// The header's switch key as the conversation it shows: the group's icon —
  /// with the dot that means "the group is filtered" — or the member's own face
  /// in a primary ring. A member's conversation carries no dot: filters do not
  /// apply there, and a dot would say they do. Keyed, so a switch fades and
  /// grows into place.
  /// One member's line in the group. The Host names the speaker by its sender
  /// Session (older hosts by the Bot id), so the face, the admin mark and the
  /// Session a path opens come from the resolved member.
  Widget _groupRow(
    BuildContext context,
    DsBotItem item, {
    required bool continued,
    required DsBotRoom room,
    required DsBotTeam team,
    required String? roomSession,
    required BotActionScope fullTextScope,
    required List<InlineMention> mentions,
    BotRunFigures? figures,
  }) {
    // `botId` is the Bot id (it looks like a Session id, hence the old naming;
    // a line that lost it still names its sender). The member's Session in this
    // group is `room.sessions[botId]` only — never the Bot's private one.
    final speakerId = roomSpeakerOf(room, team, item);
    final speaker = team.bot(speakerId);
    final speakerSession = speakerId == null ? roomSession : (room.sessions[speakerId] ?? roomSession);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (botLineAttachments(
              item,
              roomSession,
              onOpenFile: (file) => openBotAttachmentFile(context, ref, file: file, roomId: room.id),
            )
            case final shown?) ...[
          shown,
          const SizedBox(height: 6),
        ],
        GroupMessage(
          item: item,
          bot: speaker,
          continued: continued,
          figures: figures,
          mentions: mentions,
          // 这一轮的用量面板：成员在本群的那个 Session。
          onStats: speakerSession == null ? null : () => showUsageSheet(context, sessionId: speakerSession),
          admin: speakerId != null && speakerId == room.admin,
          onOpenBot: speaker == null ? null : () => Navigator.of(context).push(BotChatPage.route(speaker.id)),
          onShowAll: item.whole == null ? null : () => _showAll(item, fullTextScope),
          // A path is a file in the speaker's Session here; fall back to the
          // group Session when the speaker is unknown.
          onLinkTap: (href) => openLinkedFile(context, sessionId: speakerSession, href: href),
          onQuote: _setQuote,
        ),
      ],
    );
  }

  /// The composer's right side: the group's context ring, and — while a turn
  /// runs with an empty field — a microphone. Both may hide; then there is no
  /// accessory at all, so the send key keeps its place (the Composer adds 2dp
  /// before any accessory it is given).
  Widget? _composerAccessory({required DsBotRoom room, required bool running}) {
    final voice = _voice;
    final empty = _input.text.trim().isEmpty && _drafts.isEmpty;
    final mic = running && empty && voice.available && !voice.active;
    final sessionId = room.sessionId;
    final usage = sessionId == null ? SessionUsage.empty : ref.watch(sessionUsageProvider(sessionId));
    final members = ref.watch(roomMembersActivityProvider(room.id)).value;
    final ring = members == null ? null : roomUsageTotal(usage, members).contextFraction;
    if (ring == null && !mic) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (ring != null) RoomContextRing(roomId: room.id),
        if (mic)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 2),
            child: _ComposerMicKey(
              onPressed: () {
                // As Composer._startVoice: the keyboard covers the field.
                _focus.unfocus();
                voice.start();
              },
            ),
          ),
      ],
    );
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
        final outgoing = withQuote(text, quote);
        // The bubble shows at once, with the pictures still on this phone; the
        // host only logs the line once a relay runs, which can take a while.
        final pending = controller.beginPending(outgoing, drafts: attachments);
        try {
          // The line reaches the round through the group's current Session; a
          // group that moved on has a newer one than its id.
          final staged = await stageBotAttachments(client, _roomSession(), attachments);
          final sent = await controller.send(
            outgoing,
            images: staged.images,
            fileReceiptIds: staged.receipts,
            mode: botSendMode(mode),
            pending: pending,
          );
          if (!sent) controller.dropPending(pending);
          if (sent && mounted) {
            setState(() {
              _drafts = const [];
              _quote = null;
            });
          }
          return sent;
        } catch (error) {
          // The upload failed before `send` could take the bubble back.
          controller.dropPending(pending);
          if (mounted) messenger?.showSnackBar(SnackBar(content: Text(describeDsBotError(error))));
          return false;
        }
      },
    );
  }

  /// The last user line on the page: the round that may still be delivering
  /// starts after it. -1 when the page holds no user line.
  int _lastUserRow(List<BotRow> rows) {
    var at = -1;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (row is BotItemRow && row.item.kind == DsBotItemKind.user) at = i;
    }
    return at;
  }

  /// The Session the round runs in now, not the group's first part.
  String _roomSession() => ref.read(dsBotProvider).team?.room(widget.roomId)?.sessionId ?? widget.roomId;

  /// 活动行点开的是这一轮：还在跑就是它，跑完了就是最后一轮；一轮都还没有
  /// 时打开用量面板，至少告诉点什么，而不是点了没反应。
  void _openRunningTrajectory(String sessionId) {
    final chat = ref.read(chatProvider(sessionId));
    final turn = chat.runningTurn?.turn ?? (chat.turns.isEmpty ? null : chat.turns.last.turn);
    if (turn == null) {
      unawaited(showUsageSheet(context, sessionId: sessionId));
      return;
    }
    unawaited(showTrajectorySheet(context, sessionId: sessionId, turn: turn));
  }

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
      roomId: widget.roomId,
      onGoal: () => showGoalCompose(context, widget.roomId),
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
    // 「@名字」画成该成员自己的墨色,和网页版一致;名单就是本群成员。
    final memberMentions = [
      for (final bot in members) InlineMention(name: bot.name, color: botNameInk(context, bot.ink)),
    ];
    final chat = ref.watch(roomChatProvider(widget.roomId));
    // Which lines this group shows. Filtering is rendering only: pending,
    // unread counts, 「已说 N」 and the round's progress keep the full list.
    final pickedMode = ref.watch(roomMessageModeProvider(room.id));
    // A member who left the group, or a team that no longer has them: the stored
    // "that member only" mode stands for nothing, so the group reads as 全部
    // rather than through a face with no name.
    final mode = pickedMode.memberId != null && team.bot(pickedMode.memberId!) == null
        ? RoomMessageMode.all
        : pickedMode;
    // The conversation this page shows. A member who left the group while being
    // read falls back to the group chat, and the page says so once.
    final targetBot = _target.memberId == null ? null : team.bot(_target.memberId!);
    // The member's Session in this group, and only that one: empty means the
    // details are unavailable (old Host), never their private conversation.
    final memberSession = targetBot == null ? null : room.sessions[targetBot.id];
    final target = targetBot == null ? RoomChatTarget.all : _target;
    if (!_target.isAll && targetBot == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _target.isAll) return;
        _switchTarget(RoomChatTarget.all);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.botsRoomMemberLeft)));
      });
    }
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
      flash: _flash == null ? null : (label: _flash!, tone: _flashTone ?? StatusTone.busy),
    );

    // The last key opens a menu when the page has one; its long press and the
    // menu's 对话详情 item both land here, on whatever this page shows.
    final infoGreyed = targetBot != null && memberSession == null;
    void openInfo() {
      final layout = AdaptiveChrome.layoutOf(context);
      if (targetBot == null) {
        // The group's aggregate page has no panel form: beside the chat it is
        // the group Session's own details, which the key folds away.
        if (layout != null && layout.isExpanded && layout.panelAvailable) {
          ref.read(layoutPrefsProvider.notifier).setPanelOpen(!ref.read(layoutPrefsProvider).panelOpen);
        } else {
          Navigator.of(context).push(RoomAggregateDetailsPage.route(room.id));
        }
      } else if (memberSession == null) {
        ScaffoldMessenger.maybeOf(context)?.showBriefNotice(l10n.botsRoomMemberSessionMissing);
      } else if (layout case final layout?) {
        openBotDetail(
          context,
          ref,
          layout: layout,
          sessionId: memberSession,
          scopeLabel: l10n.botsRoomMemberScope(targetBot.name),
        );
      }
    }
    // The six seconds start when the line can actually be seen: a run or a
    // pending approval keeps the header's own state first.
    if (_flash != null &&
        _flashTimer == null &&
        statusLine.activity == null &&
        !statusLine.waiting) {
      _flashTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted) return;
        setState(() {
          _flash = null;
          _flashTone = null;
          _flashTimer = null;
        });
      });
    }
    final speaker = statusLine.bot;

    // 「名字 · 正在写」 while a member is speaking: the web draws this row too,
    // and a group's log carries no thinking of its own to draw instead.
    final typing =
        speaker == null ||
            (target.memberId != null && speaker.id != target.memberId) ||
            statusLine.activity != null
        ? null
        : BotTypingRow(
            speaker,
            l10n.botsNamedActivity(speaker.name, workPhrase(status.live.bots[speaker.id]) ?? l10n.botsTyping),
          );
    // What each member delivered in this group, from their Session here; the card
    // goes under their last line. The group Session's own delivery keeps the
    // single-conversation placement by turn.
    // One card per file, not per member: two members delivering the same file
    // would otherwise draw it twice. The first member to deliver it keeps it.
    final deliveredByBot = <String, ({String sessionId, TurnArtifacts group})>{};
    final seenFiles = <String>{};
    for (final id in room.members) {
      if (target.memberId != null && id != target.memberId) continue;
      final bot = team.bot(id);
      if (bot == null) continue;
      final memberSession = room.sessions[bot.id] ?? bot.sessionId;
      if (memberSession.isEmpty) continue;
      final artifacts = ref.watch(sessionArtifactsProvider(memberSession));
      if (artifacts.isEmpty) continue;
      // The member's newest delivered turn, and only while that turn is its
      // newest finished one: an older group must not hang under a later round.
      final memberTurns = ref.watch(chatProvider(memberSession).select((s) => s.turns));
      final own = [for (final trace in memberTurns) if (!trace.running && trace.endSeq != null) trace];
      final group = artifacts.last;
      if (own.isEmpty || own.last.endSeq != group.endSeq) continue;
      final fresh = [
        for (final file in group.files)
          if (seenFiles.add(file.path)) file,
      ];
      if (fresh.isEmpty) continue;
      deliveredByBot[id] = (
        sessionId: memberSession,
        group: TurnArtifacts(turn: group.turn, endSeq: group.endSeq, files: fresh),
      );
    }
    // The group's own Session repeats what members delivered — their presented
    // files are relayed into it. Members are collected first, so a file draws
    // one card under the member who produced it; only what no member claimed
    // keeps the relay's turn-placed card. In a member's conversation the relay's
    // card is left out entirely: it would show other members' files.
    final relayArtifacts = room.sessionId == null ? null : ref.watch(sessionArtifactsProvider(room.sessionId!));
    final groupArtifacts = target.memberId != null
        ? null
        : unclaimedArtifacts(relayArtifacts == null || relayArtifacts.isEmpty ? null : relayArtifacts.last, seenFiles);
    // A member's conversation reads the group Session's own history when the
    // host sends it: `room.log` keeps only the newest lines, so a member who
    // spoke earlier would otherwise read as having said nothing at all. The
    // group chat stays on the old shape until the new one carries what it
    // draws (each line's files).
    final memberSource = target.memberId != null && chat.sessionItems.isNotEmpty;
    final memberItems = memberSource ? chat.sessionItems : chat.items;
    final visible = target.memberId == null
        ? visibleRoomItems(
            chat.items,
            mode,
            speakerOf: (item) => roomSpeakerOf(room, team, item),
          )
        : memberTargetItems(
            memberItems,
            target.memberId!,
            speakerOf: (item) => roomSpeakerOf(room, team, item),
          );
    if (!_flashPrimed) {
      _rememberFlash(room, team, mode, target);
    }
    ref.listen(roomChatProvider(widget.roomId).select((s) => s.items), (_, _) {
      if (mounted) _rememberFlash(room, team, mode, target);
    });
    // 「只看某人」 keeps the user's own lines, so an empty list no longer means
    // the member is silent. Say it over those lines instead of not at all.
    final memberSilent =
        !mode.isAll &&
        target.memberId == null &&
        !visible.any(
          (item) => item.kind != DsBotItemKind.user && roomSpeakerOf(room, team, item) == mode.memberId,
        );
    final transcript = transcriptRows(withoutDoneEchoes(visible), pending: chat.pending, typing: typing);
    // The group's own Session is what the admin's memory tools write to; in a
    // member's conversation the line would belong to another conversation.
    final memoryNotices = target.memberId == null && room.sessionId != null
        ? ref.watch(sessionMemoryNoticesProvider(room.sessionId!))
        : const <int, MemoryNotice>{};
    final rows = attachMemoryNotices(
      attachMemberArtifacts(
        attachArtifacts(transcript, groupArtifacts, atOldestEnd: !chat.hasEarlier),
        deliveredByBot,
        roundStart: _lastUserRow(transcript),
      ),
      memoryNotices,
    );
    final topInset = BotChatHeader.heightOf(context);
    final readOnly = status.readOnly != null;
    final connected = ref.watch(activeConnectionProvider).value != null;
    // 运行时与异常时让位：最右必须是停止或警示，最重要的事不躲进菜单。
    ({IconData icon, String tooltip, VoidCallback? onTap, Color? color})? situationKey() {
      void say(String text) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(text)));
      if (!connected) {
        return (
          icon: AppIcons.warning,
          tooltip: l10n.commonNotConnected,
          onTap: () => say(l10n.commonNotConnected),
          color: DshColors.of(context).warning,
        );
      }
      if (readOnly) {
        return (
          icon: AppIcons.warning,
          tooltip: l10n.botsReadOnlyNote,
          onTap: () => say(l10n.botsReadOnlyNote),
          color: DshColors.of(context).warning,
        );
      }
      return null;
    }

    // 目标在不在，决定群名要不要让位给胶囊：没有目标时群名必须是完整那颗。
    final goalNow = ref.watch(groupGoalProvider(room.id)).value;
    final hasGoal = goalNow != null && goalNow.title.isNotEmpty;
    ref.listen(groupGoalProvider(room.id), (previous, next) {
      final gone = next.value == null || next.value!.title.isEmpty;
      if (!gone) return;
      // 目标没了：按群记的「收起成小球」一并作废、回到默认完整。顶栏形态这一
      // 帧已经按 hasGoal 判了，所以群名立刻恢复，不用 setState 也不等交互。
      _goalExpandedByRoom.remove(room.id);
      _goalExpanded = true;
    });

    return BotAdaptiveFrame(
      drawer: _drawerConfig,
      // The column beside the chat: this conversation's details. A member who
      // has no conversation in this group yet leaves it saying why.
      panel: targetBot == null
          ? SessionDetailPage.panel(key: ValueKey('room-detail-$roomSession'), sessionId: roomSession)
          : memberSession == null
          ? const _MemberDetailMissing()
          : SessionDetailPage.panel(
              key: ValueKey('member-detail-$memberSession'),
              sessionId: memberSession,
            ),
      builder: (context, layout) => BotChatFrame(
      header: BotChatHeader(
        // Three columns: the rail owns the chats key, the header drops its own.
        showLeading: !layout.isExpanded,
        // The group is what the page is about, in either conversation: its face
        // and its title stay, and the member is named on the line below.
        face: RoomAvatar(room: room, team: team, size: BotChatHeader.faceSize),
        title: room.name,
        titleHint: targetBot == null ? null : l10n.botsRoomBackToGroupChat(room.name),
        // One member's conversation says whose it is and which group it belongs
        // to: without that line the single-chat-shaped page reads as a private
        // chat.
        status: targetBot == null
            ? (statusLine.spoken == 0
                  ? statusLine.label
                  : '${statusLine.label} · ${l10n.botsAlreadySpoke} ${statusLine.spoken}')
            : '‹ ${l10n.botsGroupChat} · ${targetBot.name}',
        tone: statusLine.tone,
        scrolledUnder: _scrolled,
        onLeading: () => onBotMenu(context, ref, layout, () => _drawer.toggle(context)),
        leadingTooltip: botMenuTooltip(context, layout),
        // The title capsule is the group's: in a member's conversation it
        // switches back to the group chat, in the group chat it opens the
        // group's own details, as it always did.
        onDetails: targetBot == null
            ? () => Navigator.of(context).push(RoomDetailsPage.route(room.id))
            : () => _switchTarget(RoomChatTarget.all),
        // 群目标的顶栏：默认完整胶囊，点了才收成小球。窄屏（非三栏）时标题
        // 让给胶囊——它撑满一行，群名缩成圆头像；宽屏时两者都完整。
        //
        // 群名始终完整：合体态头像是「组内最左那颗、可点」，小球态群名也完整。
        // （旧的「窄屏把群名缩成头像」按用户口径去掉了。）
        titleCompact: false,
        // 有目标且没收成小球：目标并进群名那颗胶囊（一颗外壳、两段可点）。
        mergeTrailing: hasGoal && _goalExpanded,
        trailing: GoalBarProbe(
          roomId: room.id,
          expanded: _goalExpanded,
          bare: hasGoal && _goalExpanded,
          narrow: !layout.isExpanded,
          onExpand: () => _setGoalExpanded(true),
          onCollapse: () => _setGoalExpanded(false),
        ),
        // 没有目标时也不撑满：否则标题那颗仍按「展开态」布局，群名回不到正常。
        trailingExpand: hasGoal && _goalExpanded && !layout.isExpanded,
        // Right key = this conversation's details: the group's aggregate in the
        // group chat, the member's own Session in this group otherwise — never a
        // private one, and never the group's numbers under a member's name.
        onInfo: openInfo,
        // ⋯: the page's menu, anchored under the key (not a bottom sheet).
        // Details leads it — the key no longer carries that job alone — then the
        // message range, then the members.
        menuController: _roomMenu,
        menuChildren: (_, controller) => roomMenuItems(
          context,
          ref,
          room: room,
          team: team,
          onDetails: openInfo,
          controller: controller,
        ),
        action: situationKey(),
        infoGreyed: infoGreyed,
        infoTooltip: layout.isExpanded && layout.panelAvailable
            // Beside the chat the key is a switch for the column.
            ? (ref.watch(layoutPrefsProvider).panelOpen ? l10n.shellCollapseDetails : l10n.shellChatDetails)
            : targetBot == null
            ? null
            : (memberSession == null
                  ? l10n.botsRoomMemberSessionMissing
                  : l10n.botsRoomMemberDetails(targetBot.name)),
        // A filter is state, not an action: while one is on, a marker takes the
        // old key's place and says what it is; with none, nothing shows and the
        // title keeps the width.
        chip: mode.memberId == null
            ? null
            : _MessageFilterChip(
                label: l10n.botsRoomOnly(team.bot(mode.memberId!)?.name ?? mode.memberId!),
                // 窄屏群名要让出来：标记收成一颗 ×，宽屏才带名字。
                compact: !layout.isExpanded,
                onClear: () => ref.read(roomMessageModesProvider.notifier).set(room.id, RoomMessageMode.all),
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
              hasEarlier: memberSource ? chat.hasSessionEarlier : chat.hasEarlier,
              loadingEarlier: chat.loadingEarlier,
              onEarlier: () =>
                  ref.read(roomChatProvider(widget.roomId).notifier).loadEarlier(session: memberSource),
              notice: memberSilent
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Text(
                        l10n.botsMessageModeEmptyStretch,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: DshColors.of(context).textTertiary),
                      ),
                    )
                  : null,
              empty: targetBot != null
                  ? Center(
                      child: Text(
                        l10n.botsMessageModeEmpty,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary),
                      ),
                    )
                  : mode.isAll
                  ? _Members(room: room, team: team)
                  : Center(
                      child: Text(
                        l10n.botsMessageModeEmptyStretch,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary),
                      ),
                    ),
              rowBuilder: (context, row) => Padding(
                padding: rowPadding(row),
                child: switch (row) {
                  BotTimeRow(:final time) => BotTimeLine(time),
                  BotPendingRow(:final pending) => _pendingBubble(pending, chat.inbox, running: chat.running),
                  BotStreamingRow() => const SizedBox.shrink(),
                  BotTypingRow(:final bot, :final label) => BotTypingLine(bot: bot, label: label),
                  // A group has no tool events to show; the row exists so the
                  // switch stays exhaustive, and the same widget keeps it honest.
                  // A group's delivered cards come from each member's Session for
                  // this group (see attachMemberArtifacts), not from the group's
                  // own turns — a group line carries no DSH turn to place them by.
                  BotArtifactsRow(:final group, :final sessionId) =>
                    ArtifactCard(sessionId: sessionId ?? roomSession, group: group),
                  // A member's memory write, under the member's own line.
                  BotMemoryNoticeRow(:final notice, :final botId) => BotMemoryLine(
                    notice: notice,
                    onTap: () => Navigator.of(
                      context,
                    ).push(BotMemoryPage.route(botId: botId, roomId: botId == null ? room.id : null)),
                  ),
                  BotToolGroupRow(:final items) => BotToolGroup(items: items),
                  BotItemRow(:final item, :final continued, :final figures) => switch (item.kind) {
                    // As in a Bot's chat: the echoed line names what it carried,
                    // so the picture stays on screen after the round settles.
                    DsBotItemKind.user => BotUserMessage(
                      text: botLineText(item),
                      images: item.images,
                      attachments: botLineAttachments(
                        item,
                        roomSession,
                        onOpenFile: (file) => openBotAttachmentFile(context, ref, file: file, roomId: room.id),
                      ),
                      onQuote: _setQuote,
                    ),
                    DsBotItemKind.bot => _groupRow(
                      context,
                      item,
                      continued: continued,
                      figures: figures,
                      room: room,
                      team: team,
                      roomSession: roomSession,
                      fullTextScope: fullTextScope,
                      mentions: memberMentions,
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
                    // A member's thinking, drawn as the conversation draws it:
                    // the same collapsible pill, under that member's face, and
                    // it stays while their reply streams below.
                    DsBotItemKind.thinking =>
                      item.text.trim().isEmpty
                          ? const SizedBox.shrink()
                          : BotThinkingLine(
                              text: item.text,
                              bot: team.bot(item.botId),
                              active: chat.running && item == chat.items.last,
                              streaming: chat.running,
                            ),
                    _ => const SizedBox.shrink(),
                  },
                },
              ),
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
        // The group keeps its own status line, and carries the conversation's
        // todo, goal and permission bars too — the group's Session has them,
        // and a person who works in here should not lose the reminders they
        // have in a single chat. Without a Session yet (an older Host), the
        // bars would read an id that has no modes, so they stay off.
        BotComposerDeck(
          sessionId: roomSession,
          roomId: room.id,
          running: chat.running,
          showSessionBars: room.sessionId != null,
          // The deck speaks for whatever the page shows: the group's own
          // line on the group chat, that member's line on a member target.
          roomActivity: target.memberId == null ? statusLine : null,
          activitySessionId: memberSession,
          // 成员视图里也要知道是谁在写：拿这个成员的 Bot 当打字行的脸和名字。
          activityBot: targetBot,
          // 点活动行看这一轮：普通会话点它是「本轮轨迹」，群里跑的是某位成员，
          // 就打开那位成员在本群的这一轮；还没有轮次时退到用量面板。
          onRoomActivityTap: () {
            final running = target.memberId == null ? statusLine.sessionId : memberSession;
            if (running != null) _openRunningTrajectory(running);
          },
          showActivity: target.memberId == null || (memberSession != null && memberSession.isNotEmpty),
        ),
        // One member's conversation still sends to the group, so say it above
        // the field where the doubt starts. Not the field's own hint: that one
        // disappears as soon as the person types.
        AnimatedSize(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.bottomCenter,
          child: targetBot == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(AppIcons.groupChat, size: 12, color: DshColors.of(context).textTertiary),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            l10n.botsRoomSendsToGroup,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.35,
                              color: DshColors.of(context).textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        // The accessory shows while the field is empty, so the field's text is
        // listened to here (the Composer listens to it anyway).
        ListenableBuilder(
          listenable: _input,
          builder: (context, _) => Composer(
            hardwareEnterSends: ref.watch(settingsProvider.select((s) => s.hardwareEnterSends)),
          // The native chat's own line count for the same screen and text
          // size, so the field grows the same way here.
          maxLines: Composer.linesFor(context),
          busy: chat.loading,
            voice: _voice,
            controller: _input,
            placeholder: l10n.botsGroupComposerHint,
            // A group's 插话 only affects the relay Session and is unverified:
            // name what the send key really does — queued until this round ends.
            runningHint: chat.running ? l10n.chatGeneratingQueueHint : null,
            focusNode: _focus,
            connected: api != null && !readOnly,
            running: chat.running,
            onSend: () => _send(sendTarget),
            onSendOptions: () => _sendOptions(sendTarget, room, running: chat.running),
            onStop: _stopGuard.action(roomId: room.id),
            onKeyEvent: _mentions.handleKey,
            // The ring is the group's total; the microphone appears only while a
            // run holds the send key and the field is empty.
            accessory: _composerAccessory(room: room, running: chat.running),
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
        ),
      ],
      ),
    );
  }
}

/// The column beside a member's conversation that has none of its own in this
/// group yet: the same reason the greyed key gives.
class _MemberDetailMissing extends StatelessWidget {
  const _MemberDetailMissing();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        context.l10n.botsRoomMemberSessionMissing,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: DshColors.of(context).textTertiary),
      ),
    ),
  );
}

/// The microphone a group needs while a run holds the send key: the same quiet
/// circle the Composer draws when that key is the microphone, so the row looks
/// unchanged from the conversation's side.
class _ComposerMicKey extends StatelessWidget {
  const _ComposerMicKey({required this.onPressed});

  final VoidCallback onPressed;

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: l10n.chatVoiceInput,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: colors.onSurface.withValues(alpha: 0.06), shape: BoxShape.circle),
          child: Icon(AppIcons.voice, size: 22, color: colors.onSurface),
        ),
      ),
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

/// 顶栏的过滤标记：「只看 某人 ×」。只在过滤生效时出现，点 `×` 回「全部」；
/// 不过滤时整颗不存在，宽度还给群名。
class _MessageFilterChip extends StatelessWidget {
  const _MessageFilterChip({required this.label, required this.onClear, this.compact = false});

  final String label;
  final VoidCallback onClear;

  /// 窄屏只留这颗 ×：名字在 tooltip 与读屏里，群名不被挤窄。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = DshColors.of(context);
    if (compact) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: 32,
          child: GlassSurface(
            tier: GlassTier.chrome,
            circle: true,
            grouped: true,
            onTap: onClear,
            child: Tooltip(
              message: label,
              child: Center(child: Icon(AppIcons.close, size: 15, color: theme.colorScheme.primary)),
            ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: SizedBox(
        height: 32,
        child: GlassSurface(
          tier: GlassTier.chrome,
          stadium: true,
          grouped: true,
          onTap: onClear,
          child: Tooltip(
            message: label,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(AppIcons.close, size: 13, color: dsh.textTertiary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 群聊顶栏 ⋯ 的下拉菜单里的行：对话详情、消息范围、成员。菜单本身锚在键上
/// （`_AnchoredMenu`），从按钮下方展开、右边缘与按钮对齐；这里只给行，行高 52、
/// 图标 + 文字，跟其他菜单同一套行。清空会话、搜索此群这一版不做。
List<Widget> roomMenuItems(
  BuildContext context,
  WidgetRef ref, {
  required DsBotRoom room,
  required DsBotTeam team,
  required VoidCallback onDetails,
  required MenuController controller,
}) {
  final l10n = context.l10n;
  void close() {
    if (controller.isOpen) controller.close();
  }

  return [
    SettingsTile(
      icon: AppIcons.info,
      tinted: false,
      chevron: false,
      title: l10n.commonDetails,
      onTap: () {
        close();
        onDetails();
      },
    ),
    SettingsTile(
      icon: AppIcons.multiSelect,
      tinted: false,
      chevron: false,
      title: l10n.botsMessageScope,
      onTap: () {
        close();
        showMessageScopeSheet(context, ref, room: room, team: team);
      },
    ),
    SettingsTile(
      icon: AppIcons.groupChat,
      tinted: false,
      chevron: false,
      title: l10n.botsMembers,
      onTap: () {
        close();
        Navigator.of(context).push(RoomDetailsPage.route(room.id));
      },
    ),
  ];
}
