# Partner templates (grok-bot-cn snapshot)

Inputs for `app/tool/partner_templates.py`, which generates
`app/lib/ui/im/im_partner_templates.g.dart`.

| File | What it is |
|---|---|
| `catalog.json` | Upstream `catalog/catalog.json` snapshot, verbatim: `junze-xu/grok-bot-cn` @ `f7ecd0aa142b1ea69f5c0cd8f421eba9c4e4f15c` (catalog v1.1.0, MIT, © 2026 junze-xu). 151 templates, 12 categories. |
| `adapted.json` | The 24 templates we reviewed and rewrote: `sourceId / nameZh / nameEn / role / instructions / featured`. Only 「任务 / 边界 / 工作方式」 survive; upstream brands, paths, skills, routines and tool names are removed. |

Regenerate after editing either file:

```bash
python3 app/tool/partner_templates.py
python3 app/tool/partner_templates.py --check   # what CI runs
```

The generator fails on: ids missing from the catalog, duplicates, an unknown
category, fewer/more than 24 available templates, not exactly 6 featured, no
template in a category, `role` over 24 characters, `instructions` outside
200–3000 characters, banned words (`/workspace`, `Grok`, `skills`, `routines`,
`飞书`, `Notion`, `Slack`, …), and a generated file that is out of date.

The other 127 upstream templates are emitted with metadata only
(`available: false`): the app shows their name, tagline and category, and the
create action stays disabled. No unreviewed prompt text ships.

License: MIT, © 2026 junze-xu. The notice is in `THIRD_PARTY_NOTICES.md`.
