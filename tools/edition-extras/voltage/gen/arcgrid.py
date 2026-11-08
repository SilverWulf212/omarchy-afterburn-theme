#!/usr/bin/env python3
"""Voltage live wallpaper: an arc grid. Power lines on pylons, energy pulses running along the
wires, and lightning arcs jumping between phase conductors with a crackle.

Renders NF = 8 s x 30 fps frames at 2560x1072 and pipes them to ffmpeg (H.264, yuv420p).
Seamless: every moving thing is periodic in LOOP seconds. Pulses move an integer number of
wire lengths per loop, and arcs use a wrapped time delta, so frame 239 flows into frame 0.

Run (numpy, Pillow and scipy come from uv, nothing is installed globally):
  uv run --quiet --with numpy --with pillow --with scipy python tools/edition-extras/voltage/gen/arcgrid.py OUT.mp4 [--png FRAME,FRAME]
"""
import math
import random
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import gaussian_filter

W, H, FPS, LOOP = 2560, 1072, 30, 8.0
NF = int(FPS * LOOP)

BG = np.array([0x0C, 0x0D, 0x0B], np.float32) / 255      # voltage background
CYAN = np.array([0x45, 0xE6, 0xF5], np.float32) / 255    # voltage accent
HOT = np.array([0xF2, 0xFF, 0xFF], np.float32) / 255     # white-hot core of pulses and arcs

TOP, BASE = 170, 1060   # pylon top and base (y), base is cut off by the bottom edge


def hw(y):
    """Half-width of the pylon body at height y."""
    return 10 + (y - TOP) * (78 - 10) / (BASE - TOP)


# Pylons at x = 320 + 640 j. The two off-screen ones feed wires into the frame from both edges.
TOWER_XS = [-320, 320, 960, 1600, 2240, 2880]
ARM_Y = [262, 344, 426]      # three phase conductors
ARM_HW = [40, 56, 72]
GND_Y, GND_HW = 196, 14      # earth wire on the peak

rng = random.Random(45)


def make_wires():
    """Each wire: span i, row r (0-2 phases, 3 earth). Sampled once per pixel of x."""
    wires = []
    for i in range(len(TOWER_XS) - 1):
        xa, xb = TOWER_XS[i], TOWER_XS[i + 1]
        rows = [(y, h, 36) for y, h in zip(ARM_Y, ARM_HW)] + [(GND_Y, GND_HW, 22)]
        for r, (y, h, sag) in enumerate(rows):
            xl, xr = xa + h, xb - h
            n = int(xr - xl) + 1
            s = np.linspace(0.0, 1.0, n)
            xs = xl + (xr - xl) * s
            ys = y + sag * 4 * s * (1 - s)
            wires.append(dict(span=i, row=r, xl=xl, xr=xr, xs=xs, ys=ys,
                              speed=rng.choice([-4, -3, -2, 2, 3, 4]),
                              offset=rng.random()))
    return wires


WIRES = make_wires()


def wire_point(span, row, s):
    """Point on a wire at fraction s of its span (for placing arcs)."""
    w = next(w for w in WIRES if w["span"] == span and w["row"] == row)
    k = int(round(s * (len(w["xs"]) - 1)))
    return float(w["xs"][k]), float(w["ys"][k])


def static_layers():
    """Pylons and wires as static masks: towers 0-255 (L), wires union (L), and a label per pixel."""
    towers = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(towers)
    for x in TOWER_XS:
        if x < -60 or x > W + 60:
            continue
        # Legs.
        d.line([(x - hw(BASE), BASE), (x - hw(TOP), TOP)], fill=255, width=2)
        d.line([(x + hw(BASE), BASE), (x + hw(TOP), TOP)], fill=255, width=2)
        # Lattice: struts every 74 px and a diagonal between each pair.
        levels = list(range(TOP + 74, BASE, 74))
        for y in levels:
            d.line([(x - hw(y), y), (x + hw(y), y)], fill=255, width=2)
        ys_all = [TOP] + levels + [BASE]
        for a, b in zip(ys_all, ys_all[1:]):
            d.line([(x - hw(a), a), (x + hw(b), b)], fill=255, width=2)
            d.line([(x + hw(a), a), (x - hw(b), b)], fill=255, width=2)
        # Cross arms and the earth peak.
        for y, h in zip(ARM_Y, ARM_HW):
            d.line([(x - h, y), (x + h, y)], fill=255, width=2)
        d.line([(x, TOP), (x, GND_Y)], fill=255, width=2)
    towers = np.asarray(towers, np.float32) / 255

    union = Image.new("L", (W, H), 0)
    label = np.full((H, W), -1, np.int32)
    for k, w in enumerate(WIRES):
        c = Image.new("L", (W, H), 0)
        ImageDraw.Draw(c).line(list(zip(w["xs"], w["ys"])), fill=255, width=2)
        m = np.asarray(c) > 0
        label[m] = k
        union.paste(c, (0, 0), c)
    wires = np.asarray(union, np.float32) / 255
    return towers, wires, label


def bolt(a, b, depth, amp):
    pts = [a, b]
    for _ in range(depth):
        new = []
        for p, q in zip(pts, pts[1:]):
            m = ((p[0] + q[0]) / 2 + rng.gauss(0, amp), (p[1] + q[1]) / 2 + rng.gauss(0, amp))
            new += [p, m]
        new.append(pts[-1])
        pts = new
        amp *= 0.55
    return pts


# Arcs: (time of strike in the loop, span, row of the upper conductor, s on the span)
ARC_SPECS = [
    (0.45, 2, 0, 0.46),
    (1.90, 1, 1, 0.52),
    (2.65, 3, 2, 0.41),
    (4.20, 0, 2, 0.58),
    (5.15, 1, 2, 0.50),
    (6.70, 3, 0, 0.55),
]


def make_arc(t0, span, row, s):
    ax, ay = wire_point(span, row, s)
    bx, by = wire_point(span, row + 1, s + rng.uniform(-0.03, 0.03))
    main = bolt((ax, ay), (bx, by), 5, 16)
    branch = []
    if len(main) > 12:
        j = rng.randrange(8, len(main) - 8)
        ang = rng.uniform(-1.1, 1.1) + (math.pi / 2 if rng.random() < 0.5 else -math.pi / 2)
        ln = rng.uniform(60, 120)
        end = (main[j][0] + ln * math.cos(ang), main[j][1] + ln * math.sin(ang))
        branch = bolt(main[j], end, 3, 7)
    pts = main + branch
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    pad = 40
    x0, y0 = max(0, int(min(xs)) - pad), max(0, int(min(ys)) - pad)
    x1, y1 = min(W, int(max(xs)) + pad), min(H, int(max(ys)) + pad)
    core = Image.new("L", (x1 - x0, y1 - y0), 0)
    d = ImageDraw.Draw(core)
    shift = lambda p: (p[0] - x0, p[1] - y0)
    d.line([shift(p) for p in main], fill=255, width=2)
    if branch:
        d.line([shift(p) for p in branch], fill=255, width=1)
    # Crackle: a handful of sparks thrown off the bolt.
    for _ in range(14):
        p = rng.choice(main)
        sx, sy = shift((p[0] + rng.gauss(0, 10), p[1] + rng.gauss(0, 10)))
        r = rng.uniform(1.0, 2.2)
        d.ellipse([sx - r, sy - r, sx + r, sy + r], fill=255)
    core = np.asarray(core, np.float32) / 255
    glow = gaussian_filter(core, 9) * 2.4
    return dict(t0=t0, x0=x0, y0=y0, x1=x1, y1=y1, core=core, glow=glow, seed=len(core))


def arc_env(dt):
    """Strike envelope: a fast rise (the arc forms) and a slower fall (it dies out)."""
    if dt > 0.5:
        return 0.0
    return (1 - math.exp(-dt / 0.012)) * math.exp(-dt / 0.11)


def main():
    out_path = sys.argv[1]
    png_frames = set()
    if "--png" in sys.argv:
        png_frames = {int(v) for v in sys.argv[sys.argv.index("--png") + 1].split(",")}

    towers, wires, label = static_layers()
    static_core = 0.15 * towers + 0.24 * wires
    static_glow = gaussian_filter(static_core, 6) * 1.1
    static_rgb = static_core[..., None] * CYAN * 0.9 + static_glow[..., None] * CYAN * 0.45

    ys_w, xs_w = np.nonzero(label >= 0)
    lab = label[ys_w, xs_w]
    xl = np.array([w["xl"] for w in WIRES], np.float32)
    xr = np.array([w["xr"] for w in WIRES], np.float32)
    u = (xs_w - xl[lab]) / (xr[lab] - xl[lab])
    speeds = np.array([w["speed"] for w in WIRES], np.float32)
    offs = np.array([w["offset"] for w in WIRES], np.float32)

    arcs = [make_arc(*spec) for spec in ARC_SPECS]

    ff = subprocess.Popen(
        ["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}",
         "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "21",
         "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path],
        stdin=subprocess.PIPE)

    for f in range(NF):
        t = f / FPS
        out = np.broadcast_to(BG, (H, W, 3)).copy()
        out += static_rgb

        # Energy pulses: each wire carries one bright packet that circles its span. speed is an
        # integer, so the packet is back where it started at the loop point.
        pos = (offs + speeds * t / LOOP) % 1.0
        d = u - pos[lab]
        circ = np.abs(d - np.round(d))
        v = np.exp(-(circ / 0.025) ** 2).astype(np.float32)
        plane = np.zeros((H, W), np.float32)
        plane[ys_w, xs_w] = v
        out += plane[..., None] * HOT * 0.85
        out += gaussian_filter(plane, 7)[..., None] * CYAN * 1.0

        # Arcs and crackle. The arc light also lifts the whole grid a little.
        ambient = 0.0
        for k, a in enumerate(arcs):
            dt = (t - a["t0"]) % LOOP
            env = arc_env(dt)
            if env <= 0:
                continue
            crk = 0.55 + 0.45 * random.Random(f * 31 + k).random()
            e = env * crk
            ambient += e * 0.05
            region = out[a["y0"]:a["y1"], a["x0"]:a["x1"]]
            region += a["core"][..., None] * HOT * e * 1.6 + a["glow"][..., None] * CYAN * e * 1.0
        out += ambient * CYAN

        frame = np.clip(out * 255.0, 0, 255).astype(np.uint8)
        if f in png_frames:
            Image.fromarray(frame).save(out_path + f".{f:03d}.png")
        ff.stdin.write(frame.tobytes())

    ff.stdin.close()
    if ff.wait() != 0:
        sys.exit("ffmpeg failed")


if __name__ == "__main__":
    main()
