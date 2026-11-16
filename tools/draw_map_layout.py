#!/usr/bin/env python3
"""Draws the top-down layout sketch of the forest grove map (docs/maps/forest-grove-layout.png).

    python3 tools/draw_map_layout.py

The numbers here are the single source of truth for the level design; the map scene
is built from the same coordinates. World size 2304 x 1296 (2 x 2 screens).
"""
import math, random
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

W, H = 2304, 1296
S = 0.72                          # drawing scale
FONT = Path(__file__).resolve().parent.parent / "assets" / "fonts" / "SmileySans-Oblique.otf"

# ---- level data (world coordinates) -----------------------------------------
START = (170, 1120)
PATH = [START, (480, 1135), (760, 1040), (880, 820), (800, 640), (1010, 520), (1250, 470),
        (1560, 560), (1760, 480), (1960, 430), (2200, 420)]
ZONES = {   # name: (cx, cy, rx, ry)
    "入口林间空地": (430, 1085, 330, 190),
    "中央空地": (1270, 620, 450, 270),
    "出口林地": (1960, 430, 280, 200),
}
SECRET_TRAIL = [(520, 900), (380, 720), (330, 520), (360, 330)]
SECRET = (360, 260)
SAFE = [("安全点 1", (260, 1040)), ("安全点 2", (990, 790))]
ENEMIES = [(560, 1020), (650, 1160), (1110, 560), (1380, 520), (1260, 780), (400, 480)]
EXIT = (2200, 420)
POND = (1450, 740, 140, 80)
LAMPS = [(1960, 560), (1760, 330), (880, 960)]

def sc(p): return (p[0] * S, p[1] * S)

def dist_to_segment(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))

def near_path(p, pts, r):
    return any(dist_to_segment(p, pts[i], pts[i + 1]) < r for i in range(len(pts) - 1))

def in_ellipse(p, e, margin=0):
    cx, cy, rx, ry = e
    return ((p[0] - cx) / (rx + margin)) ** 2 + ((p[1] - cy) / (ry + margin)) ** 2 <= 1

img = Image.new("RGB", (int(W * S), int(H * S)), "#1d3b2f")
d = ImageDraw.Draw(img)
big = ImageFont.truetype(str(FONT), 30)
mid = ImageFont.truetype(str(FONT), 24)
small = ImageFont.truetype(str(FONT), 20)

# ground tint + zones
for name, e in ZONES.items():
    cx, cy, rx, ry = e
    d.ellipse([sc((cx - rx, cy - ry)), sc((cx + rx, cy + ry))], fill="#2f5d44")
# main path
for i in range(len(PATH) - 1):
    d.line([sc(PATH[i]), sc(PATH[i + 1])], fill="#a98a5a", width=int(130 * S))
for p in PATH:
    r = 65 * S; x, y = sc(p); d.ellipse([x - r, y - r, x + r, y + r], fill="#a98a5a")
# secret trail (dashed, narrower)
for i in range(len(SECRET_TRAIL) - 1):
    a, b = sc(SECRET_TRAIL[i]), sc(SECRET_TRAIL[i + 1])
    n = int(math.hypot(b[0] - a[0], b[1] - a[1]) / 14)
    for k in range(0, n, 2):
        t0, t1 = k / n, min((k + 1) / n, 1)
        d.line([(a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0), (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)], fill="#f2d98a", width=int(46 * S))
x, y = sc(SECRET); r = 90 * S
d.ellipse([x - r, y - r, x + r, y + r], fill="#3c6b56")
# pond
cx, cy, rx, ry = POND
d.ellipse([sc((cx - rx, cy - ry)), sc((cx + rx, cy + ry))], fill="#3f7fa8", outline="#9bd1ee", width=3)

# trees (deterministic): dense border + clusters, never on paths/zones/pond
random.seed(7)
trees = []
def ok(p):
    if near_path(p, PATH, 150) or near_path(p, SECRET_TRAIL, 85): return False
    if any(in_ellipse(p, e, 25) for e in ZONES.values()) or in_ellipse(p, POND, 40): return False
    if math.hypot(p[0] - SECRET[0], p[1] - SECRET[1]) < 120: return False
    if any(math.hypot(p[0] - l[0], p[1] - l[1]) < 40 for l in LAMPS): return False
    return True
for gx in range(0, W + 1, 70):
    for gy in range(0, H + 1, 70):
        p = (gx + random.randint(-22, 22), gy + random.randint(-22, 22))
        border = p[0] < 150 or p[1] < 130 or p[0] > W - 150 or p[1] > H - 130
        if (border or random.random() < 0.55) and ok(p):
            trees.append(p)
for p in trees:
    x, y = sc(p); r = random.randint(26, 40) * S
    d.ellipse([x - r, y - r, x + r, y + r], fill="#173d2a", outline="#0f2a1d")
    d.ellipse([x - r * 0.55, y - r * 0.6, x + r * 0.15, y], fill="#21553b")
for p in LAMPS:
    x, y = sc(p); d.ellipse([x - 8, y - 8, x + 8, y + 8], fill="#ffd84d", outline="#ffffff")

# screen grid (one screen = 1152 x 648)
for gx in (1152,):
    d.line([sc((gx, 0)), sc((gx, H))], fill="#ffffff", width=2)
d.line([sc((0, 648)), sc((W, 648))], fill="#ffffff", width=2)
d.text(sc((1170, 10)), "← 一屏 = 1152×648 →", font=small, fill="#ffffff")

# markers
def marker(p, text, fill, fg="#ffffff", r=22):
    x, y = sc(p); d.ellipse([x - r, y - r, x + r, y + r], fill=fill, outline="#ffffff", width=3)
    tw = d.textlength(text, font=mid); d.text((x - tw / 2, y - 14), text, font=mid, fill=fg)
for i, p in enumerate(ENEMIES, 1):
    marker(p, str(i), "#d8434f")
for name, p in SAFE:
    x, y = sc(p); r = 26
    d.polygon([(x, y - r), (x + r, y + r * 0.8), (x - r, y + r * 0.8)], fill="#5ec6ff", outline="#ffffff")
    d.text((x + 32, y - 14), name, font=small, fill="#bfe9ff")
x, y = sc(START); d.rectangle([x - 22, y - 22, x + 22, y + 22], fill="#7ad37a", outline="#ffffff", width=3)
d.text((x - 24, y + 28), "出发", font=mid, fill="#d8ffd8")
x, y = sc(SECRET)
star = []
for k in range(10):
    ang = -math.pi / 2 + k * math.pi / 5; rr = 30 if k % 2 == 0 else 13
    star.append((x + rr * math.cos(ang), y + rr * math.sin(ang)))
d.polygon(star, fill="#ffd84d", outline="#ffffff")
d.text((x + 38, y - 18), "猫猫的小秘密：老树洞", font=mid, fill="#ffe9a6")
d.text((x + 38, y + 10), "学会【三段连击】", font=small, fill="#ffe9a6")
x, y = sc(EXIT)
d.rectangle([x - 24, y - 34, x + 24, y + 34], fill="#e8c08a", outline="#ffffff", width=3)
d.text((x - 36, y + 40), "出口", font=mid, fill="#fff0d0")
d.text((x - 70, y - 70), "（清空敌人后开启）", font=small, fill="#fff0d0")

# zone labels
for name, (cx, cy, rx, ry) in ZONES.items():
    d.text(sc((cx - rx * 0.5, cy - ry * 0.95)), name, font=big, fill="#d4f5dc")
d.text(sc((1330, 840)), "小池塘（装饰，挡路）", font=small, fill="#cfeaff")
d.text(sc((560, 770)), "隐蔽小径入口\n（藏在灌木后面）", font=small, fill="#f2d98a")

# legend (bottom-right, over the unused corner of the map)
lx, ly = img.width - 330, img.height - 215
d.rectangle([lx, ly, lx + 310, ly + 195], fill="#10261c", outline="#7fbf9a", width=2)
d.text((lx + 14, ly + 8), "图例", font=mid, fill="#d4f5dc")
d.ellipse([lx + 16, ly + 46, lx + 40, ly + 70], fill="#d8434f", outline="#ffffff"); d.text((lx + 52, ly + 44), "敌人（史莱姆，按编号）", font=small, fill="#ffffff")
d.polygon([(lx + 28, ly + 80), (lx + 44, ly + 108), (lx + 12, ly + 108)], fill="#5ec6ff"); d.text((lx + 52, ly + 82), "安全点（复活）", font=small, fill="#ffffff")
d.ellipse([lx + 20, ly + 120, lx + 36, ly + 136], fill="#ffd84d", outline="#ffffff"); d.text((lx + 52, ly + 116), "路灯（装饰）", font=small, fill="#ffffff")
d.rectangle([lx + 14, ly + 152, lx + 44, ly + 162], fill="#f2d98a"); d.text((lx + 52, ly + 148), "隐蔽小径", font=small, fill="#ffffff")
d.text((lx + 170, ly + 150), "圆点密集处是树，\n走不进去", font=small, fill="#9fd4b0")
img.save(Path(__file__).resolve().parent.parent / "docs" / "maps" / "forest-grove-layout.png")
print("wrote docs/maps/forest-grove-layout.png", img.size, "trees:", len(trees))
