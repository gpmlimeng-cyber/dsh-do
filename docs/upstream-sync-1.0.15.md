# 上游 v1.0.15 合并台账

> 分支：`sync/upstream-1.0.15`（在 `feat/2.1.9` 之外解冲突，验过再合）
> 合并基准：`v1.0.15`（**附注标签**，标签对象 `5e4e3b4f`）→ 提交 **`a9877420`**。`git rev-parse v1.0.15` 得到标签对象，`git rev-parse 'v1.0.15^{commit}'` 才是提交；`MERGE_HEAD` 存的是标签对象 id，写台账与 `git log` 对照时一律用 `a9877420`。
> 上次同步点：`74028a39`
> 改动量：645 个提交、1257 个文件
> 冲突：96 个文件（A 41 / B 38 / C 17）
> 状态：96 个冲突全部解决；合并已提交 `5deb02b9`，l10n 补键提交 `0e827db4`；本台账 96 行已填满

## 口径（沿用上次，逐文件记账）

1. 上游的像素微调**不重放**（丢），布局跟上游 1.0.15 走。
2. 只保留**本地运行时逻辑**与**群聊功能**：群目标胶囊与面板、消息范围、⋯ 菜单、消息脚注一行、输入框上方一格（活动行/插件条/胶囊行三选一）、route observer 的返回不弹键盘。
3. 自绘文件头保留「本地独有：某某功能，上游无对应实现」标注；上游出现同类能力时**切上游并删自己那份**。
4. 每个冲突都要填「处理 + 理由」，不许「看起来一样就随便选」。

## 处理顺序

**C → A → B → docs**

- **C** 是底座：`pubspec.yaml`、`runtime/patches/pins.json`、assets、runtime 测试。依赖与资源先定，A/B 才有稳定前提。
- **A** 里 `packages/dsh_client/` 被 `app/lib` 直接引用，先于 B 定接口形状。
- **B** 是冲突主体（含四个自绘大文件），放在接口稳定之后解，返工最少。
- **docs/ 5 个**（`changelog.md`、`design/companion.md`、`guide/README.md`、`guide/en/06-pets.md`、`guide/zh/06-pets.md`）等代码口径定稿后再写，否则写出来的说明和实现对不上。Chief 口述的「docs 4 个」与清单不符，清单实际 5 个；C 批 17 = 架构师 12 + 产品经理 5。

## 每批「先看上游这版改了什么」的对照方法

通用三步（把 `<路径>` 换成该批任意文件）：

```bash
# 1. 上游这一版在这条路径上做了哪些提交
git log --oneline 74028a39..v1.0.15 -- <路径>
# 2. 上游具体怎么改的（只看这一版区间）
git diff 74028a39..v1.0.15 -- <路径>
# 3. 我们自己这条线在这条路径上改了什么
git log --oneline 74028a39..HEAD -- <路径>
```

冲突标记定位：`grep -n '^<<<<<<<' <文件>`；整文件对比可用 `git diff v1.0.15 -- <文件>`。

分批额外看什么：

- **A（安卓/桥接/客户端）**：上游这批是手机控制、DND 门、后台探针、runtime 的新逻辑 → 以 **upstream 为准**，只把本地运行时改造（如 `runtime/bridge` 的自有 route、`dsh_client` 的群聊字段）挑回来。
- **B（app/lib + app/test）**：四个自绘大文件（`bot_chat_kit`、`room_chat_page`、`bot_chat_page`、`room_details_page`）先判「上游有没有同类能力」——有就切上游并删本地那份；没有就保本地结构、吸收上游新增字段。测试文件跟随被测代码的取舍。
- **C（配置/资源/测试/文档）**：能取上游就取上游；本地新增的条目（`runtime/patches/pins.json` 的本地 pin、companion 资产）保留并补进上游新增项。

## 台账（96 个冲突文件）

| # | 路径 | 批 | 处理 | 理由 |
|---|---|---|---|---|
| 1 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/companion/CompanionVoicePlugin.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 2 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/links/LinksPlugin.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 3 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/media/MediaPlugin.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 4 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneContracts.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 5 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneControl.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 6 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneCore.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 7 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhonePromptUi.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 8 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneTasks.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 9 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/SerialWorker.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 10 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/SystemActions.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 11 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/SystemApi.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 12 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/a11y/Actuator.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 13 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/a11y/ControlOverlay.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 14 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/a11y/MainScreenDriver.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 15 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/BackgroundControl.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 16 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/BackgroundDisplay.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 17 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/BackgroundInputProbe.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 18 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/BackgroundTree.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 19 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/PrivilegedDisplayCore.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 20 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/PrivilegedProtocol.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 21 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/DshService.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 22 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/GuestSetup.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 23 | `app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/RuntimeController.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 24 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneCallTailOwnerTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 25 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneCorePromptOwnerTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 26 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneEngineExitTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 27 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneStaleRefreshTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 28 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/PhoneToolSchemaTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 29 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/SystemDispatchTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 30 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/BackgroundDisplayTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 31 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/phone/background/InputProbeDiagnosticsTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 32 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/SafeMoveAsideTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 33 | `app/android/app/src/test/kotlin/io/github/ccch1mneyyy/dsh_app/runtime/SafePolicyTest.kt` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 34 | `packages/dsh_client/lib/companion.dart` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 35 | `packages/dsh_client/lib/dsh_client.dart` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 36 | `packages/dsh_client/lib/src/companion_api.dart` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 37 | `runtime/bridge/dsh-go-bridge/cordis.patch.yml` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 38 | `runtime/bridge/dsh-go-bridge/lib/companion/full-context.js` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 39 | `runtime/bridge/dsh-go-bridge/lib/companion/routes.js` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 40 | `runtime/bridge/dsh-go-bridge/lib/companion/store.js` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 41 | `runtime/bridge/dsh-go-bridge/lib/index.js` | A | 取上游 | 上游 v1.0.15 是超集：本地补丁（InputProbeDiagnostics、provider_mismatch、MediaPermissionQueue、applyCaptureHidden、staleSnapshot、probeDetail、callOwner、writeDiagnostics 等）在上游都有等价实现；A 批不含群聊自绘逻辑 |
| 42 | `app/lib/companion/companion_initiative.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 43 | `app/lib/companion/companion_initiative_owner.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 44 | `app/lib/companion/companion_light.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 45 | `app/lib/companion/companion_pack.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 46 | `app/lib/companion/companion_reply.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 47 | `app/lib/companion/companion_state.dart` | B | 取上游 | Companion 是上游特性，本地这条线只有同步提交，无自研 |
| 48 | `app/lib/l10n/app_en.arb` | B | 合并 | 用 tool/l10n_merge.py 从 parts 重生成，两侧键都在 |
| 49 | `app/lib/l10n/app_zh.arb` | B | 合并 | 用 tool/l10n_merge.py 从 parts 重生成，两侧键都在 |
| 50 | `app/lib/l10n/gen/app_localizations.dart` | B | 合并 | 以上游 gen 为底，补 133 个本地独有键的 getter/实现 |
| 51 | `app/lib/l10n/gen/app_localizations_en.dart` | B | 合并 | 以上游 gen 为底，补 133 个本地独有键的 getter/实现 |
| 52 | `app/lib/l10n/gen/app_localizations_zh.dart` | B | 合并 | 以上游 gen 为底，补 133 个本地独有键的 getter/实现 |
| 53 | `app/lib/l10n/parts/companion_en.arb` | B | 取上游 | 上游 25 条 Companion 新词，本地无自有文案 |
| 54 | `app/lib/l10n/parts/companion_zh.arb` | B | 取上游 | 上游 25 条 Companion 新词，本地无自有文案 |
| 55 | `app/lib/l10n/parts/phone_en.arb` | B | 取上游 | 同一 key，文案以上游为准，本地 4 条已被覆盖 |
| 56 | `app/lib/l10n/parts/phone_zh.arb` | B | 取上游 | 同一 key，文案以上游为准，本地 4 条已被覆盖 |
| 57 | `app/lib/notify/chat_alerts.dart` | B | 取上游 | 只多一行 companion_signals import，本地无逻辑改动 |
| 58 | `app/lib/state/notify_state.dart` | B | 取上游 | import 多 petEventBusProvider，无本地逻辑 |
| 59 | `app/lib/state/usage_state.dart` | B | 保本地 | contextFraction「未测量不是 0%」是本地口径，取上游会退回 0% |
| 60 | `app/lib/ui/chat/artifact_preview.dart` | B | 取上游 | 上游重写了预览，本地无自研 |
| 61 | `app/lib/ui/chat/chat_screen.dart` | B | 合并 | 保本地「输入框上方一格」；取上游 workspace 去重与手机技能重放卡 |
| 62 | `app/lib/ui/chat/media/media_viewer.dart` | B | 取上游 | 上游改动，本地无自研 |
| 63 | `app/lib/ui/chat/widgets/attachments.dart` | B | 保本地 | 图片加载失败可点重试是本地能力，上游无对应实现 |
| 64 | `app/lib/ui/companion/companion_chrome.dart` | B | 取上游 | Companion UI 上游重写 |
| 65 | `app/lib/ui/companion/companion_page.dart` | B | 取上游 | Companion UI 上游重写 |
| 66 | `app/lib/ui/companion/companion_stage.dart` | B | 取上游 | Companion UI 上游重写 |
| 67 | `app/lib/ui/engine/engine_status.dart` | B | 取上游 | 上游新增 runtime_upgrade_blocked 分支，且已含我们原有两行 |
| 68 | `app/lib/ui/web/web_view_page.dart` | B | 取上游 | WebMarkButton 与侧栏让位是上游新实现 |
| 69 | `app/test/chat/usage_commands_test.dart` | B | 合并 | 保本地「未测量不是 0%」用例；取上游 contextWindow:0 断言 |
| 70 | `app/test/companion/companion_initiative_owner_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 71 | `app/test/companion/companion_initiative_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 72 | `app/test/companion/companion_owner_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 73 | `app/test/companion/companion_pack_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 74 | `app/test/companion/companion_page_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 75 | `app/test/companion/companion_reply_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 76 | `app/test/companion/companion_stream_state_test.dart` | B | 取上游 | 跟随新模型与 API 的测试用例 |
| 77 | `app/test/drawer/drawer_calendar_test.dart` | B | 取上游 | 条目模型改成 SessionRow，按上游取 .sessionId |
| 78 | `app/test/features/preset_editor_test.dart` | B | 取上游 | 上游 API 变化，跟随 |
| 79 | `app/test/web/web_view_page_test.dart` | B | 取上游 | 跟随 WebMarkButton |
| 80| `app/.gitignore`| C| 取上游 | 规则相同，上游注释更新为 "release builds / 发布机拷入" 的新措辞 |
| 81| `app/assets/companion/stage.js`| C| 取上游 | 本地相对基线是上次同步快照，无自绘改动；跟随上游 14 个提交（模型适配、mask 分块） |
| 82| `app/assets/skills/dsh-go-guide/README.md`| C| 取上游 | 版本号 1.0.12→1.0.15，纯跟随 |
| 83| `app/assets/skills/dsh-go-guide/en-06-pets.md`| C| 取上游 | 上游把「主动邀请」改成「她多主动」四档频率说明，本地无差异 |
| 84| `app/assets/skills/dsh-go-guide/zh-06-pets.md`| C| 取上游 | 同上，中文版跟随上游 |
| 85| `app/pubspec.yaml`| C| 取上游 | 版本 1.0.15+1（本地 1.0.12+1 是上次同步的版本号，发货版本由 CI 传入）；依赖补上游新增 image / mobile_scanner |
| 86| `app/tool/l10n_merge.py`| C| 取上游 | 上游修复 ARB 写入为 LF（newline="\n"），Windows/CI 差异；本地无逻辑改动 |
| 87 | `docs/changelog.md` | C | 合并 | 取上游 1.0.13/1.0.14/1.0.15 三段新增，保留我们 1.0.12 及更早条目（本地侧该块为空） |
| 88 | `docs/design/companion.md` | C | 取上游 | 本地侧是上次同步快照；上游含已获授权、她多主动四档、C902/C905 接线说明 |
| 89 | `docs/guide/README.md` | C | 取上游 | 版本号 1.0.12→1.0.15，纯跟随 |
| 90 | `docs/guide/en/06-pets.md` | C | 取上游 | 邀请改成 How often she speaks up 四档，本地无差异 |
| 91 | `docs/guide/zh/06-pets.md` | C | 取上游 | 与英文版同义：她多主动四档、默认偶尔；中英一致 |
| 92| `runtime/patches/pins.json`| C| 取上游 | 上游新增两个 0.2.2-rc.1 补丁 pin；冲突区块本地侧为空，无本地 pin 丢失 |
| 93| `runtime/tests/bridge-package.test.mjs`| C| 取上游 | 上游补 动态 import() 的依赖扫描，本地无改动 |
| 94| `runtime/tests/companion-route.test.mjs`| C| 取上游 | 上游新增 recall 路由与未适配 Host 的用例，计数 8→12；本地无改动 |
| 95| `runtime/tests/native-micro-generation.test.mjs`| C| 取上游 | 上游改用真实计时/墙钟替换 mock timers，本地无改动 |
| 96| `tooling/companion/whale-girl.character.json`| C| 取上游 | 上游补齐作者/许可/来源元数据；本地为空占位 |
