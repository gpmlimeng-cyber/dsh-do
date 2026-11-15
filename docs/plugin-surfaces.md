# dsh-go 原生插件插槽对照

> 2026-11-09 整理。**权威来源是 `$DSH_HOME/skills/dsh-go-plugin/SKILL.md`**——那份由 App 自动更新，本文是项目侧的对照与约定，两者不一致时以技能文档为准。
> 适用对象：**dsh-go 手机 App 的原生界面**。Cordis / Harness 网页版插件是另一套（目录、清单、安装入口都不同），不要混用。

## 一、七种插槽

| 插槽 | 出现在哪 | 每插件上限 | 文字上限 | 能否读数据 | 点按 |
| --- | --- | --- | --- | --- | --- |
| `composer.actions` | 输入框上方的胶囊 | 2 条 | `label` 10 字 | `clipboard`、`draft` | 有 `effect` 则 App 直接执行；否则回调 `on(id)` |
| `composer.strip` | 输入框上方一行状态 | 1 条 | `text` 24 字 | — | 有 `panel` 则打开面板；否则 `on(id)` |
| `composer.tools` | 加号面板 | 2 条 | `label` 8 字 | `clipboard`、`draft` | `panel` / `effect` 二选一；否则 `on(id)` |
| `session.actions` | 「信息」里（会话级） | 2 条 | `label` 12 字 | `clipboard`、`draft` | 同胶囊 |
| `message.actions` | 长按助手回复的菜单 | 2 条 | `label` 12 字 | `message`（被长按的正文） | 同胶囊 |
| `panels` | `session.tab`（对话详情页，默认）/ `features`（全部功能）/ `chat.panel`（聊天页「插件」胶囊弹层） | 4 个 | `title` 16 字 | 由 `data` 推送 | 视图里的按钮/行/选项 → `actions` |
| `turn.note` | 每轮末尾的脚注 | 1 条 | 每段 16 字 | 由 `turnNote` 推送 | **不能点** |

插件名 `title` ≤ 24 字。插槽显示与否还取决于主机：胶囊、菜单、状态条、面板只在装了 dsh-go 桥接的本机引擎上出现，其他主机只有工具卡。

## 二、所有插槽共用的限制

- **`id` 全插件唯一**，跨插槽也不能重名；字母数字开头，只含字母数字与 `_ . -`，≤ 40 字。
- **文案**写字符串或 `{ "zh": "…", "en": "…" }`；中英文都不能超各自上限（超了不是截断，是不显示）。
- **`icon`** 只能从技能文档给的白名单里挑。
- **静态 `effect`** 只有六种：`insert`（插入文字）、`command`（发命令）、`open`（打开）、`link`、`toast`、`copy`。
- **`wants`** 决定能读什么：`clipboard` / `draft` 只给胶囊与 `composer.tools`；`message` 只给长按菜单。没声明就读不到。
- 改 `package.json` 会自动重读；改 `lib/` 里的代码要**重启引擎**。

## 三、处理模型

插件代码写在 `ctx.inject(['dshGo'], (ctx) => { … })` 里：

- `on(id, (scope, event) => 效果)`：胶囊、菜单项、状态条的点击。
- `strip(id, (scope, emit, caps) => …)`：推状态行文字，返回取消函数；可以定时刷新。
- `panel(id, { view, data, actions })`：`view` 声明结构，`data` 推数据（桥接算差量），`actions` 处理面板内点按。

`scope` 带 `{ sessionId?, turnId?, messageId?, callId? }`，点按时另有声明过的 `clipboard` / `draft` / `message`；`event` 为 `{ surface, id, action?, value?, locale }`；面板选项回传 `{ value }`，确认回传 `{ confirmed }`。

## 四、本项目的用法约定

1. **顶栏 `⋯` 菜单做插件插槽时，复用 `session.actions`**（对整段对话动手），不新造动作类贡献点；页面类交给 `panels`，菜单里只放一条「插件」入口。
2. **插件项必须「一点就做」或「开面板」**，不许变成导航。
3. **每个菜单最多 2 条插件动作 + 一个插件入口**；多出来的进 `panels` 的页签。
4. **排序按 App 分组固定**：App 自己的固定项在前，插件项在后；不按插件声明顺序、不按使用频率跳。
5. **固定文字的按钮、顶栏按钮、主题、隐藏元素走 `ui.json`（dsh-go-ui 技能），不写插件。**

## 五、和本次改动的关联

- 「消息范围」（全部 / 只看某位成员）是本 App 自己的功能，不走插件。
- 菜单里的插件段属于**未来增量**：需要 App 侧先加一种贡献点（当前清单里没有「顶栏菜单」），已记在 [memo.md](memo.md)。
