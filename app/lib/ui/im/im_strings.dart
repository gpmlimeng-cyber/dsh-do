// 轻松模式界面文案：本机没有 Flutter，`lib/l10n/gen/` 无法重新生成，所以这一批
// 新文案先放在这里做双语；等哪天能跑 `flutter gen-l10n`（或拿到 l10n workflow
// 的产物），整体迁到 `lib/l10n/parts/im_zh.arb` / `im_en.arb`，删掉这个文件。
//
// 键名与将来 arb 的键一一对应，迁移时机械替换即可。
// l10n:keep-begin 本地双语表（迁移到 arb 前不参与扫描）
import '../../l10n/l10n.dart';

abstract final class ImStrings {
  static bool get _zh => AppLocale.current.languageCode == 'zh';

  // ── 底栏 ──
  static String get tabMessages => _zh ? '消息' : 'Messages';
  static String get tabCompanions => _zh ? '伙伴' : 'Buddies';
  static String get tabDiscover => _zh ? '发现' : 'Discover';
  static String get tabMe => _zh ? '我' : 'Me';

  // ── 消息 ──
  static String get messagesTitle => _zh ? '消息' : 'Messages';
  static String get pinnedGroup => _zh ? '置顶' : 'Pinned';
  static String get chatsGroup => _zh ? '对话' : 'Chats';
  static String get roomsGroup => _zh ? '群聊' : 'Groups';
  static String get newBot => _zh ? '新建 Bot' : 'New Bot';
  static String get newRoom => _zh ? '新建群聊' : 'New group';
  static String get search => _zh ? '搜索' : 'Search';
  static String get markRead => _zh ? '标为已读' : 'Mark as read';
  static String get emptyBotsTitle => _zh ? '还没有 Bot' : 'No Bots yet';
  static String get emptyBotsBody => _zh ? '建一个，随便聊点什么。' : 'Create one and just talk.';
  static String get emptyBotsCreate => _zh ? '创建 Bot' : 'Create a Bot';
  static String get emptyBotsDiscover => _zh ? '去发现里看看' : 'Look around Discover';
  static String get notInLight => _zh ? '普通会话要在专业模式里打开' : 'Plain conversations open in Pro mode';

  // ── 伙伴 ──
  static String get companionsTitle => _zh ? '伙伴' : 'Buddies';
  static String get memoryHint => _zh ? '点开看它记得什么' : 'See what it remembers';
  static String get profileSend => _zh ? '发消息' : 'Message';
  static String get profileAbilities => _zh ? '它现在能做什么' : 'What it can do';
  static String get profileSettings => _zh ? '它的设定' : 'Its instructions';
  static String get profileMemory => _zh ? '它记得的事' : 'What it remembers';
  static String get profileDelete => _zh ? '删除 Bot' : 'Delete Bot';
  static String memoryCount(int n) => _zh ? '它记得 $n 件事' : 'Remembers $n things';
  static String get memoryEmpty => _zh ? '还没记住什么' : 'Nothing remembered yet';

  // ── 发现 ──
  static String get discoverTitle => _zh ? '发现' : 'Discover';
  static String get groupChats => _zh ? '会话' : 'Chats';
  static String get groupContents => _zh ? '内容' : 'Content';
  static String get groupTools => _zh ? '工具' : 'Tools';
  static String get groupExtensions => _zh ? '扩展' : 'Extensions';
  static String get groupHost => _zh ? '主机' : 'Host';
  static String get groupSettings => _zh ? '设置' : 'Settings';
  static String get pets => _zh ? '桌宠' : 'Desk pet';
  static String get remote => _zh ? '主机与远程' : 'Host & remote';
  static String get needsConversation => _zh ? '先在时间线里和 Bot 聊一句' : 'Chat with a Bot first';

  // ── 我 ──
  static String get meTitle => _zh ? '我' : 'Me';
  static String get meAboutAi => _zh ? 'AI 对我的了解' : 'What the AI knows about me';
  static String get meAppearance => _zh ? '外观' : 'Appearance';
  static String get meServices => _zh ? 'AI 服务' : 'AI services';
  static String get meAdvanced => _zh ? '高级' : 'Advanced';
  static String get meAbout => _zh ? '关于' : 'About';
  static String get meFooter => _zh ? '轻松模式 · 数据与专业模式相同' : 'Light mode · same data as Pro';
  static String serviceCount(int n) => _zh ? '$n 个服务' : '$n services';

  // ── 时间线（轻量外观） ──
  static String get segmentDivider => _zh ? '上下文已满，从这里开始新的一段' : 'Context was full — a new part starts here';
  static String get moreMenu => _zh ? '更多' : 'More';
  static String get openInPro => _zh ? '在专业模式里打开' : 'Open in Pro mode';
  static String get profile => _zh ? 'Bot 资料' : 'Bot profile';
  static String get retry => _zh ? '重试' : 'Try again';
  static String get errorSoft => _zh ? '网络有点卡，没收到回复' : "The network hiccuped — no reply came back";
  static String get confirmationHint => _zh ? '它想让你确认一下' : 'It needs your OK';
  static String get allow => _zh ? '允许' : 'Allow';
  static String get allowOnce => _zh ? '这次不用' : 'Not this time';

  // ── 空态建议 ──
  static String get introWhatCanYouDo => _zh ? '你能做什么？' : 'What can you do?';
  static String get introPlanMyDay => _zh ? '帮我梳理今天的任务' : 'Help me plan my day';
  static String get introJustChat => _zh ? '随便聊聊' : "Let's just talk";

}
// l10n:keep-end
