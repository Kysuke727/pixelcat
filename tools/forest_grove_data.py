"""Single source of truth for the forest grove map (level design numbers).

Used by:
  tools/draw_map_layout.py   - the layout sketch (docs/maps/forest-grove-layout.png)
  tools/make_forest_tiles.py - tile atlas, prop art and the tile grid
  tools/build_forest_grove.gd (via tools/data/forest_grove_level.json) - the scene

World size: 2304 x 1280 = 72 x 40 tiles of 32 px (2 x ~2 screens of 1152 x 648).
"""
import math

W, H = 2304, 1280
TILE = 32
COLS, ROWS = W // TILE, H // TILE

START = (170, 1120)
PATH = [START, (480, 1135), (760, 1040), (880, 820), (800, 640), (1010, 520), (1250, 470),
        (1560, 560), (1760, 480), (1960, 430), (2200, 420)]
PATH_WIDTH = 130
ZONES = {   # name: (cx, cy, rx, ry)
    "入口林间空地": (430, 1085, 330, 190),
    "中央空地": (1270, 620, 450, 270),
    "出口林地": (1960, 430, 280, 200),
}
# The trail starts INSIDE the entrance glade so the two connect (the generator checks this).
SECRET_TRAIL = [(500, 970), (520, 900), (380, 720), (330, 520), (360, 330)]
TRAIL_WIDTH = 80
SECRET = (360, 260)
SECRET_RADIUS = 96
SAFE = [("安全点 1", (260, 1040)), ("安全点 2", (990, 790))]
# 9 slimes: entrance 2, secret-trail guard 1, central clearing 4, exit grove 2
ENEMIES = [(560, 1020), (650, 1160),            # 1, 2  entrance glade
           (340, 500),                           # 3     guard on the secret trail
           (1110, 560), (1380, 520), (1260, 780), (1180, 700),   # 4-7 central clearing
           (1900, 480), (2030, 380)]             # 8, 9  exit grove
# Enemies that do NOT count toward opening the exit (1-based index into ENEMIES): the
# secret-trail guard, so the secret really is optional.
OPTIONAL_ENEMIES = [3]
EXIT = (2200, 420)
POND = (1450, 740, 140, 80)
LAMPS = [(1960, 560), (1760, 330), (880, 960)]
PAWPRINTS = [(470, 905), (500, 860), (445, 815), (410, 770)]   # faint hint towards the trail
TRAIL_MOUTH = (520, 900)


def dist_to_segment(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def near_polyline(p, pts, r):
    return any(dist_to_segment(p, pts[i], pts[i + 1]) < r for i in range(len(pts) - 1))


def in_ellipse(p, e, margin=0):
    cx, cy, rx, ry = e
    return ((p[0] - cx) / (rx + margin)) ** 2 + ((p[1] - cy) / (ry + margin)) ** 2 <= 1
