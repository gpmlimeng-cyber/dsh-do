# App source changes

The dsh-Go app's own Dart, where a seam cannot do the job. A seam comes first
(ui.json, the native plugin protocol — `composer.actions`, `message.actions`,
`composer.strip`, `panels` — a tool's `presentationMeta`, a Cordis plugin); a
row here says why none of them reaches the spot.

Every row names the upstream it was written against and the commit that carries
it. Keep each change a small, standalone hunk: when a new upstream lands, a
conflict should drop that one hunk rather than the whole branch.

Upstream: `ccch1mneyyy/dsh-Go`, against `v1.0.10` (fork branch `ci/room-progress`).

| File | Written against | Why a seam cannot do it | Commit |
| --- | --- | --- | --- |
| `packages/dsh_client/lib/src/dsbot_api.dart` | v1.0.10 | The drawer hides DS Bot Sessions through one Dart set; `ui.json`'s `hideItems` is a fixed enum and cannot hide a single row, the plugin protocol has no drawer or session-list hook, and Cordis only reaches the web UI. A group that changed parts also leaked its live Session — an upstream bug, fixed upstream should take the one-line change. | `eeb5eaf` |
| `app/lib/ui/shell/session_search_page.dart` | v1.0.10 | A key's shape (36dp glass key vs a search pill) lives in the Flutter widget tree; `ui.json` cannot restyle a drawer key and the plugin protocol has no drawer slot. | `c749250` |
| `app/lib/ui/chat/turn_usage.dart` | v1.0.10 | New file, no upstream hunk: one card for the conversation's context tab and a group's, so the two cannot drift apart again. Nothing to patch; listed so the widget has a home in this record. | `dd88520` |
| `app/lib/ui/bots/room_aggregate_details_page.dart` | v1.0.10 | The details page's title, block order and the trajectory tab's chips are Flutter layout inside a page no seam exposes (the plugin protocol opens its own views, it cannot restyle this one). | `69afae8`, `c4fc9c7` |
| `app/lib/ui/session/session_detail_page.dart` | v1.0.10 | The context tab's inline "每轮用量" block is replaced by the shared card. A single upstream hunk, kept in its own commit so a conflict drops just this block. | `83b5320` |
