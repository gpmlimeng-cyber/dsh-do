# 群目标面板 · 与网页端 GoalPanel 逐块差异表（rc.17 口径）

- 对照基准：`ds-bot/src/client/goal.js` 的 `GoalPanel`（149–235 行，`STOP_ARM_MS` 在 145 行）
- 手机端：`dsh-212/app/lib/ui/bots/group_goal.dart`（HEAD `371e39a4`，含最新四条：折叠内容回到折叠行上方、卡片展开时 86%、「同时停止当前工作」并入底栏右侧、底栏用网页浅色、面板顶部补胶囊第二行）；顶栏入口在 `room_chat_page.dart:985–1035`
- 状态口径：**一致**＝行为与文案都对上；**按要求偏离**＝用户明确要求不同，不算回归；**平台性差异**＝Web 与原生控件形态不同，不追平；**已知未修**＝已确认差异，本轮不修；**未做**＝网页端有、本轮不做
- 行号说明：手机端行号是当前工作区的实测值；rc.17 合提交后若有偏移，以符号名（类名/方法名）为准

## A. 面板与容器

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| A1 | 面板容器 | `goal.js:149` `GoalPanel`，pod 挂在顶栏下，宽屏常驻 | `group_goal.dart:922` `_GoalExpandLayer`，浮卡，点卡外收起 | 平台性差异 |
| A2 | 收起成小球 / 关闭面板 | 无「收起」，pod 常驻 | 头部圆盘**只关面板**（`1204–1212`）；收成小球改为**长按完整胶囊**（`185`、`494`）；小球态点它展开（`416–443`） | 按要求偏离 |
| A3 | 面板头部标题 | `goal.js:178` `aria-label = view.title` | `group_goal.dart:1187–1194` 标题；停止待确认时替换为「确认终止？」 | 一致 |
| A6 | 面板顶边与胶囊齐平 | 不涉及（pod 从顶栏下起） | `pillTop = padding.top + max(0, (barHeightOf − pillHeightOf)/2)`，卡片再上提 1px 兜住圆角交界：计算在 `group_goal.dart:1143–1145`，落位在 `1165` | 平台性差异 |
| A7 | 面板顶部的第二行 | 不涉及：网页端没有浮卡，胶囊不被遮住 | `group_goal.dart:1217`（`_GoalPanelSecondLine`）在动作行下、正文前；与胶囊共用 `_GoalBarLine`（`:312`）、`goalDynamicLine`（`:225`）与 `splitForPill`（`:244`），同一份数据、同一套省略规则 | 平台性差异 |

## B. 阶段步进器

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| B1 | 步进器容器 | `goal.js:183–190` | `group_goal.dart:591–597` `_StageStrip` | 一致 |
| B2 | 显示条件 | `goal.js:183`：`status != drafting` 即显示，1 段也画 | `group_goal.dart:591`：`status != drafting && stages.length > 1` | 已知未修 |
| B3 | 窄宽隐去数字 | `goal.js:167–170` ResizeObserver + `bt-goal-mini` | 无对应逻辑 | 平台性差异 |
| B4 | 点阶段切换 | `goal.js:186` `onClick: setSelected` | `group_goal.dart:654` `_StageStrip`，`onSelect` 在 `520` | 一致 |

## C. 当前阶段

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| C1 | 阶段标题 | `goal.js:201–202` | `group_goal.dart:618–620` | 一致 |
| C2 | 当前 / 已完成标记 | `goal.js:186` `data-step=current/waiting` | `group_goal.dart:621–626`「当前阶段 / 已完成」 | 平台性差异 |
| C3 | 回到当前阶段 | `goal.js:203` `Back to current stage` | `group_goal.dart:627–631` | 一致 |
| C4 | 完成标准 | `goal.js:204` `Done when: x` | `group_goal.dart:638` `完成标准：x` | 一致 |
| C5 | 打回文案 | `goal.js:206–208`（含次数） | `group_goal.dart:645–647`（`chatGoalReworkByTimes`） | 一致 |
| C6 | 完成证据 | `goal.js:209` `Evidence: x` | `group_goal.dart:653–655` `证据：x` | 一致 |
| C7 | 成员任务行 | `goal.js:210` `TaskRow` | `group_goal.dart:661–662` `_GoalTaskRow` | 一致 |

## D. 目标收尾（未选中阶段时）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| D1 | 摘要 summary | `goal.js:196` | `group_goal.dart:607` | 一致 |
| D2 | 证据 evidence | `goal.js:197` | `group_goal.dart:608–610` | 一致 |
| D3 | 停止原因 reason | `goal.js:198` 仅 `stopped` | `group_goal.dart:612–614` 仅 `stopped` | 一致 |

## E. 起草态

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| E1 | brief 正文 | `goal.js:194` | `group_goal.dart:600–604`，与标题同值时去重 | 一致 |
| E2 | 状态行 | 无 | `group_goal.dart:605`「起草中，等管理员开始」 | 按要求偏离 |

## F. 「目标与验收」折叠

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| F1 | 折叠按钮与底栏颜色 | `goal.js:216–219` `Goal and checks` + `aria-expanded`；`.bt-goal-checks` 用 ink-2 | `group_goal.dart:674`（`GoalChecksBar`），落在固定栏 `1241–1256`；按钮文字用 `onSurfaceVariant`（ink-2）、箭头仍 ink-3，对应网页两种灰 | 一致 |
| F2 | Objective | `goal.js:212` | `group_goal.dart:754` | 一致 |
| F3 | Done when | `goal.js:213` | `group_goal.dart:755` | 一致 |
| F4 | Rules | `goal.js:214–215` `<ul>` 列表 | `group_goal.dart:756` 每条一行 `_Block` | 平台性差异 |
| F5 | 展开位置（上一轮结论，已作废） | `goal.js:211–215` 的 `ckbody` 在 `bt-goal-foot`（`216`）**之前**，即展开在 foot **上方** | 现行：也在折叠行**上方**、正文之后（`group_goal.dart:1228–1237`），卡片展开时高到 86%（`1141`）；上一轮曾放折叠行**下方** | 已作废 |

## G. 动作区（网页在底部 foot，手机在面板顶部右侧）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| G1 | Pause | `goal.js:222` `bt-goal-foot` 内 | `group_goal.dart:1421–1426` 面板顶部圆盘 | 按要求偏离 |
| G2 | Resume | `goal.js:223` | `group_goal.dart:1421–1426` | 按要求偏离 |
| G3 | Stop | `goal.js:224–227` | `group_goal.dart:1427–1434`，与暂停同一行、圆盘在其右 | 按要求偏离 |
| G4 | 停止两段式 | `goal.js:145` `STOP_ARM_MS=3000`；`goal.js:227` 文字变 `Stop the goal?` | `group_goal.dart:1383–1391` 3 秒；`1187–1194` 标题变「确认终止？」；`1430` 停止键染红 | 一致 |
| G5 | Clear | `goal.js:228–229` 文字按钮 | `group_goal.dart:1400–1407` 圆盘，`tooltip` 清除目标 | 按要求偏离 |
| G6 | Cancel（起草态） | `goal.js:230–231` | `group_goal.dart:1408–1415` 同一个 `clear` 动作 | 按要求偏离 |
| G7 | 清除 / 取消不染红 | 网页无危险色 | `group_goal.dart:1404`、`1412` 用 `textTertiary` | 一致 |
| G8 | 同时停止当前工作 | `goal.js:221` 在 `bt-goal-foot` 的 facts 区，条件 `paused && working.size > 0`，原串「Stop current work too」 | 并入底栏行最右：`GoalChecksBar.trailing`（`group_goal.dart:688`），条件 `goal.status == 'paused' && working`（`:1245–1254`），文案「同时停止当前工作」，仍走 `stopRoomWork` | 一致 |
| G9 | 顶栏是否放停止键 | 不涉及 | 不放，顶栏只有 `⋯`（`room_chat_page.dart:999–1000`） | 按要求偏离 |

## H. 胶囊（含两行）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| H1 | 胶囊形态 | 单行标题胶囊 | `group_goal.dart:384–533` 两行：上行目标（14/w600），下行动态（11，窄屏 10.5） | 按要求偏离 |
| H2 | 下行文案优先级 | 无 | `group_goal.dart:225–242` `goalDynamicLine` 九条优先级 | 按要求偏离 |
| H3 | 下行截断 | 无 | `group_goal.dart:244–267` `splitForPill`，按「·」分段、空后缀连分隔符去掉 | 按要求偏离 |
| H4 | 默认与收起 | 总是完整 | 默认完整；**点胶囊开面板、长按收成小球**（`184–185`）；本轮内记住，重启回默认完整 | 按要求偏离 |
| H5 | 小球态 | 无 | `group_goal.dart:416–443` 32 圆环按钮，群名完整；暂停时带暂停角标 | 按要求偏离 |
| H6 | 高度 | 不涉及 | `group_goal.dart:270` `pillHeightOf`，与顶栏键同高 44 | 平台性差异 |

## I. 平台与交互惯例

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| I1 | 面板呈现 | 页面内 pod 展开 | 原生浮层：`showGoalExpand`（`group_goal.dart:1060–1068`）、薄抽屉 `showGroupGoalSheet`（`1449` 起） | 平台性差异 |
| I2 | ⋯ 菜单形态 | 网页端是页面内浮层（自绘下拉） | 手机是**贴着按钮的锚定下拉**：`MenuAnchor`、`bottomEnd`、往下 8 的缝、208 宽、20 圆角、行高 52、图标在左、返回键先收菜单（`bot_chat_kit.dart:432–470`） | 平台性差异 |
| I3 | 长按菜单 | 网页右键 / hover | 原生长按菜单（消息菜单、任务行；胶囊长按 = 收起小球） | 平台性差异 |
| I4 | 读屏 | `aria-label` / `aria-current` | `Semantics(label:)` + `excludeSemantics`（`group_goal.dart:417`、`478` 等） | 平台性差异 |
| I5 | ⋯ 菜单的项 | 网页端 `GoalPanel` 之外还有群内搜索、清空会话 | 当前只有三项：对话详情 → 消息范围 → 成员 | 未做 |

## J. 文案对照（全部按网页端措辞落地）

| 网页端 | 手机端键 | 状态 |
| --- | --- | --- |
| Objective | `chatGoal`「目标」 | 一致 |
| Done when | `chatGoalStageDone`「验收方法」 | 一致 |
| Done when: x | `chatGoalDoneWhen`「完成标准：x」 | 一致 |
| Goal and checks | `chatGoalAcceptance`「目标与验收」 | 一致 |
| Back to current stage | `botsGoalBackToCurrent`「回到当前阶段」 | 一致 |
| Sent back by X | `chatGoalReworkBy` | 一致 |
| Stop the goal? | `chatGoalConfirmStop`「确认终止？」 | 一致 |
| Cancel / Clear | `commonCancel` / `chatClearGoal` | 一致 |

## 统计

- 一致：A3、B1、B4、C1、C3、C4、C5、C6、C7、D1、D2、D3、E1、F1、F2、F3、G4、G7、G8 + 文案 8 条 = **27**
- 按要求偏离：A2、E2、G1、G2、G3、G5、G6、G9、H1–H5 = **13**
- 平台性差异：A1、A6、A7、B3、C2、F4、H6、I1–I4 = **11**
- 已知未修：B2（单阶段目标不画步进器）= **1**
- 未做：I5（⋯ 菜单缺群内搜索、清空会话）= **1**
- 已作废：F5（展开位置，上一轮判「按要求偏离」）= **1**，不计入上面五项

**F5 作废说明**：上一轮 F5 判「按要求偏离」，理由是网页端 `ckbody`（`goal.js:211–215`）在 `foot`（`216`）之前、手机放折叠行下方。用户后来改为对齐网页端，实现已移到折叠行**上方**（`group_goal.dart:1228–1237`，卡片展开时长到 86%），方向与网页端一致。原判据保留在表里备查，状态标「已作废」，不再计入统计。

I5 不混进「按要求偏离」：群内搜索与清空会话在网页端就有，手机上本轮没做；两者都要新 Host 端点（`room/message-search`、`room-clear`），按 `docs/memo.md` 记录均为未实现，属于后续版本。

本轮删掉了原 A4「面板上方摘要」：用户要求面板上方不显示目标与验收方法，该块已从正文移除，面板从步进器/当前阶段开始，完整内容仍在底部折叠里。

单阶段不画步进器是唯一已知未修项，影响为「一段目标时没有可切换的步进器」，不影响状态与动作，不阻断发版。
