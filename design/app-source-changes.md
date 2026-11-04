# App source changes

The dsh-Go app's own Dart, where a seam cannot do the job. A seam comes first
(ui.json, the native plugin protocol — `composer.actions`, `message.actions`,
`composer.strip`, `panels` — a tool's `presentationMeta`, a Cordis plugin); a
row here says why none of them reaches the spot.

One row per commit. Every row names the upstream it was written against and the
commit that carries it. Keep each change a small, standalone hunk: when a new
upstream lands, a conflict should drop that one hunk rather than the whole
branch. This file itself is new — it replaces no upstream hunk.

Upstream: `ccch1mneyyy/dsh-Go`, against `v1.0.10` (fork branch `ci/room-progress`).

| Commit | File | Written against | Why a seam cannot do it |
| --- | --- | --- | --- |
| `eeb5eaf` | `packages/dsh_client/lib/src/dsbot_api.dart` | v1.0.10 | The drawer hides DS Bot Sessions through one Dart set; `ui.json`'s `hideItems` is a fixed enum and cannot hide a single row, the plugin protocol has no drawer or session-list hook, and Cordis only reaches the web UI. A group that changed parts also leaked its live Session — an upstream bug, so the one-line change is worth sending upstream too. |
| `c749250` | `app/lib/ui/shell/session_search_page.dart` | v1.0.10 | A key's shape (36dp glass key vs a search pill) lives in the Flutter widget tree; `ui.json` cannot restyle a drawer key and the plugin protocol has no drawer slot. |
| `dd88520` | `app/lib/ui/chat/turn_usage.dart` (new) | v1.0.10 | No upstream hunk: one card for the conversation's context tab and a group's, so the two cannot drift apart again (the group's copy had lost its tabular figures). |
| `69afae8` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The context page's block order and the shape of the turn usage card are Flutter layout inside a page no seam exposes. |
| `83b5320` | `app/lib/ui/session/session_detail_page.dart` | v1.0.10 | The context tab's inline "每轮用量" block is replaced by the shared card. A single upstream hunk, kept in its own commit so a conflict drops just this block. |
| `c4fc9c7` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The trajectory tab's member summary card becomes a row of chips that switch the Session; the plugin protocol opens its own views but cannot restyle this page. |
| `61a26d6` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The bar's title is set in Dart (`AppPage(title: ...)`); no seam can rename a hero page's bar. |
| `ba6fdda` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The 上下文 tab's two top cards total the group: the group Session plus every member's Session in this group. A seam sees the plugin's own data, not the page's Flutter cards, and the totals need the page's own `SessionUsage` composition. |
| `5c4582b` | `app/lib/state/bots_state.dart` (+ its test `app/test/bots/bots_state_test.dart`) | v1.0.10 | A local send is paired with its echo by text; the echo can carry the picture's reading note, so the pairing had to learn the note's shape. `ui.json` and the plugin protocol cannot change how a pending send settles. |
| `a03c5ee` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The context tab held the last figures in a state field; a reload would otherwise blank the tab and jump to the top. Superseded by `ea4a6cc`'s provider, kept for the record. |
| `ea4a6cc` | `app/lib/state/room_activity_state.dart` (new), `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The member read belongs to the state layer, behind one provider keyed by strings — no seam can make two Flutter screens share it. |
| `8827e41` | `app/lib/ui/bots/room_activity_strip.dart` (new), `app/lib/ui/bots/bot_composer_deck.dart`, `app/lib/ui/bots/room_chat_page.dart` | v1.0.10 | The group's status line is a Flutter dock slot above the composer; the plugin protocol cannot draw inside the composer's deck. |
| `007edf5` | `app/lib/ui/bots/bot_composer_deck.dart`, `app/lib/ui/bots/room_chat_page.dart`, `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The context ring and the running microphone sit in the Composer's `accessory`, which only the page assembles; the details page's initial tab is a Dart parameter. |
| `1c45494` | `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The trajectory chips' fallback lives in the tab's state; no seam owns that widget's selection. |
| `be0e1b6` | `app/lib/ui/bots/room_aggregate_details_page.dart`, `app/lib/ui/bots/bot_composer_deck.dart`, `app/lib/ui/bots/room_chat_page.dart` | v1.0.10 | riverpod 3 removed `valueOrNull`; the composer's accessory must answer null so the send key keeps its place. |
| `1b0bd63` | `app/lib/ui/bots/bot_chat_kit.dart` | v1.0.10 | A message's long-press menu is built by the widget that draws the bubble; no seam changes its actions or preview. |
| `8a99834` | `app/lib/ui/bots/bot_chat_kit.dart` | v1.0.10 | The person's bubble menu is the same widget's other path: no 分享, masked preview, 选择文字 as plain text. |
| `51c56b0` | `app/lib/ui/bots/room_aggregate_details_page.dart`, `app/lib/ui/bots/bot_chat_kit.dart` | v1.0.10 | Restores the trajectory tab's fallback that a stale copy had dropped, and shares a Bot reply's plain text (the view JSON is not what sharing means). |
| `6341c4b` | `app/lib/state/room_message_mode.dart` (new), `app/lib/ui/bots/room_message_sheet.dart` (new), `app/lib/ui/bots/bot_chat_kit.dart`, `app/lib/ui/bots/room_chat_page.dart`, `app/lib/l10n/` | v1.0.10 | The mode key and its sheet are Flutter widgets, and the filter is a derived list over the chat's own items; no seam changes what a group chat renders. |
| `4accb1f` | `app/lib/ui/bots/room_message_sheet.dart`, `app/lib/state/room_message_mode.dart` | v1.0.10 | Unused import, the 仅与我相关 stretch end, and a pick made while the stored modes load. |
| `8426613` | `app/lib/ui/bots/room_activity_strip.dart`, `app/lib/ui/bots/bot_composer_deck.dart` | v1.0.10 | The header's words and the capsule row's visibility are Flutter layout; no seam renames a status line or folds the plugin row. |
| `f75a828` | `app/lib/ui/bots/room_chat_page.dart`, `app/lib/ui/bots/room_activity_strip.dart`, `app/lib/state/room_message_mode.dart`, `app/lib/l10n/` | v1.0.10 | The finished-round flash is page-local state and Flutter timing; the flow's `done` echo and the mode coupling live in the derived list, which no seam owns. |
| `44c665b` | `app/lib/state/bots_state.dart`, `app/lib/ui/bots/room_chat_page.dart` | v1.0.10 | The sending bubble is the chat's own state machine: pending entries and their local drafts — no seam sees or draws them. |
| `a497863` | `app/lib/ui/bots/room_chat_page.dart` | v1.0.10 | The finished-round flash's timer is page state; it is cancelled with the page, as the progress timer is. |
| `8e13cad` | `app/lib/state/bots_state.dart`, `app/lib/ui/bots/room_chat_page.dart` | v1.0.10 | An empty-text bubble pairs only with lines past the seq it was made at; a send that could not start takes it back. |
| `53b0ef9` | `app/lib/state/bots_state.dart` | v1.0.10 | The pairing record carries `seq`, so the comparison compiles. |
| `50ee102` | `app/lib/ui/bots/bot_chat_kit.dart`, `app/lib/ui/bots/room_chat_page.dart`, `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | Where a group's cards hang and what its context tab draws are Flutter layout; no seam owns either. |
| `1f0adb1` | `app/lib/ui/bots/room_activity_strip.dart`, `app/lib/ui/bots/room_chat_page.dart`, `app/lib/l10n/` | v1.0.10 | The line's contents and the composer's hint are Flutter widget work; no seam draws the group's deck. |
