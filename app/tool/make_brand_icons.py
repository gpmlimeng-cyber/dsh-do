#!/usr/bin/env python3
"""Generate the launcher icons from app/assets/brand/brand-icon-source.jpg.

Run from the repo root (or app/):  python3 app/tool/make_brand_icons.py

What it writes (idempotent; same input → same bytes):
  * mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher{,_round}.png        48..192
  * the four looks — default, frost, ink, night — as ic_launcher_<look>.png (+ _round)
  * adaptive foregrounds ic_launcher[_<look>]_foreground.png                108..432
    (transparent 108dp grid, artwork centred inside the 66dp safe circle)
  * ic_launcher_monochrome.png: the artwork as a white silhouette, same grid
  * drawable/ic_launcher_background.xml: the picture's own deep-navy edge colour

The artwork is cut out of its background by colour distance from the corner pixel,
so a re-shot picture with the same composition works without hand-tuning.
Only Pillow is required.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]  # repo root
SOURCE = ROOT / 'app/assets/brand/brand-icon-source.jpg'
RES = ROOT / 'app/android/app/src/main/res'

# Legacy icon sizes (mdpi … xxxhdpi) and the 108dp adaptive grid for the same.
LEGACY = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

# The in-app mark (`BrandMark`, the icon picker) bundles the same four looks at 512.
BRAND = {'mist': (132, 158, 175), 'frost': (238, 242, 245), 'ink': (2, 4, 3), 'night': (10, 17, 42)}
BRAND_SIZE = 512
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}

# The four looks keep their existing background tones, so they stay distinguishable;
# the artwork on top is the same picture in all of them.
LOOKS = {
    'frost': (238, 242, 245),
    'ink': (2, 4, 3),
    'night': (10, 17, 42),
}

# How much of the tile the artwork takes. Legacy icons sit a little larger than the
# adaptive foreground, which must stay inside the 66/108 safe circle.
LEGACY_SCALE = 0.80
FOREGROUND_SCALE = 0.60


def cut_out(source: Image.Image) -> tuple[Image.Image, tuple[int, int, int]]:
    """The artwork as RGBA on transparency, plus the background's edge colour."""
    rgb = source.convert('RGB')
    bg = rgb.getpixel((2, 2))
    # The artwork is brighter than its background; its own dark lens is not, so the
    # mask is closed (dilate then erode) to fill the eyes before feathering. Using
    # brightness also keeps the picture's drop shadow out of the cut-out.
    floor = (bg[0] * 299 + bg[1] * 587 + bg[2] * 114) // 1000
    bright = rgb.convert('L')
    # Pixels brighter than the background are the artwork; the dark lens and the
    # drop shadow are not. Flood the *outside* background and keep everything it
    # cannot reach: that fills the lens back in while leaving the shadow out.
    body = bright.point(lambda v: 0 if v > floor + 22 else 255)
    ImageDraw.floodfill(body, (0, 0), 128, thresh=0)
    alpha = body.point(lambda v: 0 if v == 128 else 255)
    alpha = alpha.filter(ImageFilter.GaussianBlur(1.2))
    art = rgb.convert('RGBA')
    art.putalpha(alpha)
    bbox = alpha.point(lambda v: 255 if v > 40 else 0).getbbox()
    if bbox is None:
        raise SystemExit('could not find the artwork in the source picture')
    art = art.crop(bbox)
    return art, bg


def on_background(art: Image.Image, size: int, colour: tuple[int, int, int], *, round_corners: bool) -> Image.Image:
    tile = Image.new('RGBA', (size, size), (*colour, 255))
    side = int(round(size * LEGACY_SCALE))
    scaled = art.copy()
    scaled.thumbnail((side, side), Image.LANCZOS)
    tile.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    if round_corners:
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
        tile.putalpha(ImageChops.multiply(tile.getchannel('A'), mask))
    return tile


def foreground(art: Image.Image, size: int, *, white: bool = False) -> Image.Image:
    tile = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    side = int(round(size * FOREGROUND_SCALE))
    scaled = art.copy()
    scaled.thumbnail((side, side), Image.LANCZOS)
    if white:
        silhouette = Image.new('RGBA', scaled.size, (255, 255, 255, 255))
        silhouette.putalpha(scaled.getchannel('A'))
        scaled = silhouette
    tile.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2))
    return tile


def main() -> int:
    if not SOURCE.exists():
        print(f'missing {SOURCE}', file=sys.stderr)
        return 1
    source = Image.open(SOURCE)
    art, bg = cut_out(source)
    print(f'artwork {art.width}x{art.height}, background {bg}')

    for density, size in LEGACY.items():
        out = RES / f'mipmap-{density}'
        out.mkdir(parents=True, exist_ok=True)
        looks = {'': (9, 25, 40), **LOOKS}
        for suffix, colour in looks.items():
            name = f'ic_launcher{"_" + suffix if suffix else ""}'
            on_background(art, size, colour, round_corners=False).save(out / f'{name}.png')
            on_background(art, size, colour, round_corners=True).save(out / f'{name}_round.png')

    for density, size in ADAPTIVE.items():
        out = RES / f'mipmap-{density}'
        out.mkdir(parents=True, exist_ok=True)
        for suffix in ('', 'frost', 'ink', 'night'):
            name = f'ic_launcher{"_" + suffix if suffix else ""}_foreground'
            foreground(art, size).save(out / f'{name}.png')
        foreground(art, size, white=True).save(out / 'ic_launcher_monochrome.png')

    # In-app brand mark: a rounded tile per look, the artwork alone, and the mono silhouette.
    brand = ROOT / 'app/assets/brand/icons'
    brand.mkdir(parents=True, exist_ok=True)
    for look, colour in BRAND.items():
        tile = on_background(art, BRAND_SIZE, colour, round_corners=False)
        mask = Image.new('L', (BRAND_SIZE, BRAND_SIZE), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            (0, 0, BRAND_SIZE - 1, BRAND_SIZE - 1), radius=int(BRAND_SIZE * 0.22), fill=255
        )
        tile.putalpha(ImageChops.multiply(tile.getchannel('A'), mask))
        tile.save(brand / f'logo_{look}.png')
        art512 = Image.new('RGBA', (BRAND_SIZE, BRAND_SIZE), (0, 0, 0, 0))
        scaled = art.copy()
        scaled.thumbnail((int(BRAND_SIZE * 0.86), int(BRAND_SIZE * 0.86)), Image.LANCZOS)
        art512.alpha_composite(scaled, ((BRAND_SIZE - scaled.width) // 2, (BRAND_SIZE - scaled.height) // 2))
        art512.save(brand / f'logo_{look}_art.png')
    mono = Image.new('RGBA', (BRAND_SIZE, BRAND_SIZE), (0, 0, 0, 0))
    scaled = art.copy()
    scaled.thumbnail((int(BRAND_SIZE * 0.86), int(BRAND_SIZE * 0.86)), Image.LANCZOS)
    white = Image.new('RGBA', scaled.size, (255, 255, 255, 255))
    white.putalpha(scaled.getchannel('A'))
    mono.alpha_composite(white, ((BRAND_SIZE - white.width) // 2, (BRAND_SIZE - white.height) // 2))
    mono.save(brand / 'logo_mono.png')

    background = RES / 'drawable/ic_launcher_background.xml'
    background.write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<!-- Adaptive icon background: the brand picture's own edge colour, so the\n"
        '     launcher mask that cuts the square corners shows the same tone. -->\n'
        '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">\n'
        f'    <solid android:color="#FF{bg[0]:02X}{bg[1]:02X}{bg[2]:02X}"/>\n'
        '</shape>\n',
        encoding='utf-8',
    )
    print(f'wrote icons for {len(LEGACY)} densities (4 looks) and the adaptive grid')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
