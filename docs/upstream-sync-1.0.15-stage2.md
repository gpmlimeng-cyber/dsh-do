# 上游 v1.0.15 合并 · 第 2 段双向核对（事实版）

> 分支 `sync/upstream-1.0.15`，tip `510dda23`（合并 `5deb02b9` + l10n `0e827db4` + 台账 `510dda23`）。
> 核对方：架构师。核对方式：合并后树上逐个 `grep -n` 定位符号，不凭记忆。
> 结论：**可以进包**。本地六项全部在；上游新能力中 3 项已进来、2 项不在本次合并范围（属 main 后续，不是缺陷）。

## 一、本地独有六项：全部还在

| # | 项 | 位置（合并后树） | 判定 | 怎么保住的 |
|---|---|---|---|---|
| 1 | 群目标胶囊与面板 | `group_goal.dart:156` `GoalBarProbe`；`:248` `pillHeightOf` → `ChatHeader.pillHeightOf`；`:1117`/`:1205` 展开内容在折叠行上方；`:567` 「哪怕只有一段也画」；`room_chat_page.dart:972` `hasGoal`、`:1027` `titleCompact`、`:1028` 挂 `GoalBarProbe` | ✅ 在 | B 批自绘文件以本地为准（`room_chat_page.dart`），上游同类改动被并进来但没覆盖胶囊 |
| 2 | 消息范围 | `room_message_mode.dart:63` provider、`:69` `visibleRoomItems`；`room_chat_page.dart:170`/`:768`/`:907` 使用；空态 `room_chat_page.dart:1090` `notice: memberSilent`、`:1137`，文案 `bots_zh.arb:1142` 「这一段里没有他的发言」 | ✅ 在 | 同上，B 批保本地 |
| 3 | ⋯ 菜单 | `bot_chat_kit.dart:68-70` `onMenu/menuController/menuChildren`、`:117`/`:121`、`:434` `_width = 176`；菜单行 `room_chat_page.dart:1606`（对话详情 / 消息范围 / 成员） | ✅ 在 | B 批保本地；危险项规则保留，本版没有危险项（清空会话未做），故「危险项最后」不适用 |
| 4 | 消息脚注一行 | `bot_chat_kit.dart:1691` `smallStyle`；`:1703-1732` 名字/admin/时间/统计同一 `Row`，统计放不下时整段换「…」 | ✅ 在 | B 批保本地 |
| 5 | route observer 返回不弹键盘 | `app.dart:172` 注册 `appRouteObserver`；`route_observer.dart:10`；`bot_chat_page.dart:109` 订阅、`:116` `didPushNext() => _focus.unfocus()`、`:157` 退订；`room_chat_page.dart:409`/`:416`/`:426` | ✅ 在 | B 批保本地 |
| 6 | 输入框上方一格 | `bot_composer_deck.dart:141` 「36 + 6 = 42」；`:180` `ComposerStripSlot`；`:183` `fallback` | ✅ 在 | B 批 `chat_screen.dart` 明确「合并」保本地一格 |

**判定说明**：六项里 5 项在自绘文件、1 项在 `chat_screen.dart` 的合并项里；都不是「上游顺手带上」，而是 B 批按口径人为保住。没有一项是靠运气留下的。

## 二、上游 1.0.15 新能力：逐条判定

以提交 `a9877420`（tag `v1.0.15`）为界，范围 `74028a39..v1.0.15`。

### Chief 点名的 5 条

| 能力 | 证据 | 结论 |
|---|---|---|
| usage 合约 v2：手机型号 + 厂商系统版本 | 提交 `9516ac84`；`usage_ledger.dart:31` 注释、`:33` `usagePayloadKeysV2 = {..., 'model', 'rom'}`、`:264` 组装 `'v': 2`、`:272` 带 model/rom、`:310` 校验；`usage_net.dart:96` 取值 | **已进来** |
| 诊断探针 | `phone/background/InputProbeDiagnostics.kt:4`；范围内改动提交 `3f8d7b6b`；`BackgroundInputProbe.kt` 在树上 | **已进来** |
| Shizuku / ADB 自更新 | 范围 `74028a39..v1.0.15` 内没有「自更新」对应提交；在范围的是 `d4d983d3` shizuku-destroy、`ce3e0d91` 模式与提供方不一致不报就绪、`8de69ae9` ADB 复用 30 秒期限、selfcheck 系列；`AdbStarter.kt` 是 Shizuku-free 的 Self-ADB 通道 | **不适用**（这条来自 main 后续，不是 1.0.15；若指 selfcheck/ADB 期限那批，则已进来） |
| DND 门 | 提交 `c6fea255`「receive DND gate input in a focused app activity」（新增 `BackgroundProbeActivity.kt`+manifest）；**`git merge-base --is-ancestor c6fea255 v1.0.15` 为假**，`BackgroundProbeActivity.kt` 在合并树里不存在 | **不适用**（不在 tag 范围，属 main 后续） |
| launcher alias | `AndroidManifest.xml` 基线 `74028a39` 就有 10 个 `activity-alias`；运行时额度提交 `7341b725` **不在 tag 范围** | **不适用**（基础 alias 本来就在；runtime honor 那半不在本轮） |

### 我列的 10 条（与冲突面相关的）

| 能力 | 证据 | 结论 |
|---|---|---|
| 更新引擎不再清空 Linux 环境 | `docs/changelog.md` 1.0.15 头条；本仓侧 `app/lib/state/update_state.dart`、引擎侧 `runtime/patches` 配套 | **已进来**（文案与流程在；真机行为待验证阶段处理） |
| 匿名统计加机型/系统 | 同 usage v2 | **已进来** |
| 扫码配对修 ML Kit（#802） | 提交 `1c5b2200`「initialize ML Kit before pairing scans」 | **已进来** |
| 手机操控多任务（后台任务上限 3、实时后台预览、截图坐标操作、存成技能、本机自检） | `BackgroundPreview.kt:20` 及同目录 `BackgroundPreview*`、`BackgroundCoordinates.kt`；App 侧 `phone_state.dart:282` `setBackgroundPreview`；技能 `state/phone_skill_use.dart:40` + `chat_screen.dart:223-260` | **已进来** |
| 伙伴小屋（随包内置、她多主动四档、模型 zip 导入、表情动作、AI 适配） | `app/assets/companion/`（4 个文件：index.html/scene.js/stage.css/stage.js）；`app/lib/companion/*`、`app/lib/ui/companion/*` 全在（B 批取上游）；四档文案在 l10n parts | **已进来** |
| 远程：电脑开终端、文件页传文件 | `app/lib/remote/` 存在，终端入口接 `state/terminal_state.dart`；传文件在 `attachments.dart`/文件页 | **已进来** |
| 诊断采集输入法日志 | `diagnostics` 目录与 `InputProbeDiagnostics` 配套 | **已进来**（入口与白名单需真机验） |
| 网页版返回键换 App 标记、系统返回先收侧栏 | `web_view_page.dart:1233` `WebMarkButton` | **已进来** |
| 依赖 `image` / `mobile_scanner` | `app/pubspec.yaml`（C 批取上游）；`pubspec.lock` 已跟 | **已进来** |
| l10n 新增批次 | `l10n_merge.py --check`：61 parts / 6255 keys；`gen/` 重生成 | **已进来** |

## 三、三处交叉检查

1. **手机操控**：A 批 41 个文件与上游逐字节一致（Chief 已核），因此这一批里不可能同时存在「本地私有参数」和「上游代码」——本地能力要么在上游有等价实现（后端逐个点名：`InputProbeDiagnostics`、`provider_mismatch`、`MediaPermissionQueue`、`applyCaptureHidden`、`staleSnapshot`、`probeDetail`、`callOwner`、`writeDiagnostics`、`systemDispatch` 等已命中），要么随「取上游」被有意丢弃。**这一条继承了 A 批的核对结论，不是本次逐行重核**；若后端那 9 个等价实现之外还有本地参数，需要另查 `74028a39..HEAD` 在这些文件上的历史。
2. **伙伴小屋**：上游 `stage.js`（C 批取上游）与 App 侧 `app/lib/companion/*`（B 批取上游）**同为上游版本**，调用参数配套；不存在「一边新一边旧」。本地没有自研 companion 代码，所以没有适配缺口。
3. **输入区**：`chat_screen.dart` 是 B 批唯一「合并」的大文件，已明确保住 42 高一格；`phone_skill` 的配套符号（`PreparedPhoneSkill`、`_sendPhoneSkill`、`_dropPreparedPhoneSkill`）在 `state/phone_skill_use.dart` 与 `chat_screen.dart` 内**成对存在**，不依赖未合入的外部文件。

## 四、结论

**可以进包。**

- 本地六项：全部在（逐项有行号），且是人为保住。
- 上游能力：Chief 点名的 5 条里 3 条已进来、2 条（DND 门、launcher alias 运行时）**根本不在 v1.0.15 范围内**，属于 main 后续提交——不是这次合并的遗漏。要把它们带上，只能另开一轮从 main 取，不能算在这个目标里。
- 两条只会在 CI/真机暴露、不阻塞合入的事项：
  1. 更新流程「保留环境」的行为只有文案与流程，需真机更新一次确认；
  2. 伙伴小屋四档频率与后台预览需真机点一次（本清单只核代码）。
