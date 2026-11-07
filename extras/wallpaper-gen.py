import sys, random, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops

OUT = sys.argv[1]
W, H = 3440, 1440
BG = (12, 13, 11)
OR = (245, 145, 69)
EMBER = (255, 90, 31)
PALE = (255, 184, 120)
FONT = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf"
FONTB = "/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Bold.ttf"
import glob
for f in glob.glob("/usr/share/fonts/**/JetBrainsMonoNerdFont-Regular.ttf", recursive=True): FONT = f
for f in glob.glob("/usr/share/fonts/**/JetBrainsMonoNerdFont-Bold.ttf", recursive=True): FONTB = f


def glow(layer, radii=(2, 8, 30), gains=(1.0, 0.8, 0.6)):
    out = np.zeros((H, W, 3), np.float32)
    base = np.asarray(layer, np.float32)
    out += base
    for r, g in zip(radii, gains):
        out += np.asarray(layer.filter(ImageFilter.GaussianBlur(r)), np.float32) * g
    return out


def finish(arr, seed, name):
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # vignette
    d = np.sqrt(((xx - W / 2) / (W * 0.62)) ** 2 + ((yy - H / 2) / (H * 0.75)) ** 2)
    vig = np.clip(1.15 - d * 0.75, 0.35, 1.0)[..., None]
    arr = np.asarray(BG, np.float32) + arr
    arr = arr * vig
    # scanlines + grain
    arr *= (0.94 + 0.06 * (np.sin(yy * math.pi / 2) ** 2))[..., None]
    arr += rng.normal(0, 3.2, (H, W, 1))
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(f"{OUT}/{name}", quality=94)


def tint(img_l, color):
    a = np.asarray(img_l, np.float32)[..., None] / 255.0
    return Image.fromarray((a * np.array(color, np.float32)).astype(np.uint8))


def horizon():
    hz = int(H * 0.58)
    lines = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(lines)
    cx = W / 2
    for i in range(-40, 41):
        x_far = cx + i * 38
        x_near = cx + i * 520
        d.line([(x_far, hz), (x_near, H + 200)], fill=95, width=2)
    z = 1.0
    while True:
        y = hz + (H - hz) * (0.06 / z)
        if y > H: break
        y = hz + 18 * (1.32 ** (z * 3)) - 18
        if y > H: break
        d.line([(0, y), (W, y)], fill=int(min(140, 50 + z * 9)), width=2)
        z += 0.35
    # fade grid toward horizon
    g = np.asarray(lines, np.float32)
    yy = np.arange(H, dtype=np.float32)[:, None]
    fade = np.clip((yy - hz) / (H - hz), 0, 1) ** 0.6
    g = (g * fade)
    grid = tint(Image.fromarray(g.astype(np.uint8)), OR)
    arr = glow(grid, (2, 10), (0.7, 0.5)) * 0.85
    # sun: disc with slit cuts
    sun = Image.new("L", (W, H), 0)
    sd = ImageDraw.Draw(sun)
    r = 330
    sd.ellipse([cx - r, hz - r * 1.05, cx + r, hz + r * 0.95], fill=255)
    for k in range(9):
        yk = hz - r * 0.62 + k * 38
        sd.rectangle([0, yk, W, yk + 3 + k * 2.6], fill=0)
    sd.rectangle([0, hz, W, H], fill=0)
    s = np.asarray(sun, np.float32) / 255.0
    grad = np.clip((np.arange(H)[:, None] - (hz - r)) / (r * 1.2), 0, 1)
    col = (np.array(PALE) * (1 - grad[..., None]) + np.array(EMBER) * grad[..., None])
    sunrgb = Image.fromarray((s[..., None] * col * 0.55).astype(np.uint8))
    arr += glow(sunrgb, (6, 40, 160), (0.35, 0.4, 0.7))
    # horizon line
    hl = Image.new("L", (W, H), 0)
    ImageDraw.Draw(hl).line([(0, hz), (W, hz)], fill=255, width=3)
    arr += glow(tint(hl, OR), (3, 20, 90), (0.9, 0.7, 0.6)) * 0.9
    # dust
    rng = random.Random(7)
    st = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(st)
    for _ in range(420):
        x, y = rng.uniform(0, W), rng.uniform(0, hz - 40)
        dd.point((x, y), fill=rng.randint(40, 170))
    arr += glow(tint(st, PALE), (1,), (0.8,))
    finish(arr, 1, "1-horizon.jpg")


def prompt():
    # dot grid
    dots = Image.new("L", (W, H), 0)
    dd = ImageDraw.Draw(dots)
    for x in range(40, W, 48):
        for y in range(40, H, 48):
            dd.point((x, y), fill=70)
    arr = np.asarray(tint(dots, OR), np.float32) * 0.6
    txt = Image.new("RGB", (W, H), 0)
    td = ImageDraw.Draw(txt)
    big = ImageFont.truetype(FONTB, 230)
    x0, y0 = int(W * 0.14), int(H * 0.38)
    td.text((x0, y0), "❯ afterburn", font=big, fill=OR)
    tw = td.textlength("❯ afterburn ", font=big)
    td.rectangle([x0 + tw, y0 + 40, x0 + tw + 120, y0 + 250], fill=(235, 125, 55))
    small = ImageFont.truetype(FONT, 30)
    td.text((x0 + 8, y0 + 300), "cyber  //  0xF59145  //  jetbrains mono", font=small, fill=(164, 150, 130))
    arr += glow(txt, (3, 18, 90), (0.6, 0.5, 0.55))
    # HUD corner brackets + labels
    hud = Image.new("RGB", (W, H), 0)
    hd = ImageDraw.Draw(hud)
    m, L = 70, 90
    for (cx, cy, sx, sy) in [(m, m, 1, 1), (W - m, m, -1, 1), (m, H - m, 1, -1), (W - m, H - m, -1, -1)]:
        hd.line([(cx, cy), (cx + sx * L, cy)], fill=OR, width=3)
        hd.line([(cx, cy), (cx, cy + sy * L)], fill=OR, width=3)
    lab = ImageFont.truetype(FONT, 22)
    hd.text((m + 20, m + 20), "SYS://AFTERBURN", font=lab, fill=(150, 110, 70))
    hd.text((W - m - 330, H - m - 46), "SESSION 01  ●  ONLINE", font=lab, fill=(150, 110, 70))
    # side tick ruler
    for i in range(0, 40):
        y = int(H * 0.25) + i * 18
        hd.line([(W - m - (24 if i % 5 == 0 else 10), y), (W - m, y)], fill=(120, 80, 45), width=2)
    arr += glow(hud, (2, 10), (0.5, 0.3))
    # soft ember haze bottom-right
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    haze = np.exp(-(((xx - W * 0.85) / (W * 0.35)) ** 2 + ((yy - H * 1.05) / (H * 0.5)) ** 2))
    arr += haze[..., None] * np.array(EMBER, np.float32) * 0.22
    finish(arr, 2, "2-prompt.jpg")


def circuit():
    rng = random.Random(42)
    lay = Image.new("L", (W, H), 0)
    nodes = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(lay); n = ImageDraw.Draw(nodes)
    step = 24
    for _ in range(260):
        x = rng.randrange(0, W // step) * step
        y = rng.randrange(0, H // step) * step
        bright = rng.randint(40, 200) if rng.random() < 0.2 else rng.randint(25, 80)
        pts = [(x, y)]
        dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        dx, dy = rng.choice(dirs)
        for _ in range(rng.randint(3, 9)):
            ln = rng.randint(3, 22) * step
            x += dx * ln; y += dy * ln
            pts.append((x, y))
            if rng.random() < 0.6:
                # 45-degree jog
                j = rng.randint(1, 4) * step
                ax, ay = (dy, dx) if rng.random() < 0.5 else (-dy, -dx)
                x += dx * j + ax * j; y += dy * j + ay * j
                pts.append((x, y))
            dx, dy = rng.choice([(dy, dx), (-dy, -dx), (dx, dy)])
        d.line(pts, fill=bright, width=2, joint="curve")
        for (px, py) in (pts[0], pts[-1]):
            r = 5
            n.ellipse([px - r, py - r, px + r, py + r], outline=min(255, bright + 60), width=2)
    arr = glow(tint(lay, OR), (2, 12), (0.6, 0.4)) * 0.8
    arr += glow(tint(nodes, PALE), (2, 10), (0.8, 0.5))
    # central breathing core
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    core = np.exp(-(((xx - W * 0.5) / (W * 0.22)) ** 2 + ((yy - H * 0.5) / (H * 0.35)) ** 2))
    arr *= (0.35 + 0.9 * core)[..., None]
    arr += core[..., None] * np.array(EMBER, np.float32) * 0.10
    finish(arr, 3, "3-circuit.jpg")


horizon(); prompt(); circuit()
print("done")
