#!/usr/bin/env python3
"""Draws Pane's two custom SF Symbol templates (Home and Rotate Left) from geometry.

Device Hub's toolbar glyphs (`app.grid.3x3` and its rotate) are private to Apple, so Pane draws
look-alikes from measurements of Device Hub's rendering, never from Apple's artwork. Each template
has Ultralight, Regular and Black at the small scale, which is all Xcode needs to interpolate every
weight and scale (template format 4.0). The three share one path structure, as interpolation needs.

Usage: scripts/make-symbols.py [scale]   writes Resources/Assets.xcassets/*.symbolset
       (scale multiplies every size; the default is calibrated so a 15 pt medium-scale image
       matches Device Hub's toolbar at 15 pt.)
"""
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Resources", "Assets.xcassets")

# Template geometry (points at 100 pt; the system scales it). Baseline and cap line of the small row.
BASELINE = 696.0
CAP_HEIGHT = 70.459
# Symbols are centred on the cap line's middle, as text-aligned SF Symbols are.
MID_Y = -CAP_HEIGHT / 2
SIDE_BEARING = 3.0
KAPPA = 0.5522847498

WEIGHTS = {
    # name: (column left x in the template, stroke width multiplier)
    "Ultralight": (511.392, 0.42),
    "Regular": (1399.21, 1.0),
    "Black": (2877.74, 1.9),
}

# The medium scale draws the small-scale design about 1.25 times larger; 0.8 undoes that, so the
# measurements below (taken at medium, Pane's scale) come out as measured.
SCALE = 0.8 * (float(sys.argv[1]) if len(sys.argv) > 1 else 1.0)


def fmt(v):
    return f"{v:.3f}".rstrip("0").rstrip(".")


class Path:
    """Closed contours of cubic segments, in y-down coordinates around the glyph centre."""

    def __init__(self):
        self.contours = []

    def add(self, contour):
        # contour: start point plus a list of (c1, c2, end); lines are cubics with thirds.
        self.contours.append(contour)


def line(p, q):
    return ((p[0] + (q[0] - p[0]) / 3, p[1] + (q[1] - p[1]) / 3),
            (p[0] + 2 * (q[0] - p[0]) / 3, p[1] + 2 * (q[1] - p[1]) / 3), q)


def arc(c, r, a0, a1):
    """Cubic segments along a circle from angle a0 to a1 (radians, y-down), at most 90° each."""
    segs = []
    n = max(1, math.ceil(abs(a1 - a0) / (math.pi / 2) - 1e-9))
    step = (a1 - a0) / n
    k = 4 / 3 * math.tan(step / 4)
    for i in range(n):
        t0, t1 = a0 + i * step, a0 + (i + 1) * step
        p0 = (c[0] + r * math.cos(t0), c[1] + r * math.sin(t0))
        p3 = (c[0] + r * math.cos(t1), c[1] + r * math.sin(t1))
        c1 = (p0[0] - k * r * math.sin(t0), p0[1] + k * r * math.cos(t0))
        c2 = (p3[0] + k * r * math.sin(t1), p3[1] - k * r * math.cos(t1))
        segs.append((c1, c2, p3))
    return segs


def point_at(c, r, a):
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def rounded_rect(cx, cy, hw, hh, r, clockwise=True):
    """A rounded rectangle; clockwise on screen (y down) unless told otherwise."""
    r = max(0.01, min(r, hw, hh))
    segs = []
    start = (cx - hw + r, cy - hh)
    pts = start
    # top edge, top-right corner, right edge, bottom-right, bottom, bottom-left, left, top-left
    plan = [
        ("L", (cx + hw - r, cy - hh)), ("A", (cx + hw - r, cy - hh + r), -math.pi / 2, 0),
        ("L", (cx + hw, cy + hh - r)), ("A", (cx + hw - r, cy + hh - r), 0, math.pi / 2),
        ("L", (cx - hw + r, cy + hh)), ("A", (cx - hw + r, cy + hh - r), math.pi / 2, math.pi),
        ("L", (cx - hw, cy - hh + r)), ("A", (cx - hw + r, cy - hh + r), math.pi, 3 * math.pi / 2),
    ]
    for step in plan:
        if step[0] == "L":
            segs.append(line(pts, step[1]))
            pts = step[1]
        else:
            s = arc(step[1], r, step[2], step[3])
            segs.extend(s)
            pts = s[-1][2]
    contour = (start, segs)
    return contour if clockwise else reverse(contour)


def reverse(contour):
    start, segs = contour
    pts = [start] + [s[2] for s in segs]
    out = []
    for i in range(len(segs) - 1, -1, -1):
        c1, c2, _ = segs[i]
        out.append((c2, c1, pts[i]))
    return (pts[-1], out)


def rounded_polygon(points, r):
    """A convex polygon (clockwise on screen) with each corner rounded by a cubic of radius ~r."""
    n = len(points)
    segs = []
    corners = []
    for i in range(n):
        p_prev, p, p_next = points[i - 1], points[i], points[(i + 1) % n]
        def toward(a, b, d):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy)
            return (a[0] + dx / length * d, a[1] + dy / length * d)
        corners.append((toward(p, p_prev, r), p, toward(p, p_next, r)))
    start = corners[0][2]
    cur = start
    for i in range(1, n + 1):
        a, p, b = corners[i % n]
        segs.append(line(cur, a))
        # A corner: a cubic whose handles sit 55% of the way to the corner point.
        c1 = (a[0] + (p[0] - a[0]) * KAPPA, a[1] + (p[1] - a[1]) * KAPPA)
        c2 = (b[0] + (p[0] - b[0]) * KAPPA, b[1] + (p[1] - b[1]) * KAPPA)
        segs.append((c1, c2, b))
        cur = b
    return (start, segs)


def stroked_arc(c, r, w, a0, a1):
    """A thick arc from a0 to a1 (screen angles, a1 < a0 means counter-clockwise) with a round
    cap at the a0 end and a flat end at a1 (an arrowhead covers it)."""
    outer = arc(c, r + w / 2, a0, a1)
    inner = arc(c, r - w / 2, a1, a0)
    start = point_at(c, r + w / 2, a0)
    segs = list(outer)
    segs.append(line(outer[-1][2], point_at(c, r - w / 2, a1)))
    segs.extend(inner)
    # Round cap back to the start, bulging away from the arc's direction of travel.
    cap_c = point_at(c, r, a0)
    direction = -1 if a1 < a0 else 1
    base = a0 + math.pi
    segs.extend(arc(cap_c, w / 2, base, base + direction * math.pi))
    return (start, segs)


def signed_area(contour):
    start, segs = contour
    pts = [start]
    cur = start
    for c1, c2, end in segs:
        for t in (0.25, 0.5, 0.75, 1.0):
            mt = 1 - t
            x = mt**3 * cur[0] + 3 * mt * mt * t * c1[0] + 3 * mt * t * t * c2[0] + t**3 * end[0]
            y = mt**3 * cur[1] + 3 * mt * mt * t * c1[1] + 3 * mt * t * t * c2[1] + t**3 * end[1]
            pts.append((x, y))
        cur = end
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def clockwise(contour):
    # y down: positive shoelace area is clockwise on screen.
    return contour if signed_area(contour) > 0 else reverse(contour)


def bounds(path):
    xs, ys = [], []
    for start, segs in path.contours:
        xs.append(start[0]); ys.append(start[1])
        for seg in segs:
            for p in seg:
                xs.append(p[0]); ys.append(p[1])
    return min(xs), min(ys), max(xs), max(ys)


def to_d(path, dx):
    out = []
    for start, segs in path.contours:
        out.append(f"M{fmt(start[0] + dx)} {fmt(start[1] + MID_Y)}")
        for c1, c2, end in segs:
            out.append(
                f"C{fmt(c1[0] + dx)} {fmt(c1[1] + MID_Y)} {fmt(c2[0] + dx)} {fmt(c2[1] + MID_Y)} "
                f"{fmt(end[0] + dx)} {fmt(end[1] + MID_Y)}")
        out.append("Z")
    return "".join(out)


# --- The glyphs. Sizes are Device Hub's, measured at 2x in its toolbar and converted to template
# units: one 2x pixel at a 15 pt symbol is 0.5 / 15 * 100 = 3.33 units.

def home(m):
    """Nine rounded app-icon squares, three by three. Heavier weights grow the tiles, not the grid."""
    s = SCALE
    pitch = 30.0 * s
    tile = (22.0 + (m - 1) * 6.0) * s
    radius = tile * 0.27
    path = Path()
    for row in (-1, 0, 1):
        for col in (-1, 0, 1):
            path.add(rounded_rect(col * pitch, row * pitch, tile / 2, tile / 2, radius))
    return path


def rotate(m):
    """A device outline with two arrows turning counter-clockwise: one off its top-right corner
    pointing left, one off its bottom-left corner pointing right."""
    s = SCALE
    w = 9.3 * m * s
    half = 38.0 * s
    outer_r = 10.0 * s
    path = Path()
    path.add(rounded_rect(0, 0, half, half, outer_r))
    path.add(rounded_rect(0, 0, half - w, half - w, max(0.5, outer_r - w), clockwise=False))
    arc_c = 31.7 * s
    arc_r = 26.7 * s
    head_len = (21.0 + (m - 1) * 3.0) * s
    head_half = (14.5 + (m - 1) * 3.5) * s
    corner = 2.5 * s
    for sign in (1, -1):
        c = (sign * arc_c, -sign * arc_c)
        if sign == 1:
            a0, a1 = 0.0, -math.pi / 2          # right side up to the top, counter-clockwise
        else:
            a0, a1 = math.pi, math.pi / 2       # left side down to the bottom, counter-clockwise
        path.add(clockwise(stroked_arc(c, arc_r, w, a0, a1)))
        end = point_at(c, arc_r, a1)
        # The head points along the arc's travel at its end: left at the top, right at the bottom.
        base_x = end[0] + sign * (head_len * 0.3)
        tip = (base_x - sign * head_len, end[1])
        pts = [tip, (base_x, end[1] - head_half), (base_x, end[1] + head_half)]
        path.add(clockwise(rounded_polygon(pts if signed_area((pts[0], [line(pts[0], pts[1]), line(pts[1], pts[2]), line(pts[2], pts[0])])) > 0 else [pts[0], pts[2], pts[1]], corner)))
    return path


GLYPHS = {"pane.home": (home, "Pane Home: nine app-icon squares"), "pane.rotate.left": (rotate, "Pane Rotate Left")}


def template(name, make, description):
    guides, symbols = [], []
    for weight, (left, m) in WEIGHTS.items():
        path = make(m)
        x0, _, x1, _ = bounds(path)
        dx = SIDE_BEARING - x0
        right = left + (x1 - x0) + 2 * SIDE_BEARING
        guides.append(
            f'  <line id="left-margin-{weight}-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" '
            f'x1="{fmt(left)}" x2="{fmt(left)}" y1="600.785" y2="720.121"/>')
        guides.append(
            f'  <line id="right-margin-{weight}-S" style="fill:none;stroke:#00AEEF;stroke-width:0.5;opacity:1.0;" '
            f'x1="{fmt(right)}" x2="{fmt(right)}" y1="600.785" y2="720.121"/>')
        symbols.append(
            f'  <g id="{weight}-S" transform="matrix(1 0 0 1 {fmt(left)} {fmt(BASELINE)})">\n'
            f'   <path d="{to_d(path, dx)}"/>\n  </g>')
    lines_ = []
    for scale, base in (("S", 696), ("M", 1126), ("L", 1556)):
        lines_.append(
            f'  <line id="Baseline-{scale}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" '
            f'x1="263" x2="3036" y1="{base}" y2="{base}"/>')
        lines_.append(
            f'  <line id="Capline-{scale}" style="fill:none;stroke:#27AAE1;opacity:1;stroke-width:0.5;" '
            f'x1="263" x2="3036" y1="{fmt(base - CAP_HEIGHT)}" y2="{fmt(base - CAP_HEIGHT)}"/>')
    text = "stroke:none;fill:black;font-family:sans-serif;font-size:13;text-anchor:end;"
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<!-- Generated by scripts/make-symbols.py; edit the script, not this file. -->
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="3300" height="2200">
 <g id="Notes">
  <rect height="2200" id="artboard" style="fill:white;opacity:1" width="3300" x="0" y="0"/>
  <text id="template-version" style="{text}" transform="matrix(1 0 0 1 3036 1933)">Template v.4.0</text>
  <text style="{text}" transform="matrix(1 0 0 1 3036 1951)">Requires Xcode 14 or greater</text>
  <text id="descriptive-name" style="{text}" transform="matrix(1 0 0 1 3036 1969)">{description}</text>
  <text style="{text}" transform="matrix(1 0 0 1 3036 1987)">Typeset at 100 points</text>
 </g>
 <g id="Guides">
{chr(10).join(lines_)}
{chr(10).join(guides)}
 </g>
 <g id="Symbols">
{chr(10).join(symbols)}
 </g>
</svg>
"""


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)
        f.write("\n")
    for name, (make, description) in GLYPHS.items():
        folder = os.path.join(OUT, f"{name}.symbolset")
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, f"{name}.svg"), "w") as f:
            f.write(template(name, make, description))
        with open(os.path.join(folder, "Contents.json"), "w") as f:
            json.dump({"info": {"author": "xcode", "version": 1},
                       "symbols": [{"filename": f"{name}.svg", "idiom": "universal"}]}, f, indent=2)
            f.write("\n")
        print(f"wrote {folder}")


if __name__ == "__main__":
    main()
