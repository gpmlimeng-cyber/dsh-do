# 群目标面板 · 与网页端 GoalPanel 逐块差异表（rc.17 口径）

- 对照基准：`ds-bot/src/client/goal.js` 的 `GoalPanel`（149–235 行，`STOP_ARM_MS` 在 145 行）
- 手机端：`dsh-212/app/lib/ui/bots/group_goal.dart`（HEAD `6267ecc7`，含 rc.17 批次：删掉面板上方摘要、圆盘只关面板、长按胶囊收小球）；顶栏入口在 `room_chat_page.dart:985–1035`
- 状态口径：**一致**＝行为与文案都对上；**按要求偏离**＝用户明确要求不同，不算回归；**平台性差异**＝Web 与原生控件形态不同，不追平；**已知未修**＝已确认差异，本轮不修
- 行号说明：手机端行号是当前工作区的实测值；rc.17 合提交后若有偏移，以符号名（类名/方法名）为准

## A. 面板与容器

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| A1 | 面板容器 | `goal.js:149` `GoalPanel`，pod 挂在顶栏下，宽屏常驻 | `group_goal.dart:922` `_GoalExpandLayer`，浮卡，点卡外收起 | 平台性差异 |
| A2 | 收起成小球 / 关闭面板 | 无「收起」，pod 常驻 | 头部圆盘**只关面板**（`1001–1010`）；收成小球改为**长按完整胶囊**（`184–185`、`354`）；小球态点它展开（`311–338`） | 按要求偏离 |
| A3 | 面板头部标题 | `goal.js:178` `aria-label = view.title` | `group_goal.dart:987–993` 标题；停止待确认时替换为「确认终止？」 | 一致 |

## B. 阶段步进器

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| B1 | 步进器容器 | `goal.js:183–190` | `group_goal.dart:515–521` `_StageStrip` | 一致 |
| B2 | 显示条件 | `goal.js:183`：`status != drafting` 即显示，1 段也画 | `group_goal.dart:515`：`status != drafting && stages.length > 1` | 已知未修 |
| B3 | 窄宽隐去数字 | `goal.js:167–170` ResizeObserver + `bt-goal-mini` | 无对应逻辑 | 平台性差异 |
| B4 | 点阶段切换 | `goal.js:186` `onClick: setSelected` | `group_goal.dart:654` `_StageStrip`，`onSelect` 在 `520` | 一致 |

## C. 当前阶段

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| C1 | 阶段标题 | `goal.js:201–202` | `group_goal.dart:543–545` | 一致 |
| C2 | 当前 / 已完成标记 | `goal.js:186` `data-step=current/waiting` | `group_goal.dart:546–549`「当前阶段 / 已完成」 | 平台性差异 |
| C3 | 回到当前阶段 | `goal.js:203` `Back to current stage` | `group_goal.dart:550–555` | 一致 |
| C4 | 完成标准 | `goal.js:204` `Done when: x` | `group_goal.dart:560` `完成标准：x` | 一致 |
| C5 | 打回文案 | `goal.js:206–208`（含次数） | `group_goal.dart:565–567`（`chatGoalReworkByTimes`） | 一致 |
| C6 | 完成证据 | `goal.js:209` `Evidence: x` | `group_goal.dart:572–574` `证据：x` | 一致 |
| C7 | 成员任务行 | `goal.js:210` `TaskRow` | `group_goal.dart:580–582` `_GoalTaskRow` | 一致 |

## D. 目标收尾（未选中阶段时）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| D1 | 摘要 summary | `goal.js:196` | `group_goal.dart:531` | 一致 |
| D2 | 证据 evidence | `goal.js:197` | `group_goal.dart:532–534` | 一致 |
| D3 | 停止原因 reason | `goal.js:198` 仅 `stopped` | `group_goal.dart:536–538` 仅 `stopped` | 一致 |

## E. 起草态

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| E1 | brief 正文 | `goal.js:194` | `group_goal.dart:524–528`，与标题同值时去重 | 一致 |
| E2 | 状态行 | 无 | `group_goal.dart:529`「起草中，等管理员开始」 | 按要求偏离 |

## F. 「目标与验收」折叠

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| F1 | 折叠按钮 | `goal.js:216–219` `Goal and checks` + `aria-expanded` | `group_goal.dart:590–605`，箭头随展开旋转 | 一致 |
| F2 | Objective | `goal.js:212` | `group_goal.dart:618` | 一致 |
| F3 | Done when | `goal.js:213` | `group_goal.dart:619` | 一致 |
| F4 | Rules | `goal.js:214–215` `<ul>` 列表 | `group_goal.dart:620` 每条一行 `_Block` | 平台性差异 |

## G. 动作区（网页在底部 foot，手机在面板顶部右侧）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| G1 | Pause | `goal.js:222` `bt-goal-foot` 内 | `group_goal.dart:1147–1152` 面板顶部圆盘 | 按要求偏离 |
| G2 | Resume | `goal.js:223` | `group_goal.dart:1147–1152` | 按要求偏离 |
| G3 | Stop | `goal.js:224–227` | `group_goal.dart:1153–1159` | 按要求偏离 |
| G4 | 停止两段式 | `goal.js:145` `STOP_ARM_MS=3000`；`goal.js:227` 文字变 `Stop the goal?` | `group_goal.dart:1110–1118` 3 秒；`987–992` 标题变「确认终止？」；`1156` 停止键染红 | 一致 |
| G5 | Clear | `goal.js:228–229` 文字按钮 | `group_goal.dart:1126–1133` 圆盘，`tooltip` 清除目标 | 按要求偏离 |
| G6 | Cancel（起草态） | `goal.js:230–231` | `group_goal.dart:1134–1141` 同一个 `clear` 动作 | 按要求偏离 |
| G7 | 清除 / 取消不染红 | 网页无危险色 | `group_goal.dart:1130`、`1138` 用 `textTertiary` | 一致 |
| G8 | 连当前工作一起停 | `goal.js:221` foot 内次要文字 | `group_goal.dart:606–613` 底部唯一条件项 | 一致 |
| G9 | 顶栏是否放停止键 | 不涉及 | 不放，顶栏只有 `⋯`（`room_chat_page.dart:999–1000`） | 按要求偏离 |

## H. 胶囊（含两行）

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| H1 | 胶囊形态 | 单行标题胶囊 | `group_goal.dart:283–417` 两行：上行目标（14/w600），下行动态（11，窄屏 10.5） | 按要求偏离 |
| H2 | 下行文案优先级 | 无 | `group_goal.dart:221–247` `goalDynamicLine` 九条优先级 | 按要求偏离 |
| H3 | 下行截断 | 无 | `group_goal.dart:249–281` `splitForPill`，按「·」分段、空后缀连分隔符去掉 | 按要求偏离 |
| H4 | 默认与收起 | 总是完整 | 默认完整；**点胶囊开面板、长按收成小球**（`184–185`）；本轮内记住，重启回默认完整 | 按要求偏离 |
| H5 | 小球态 | 无 | `group_goal.dart:311–338` 32 圆环按钮，群名完整；暂停时带暂停角标 | 按要求偏离 |
| H6 | 高度 | 不涉及 | `group_goal.dart:274` `pillHeightOf`，与顶栏键同高 44 | 平台性差异 |

## I. 平台与交互惯例

| # | 区块 / 元素 | 网页端（行号） | 手机端（行号） | 状态 |
| --- | --- | --- | --- | --- |
| I1 | 面板呈现 | 页面内 pod 展开 | 原生浮层：`showGoalExpand`（`group_goal.dart:901–909`）、薄抽屉 `showGroupGoalSheet`（`1175` 起） | 平台性差异 |
| I2 | 菜单 | 网页自定义下拉 | 原生 sheet：`showRoomMenu`（`room_chat_page.dart:999`），⋯ 恒为顶栏最右 | 平台性差异 |
| I3 | 长按菜单 | 网页右键 / hover | 原生长按菜单（消息菜单、任务行；胶囊长按 = 收起小球） | 平台性差异 |
| I4 | 读屏 | `aria-label` / `aria-current` | `Semantics(label:)` + `excludeSemantics`（`group_goal.dart:340–345` 等） | 平台性差异 |

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
- 平台性差异：A1、B3、C2、F4、H6、I1–I4 = **9**
- 已知未修：B2（单阶段目标不画步进器）= **1**

本轮删掉了原 A4「面板上方摘要」：用户要求面板上方不显示目标与验收方法，该块已从正文移除，面板从步进器/当前阶段开始，完整内容仍在底部折叠里。

单阶段不画步进器是唯一已知未修项，影响为「一段目标时没有可切换的步进器」，不影响状态与动作，不阻断发版。
