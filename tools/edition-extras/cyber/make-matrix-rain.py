#!/usr/bin/env python3
"""Render the cyber edition's live wallpaper: acid-green matrix rain on a phosphor CRT.

Usage: uv run --with numpy --with pillow python3 make-matrix-rain.py OUT.mp4 [STILL.png]

Seamless 8 s loop, 2560x1072 at 30 fps (240 frames). Every motion term is periodic in the
frame index N: each column's head travels a whole number of wraps per loop, and the glyph
flicker is keyed on (frame // 12) % 20. Frame 240 therefore equals frame 0.
"""
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS, N = 2560, 1072, 30, 240
CW, CH = 16, 16                      # one glyph cell
COLS, ROWS = W // CW, H // CH        # 160 x 67
TAIL_PAD = 30                        # rows of off-screen travel so trails wrap out of view
P = ROWS + TAIL_PAD                  # wrap period, in rows
BG = np.array([12, 13, 11], float)   # #0c0d0b, the Afterburn background
GREEN = np.array([84, 245, 69], float)    # #54f545, the cyber accent
HEAD = np.array([223, 255, 216], float)   # near-white phosphor head
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
GLYPHS = list("0123456789ABCDEF<>|/:=+*-.")
NB = 20                              # glyph-flicker blocks per loop (12 frames each)

out_path = sys.argv[1]
still_path = sys.argv[2] if len(sys.argv) > 2 else None

# Glyph atlas: one 16x16 coverage mask per character.
font = ImageFont.truetype(FONT, 14)
atlas = np.zeros((len(GLYPHS), CH, CW), float)
for i, ch in enumerate(GLYPHS):
    im = Image.new("L", (CW, CH), 0)
    ImageDraw.Draw(im).text((CW / 2, CH / 2), ch, font=font, fill=255, anchor="mm")
    atlas[i] = np.asarray(im, float) / 255.0

rng = np.random.default_rng(20261107)
phase = rng.uniform(0, P, COLS)
cycles = rng.choice([1, 1, 2], COLS).astype(float)   # whole wraps per loop
trail = rng.integers(10, 30, COLS).astype(float)     # tail length in rows
active = rng.random(COLS) < 0.78                     # some columns stay dark
base_idx = rng.integers(0, len(GLYPHS), (ROWS, COLS))
rand_idx = rng.integers(0, len(GLYPHS), (NB, ROWS, COLS))
change = rng.random((NB, ROWS, COLS)) < 0.12

ys = np.arange(ROWS, dtype=float)[:, None]

# Scanlines (every third row) and a gentle CRT vignette, both static.
yy, xx = np.mgrid[0:H, 0:W].astype(float)
vig = 1.0 - 0.30 * ((xx - W / 2) / (W / 2)) ** 2 - 0.30 * ((yy - H / 2) / (H / 2)) ** 2
scan = np.where(np.arange(H) % 3 == 2, 0.80, 1.0)[:, None]
static = (vig * scan)[..., None]

proc = subprocess.Popen(
    ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
     "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
     "-c:v", "libx264", "-preset", "slow", "-crf", "24", "-profile:v", "high",
     "-pix_fmt", "yuv420p", "-movflags", "+faststart", out_path],
    stdin=subprocess.PIPE,
)

for f in range(N):
    heads = (phase + f * cycles * P / N) % P
    d = (heads[None, :] - ys) % P                        # rows behind each head
    inside = (d < trail[None, :]) & active[None, :]
    fade = np.clip(1.0 - d / trail[None, :], 0.0, 1.0)
    b = np.where(inside, fade ** 2.2, 0.0)
    head = (inside & (d < 1.0)).astype(float)
    dim = np.where(active[None, :], 0.05, 0.035)         # dormant glyph field
    inten = np.maximum(b, dim)

    blk = (f // 12) % NB
    idx = np.where(change[blk], rand_idx[blk], base_idx)
    masks = atlas[idx]                                   # (ROWS, COLS, CH, CW)
    ink = masks * inten[..., None, None]
    hd = masks * head[..., None, None]

    def to_img(a):
        return a.transpose(0, 2, 1, 3).reshape(H, W)

    ink_i, hd_i = to_img(ink), to_img(hd)
    rgb = (BG[None, None, :]
           + ink_i[..., None] * GREEN
           + hd_i[..., None] * (HEAD - GREEN))
    # Phosphor bloom: a soft halo of the bright parts.
    lum = np.clip(rgb, 0, 255).astype(np.uint8)
    bloom = np.asarray(Image.fromarray(lum).filter(ImageFilter.GaussianBlur(6)), float)
    rgb = rgb + 0.55 * bloom
    flicker = 1.0 + 0.025 * np.sin(2 * np.pi * f * 2 / N)  # two slow breaths per loop
    rgb = rgb * static * flicker
    frame = np.clip(rgb, 0, 255).astype(np.uint8)
    proc.stdin.write(frame.tobytes())
    if still_path and f == 60:
        Image.fromarray(frame).save(still_path)

proc.stdin.close()
if proc.wait() != 0:
    sys.exit("ffmpeg failed")
print("wrote", out_path)
