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
  static String get companionBusy => _zh ? '正在忙' : 'Working';
  // ── 伙伴模板 ──
  static String get templateStart => _zh ? '从模板开始' : 'Start from a template';
  static String get templateAll => _zh ? '全部模板' : 'All templates';
  static String get templatesTitle => _zh ? '模板' : 'Templates';
  static String get templateSearch => _zh ? '搜名字或一句话' : 'Search name or one-liner';
  static String get templateAllCategory => _zh ? '全部' : 'All';
  static String get templateComingSoon => _zh ? '即将支持' : 'Coming soon';
  static String get templateUse => _zh ? '用这个模板创建' : 'Create from this template';
  static String get templateResponsible => _zh ? '它负责什么' : 'What it does';
  static String get templateHow => _zh ? '工作方式与边界' : 'How it works, and what it will not do';
  static String get templateSource => _zh ? '来源' : 'Source';
  static String get templateBlank => _zh ? '自己做' : 'Start from scratch';
  static String get addCompanion => _zh ? '添加伙伴' : 'Add a buddy';
  static String get blankCompanion => _zh ? '自己捏一个伙伴' : 'Make your own';
  static String get blankCompanionHint => _zh ? '起个名字，挑几个性格词就好' : 'A name, a few personality words';
  static String get templateAdded => _zh ? '已添加' : 'Added';
  static String get templateAdd => _zh ? '添加' : 'Add';
  static String get templateSeeAll => _zh ? '查看全部模板' : 'See all templates';
  static String get templateBlankHint => _zh ? '从空白伙伴开始' : 'A blank buddy';
  static String get companionWaiting => _zh ? '等你确认' : 'Needs you';
  static String get profileSend => _zh ? '发消息' : 'Message';
  static String get profileAbilities => _zh ? '它现在能做什么' : 'What it can do';
  static String get profileSettings => _zh ? '它的设定' : 'Its instructions';
  static String get profileMemory => _zh ? '它记得的事' : 'What it remembers';
  static String get profileDelete => _zh ? '删除 Bot' : 'Delete Bot';
  static String get renameBot => _zh ? '改名字' : 'Rename';
  static String get renameRole => _zh ? '改角色' : 'Edit role';
  static String get profileLook => _zh ? '更换形象' : 'Change look';
  static String get profileLookReset => _zh ? '恢复默认形象' : 'Reset look';
  static String get profileLookPhoto => _zh ? '用回宿主照片' : 'Use host photo';
  static String get lookKindMascot => _zh ? '吉祥物' : 'Mascot';
  static String get lookKindLetter => _zh ? '字团' : 'Letter';
  static String get lookKindEmoji => _zh ? '表情头像' : 'Emoji';
  static String get lookKindPhoto => _zh ? '宿主照片' : 'Host photo';
  static String get lookKindDefault => _zh ? '默认形象' : 'Default look';
  static String get roleEmpty => _zh ? '还没写角色' : 'No role yet';
  static String get profileSettingsHint => _zh ? '它要怎么说话' : 'How it should talk';
  static String deleteBotBody(String name) => _zh ? '删除「$name」后，它记得的事和对话都会没有。' : 'Deleting $name also removes its chats and what it remembers.';
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

  // ── 发现页卡片的一句话 ──
  static String get discoverBotsSub => _zh ? 'Bot 团队与群聊' : 'Bot teams and group chats';
  static String get discoverJobsSub => _zh ? '长任务现在跑到哪' : 'Where long jobs stand';
  static String get discoverWorkspacesSub => _zh ? '添加与切换目录' : 'Add and switch folders';
  static String get discoverShareSub => _zh ? '分享给同事' : 'Share with a colleague';
  static String get discoverTerminalSub => _zh ? '命令行' : 'A command line';
  static String get discoverPhoneSub => _zh ? '看屏幕、帮你点按' : 'See the screen, tap for you';
  static String get discoverVoiceSub => _zh ? '输入框里的麦克风' : 'The mic in the composer';
  static String get discoverPetsSub => _zh ? '桌面上的小家伙' : 'The little one on the desktop';
  static String get discoverPluginsSub => _zh ? '已安装与插件市场' : 'Installed and the market';
  static String get discoverSkillsSub => _zh ? '技能的开关' : 'Turn skills on and off';
  static String get discoverCommunitySub => _zh ? '精选与交流群' : 'Picks and chat groups';
  static String get discoverRemoteSub => _zh ? '连接电脑或服务器' : 'Connect a computer or server';
  static String get discoverEngineSub => _zh ? '运行时与版本' : 'Runtime and version';
  static String get discoverModelsSub => _zh ? '订阅与自定义渠道' : 'Subscriptions and channels';
  static String get discoverAllSettingsSub => _zh ? '所有设置项' : 'Every setting';

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
  static String get backToMessages => _zh ? '返回消息' : 'Back to messages';
  static String get pin => _zh ? '置顶' : 'Pin';
  static String get unpin => _zh ? '取消置顶' : 'Unpin';
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
