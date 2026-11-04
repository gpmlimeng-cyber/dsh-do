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
| `5c4582b` | `app/lib/state/bots_state.dart` | v1.0.10 | A local send is paired with its echo by text; the echo can carry the picture's reading note, so the pairing had to learn the note's shape. `ui.json` and the plugin protocol cannot change how a pending send settles. |
