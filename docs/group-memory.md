# DSHGO二开 · 群记忆与交接

换设备后照这份恢复上下文；细节以仓库里的 `design/*.md` 为准。

## 一、项目定位
- 项目：dsh-Go（安卓原生 App）非侵入二开，品牌名 **MODO**（包名 `io.github.gpmlimeng.modo`）。
- 原则：手机是 DS Bot 的一等客户端，原生画、不嵌网页；扩展优先插槽/插件，其次补丁，最后才改源码。
- 上游：`ccch1mneyyy/dsh-Go`；我们的仓库：`gpmlimeng-cyber/dsh-do`（App）与 `gpmlimeng-cyber/dsh-bot`（插件）。

## 二、版本与发布（现行规则）
- 版本格式：`2.<上游基线代次>.<我们的迭代>`，当前基线 v1.0.8，首版 2.0.0。
- tag：正式版 `v2.0.N`（标 latest）；预览版 `v2.1.0-rc.M`（标 prerelease，不进 latest）。
- 资产名必须严格 `dsh-go-<版本>-arm64.apk`，更新器按这个正则找包。
- **更新说明放在仓库** `docs/release-notes/<版本>.md`，分「新功能 / 缺陷修复 / 已知问题」三节；CI 自动读取。
- CI 的辅助产物（analyze/tests/l10n/goldens/buildlog/ci- 包）一律 `--prerelease`，绝不占 `releases/latest`。
- 构建入口：`.github/workflows/build-apk.yml`，dispatch 时 ref 指向当前开发分支，`version` 填目标版本。
- **打包时必须把版本名写进包内**：`tooling/build-apk.sh --build-name $VERSION`，否则装完仍显示 2.0.0。

## 三、当前进度（2026-11-03）
- 已发布：2.0.0 / 2.0.1 / 2.0.2 / 2.0.3；最新 = `v2.0.3`。
- 2.0.3 内容：群级权限（全员统一）、停全部、成员行「等待你审批」、排队等待时长、回到底部新内容角标、本轮发言进度。
- 进行中（2.0.4，缺陷修复版）：更新链路加固（丢坏半包、显示源与摘要）、桌面图标缩放、版本名写入包内、C 类测试回归。
- 分支：`ci/wordmark`（成员开发）、`ci/room-progress`（当前发版分支）。

## 四、待办 backlog
- 群聊活动汇总面板：要服务端算 `totals`（成员上下文/轮次/步数 + 群工作目录文件），需改 ds-bot 并重启引擎，**等用户批准**。
- 群聊产出/累计产出：要服务端下发 `room.sessions` 与 `deliverables/presented`，同上批次。
- 真实已读（`seen`）与 `room-progress.pending`：同批次。
- 品牌改名：`AppInfo.name`/`AppStrings.APP_NAME` 仍是 DSH Go，需单独一笔；相册目录 `Pictures/DSH Go` **不改名**。
- B1 快捷方式包名（`shortcuts.xml` 指向旧包名，长按图标无效）：要改 Android 原生。
- golden 全量重跑：C 类修复之后再做。

## 五、已知问题
- 开启毛玻璃时，抽屉顶部两个圆钮会透出一条横向亮带（关闭毛玻璃即消失，上游皮肤）。
- 测试长期有 120～126 条失败，集中在 golden 与 Bot 页渲染，未清零。

## 六、群记忆原文（MEMORY.md，23 条）
（以下为写这份文档时的快照，逐条保留，便于换设备后续接）

1. dsh-Go 已原生适配 DS Bot：界面层 ui/bots 约6300行、状态层 bots_state.dart 1100行、协议客户端 dsbot_api.dart 1670行；DS Bot 侧 hello 握手已补通。
2. dsh-Go 对 DS Bot 采用外部插件 + 原生客户端方案；DS Bot 侧新增移动端 API v1。
3. dsh-Go 移植了部分 dsh-ui 代码，Apache-2.0 来源已登记在 THIRD_PARTY_NOTICES。
4. DS Bot 插件需装在主机（引擎）上；未安装时 App 内有“安装 DS Bot”按钮。
5. 用户已撤掉先前为测试原生插件所加的插件与胶囊功能（源码仍留）。
6. 与 DS Bot 对接的部分全部与上游 feat/mobile-api 分支保持一致。
7. 附件上传问题已通过升级 App 解决，根因是安装包比提交早一天。
8. ds-bot 的 feat/mobile-api-remote 分支已推送，远端 bf1cedd1，PR #1 开到 main。
9. 用户要求 ds-bot 的改动走分支 PR。
10. 用户要求先不做 PR 的测试检查，先推进。
11. 本机无法构建 APK（Linux ARM64 缺 Flutter 引擎），改用 GitHub Actions x86 构建。
12. 用户已批准 APK 构建工作流：`ci/build-apk` 分支，先 `runtime/build-runtime.sh`，再 `tooling/build-apk.sh`。
13. CI 测试包用独立包名与固定测试签名，与正式版并存。
14. room 事件已加，群聊实时刷新已验证通过（`fix/room-feed-events`）。
15. 群聊页输入框与 Bot 对话页不同，原生插件胶囊层未接在群聊页。
16. 文档类结论要给可点开的卡片或链接。
17. Bot 底层也是 DSH 会话，Bot 页附件走 `fileUploads/upload` + `send` 透传。
18. 改动尽量放在接缝上，减少补丁失效。
19. 附件方案：图片+文件，文件 30MB、图片 20MB；加号面板复用 `showPlusPanel`；撤掉 @ 按钮。
20. 用户要求 dsh-Go 的 CI 正式版与预览版分离，检查更新可开关「包含预览版」。
21. 更新源切到本仓库，资产名 `dsh-go-<版本>-arm64.apk`。
22. 发布说明必须写入 tag/release（新功能/缺陷修复两节）。
23. 2.0.3 起群聊为迭代重点，标准是「补齐网页端与原生端的差距」，不做纯新功能。
