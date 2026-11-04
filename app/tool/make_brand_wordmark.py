#!/usr/bin/env python3
"""Generates lib/ui/shell/brand_wordmark.g.dart from assets/brand/wordmark.svg.

Run from app/:

    python3 tool/make_brand_wordmark.py

The wordmark master (design/brand-svg/modo-wordmark.svg) is the four mark shapes laid
out in one row in a 1064x196 viewBox, filled with a flat `currentColor`. Unlike the
icon masters it still carries SVG's curve and arc commands (`Q`, `A`) and two
`<circle>`s, so this script converts everything to absolute `M`/`C`/`Z` first: arcs
become up to four cubic segments, a circle becomes four, and `Q` becomes one. The
result is a single `Path`, since the whole wordmark is one flat fill.

Pure Python, no dependencies.
"""
import math
import os
import re
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(APP, 'assets', 'brand', 'wordmark.svg')
OUT = os.path.join(APP, 'lib', 'ui', 'shell', 'brand_wordmark.g.dart')
ANDROID = os.path.join(APP, 'android', 'app', 'src', 'main', 'res', 'drawable', 'ic_wordmark.xml')

NUM = r'[-+]?(?:\d+\.\d*|\.\d+|\d+)(?:[eE][-+]?\d+)?'
TOKEN = re.compile(r'[MmLlHhVvCcSsQqTtAaZz]|' + NUM)
KAPPA = 0.5522847498307936  # cubic handle length for a quarter circle


def read():
    return open(SRC, encoding='utf-8').read()


def circles(svg):
    return [(float(m.group(1)), float(m.group(2)), float(m.group(3)))
            for m in re.finditer(r'<circle\s+cx="([^"]+)"\s+cy="([^"]+)"\s+r="([^"]+)"', svg)]


def circle_subs(cx, cy, r):
    """A circle as four cubic quarter arcs, clockwise from the right."""
    k = KAPPA * r
    return [
        ((cx + r, cy), [((cx + r, cy + k), (cx + k, cy + r), (cx, cy + r))]),
        ((cx, cy + r), [((cx - k, cy + r), (cx - r, cy + k), (cx - r, cy))]),
        ((cx - r, cy), [((cx - r, cy - k), (cx - k, cy - r), (cx, cy - r))]),
        ((cx, cy - r), [((cx + k, cy - r), (cx + r, cy - k), (cx + r, cy))]),
    ]


def arc_cubics(p0, rx, ry, phi_deg, large, sweep, p1):
    """SVG endpoint arc (see the spec's implementation notes) as cubic segments."""
    if rx == 0 or ry == 0 or p0 == p1:
        return [(p0, p1, p1)]
    phi = math.radians(phi_deg)
    cosphi, sinphi = math.cos(phi), math.sin(phi)
    dx2, dy2 = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1p = cosphi * dx2 + sinphi * dy2
    y1p = -sinphi * dx2 + cosphi * dy2
    rx, ry = abs(rx), abs(ry)
    lam = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
    den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
    coef = (-1.0 if large == sweep else 1.0) * math.sqrt(max(0.0, num / den))
    cxp = coef * rx * y1p / ry
    cyp = -coef * ry * x1p / rx
    cx = cosphi * cxp - sinphi * cyp + (p0[0] + p1[0]) / 2
    cy = sinphi * cxp + cosphi * cyp + (p0[1] + p1[1]) / 2

    def angle(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    ux, uy = (x1p - cxp) / rx, (y1p - cyp) / ry
    vx, vy = (-x1p - cxp) / rx, (-y1p - cyp) / ry
    theta1 = angle(1, 0, ux, uy)
    dtheta = angle(ux, uy, vx, vy)
    if not sweep and dtheta > 0:
        dtheta -= 2 * math.pi
    elif sweep and dtheta < 0:
        dtheta += 2 * math.pi

    def point(a):
        return (cx + cosphi * rx * math.cos(a) - sinphi * ry * math.sin(a),
                cy + sinphi * rx * math.cos(a) + cosphi * ry * math.sin(a))

    def tangent(a):
        return (-cosphi * rx * math.sin(a) - sinphi * ry * math.cos(a),
                -sinphi * rx * math.sin(a) + cosphi * ry * math.cos(a))

    n = max(1, int(math.ceil(abs(dtheta) / (math.pi / 2) - 1e-9)))
    delta = dtheta / n
    h = 4 / 3 * math.tan(delta / 4)
    out = []
    for i in range(n):
        a1 = theta1 + i * delta
        a2 = a1 + delta
        s, e = point(a1), point(a2)
        t1, t2 = tangent(a1), tangent(a2)
        out.append(((s[0] + h * t1[0], s[1] + h * t1[1]),
                    (e[0] - h * t2[0], e[1] - h * t2[1]), e))
    return out


def parse_path(d):
    """SVG path data → [(start, [(c1, c2, end), ...])], absolute coordinates."""
    toks = TOKEN.findall(d)
    subs, i = [], 0
    cur = start = None
    segs = []
    prev_cubic = prev_quad = None  # last control point, for S/T
    cmd = None
    done = True  # the current subpath has already been flushed

    def num():
        nonlocal i
        v = float(toks[i])
        i += 1
        return v

    def flush():
        nonlocal done
        if cur is not None and not done:
            subs.append((start, segs))
            done = True

    while i < len(toks):
        t = toks[i]
        if re.match(r'[A-Za-z]', t):
            cmd = t
            i += 1
            if cmd in 'Zz':
                flush()
                if cur is not None:
                    cur = start
                prev_cubic = prev_quad = None
                continue
        elif cmd is None:
            raise ValueError('path data starts without a command')
        rel = cmd.islower()
        c = cmd.upper()
        if c == 'M':
            x, y = num(), num()
            if rel and cur is not None:
                x, y = cur[0] + x, cur[1] + y
            flush()
            start = cur = (x, y)
            segs = []
            done = False
            prev_cubic = prev_quad = None
            cmd = 'l' if rel else 'L'  # implicit lineto for the following pairs
        elif c == 'L':
            x, y = num(), num()
            if rel:
                x, y = cur[0] + x, cur[1] + y
            p = (x, y)
            segs.append((cur, p, p))
            cur = p
            prev_cubic = prev_quad = None
        elif c == 'H':
            x = num()
            x = cur[0] + x if rel else x
            p = (x, cur[1])
            segs.append((cur, p, p))
            cur = p
            prev_cubic = prev_quad = None
        elif c == 'V':
            y = num()
            y = cur[1] + y if rel else y
            p = (cur[0], y)
            segs.append((cur, p, p))
            cur = p
            prev_cubic = prev_quad = None
        elif c in 'CS':
            if c == 'C':
                x1, y1, x2, y2, x, y = (num() for _ in range(6))
                c1 = (x1, y1)
            else:
                x2, y2, x, y = (num() for _ in range(4))
                c1 = ((2 * cur[0] - prev_cubic[0], 2 * cur[1] - prev_cubic[1])
                      if prev_cubic else cur)
            c2 = (x2, y2)
            p = (x, y)
            if rel:
                c1 = (cur[0] + c1[0], cur[1] + c1[1])
                c2 = (cur[0] + c2[0], cur[1] + c2[1])
                p = (cur[0] + p[0], cur[1] + p[1])
            segs.append((c1, c2, p))
            prev_cubic, prev_quad = c2, None
            cur = p
        elif c in 'QT':
            if c == 'Q':
                qx, qy, x, y = (num() for _ in range(4))
                q = (qx, qy)
            else:
                x, y = num(), num()
                q = ((2 * cur[0] - prev_quad[0], 2 * cur[1] - prev_quad[1])
                     if prev_quad else cur)
            p = (x, y)
            if rel:
                q = (cur[0] + q[0], cur[1] + q[1])
                p = (cur[0] + p[0], cur[1] + p[1])
            c1 = (cur[0] + 2 / 3 * (q[0] - cur[0]), cur[1] + 2 / 3 * (q[1] - cur[1]))
            c2 = (p[0] + 2 / 3 * (q[0] - p[0]), p[1] + 2 / 3 * (q[1] - p[1]))
            segs.append((c1, c2, p))
            prev_quad, prev_cubic = q, None
            cur = p
        elif c == 'A':
            rx, ry, rot, large, sweep, x, y = (num() for _ in range(7))
            p = (x, y)
            if rel:
                p = (cur[0] + p[0], cur[1] + p[1])
            segs += arc_cubics(cur, rx, ry, rot, int(large), int(sweep), p)
            cur = p
            prev_cubic = prev_quad = None
        else:
            raise ValueError(f'unsupported path command {cmd!r}')
    flush()
    return subs


def shapes(svg):
    """Every wordmark shape in document order: (start, segs)."""
    out = []
    for m in re.finditer(r'<path\s+d="([^"]+)"|<circle\s+cx="([^"]+)"\s+cy="([^"]+)"\s+r="([^"]+)"', svg):
        if m.group(1):
            out += parse_path(m.group(1))
        else:
            out += circle_subs(float(m.group(2)), float(m.group(3)), float(m.group(4)))
    return out


def flatten(subs, n=128):
    polys = []
    for start, segs in subs:
        pts, cur = [start], start
        for c1, c2, p3 in segs:
            for k in range(1, n + 1):
                t = k / n
                mt = 1 - t
                pts.append(tuple(mt ** 3 * a + 3 * mt * mt * t * b + 3 * mt * t * t * c + t ** 3 * d
                                 for a, b, c, d in zip(cur, c1, c2, p3)))
            cur = p3
        polys.append(pts)
    return polys


def f(v):
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def dart_path(subs):
    lines = ['Path()']
    for (x, y), segs in subs:
        lines.append(f'    ..moveTo({f(x)}, {f(y)})')
        for (a, b), (c, d), (e, g) in segs:
            lines.append(f'    ..cubicTo({f(a)}, {f(b)}, {f(c)}, {f(d)}, {f(e)}, {f(g)})')
        lines.append('    ..close()')
    return '\n'.join(lines)


def dart_path_data(subs):
    """The same shapes as one SVG/Android path data string."""
    parts = []
    for (x, y), segs in subs:
        parts.append(f'M{f(x)} {f(y)}')
        for (a, b), (c, d), (e, g) in segs:
            parts.append(f'C{f(a)} {f(b)} {f(c)} {f(d)} {f(e)} {f(g)}')
        parts.append('Z')
    return ' '.join(parts)


def main():
    svg = read()
    subs = shapes(svg)
    if not subs:
        sys.exit('wordmark.svg: no paths or circles found')
    pts = [p for poly in flatten(subs) for p in poly]
    xs = [x for x, _ in pts]
    ys = [y for _, y in pts]
    box = (min(xs), min(ys), max(xs), max(ys))
    w, h = box[2] - box[0], box[3] - box[1]

    out = f'''// GENERATED by tool/make_brand_wordmark.py from assets/brand/wordmark.svg.
// Do not edit; change the master and run the tool.
//
// The dsh-go wordmark: the four mark shapes in one row, one flat fill, in the
// master's own 1064x196 grid.

// dart format off
import 'dart:ui' show Path, Rect;

/// Paths and measurements of the brand wordmark (see `brand_wordmark.dart`).
/// Named `…Paths` so the widget can be `BrandWordmark`.
abstract final class BrandWordmarkPaths {{
  /// The wordmark's ink box.
  static const box = Rect.fromLTRB({f(box[0])}, {f(box[1])}, {f(box[2])}, {f(box[3])});

  /// Width / height of [box].
  static const aspect = {w / h:.6f};

  /// Every shape of the wordmark as one path, in the master's grid.
  static final Path ink = {dart_path(subs)};
}}
'''
    open(OUT, 'w', encoding='utf-8').write(out)

    # The same path as an Android vector, for the native side (the launch screen and the
    # system splash's branding image). One flat fill, tinted by the caller.
    xml = f'''<?xml version="1.0" encoding="utf-8"?>
<!-- GENERATED by tool/make_brand_wordmark.py from assets/brand/wordmark.svg. Do not edit;
     change the master and run the tool. -->
<!-- The dsh-go wordmark, absolute M/C/Z only and one fill, so it needs no gradients: tint it
     (android:tint) for light and dark pages. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="{w / 196 * 44:.4f}dp"
    android:height="44dp"
    android:viewportWidth="{f(w)}"
    android:viewportHeight="{f(h)}">
    <path
        android:pathData="{dart_path_data(subs)}"
        android:fillColor="#FFFFFFFF" />
</vector>
'''
    open(ANDROID, 'w', encoding='utf-8').write(xml)
    print(f'wrote {os.path.relpath(OUT, APP)} and {os.path.relpath(ANDROID, APP)}: {len(subs)} subpaths, '
          f'box LTRB({f(box[0])}, {f(box[1])}, {f(box[2])}, {f(box[3])}), '
          f'size {f(w)} x {f(h)}, aspect {w / h:.6f}')


if __name__ == '__main__':
    main()
