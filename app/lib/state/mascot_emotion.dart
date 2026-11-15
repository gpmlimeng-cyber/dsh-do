// 吉祥物表情: 把 lively-mascot 的 40 个情绪接到我们会话状态上。
//
// 纯调度层,不画东西(渲染在 ui/mascots/)。[emotionFor] 是纯函数: 同一个
// [MascotMoment] 永远得到同一个表情, 方便单测; 时间相关只走 [now] 参数。
//
// 三条规则:
//   1. 状态一变立刻换表情, 不排队 —— 每次重建都用最新 moment 重算。
//   2. 列表/置顶瓦片只画静态帧, 聊天页/资料卡才按 emotion 播动画(渲染层决定)。
//   3. 瞬时表情只有 Success(完成一轮, 停 1.5 秒); 其余都是由状态本身维持的
//      粘性表情, 状态消失就回落, 不需要计时器。

import 'package:dsh_client/dsh_client.dart';

/// lively-mascot 的 40 个情绪, id 与它的 `LivelyEmotions` 一一对应。
enum MascotEmotion {
  sleep('00', 'Sleep'),
  wake('01', 'Wake'),
  idle('02', 'Idle'),
  breathe('03', 'Breathe'),
  ready('04', 'Ready'),
  pause('05', 'Pause'),
  refresh('06', 'Refresh'),
  lowBattery('07', 'LowBattery'),
  offline('08', 'Offline'),
  boot('09', 'Boot'),
  happy('10', 'Happy'),
  curious('11', 'Curious'),
  aggrieved('12', 'Aggrieved'),
  angry('13', 'Angry'),
  surprised('14', 'Surprised'),
  shy('15', 'Shy'),
  love('16', 'Love'),
  confused('17', 'Confused'),
  cool('18', 'Cool'),
  smug('19', 'Smug'),
  thinking('20', 'Thinking'),
  listening('21', 'Listening'),
  talking('22', 'Talking'),
  searching('23', 'Searching'),
  reading('24', 'Reading'),
  writing('25', 'Writing'),
  coding('26', 'Coding'),
  designing('27', 'Designing'),
  loading('28', 'Loading'),
  processing('29', 'Processing'),
  success('30', 'Success'),
  error('31', 'Error'),
  grateful('32', 'Grateful'),
  retrying('33', 'Retrying'),
  cancelled('34', 'Cancelled'),
  crying('35', 'Crying'),
  bored('36', 'Bored'),
  nervous('37', 'Nervous'),
  eureka('38', 'Eureka'),
  waiting('39', 'Waiting');

  const MascotEmotion(this.id, this.name);

  /// The engine's id (`"02"`), the key its CSS uses.
  final String id;

  /// The engine's name (`Idle`), for debug logs and the gallery page.
  final String name;
}

/// 连接状态, 来自 `DsBotStatus.availability` + `feedConnected`。
enum MascotLink {
  /// ready 且 feed 连着。
  online,

  /// 连主机 / 问 DS Bot / 引擎启动中。
  boot,

  /// ready 但 feed 掉线, 正在自动重连。
  retrying,

  /// 没有主机、或中继不转发插件路由。
  offline,

  /// 主机没有 DS Bot、版本不兼容、或 DS Bot 答非所问。
  failed,
}

/// 这一轮在做什么, 来自 `DsBotLive.bots[botId]` 与 `DsBotItem` 流式状态。
enum MascotWork { none, thinking, searching, coding, talking }

/// One moment of a Bot, as the avatar should show it.
class MascotMoment {
  const MascotMoment({
    this.link = MascotLink.online,
    this.work = MascotWork.none,
    this.waiting = false,
    this.error = false,
    this.paused = false,
    this.listening = false,
    this.unread = false,
    this.settledAt,
    this.idleSince,
  });

  final MascotLink link;
  final MascotWork work;

  /// 有等你确认的问题/审批卡。
  final bool waiting;

  /// 上一轮失败, 用户还没处理。
  final bool error;

  /// 目标被暂停, 或开着但已解除自动推进。
  final bool paused;

  /// 群里别的成员正在跑, 这个 Bot 在听。
  final bool listening;

  /// 有未读, 或被 @。
  final bool unread;

  /// 刚跑完一轮的时刻; 只在过去 1.5 秒内算 Success。
  final DateTime? settledAt;

  /// 进入空闲的时刻, 用来区分 Idle 与长时间无动作的 Breathe。
  final DateTime? idleSince;
}

/// 一个表情, 以及它是不是瞬时(需要调用方计时回落)。
class MascotMood {
  const MascotMood(this.emotion, {this.transient = false, this.hold});

  final MascotEmotion emotion;

  /// 只由定时器维持的表情; 现在只有 Success。
  final bool transient;

  /// 瞬时的剩余时长; 调用方 `Timer(hold, …)` 后重算即可回落。
  final Duration? hold;
}

/// 完成一轮后 Success 停留的时间。
const mascotSuccessHold = Duration(milliseconds: 1500);

/// 空闲多久后从 Idle 变 Breathe。
const mascotIdleBreatheAfter = Duration(seconds: 30);

/// 这个 Bot 现在该是什么表情。纯函数, 同一输入同一输出。
///
/// 优先级(高 → 低): 连接 → 等你确认 → 出错 → 暂停 → 正在做 → 旁听 →
/// 刚完成(瞬时) → 未读 → 空闲/呼吸。连接类排最前, 因为那时其余状态都不可信。
MascotMood emotionFor(MascotMoment moment, {DateTime? now}) {
  switch (moment.link) {
    case MascotLink.offline:
      return const MascotMood(MascotEmotion.offline);
    case MascotLink.boot:
      return const MascotMood(MascotEmotion.boot);
    case MascotLink.retrying:
      return const MascotMood(MascotEmotion.retrying);
    case MascotLink.failed:
      return const MascotMood(MascotEmotion.error);
    case MascotLink.online:
      break;
  }
  if (moment.waiting) return const MascotMood(MascotEmotion.waiting);
  if (moment.error) return const MascotMood(MascotEmotion.error);
  if (moment.paused) return const MascotMood(MascotEmotion.pause);

  switch (moment.work) {
    case MascotWork.searching:
      return const MascotMood(MascotEmotion.searching);
    case MascotWork.coding:
      return const MascotMood(MascotEmotion.coding);
    case MascotWork.talking:
      return const MascotMood(MascotEmotion.talking);
    case MascotWork.thinking:
      return const MascotMood(MascotEmotion.thinking);
    case MascotWork.none:
      break;
  }
  if (moment.listening) return const MascotMood(MascotEmotion.listening);

  final at = now ?? DateTime.now();
  final settled = moment.settledAt;
  if (settled != null) {
    final elapsed = at.difference(settled);
    if (elapsed >= Duration.zero && elapsed < mascotSuccessHold) {
      return MascotMood(MascotEmotion.success, transient: true, hold: mascotSuccessHold - elapsed);
    }
  }

  if (moment.unread) return const MascotMood(MascotEmotion.curious);

  final idle = moment.idleSince;
  if (idle != null && at.difference(idle) >= mascotIdleBreatheAfter) {
    return const MascotMood(MascotEmotion.breathe);
  }
  return const MascotMood(MascotEmotion.idle);
}

/// 把 `DsBotWork` + 流式状态折成一个 [MascotWork]。
///
/// 搜索/改文件按工具名分, 其余工具(读、记忆、团队…)统一算思考——表只要求
/// 这三种精细动作。正在流式输出且没有工具在跑时是说话。
MascotWork mascotWorkOf(DsBotWork? work, {bool streaming = false, String? activity}) {
  if (work != null) {
    if (work.switching) return MascotWork.thinking;
    final tool = work.tool;
    if (tool != null) {
      if (tool == 'web_search' || tool.contains('search')) return MascotWork.searching;
      if (const {'write', 'edit', 'apply_patch', 'str_replace_editor'}.contains(tool)) return MascotWork.coding;
      return MascotWork.thinking;
    }
    return MascotWork.thinking;
  }
  if (streaming) return MascotWork.talking;
  if (activity == 'thinking') return MascotWork.thinking;
  return MascotWork.none;
}
