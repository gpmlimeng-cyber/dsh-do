// 设置 › 界面 里「聊天界面」那一段的文案：专业模式 / 轻松模式、首次说明卡。
//
// 本机没有 Flutter，`lib/l10n/gen/` 无法重新生成，所以这一批新文案先放这里做
// 双语；等能跑 `flutter gen-l10n`（或拿到 l10n workflow 的产物）时，整体迁到
// `lib/l10n/parts/hub_zh.arb` / `hub_en.arb`，删掉这个文件。
//
// 键名与将来 arb 的键一一对应（hubInterfaceChatFace 等），迁移时机械替换即可。
// l10n:keep-begin 本地双语表（迁移到 arb 前不参与扫描）

import '../../l10n/l10n.dart';

abstract final class ImFaceStrings {
  static bool get _zh => AppLocale.current.languageCode == 'zh';

  static String get faceTitle => _zh ? '聊天界面' : 'Chat interface';
  static String get pro => _zh ? '专业模式' : 'Professional';
  static String get light => _zh ? '轻松模式' : 'Light';
  static String get lightHint => _zh
      ? '像聊天一样和 Bot 说话；专业功能都还在，随时切回'
      : 'Talk to your Bots like a chat; every professional feature stays, switch back anytime';
  static String get lightNativeOnly => _zh
      ? '轻松模式只在本机原生界面运行，切回专业模式后可再选网页'
      : 'Light mode runs on the native interface only; choose the web home again in professional mode';
  static String get introTitle => _zh ? '轻松模式' : 'Light mode';
  static String get introBody => _zh
      ? '这里是轻松版：只有消息、伙伴、发现、我四个页面。终端、插件、全部设置这些入口还在「发现」和「全部设置」里，想全用就切回专业模式。'
      : 'This is the light home: four pages — Chats, Companions, Discover, Me. Terminals, plugins and every setting stay in Discover and All settings; switch back to professional mode for the full workspace.';
  static String get introStart => _zh ? '开始使用' : 'Start';
}
