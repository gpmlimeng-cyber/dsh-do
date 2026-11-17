#!/usr/bin/env python3
"""Generates app/lib/ui/im/im_partner_templates.g.dart.

Inputs (both committed, pinned snapshots — no network at build time):
  tooling/partner_templates/catalog.json  upstream grok-bot-cn catalog snapshot (MIT)
  tooling/partner_templates/adapted.json  our reviewed 24 templates

Usage:
  python3 app/tool/partner_templates.py            # write the generated Dart
  python3 app/tool/partner_templates.py --check    # validate only; fail if stale

Checks (all fatal): ids resolve in the catalog, no duplicate ids, category coverage,
24 available / 6 featured, role and instructions bounds, banned-word scan, and the
generated file matching what the inputs produce.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / 'tooling' / 'partner_templates' / 'catalog.json'
ADAPTED = ROOT / 'tooling' / 'partner_templates' / 'adapted.json'
OUT = ROOT / 'app' / 'lib' / 'ui' / 'im' / 'im_partner_templates.g.dart'

EXPECTED_AVAILABLE = 24
EXPECTED_FEATURED = 6
ROLE_MAX = 24
INSTRUCTIONS_MIN = 200
INSTRUCTIONS_MAX = 3000
TAGLINE_MAX = 80

BANNED = [
    '/workspace',
    'Grok',
    'grok',
    'draft_bug_report',
    'skills',
    'routines',
    '飞书',
    'Notion',
    'Slack',
    '设置 → 插件',
    '插件市场',
]

# (wire, zh, en, character, color, motion) — the mascot a category gets unless
# adapted.json carries an override (it does not today).
CATEGORIES = [
    ('engineering', '工程', 'Engineering', 'robot', 'steel', 'quiet'),
    ('ops', '运营', 'Operations', 'orb', 'peach', 'quiet'),
    ('creator', '创作', 'Creation', 'jelly', 'rose', 'lively'),
    ('research', '研究', 'Research', 'triangle', 'lavender', 'quiet'),
    ('personal', '生活', 'Life', 'star', 'lemon', 'lively'),
    ('marketing', '营销', 'Marketing', 'orb', 'rose', 'lively'),
    ('finance', '财务', 'Finance', 'onigiri', 'cream', 'quiet'),
    ('support', '客服', 'Support', 'ghost', 'paleCyan', 'lively'),
    ('sales', '销售', 'Sales', 'mango', 'sky', 'lively'),
    ('product', '产品', 'Product', 'triangle', 'steel', 'quiet'),
    ('meta', '元', 'Meta', 'robot', 'miffanInkJade', 'quiet'),
    ('legal', '法律', 'Legal', 'ghost', 'miffanInkJade', 'quiet'),
]
BY_CATEGORY = {c[0]: c for c in CATEGORIES}
SOURCE = {
    'name': 'grok-bot-cn',
    'url': 'https://github.com/junze-xu/grok-bot-cn',
    'license': 'MIT',
    'commit': 'f7ecd0aa142b1ea69f5c0cd8f421eba9c4e4f15c',
}


def fail(message: str) -> None:
    print(f'error: {message}', file=sys.stderr)
    raise SystemExit(1)


def dart_str(value: str) -> str:
    """A Dart string literal: JSON escaping, and `$` escaped so it cannot interpolate."""
    return '"' + json.dumps(str(value), ensure_ascii=False)[1:-1].replace('$', '\\$') + '"'


def load() -> tuple[dict, list[dict]]:
    try:
        catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
        adapted = json.loads(ADAPTED.read_text(encoding='utf-8'))
    except (OSError, ValueError) as error:
        fail(f'cannot read inputs: {error}')
    if not isinstance(catalog, dict) or not isinstance(catalog.get('templates'), list):
        fail('catalog.json is not a grok-bot-cn catalog')
    if not isinstance(adapted, list):
        fail('adapted.json must be a top-level array')
    return catalog, adapted


def validate(catalog: dict, adapted: list[dict]) -> dict[str, dict]:
    upstream = {t['id']: t for t in catalog['templates']}
    seen: set[str] = set()
    categories: dict[str, int] = {}
    featured = 0
    for entry in adapted:
        sid = entry.get('sourceId')
        if not isinstance(sid, str) or sid == '':
            fail('an adapted entry has no sourceId')
        if sid not in upstream:
            fail(f'{sid}: not in catalog.json (catalog v{catalog.get("version")})')
        if sid in seen:
            fail(f'{sid}: duplicated in adapted.json')
        seen.add(sid)
        tmpl = upstream[sid]
        category = tmpl.get('category')
        if category not in BY_CATEGORY:
            fail(f'{sid}: unknown category {category!r}')
        categories[category] = categories.get(category, 0) + 1
        for field in ('nameZh', 'nameEn', 'role', 'instructions'):
            if not isinstance(entry.get(field), str) or entry[field].strip() == '':
                fail(f'{sid}: {field} must be a non-empty string')
        if len(entry['role']) > ROLE_MAX:
            fail(f'{sid}: role is {len(entry["role"])} characters (max {ROLE_MAX})')
        length = len(entry['instructions'])
        if not INSTRUCTIONS_MIN <= length <= INSTRUCTIONS_MAX:
            fail(f'{sid}: instructions is {length} characters (want {INSTRUCTIONS_MIN}-{INSTRUCTIONS_MAX})')
        if entry.get('featured') is True:
            featured += 1
        blob = ' '.join(entry[f] for f in ('nameZh', 'nameEn', 'role', 'instructions'))
        for word in BANNED:
            if word in blob:
                fail(f'{sid}: banned word {word!r} in its copy')
    if len(adapted) != EXPECTED_AVAILABLE:
        fail(f'{len(adapted)} adapted templates (want {EXPECTED_AVAILABLE})')
    if featured != EXPECTED_FEATURED:
        fail(f'{featured} featured templates (want {EXPECTED_FEATURED})')
    missing = [c for c in BY_CATEGORY if c not in categories]
    if missing:
        fail(f'no adapted template in categories: {", ".join(missing)}')
    return upstream


def render(catalog: dict, adapted: list[dict], upstream: dict[str, dict]) -> str:
    adapted_ids = {entry['sourceId'] for entry in adapted}
    lines: list[str] = [
        '// GENERATED by app/tool/partner_templates.py — do not edit by hand.',
        '//',
        f'// Source: {SOURCE["name"]} ({SOURCE["license"]}), '
        f'{SOURCE["url"]}, snapshot {SOURCE["commit"]}.',
        '// Catalog v' + str(catalog.get('version')) + ': '
        + f'{len(catalog["templates"])} templates, {len(CATEGORIES)} categories.',
        '// See THIRD_PARTY_NOTICES.md and tooling/partner_templates/README.md.',
        '',
        "import '../mascots/mascot_avatar.dart';",
        '',
        '/// Where a template came from, for the detail page and the notices.',
        'class PartnerTemplateSource {',
        '  const PartnerTemplateSource({',
        '    required this.name,',
        '    required this.url,',
        '    required this.license,',
        '    required this.commit,',
        '  });',
        '',
        '  final String name;',
        '  final String url;',
        '  final String license;',
        '  final String commit;',
        '}',
        '',
        'const partnerTemplateSource = PartnerTemplateSource(',
        f'  name: {dart_str(SOURCE["name"])},',
        f'  url: {dart_str(SOURCE["url"])},',
        f'  license: {dart_str(SOURCE["license"])},',
        f'  commit: {dart_str(SOURCE["commit"])},',
        ');',
        '',
        '/// One template category, with the names the UI shows.',
        'class PartnerTemplateCategory {',
        '  const PartnerTemplateCategory(this.id, this.zh, this.en, this.mascot);',
        '',
        '  final String id;',
        '  final String zh;',
        '  final String en;',
        '',
        '  /// The mascot a template in this category gets unless it overrides one.',
        '  final MascotSpec mascot;',
        '}',
        '',
        'const partnerTemplateCategories = <PartnerTemplateCategory>[',
    ]
    for wire, zh, en, character, color, motion in CATEGORIES:
        lines.append(
            '  PartnerTemplateCategory('
            f'{dart_str(wire)}, {dart_str(zh)}, {dart_str(en)}, '
            f'MascotSpec(character: MascotCharacter.{character}, color: MascotColor.{color}, '
            f'motion: MascotMotion.{motion})),'
        )
    lines += [
        '];',
        '',
        '/// A partner template: what 「用这个模板创建」 prefills.',
        'class PartnerTemplate {',
        '  const PartnerTemplate({',
        '    required this.id,',
        '    required this.nameZh,',
        '    required this.nameEn,',
        '    required this.category,',
        '    required this.tagline,',
        '    required this.role,',
        '    required this.instructions,',
        '    required this.mascot,',
        '    required this.available,',
        '    required this.featured,',
        '    this.source = partnerTemplateSource,',
        '  });',
        '',
        '  /// List key only — never a Bot id. Upstream ones are `grok.<sourceId>`.',
        '  final String id;',
        '  final String nameZh;',
        '  final String nameEn;',
        '',
        '  /// One of `partnerTemplateCategories`.',
        '  final String category;',
        '',
        '  /// One line under the name.',
        '  final String tagline;',
        '',
        '  /// The Host `role` field (≤24 characters).',
        '  final String role;',
        '',
        '  /// The full prompt, sent as-is; empty while [available] is false.',
        '  final String instructions;',
        '  final MascotSpec mascot;',
        '',
        '  /// False = 「即将支持」: shown with its metadata, cannot be created.',
        '  final bool available;',
        '',
        '  /// The six on the 伙伴 tab home.',
        '  final bool featured;',
        '  final PartnerTemplateSource source;',
        '}',
        '',
        'const partnerTemplates = <PartnerTemplate>[',
    ]
    for entry in adapted:
        sid = entry['sourceId']
        tmpl = upstream[sid]
        wire, _zh, _en, character, color, motion = BY_CATEGORY[tmpl['category']]
        lines.append('  PartnerTemplate(')
        lines.append(f'    id: {dart_str("grok." + sid)},')
        lines.append(f'    nameZh: {dart_str(entry["nameZh"])},')
        lines.append(f'    nameEn: {dart_str(entry["nameEn"])},')
        lines.append(f'    category: {dart_str(wire)},')
        lines.append(f'    tagline: {dart_str(entry["role"])},')
        lines.append(f'    role: {dart_str(entry["role"])},')
        lines.append(f'    instructions: {dart_str(entry["instructions"])},')
        lines.append(
            '    mascot: MascotSpec('
            f'character: MascotCharacter.{character}, color: MascotColor.{color}, '
            f'motion: MascotMotion.{motion}),'
        )
        lines.append('    available: true,')
        lines.append(f'    featured: {"true" if entry.get("featured") is True else "false"},')
        lines.append('  ),')
    for tmpl in catalog['templates']:
        if tmpl['id'] in adapted_ids:
            continue
        wire, _zh, _en, character, color, motion = BY_CATEGORY[tmpl['category']]
        name = str(tmpl.get('name') or tmpl.get('title') or tmpl['id'])
        tagline = str(tmpl.get('tagline') or tmpl.get('why') or '').strip()
        if len(tagline) > TAGLINE_MAX:
            tagline = tagline[:TAGLINE_MAX].rstrip() + '…'
        lines.append('  PartnerTemplate(')
        lines.append(f'    id: {dart_str("grok." + tmpl["id"])},')
        lines.append(f'    nameZh: {dart_str(name)},')
        lines.append('    nameEn: "",')
        lines.append(f'    category: {dart_str(wire)},')
        lines.append(f'    tagline: {dart_str(tagline)},')
        lines.append('    role: "",')
        lines.append('    instructions: "",')
        lines.append(
            '    mascot: MascotSpec('
            f'character: MascotCharacter.{character}, color: MascotColor.{color}, '
            f'motion: MascotMotion.{motion}),'
        )
        lines.append('    available: false,')
        lines.append('    featured: false,')
        lines.append('  ),')
    lines += ['];', '']
    return '\n'.join(lines)


def main() -> None:
    catalog, adapted = load()
    upstream = validate(catalog, adapted)
    text = render(catalog, adapted, upstream)
    old = OUT.read_text(encoding='utf-8') if OUT.exists() else ''
    if '--check' in sys.argv[1:]:
        if old != text:
            fail(f'{OUT.relative_to(ROOT)} is stale; run python3 app/tool/partner_templates.py')
        print(f'✓ partner templates up to date ({len(adapted)} available, {len(catalog["templates"])} total)')
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(text, encoding='utf-8')
    print(f'✓ wrote {OUT.relative_to(ROOT)} ({len(adapted)} available, {len(catalog["templates"])} total)')


if __name__ == '__main__':
    main()
