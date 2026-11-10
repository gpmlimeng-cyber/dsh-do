# 上游 v1.0.15 合并 · 第 2 段核对清单（草稿）

> 用途：A/B 批解完后，逐条核对「本地独有功能是否还在」+「上游 1.0.15 新能力是否真的进来了」。
> 依据：用户定的口径（像素微调不重放、布局跟上游、只保本地运行时逻辑与群聊功能）。
> 状态：草稿。A/B 未解完前不执行；执行时把每条勾成 ✅ / ❌（❌ 附文件与现象）。

## 一、本地独有六项（少一条都不算过）

判断方式：先 `grep` 锚点确认代码在，再按「判据」看行为；**代码在但行为不对也算 ❌**。

### 1) 群目标胶囊与面板

- 锚点：`GoalBarProbe`、`GroupGoalBar`（`group_goal.dart`）、`pillHeightOf`、`_goalExpanded`、`hasGoal`（`room_chat_page.dart`）
- 判据：
  - 群聊顶栏有目标胶囊，显示阶段/进度；点开是浮卡面板（86% 高度、阶段步进器、底部按钮在折叠行**上方**、底栏浅色、一段也画步进器）。
  - 群聊**不画**目标卡、不画待办卡（`showSessionBars = room.sessionId != null` 时也不会两张一起亮）。
  - 暂停/恢复/停止按 `docs/composer-strip.md` §10.5 的 2×2 分派。
- ❌ 失败症状：胶囊不出现 / 出现两张 / 面板按钮跑到折叠行下面 / 停止只停 relay 却显示已停。
- 威胁来源：B 批 `room_chat_page.dart`、`bot_chat_kit.dart`；上游 1.0.15 改过 `chat_header` 与输入区布局。

### 2) 消息范围（群聊与成员会话）

- 锚点：`RoomMessageMode`、`visibleRoomItems`（`state/room_message_mode.dart`）、`roomMessageModeProvider`
- 判据：消息模式键存在；切「只看某人」时只显示该成员的行；空态文案是「这一段里没有他的发言」且作为列表里一条出现（不是整屏替换）；保留我自己的 user 行。
- ❌ 失败症状：过滤失效 / 空态不出现 / 整屏空。
- 威胁来源：B 批 `room_chat_page.dart`；上游 1.0.15 的消息流布局改动。

### 3) ⋯ 菜单

- 锚点：`AppIcons.more`、`BotChatHeader.onMenu` / `menuController` / `menuChildren`（`bot_chat_kit.dart`，锚定下拉不是底部抽屉）
- 判据：右侧键最左是 ⋯（详情已并进菜单第一项）；锚定下拉、宽 176；项序：对话详情 / 消息范围 / 成员（本版只三项）；危险项红字单独分组（本版无清空项，先不出现）。
- ❌ 失败症状：详情键又单独出现 / 菜单顺序变 / 宽度不对。
- 威胁来源：B 批 `bot_chat_kit.dart`（顶栏键区）。

### 4) 消息脚注同一行

- 锚点：`smallStyle`（`bot_chat_kit.dart`）
- 判据：一条消息的脚注里「名字 → admin → 时间 → 统计」在同一行、共用同一字号；大字号下不换行错位。
- ❌ 失败症状：脚注被拆两行 / 字号不一致。
- 威胁来源：B 批 `bot_chat_kit.dart`；上游 1.0.15 改过消息行结构。

### 5) route observer 返回不弹键盘

- 锚点：`appRouteObserver`（`ui/common/route_observer.dart`，注册在 `app.dart`）、两处 `RouteAware`（`bot_chat_page.dart`、`room_chat_page.dart`）
- 判据：从详情页/设置页返回会话页，输入框**不**自动弹键盘；离开页面时键盘收起。
- ❌ 失败症状：返回就弹键盘 / 页面被销毁（或重复订阅）。
- 威胁来源：B 批两个页面；上游 1.0.15 改过页面生命周期。

### 6) 输入框上方一格

- 锚点：`bot_composer_deck.dart` 的「36 + 6 = 42」那一格、`ComposerStripSlot` / `ComposerStripSlot.fallback`
- 判据：活动行 / 插件条 / 胶囊行**三选一**，永远只有一条；高 42；群聊与私聊都不叠两行。
- ❌ 失败症状：两行同时出现 / 高度跳变 / 活动行与插件条各占一行。
- 威胁来源：B 批 `bot_composer_deck.dart`；上游 1.0.15 的输入区重构。

## 二、上游 1.0.15 新能力（要确认真的进来了，不是被我们冲掉）

对照 `v1.0.15:docs/changelog.md` 的 1.0.13–1.0.15 三段，只看与本仓冲突面相关的：

| 上游能力 | 判据 | 主要落点 |
|---|---|---|
| 更新引擎不再清空 Linux 环境（只替换 App 管的引擎部分） | 更新流程代码里能看出「保留用户目录」，`apt`/pip 包不删 | `app/lib/ui/engine/*`、`runtime/*` |
| 匿名统计加机型与系统版本 | 统计项里出现型号/系统版本，且隐私页开关仍生效 | `app/lib/state/*`、`app/lib/ui/settings/*` |
| 扫码配对修 ML Kit（#802） | 扫码前按需准备 ML Kit；SDK 错与无码分开提示 | `LinksPlugin.kt`、配对页 |
| 手机操控多任务（每任务独立暂停/停止、后台任务上限 3、实时后台预览、截图坐标操作、存成技能、本机自检） | A 批 Kotlin 与悬浮条/通知的动作只作用于显示时那个任务；上限可配 | `app/android/.../phone/**`、`runtime/bridge/**` |
| 伙伴小屋（随包内置鲸鱼娘、她多主动四档、模型 zip 导入、表情动作、AI 适配、像素宠物导入） | 首次进小屋自动安置；菜单四项频率；导入/适配入口在 | `app/lib/companion/*`、`app/lib/ui/companion/*`、`app/assets/companion/*` |
| 远程：电脑上开终端、会话文件页「传文件到电脑」 | 入口在，远程断开时有说明 | `app/lib/remote/*`、`app/lib/ui/chat/*` |
| 诊断采集输入法日志 | 诊断页可逐次确认后采集，只留白名单事件 | `app/lib/diagnostics/*` |
| 网页版返回键换 App 标记、系统返回先收官方侧栏 | 关手机布局时行为一致 | `app/lib/ui/web/*` |
| 依赖新增 `image`、`mobile_scanner` | `pubspec.yaml` 有且能构建 | C 批（已取上游） |
| l10n 新增一大批（伴生、宠物、手机操控等） | `gen/` 由 `l10n_merge.py` 重生成，不手改 | B 批 l10n + C 批工具 |

## 三、冲突面交叉检查（最容易互相踩的三处）

1. **手机操控**：A 批取上游逻辑后，本地「不打扰模式/悬浮条/后台探针」的参数与行为要逐条保留（用户明确点过这三块）。
2. **伙伴小屋**：B 批 `app/lib/companion/*` 与 `stage.js`（C 批已取上游）要配套——上游 stage.js 变了（模型适配、mask 分块），App 侧调用参数若还是旧的会白屏或错位。
3. **输入区**：上游 1.0.15 的输入区/首页改动 vs 本地的「42 高一格」与「新对话面板」——两者都在 `bot_composer_deck` / `composer` 附近，解冲突后必须真机看一次，不能只看代码。

## 四、执行顺序

1. A/B 两批解完、`git diff --diff-filter=U` 为空。
2. 本清单第一、二节逐条 grep + 代码审；第三节点名交叉项。
3. 只对「代码在但行为可能变」的项进真机验证（第 1/2/5/6 项与交叉项 2、3）。
4. 结果回填台账 96 行「处理」列，并给产品经理收口。
