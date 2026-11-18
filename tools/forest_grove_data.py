"""Single source of truth for the forest grove map (level design numbers).

Used by:
  tools/draw_map_layout.py   - the layout sketch (docs/maps/forest-grove-layout.png)
  tools/make_forest_tiles.py - tile atlas, prop art, tile grid + checks, tools/data/forest_grove_level.json
  tools/build_forest_grove.gd (via the JSON) - the scene

World size: 4608 x 2560 = 144 x 80 tiles of 32 px (about 4 x 4 screens of 1152 x 648).
All coordinates are world pixels.
"""
import math

W, H = 4608, 2560
TILE = 32
COLS, ROWS = W // TILE, H // TILE

START = (230, 2250)
EXIT = (4430, 600)

# Main road, start -> exit.
PATH = [START, (700, 2240), (1000, 2100), (1350, 1900), (1650, 1700), (1900, 1450), (2200, 1320),
        (2500, 1150), (2900, 1200), (3200, 1400), (3500, 1600), (3750, 1350), (3900, 1000),
        (4050, 700), EXIT]
PATH_WIDTH = 130

ZONES = {   # name: (cx, cy, rx, ry)
    "入口林间空地": (520, 2150, 400, 230),
    "溪边空地": (1350, 1900, 430, 250),
    "倒树林地": (1900, 1450, 300, 210),
    "中央空地": (2500, 1150, 640, 360),
    "营地": (3500, 1600, 420, 270),
    "出口林地": (4050, 650, 420, 280),
    "蘑菇圈": (2350, 480, 300, 220),
    "小仓库": (3800, 2250, 320, 200),
    "旧长椅": (900, 1000, 330, 230),
}

# Side roads (each ends in one of the zones above).
BRANCHES = [
    {"name": "北路", "points": [(2450, 1050), (2420, 800), (2350, 560)], "width": 96},
    {"name": "东南路", "points": [(3500, 1650), (3600, 2000), (3760, 2200)], "width": 96},
    {"name": "西路", "points": [(1300, 1800), (1100, 1560), (950, 1260), (900, 1050)], "width": 96},
]

# Hidden trails: narrow, half hidden behind bushes at the mouth, lead to a chamber.
TRAILS = [
    {"name": "秘密小径", "points": [(560, 2100), (640, 2000), (500, 1700), (420, 1400), (380, 1000), (420, 650), (430, 430)],
     "width": 100, "mouth": (640, 2000)},
]
CHAMBERS = [{"center": (430, 380), "radius": 100}]
PONDS = [(1500, 2000, 140, 80), (2750, 1370, 160, 85)]   # (cx, cy, rx, ry), solid water

# Enemies. "type" is slime (default), charger or flyer. "optional" ones do not count toward opening the exit (guards of side spots).
ENEMIES = [
    {"pos": (640, 2110), "name": "Slime1"}, {"pos": (790, 2290), "name": "Slime2"},
    {"pos": (1030, 2090), "name": "Slime3"},
    {"pos": (1250, 1850), "name": "Slime4"}, {"pos": (1500, 1830), "name": "Slime5"},
    {"pos": (1860, 1440), "name": "Charger1", "type": "charger"}, {"pos": (2000, 1490), "name": "Slime7"},
    {"pos": (860, 1030), "name": "Slime8"}, {"pos": (1010, 970), "name": "Slime9"},
    {"pos": (2300, 1100), "name": "Slime10"}, {"pos": (2560, 1010), "name": "Flyer1", "type": "flyer"},
    {"pos": (2450, 1290), "name": "Slime12"}, {"pos": (2820, 1070), "name": "Charger2", "type": "charger"},
    {"pos": (2650, 1150), "name": "Slime14"},
    {"pos": (3380, 1560), "name": "Slime15"}, {"pos": (3600, 1700), "name": "Charger3", "type": "charger"},
    {"pos": (3560, 1480), "name": "Flyer2", "type": "flyer"},
    {"pos": (3980, 780), "name": "Flyer3", "type": "flyer"}, {"pos": (4200, 630), "name": "Charger4", "type": "charger"},
    {"pos": (420, 1400), "name": "SecretGuard", "optional": True},
    {"pos": (2330, 540), "name": "NookGuard", "optional": True},
    {"pos": (3790, 2240), "name": "StashGuard", "optional": True},
]

LAMPS = [(760, 2180), (1180, 1960), (1750, 1560), (2280, 1250), (2950, 1130), (3300, 1500),
         (3880, 900), (4200, 700), (2450, 900), (1000, 1300)]

# Faint paw prints that point towards the secret trail's mouth.
PAWPRINTS = [(590, 2070), (640, 2030), (610, 1960), (560, 1880), (520, 1800)]

# "Cat secrets": walking in teaches a move once.
SECRETS = [
    {"id": "old_tree_hollow", "pos": (430, 402), "move_id": "triple_combo"},
    {"id": "bench_hollow", "pos": (740, 920), "move_id": "shield_bash"},
]

# Hidden stashes. items = item_id -> quantity (the backpack must have room for ALL of it).
LOOT = [
    {"id": "mushroom_nook", "pos": (2350, 500), "items": {"yarn": 3, "stone": 2, "herb_pack": 1}, "fish": 0},
    {"id": "stash", "pos": (3800, 2270), "items": {"wood": 4, "stone": 3}, "fish": 3},
    {"id": "camp", "pos": (3440, 1650), "items": {"wood": 3, "yarn": 2, "herb_pack": 1}, "fish": 0},
    {"id": "bench", "pos": (930, 1080), "items": {"yarn": 2, "herb_pack": 1}, "fish": 2},
]

# Decoration / landmarks. type -> sprite assets/props/<type>.png. Signposts carry a short text.
LANDMARKS = [
    {"type": "fallen_log", "pos": (1900, 1480)},
    {"type": "stump", "pos": (1300, 2130)},
    {"type": "campfire", "pos": (3500, 1600)},
    {"type": "bench", "pos": (880, 1060)},
    {"type": "mushroom", "pos": (2270, 450)}, {"type": "mushroom", "pos": (2330, 440)},
    {"type": "mushroom", "pos": (2390, 470)}, {"type": "mushroom", "pos": (2380, 525)},
    {"type": "mushroom", "pos": (2310, 540)},
    {"type": "signpost", "pos": (1340, 1800), "text": "西 · 旧长椅"},
    {"type": "signpost", "pos": (2470, 1010), "text": "北 · 蘑菇圈"},
    {"type": "signpost", "pos": (3470, 1720), "text": "东南 · 小仓库"},
]

# Fireflies drift over every clearing and chamber (x, y, w, h).
FIREFLY_AREAS = (
    [(cx - rx * 0.8, cy - ry * 0.8, rx * 1.6, ry * 1.6) for (cx, cy, rx, ry) in ZONES.values()]
    + [(c["center"][0] - c["radius"], c["center"][1] - c["radius"], c["radius"] * 2, c["radius"] * 2) for c in CHAMBERS]
)


def dist_to_segment(p, a, b):
    ax, ay = a; bx, by = b; px, py = p
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def near_polyline(p, pts, r):
    return any(dist_to_segment(p, pts[i], pts[i + 1]) < r for i in range(len(pts) - 1))


def dist_to_polyline(p, pts):
    return min(dist_to_segment(p, pts[i], pts[i + 1]) for i in range(len(pts) - 1))


def in_ellipse(p, e, margin=0):
    cx, cy, rx, ry = e
    return ((p[0] - cx) / (rx + margin)) ** 2 + ((p[1] - cy) / (ry + margin)) ** 2 <= 1
