#!/usr/bin/env python3
"""Generates the forest grove's placeholder art and its tile grid.

    python3 tools/make_forest_tiles.py

Outputs
  assets/tilesets/forest_tiles.png   32x32 tiles in one row (see TILE_NAMES for the order)
  assets/props/*.png                 pawprint, tree_hollow, fallen_log, stump, campfire, bench,
                                     mushroom, signpost, loot_sack (small placeholder sprites)
  tools/data/forest_grove_level.json tile grid + object positions for tools/build_forest_grove.gd

The art is deliberately simple PLACEHOLDER pixel art. To use your own tiles: draw a
tileset with the same tile order (or repaint the map in the Godot TileMap editor) and
replace assets/tilesets/forest_tiles.png - the layout, collisions, enemies and secret
spots stay as they are.

The script also CHECKS the design: everything must stand on walkable ground and be
reachable from the start (breadth-first search over the tile grid).
"""
import json, math, random, sys
from collections import deque
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from PIL import Image
from forest_grove_data import *   # noqa: F401,F403

ROOT = Path(__file__).resolve().parent.parent

TILE_NAMES = ["grass_a", "grass_b", "dirt", "tree_a", "tree_b", "tree_c", "bush", "water",
              "flowers", "stones", "dirt_light"]
IDX = {n: i for i, n in enumerate(TILE_NAMES)}
SOLID = {"tree_a", "tree_b", "tree_c", "bush", "water"}
WALKABLE = {"grass_a", "grass_b", "dirt", "flowers", "stones", "dirt_light"}


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def speckle(img, base, colors, density, seed):
    rnd = random.Random(seed)
    for y in range(TILE):
        for x in range(TILE):
            img.putpixel((x, y), base)
    for _ in range(int(TILE * TILE * density)):
        x, y = rnd.randrange(TILE), rnd.randrange(TILE)
        img.putpixel((x, y), rnd.choice(colors))


def disc(img, cx, cy, r, fill, outline=None):
    for y in range(TILE):
        for x in range(TILE):
            dd = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if dd <= r:
                img.putpixel((x, y), fill)
            if outline and r - 1.2 < dd <= r:
                img.putpixel((x, y), outline)


def make_tile(name):
    t = Image.new("RGBA", (TILE, TILE))
    if name in ("grass_a", "grass_b"):
        speckle(t, hexc("#2f5d44"), [hexc("#356a4d"), hexc("#2a5340"), hexc("#3a7355")], 0.10 if name == "grass_a" else 0.16, 11 if name == "grass_a" else 12)
    elif name == "dirt":
        speckle(t, hexc("#a98a5a"), [hexc("#b89a68"), hexc("#9a7c4e"), hexc("#8f7248")], 0.12, 21)
    elif name == "dirt_light":
        speckle(t, hexc("#c9aa72"), [hexc("#d6ba84"), hexc("#b99c66")], 0.10, 22)
    elif name.startswith("tree"):
        seed = {"tree_a": 31, "tree_b": 32, "tree_c": 33}[name]
        rnd = random.Random(seed)
        speckle(t, hexc("#173d2a"), [hexc("#1c4631"), hexc("#12331f")], 0.12, seed)
        for k in range(3):
            cx, cy = 10 + rnd.randint(-1, 12), 10 + rnd.randint(-1, 12)
            disc(t, cx, cy, rnd.randint(7, 10), hexc("#21553b"), hexc("#0f2a1d"))
            disc(t, cx - 2, cy - 2.5, 3.2, hexc("#2e6f4b"))
    elif name == "bush":
        speckle(t, hexc("#2f5d44"), [hexc("#356a4d")], 0.10, 41)
        disc(t, 16, 17, 12.5, hexc("#2f7a4f"), hexc("#1d5236"))
        disc(t, 12, 12.5, 4.5, hexc("#3f9462"))
        rnd = random.Random(42)
        for _ in range(5):
            x, y = rnd.randint(8, 24), rnd.randint(9, 25)
            t.putpixel((x, y), hexc("#e0507a")); t.putpixel((x + 1, y), hexc("#e0507a"))
    elif name == "water":
        speckle(t, hexc("#3f7fa8"), [hexc("#4a8fb8"), hexc("#366f96")], 0.08, 51)
        for y in (7, 15, 23):
            for x in range(4, 28):
                if (x + y) % 6 < 3:
                    t.putpixel((x, y), hexc("#9bd1ee"))
    elif name == "flowers":
        speckle(t, hexc("#2f5d44"), [hexc("#356a4d"), hexc("#2a5340")], 0.10, 61)
        rnd = random.Random(62)
        for col in ("#f08ab0", "#ffe27a", "#ffffff", "#f08ab0", "#ffe27a"):
            x, y = rnd.randint(3, 28), rnd.randint(3, 28)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)):
                t.putpixel((x + dx, y + dy), hexc(col))
            t.putpixel((x, y), hexc("#ffd84d"))
    elif name == "stones":
        speckle(t, hexc("#2f5d44"), [hexc("#356a4d")], 0.10, 71)
        rnd = random.Random(72)
        for _ in range(3):
            x, y = rnd.randint(4, 24), rnd.randint(4, 24)
            for dx in range(5):
                for dy in range(3):
                    t.putpixel((x + dx, y + dy), hexc("#8a8f94"))
            for dx in range(4):
                t.putpixel((x + dx, y), hexc("#aab0b5"))
    return t


def px(img, x, y, c):
    if 0 <= x < img.width and 0 <= y < img.height:
        img.putpixel((x, y), c)


def rect(img, x0, y0, x1, y1, c):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px(img, x, y, c)


def ellipse(img, cx, cy, rx, ry, fill, edge=None):
    for y in range(img.height):
        for x in range(img.width):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1.0:
                px(img, x, y, fill)
                if edge and d > 0.7:
                    px(img, x, y, edge)


def make_props():
    props = ROOT / "assets" / "props"
    props.mkdir(parents=True, exist_ok=True)
    # faint paw print: one pad + four toes, semi-transparent warm cream
    paw = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    col = hexc("#f2e2b8", 255)
    for (x, y) in [(6, 9), (7, 9), (8, 9), (9, 9), (5, 10), (6, 10), (7, 10), (8, 10), (9, 10), (10, 10),
                   (6, 11), (7, 11), (8, 11), (9, 11), (7, 12), (8, 12),
                   (3, 6), (3, 7), (4, 6), (4, 7), (6, 3), (6, 4), (7, 3), (7, 4),
                   (9, 3), (9, 4), (10, 3), (10, 4), (12, 6), (12, 7), (13, 6), (13, 7)]:
        paw.putpixel((x, y), col)
    paw.save(props / "pawprint.png")

    # old tree hollow: a big gnarled trunk seen from the front with a dark opening
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    for y in range(6, 62):
        half = 15 + (4 if y > 40 else 0) - (3 if y < 14 else 0)
        for x in range(32 - half, 32 + half):
            px(img, x, y, hexc("#6b4a2f") if (x + y // 3) % 7 else hexc("#5c3f27"))
        px(img, 32 - half, y, hexc("#3b2716")); px(img, 32 + half - 1, y, hexc("#3b2716"))
    for cx, cy, r in ((32, 12, 22), (14, 20, 12), (50, 20, 12), (24, 6, 12), (40, 6, 12)):
        for y in range(64):
            for x in range(64):
                if math.hypot(x - cx, y - cy) <= r:
                    px(img, x, y, hexc("#21553b") if (x * 3 + y * 5) % 11 else hexc("#2e6f4b"))
    for y in range(30, 56):
        w = 9 - abs(y - 43) // 3
        rect(img, 32 - w, y, 32 + w - 1, y, hexc("#140c07"))
    for x in range(23, 41):
        px(img, x, 29, hexc("#3b2716")); px(img, x, 56, hexc("#3b2716"))
    for (x, y) in ((28, 46), (36, 40)):
        px(img, x, y, hexc("#ffd84d")); px(img, x + 1, y, hexc("#ffd84d"))
    img.save(props / "tree_hollow.png")

    # fallen log: horizontal trunk, ring end on the left, moss on top
    log = Image.new("RGBA", (64, 24), (0, 0, 0, 0))
    rect(log, 6, 6, 60, 19, hexc("#6b4a2f"))
    for x in range(6, 61):
        if x % 5 < 2:
            px(log, x, 8, hexc("#5c3f27")); px(log, x, 14, hexc("#5c3f27"))
    for x in range(6, 61):
        px(log, x, 6, hexc("#3b2716")); px(log, x, 19, hexc("#3b2716"))
    ellipse(log, 6, 12.5, 6, 7, hexc("#b88a5a"), hexc("#3b2716"))
    ellipse(log, 6, 12.5, 3, 4, hexc("#d6aa78"))
    for x in range(20, 46):
        px(log, x, 5, hexc("#3f9462")); px(log, x, 4 if x % 3 == 0 else 5, hexc("#2f7a4f"))
    log.save(props / "fallen_log.png")

    # stump
    st = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    rect(st, 4, 10, 19, 21, hexc("#6b4a2f"))
    for y in range(10, 22):
        px(st, 4, y, hexc("#3b2716")); px(st, 19, y, hexc("#3b2716"))
    rect(st, 4, 21, 19, 21, hexc("#3b2716"))
    ellipse(st, 12, 10, 8, 4, hexc("#c99a68"), hexc("#3b2716"))
    ellipse(st, 12, 10, 4, 2, hexc("#dcb988"))
    st.save(props / "stump.png")

    # campfire: crossed logs and a flame
    fire = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    for i in range(14):
        px(fire, 3 + i, 20 - i // 3, hexc("#6b4a2f")); px(fire, 3 + i, 21 - i // 3, hexc("#4a3220"))
        px(fire, 20 - i, 20 - i // 3, hexc("#7a5538")); px(fire, 20 - i, 21 - i // 3, hexc("#4a3220"))
    for (cx, cy, rx, ry, c) in ((12, 13, 5, 7, "#ff7a2a"), (12, 14, 3.5, 5, "#ffb52e"), (12, 15, 2, 3, "#fff2a8")):
        ellipse(fire, cx, cy, rx, ry, hexc(c))
    fire.save(props / "campfire.png")

    # bench
    bench = Image.new("RGBA", (40, 22), (0, 0, 0, 0))
    rect(bench, 2, 6, 37, 11, hexc("#8a5a3b"))
    rect(bench, 2, 6, 37, 6, hexc("#b88a5a"))
    rect(bench, 2, 11, 37, 11, hexc("#4a3220"))
    for x in (4, 34):
        rect(bench, x, 12, x + 2, 20, hexc("#4a3220"))
    rect(bench, 2, 0, 37, 2, hexc("#8a5a3b"))
    rect(bench, 4, 3, 5, 6, hexc("#4a3220")); rect(bench, 34, 3, 35, 6, hexc("#4a3220"))
    bench.save(props / "bench.png")

    # mushroom
    mush = Image.new("RGBA", (12, 12), (0, 0, 0, 0))
    rect(mush, 5, 6, 6, 10, hexc("#f2e6d0"))
    ellipse(mush, 6, 5, 5.5, 4, hexc("#d8434f"), hexc("#8a2630"))
    for (x, y) in ((4, 4), (7, 3), (8, 5)):
        px(mush, x, y, hexc("#ffffff"))
    mush.save(props / "mushroom.png")

    # signpost: wooden post with a board
    sign = Image.new("RGBA", (24, 34), (0, 0, 0, 0))
    rect(sign, 11, 8, 13, 32, hexc("#6b4a2f"))
    rect(sign, 2, 4, 21, 13, hexc("#b88a5a"))
    for x in range(2, 22):
        px(sign, x, 4, hexc("#6b4a2f")); px(sign, x, 13, hexc("#6b4a2f"))
    for y in range(4, 14):
        px(sign, 2, y, hexc("#6b4a2f")); px(sign, 21, y, hexc("#6b4a2f"))
    for (x, y) in ((5, 7), (8, 9), (12, 7), (15, 9), (18, 7)):
        px(sign, x, y, hexc("#8a5a3b")); px(sign, x + 1, y, hexc("#8a5a3b"))
    sign.save(props / "signpost.png")

    # loot sack: a tied cloth pouch with a golden sparkle
    sack = Image.new("RGBA", (22, 22), (0, 0, 0, 0))
    ellipse(sack, 11, 13, 8, 7, hexc("#c9a46a"), hexc("#6b4a2f"))
    rect(sack, 8, 5, 13, 7, hexc("#c9a46a"))
    rect(sack, 8, 7, 13, 7, hexc("#8a5a3b"))
    px(sack, 7, 4, hexc("#c9a46a")); px(sack, 14, 4, hexc("#c9a46a"))
    for (x, y) in ((17, 3), (18, 2), (18, 4), (19, 3), (18, 3)):
        px(sack, x, y, hexc("#ffd84d"))
    sack.save(props / "loot_sack.png")


def mark_walkable(grid, walk, rnd):
    """Fill the tile grid from the level data (road, side roads, trails, clearings, chambers, ponds)."""
    for r in range(ROWS):
        for c in range(COLS):
            p = (c * TILE + TILE / 2, r * TILE + TILE / 2)
            in_pond = any(in_ellipse(p, e) for e in PONDS)
            on_road = near_polyline(p, PATH, PATH_WIDTH / 2) or any(near_polyline(p, b["points"], b["width"] / 2) for b in BRANCHES)
            on_trail = any(near_polyline(p, t["points"], t["width"] / 2) for t in TRAILS)
            in_zone = any(in_ellipse(p, e) for e in ZONES.values())
            in_chamber = any(math.hypot(p[0] - ch["center"][0], p[1] - ch["center"][1]) <= ch["radius"] for ch in CHAMBERS)
            if in_pond:
                grid[r][c] = "water"
            elif on_road:
                grid[r][c] = "dirt"
                walk[r][c] = True
            elif on_trail:
                grid[r][c] = "dirt_light"
                walk[r][c] = True
            elif in_zone or in_chamber:
                x = rnd.random()
                grid[r][c] = "flowers" if x < 0.08 else ("stones" if x < 0.11 else ("grass_b" if x < 0.5 else "grass_a"))
                walk[r][c] = True


def build_grid():
    rnd = random.Random(2026)
    grid = [[None] * COLS for _ in range(ROWS)]
    walk = [[False] * COLS for _ in range(ROWS)]
    mark_walkable(grid, walk, rnd)
    # Everything else is forest: solid trees, with bushes lining the clearings.
    for r in range(ROWS):
        for c in range(COLS):
            if grid[r][c] is not None:
                continue
            near_open = any(0 <= r + dr < ROWS and 0 <= c + dc < COLS and walk[r + dr][c + dc]
                            for dr in (-1, 0, 1) for dc in (-1, 0, 1))
            grid[r][c] = "bush" if (near_open and rnd.random() < 0.28) else rnd.choice(["tree_a", "tree_b", "tree_c"])
    # Each secret trail's mouth is half hidden: near the entrance only a narrow channel around the
    # trail's centre line stays open (>= 1.5 tiles so it is 4-connected), the rest becomes bushes.
    for trail in TRAILS:
        mouth = trail.get("mouth")
        if mouth is None:
            continue
        for r in range(ROWS):
            for c in range(COLS):
                if grid[r][c] != "dirt_light":
                    continue
                p = (c * TILE + TILE / 2, r * TILE + TILE / 2)
                if math.hypot(p[0] - mouth[0], p[1] - mouth[1]) > 80:
                    continue
                if dist_to_polyline(p, trail["points"]) > 24:
                    grid[r][c] = "bush"
                    walk[r][c] = False
    return grid, walk


def fill_pockets(grid, walk):
    """Walkable cells that cannot be reached from the start become trees (no dead holes)."""
    seen = flood(walk)
    filled = 0
    for r in range(ROWS):
        for c in range(COLS):
            if walk[r][c] and (r, c) not in seen:
                grid[r][c] = "tree_a"
                walk[r][c] = False
                filled += 1
    if filled:
        print(f"filled {filled} unreachable pocket cell(s) with trees")


def cell_of(p):
    return int(p[1] // TILE), int(p[0] // TILE)


def flood(walk):
    start = cell_of(START)
    seen = {start}
    queue = deque([start])
    while queue:
        r, c = queue.popleft()
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (r + dr, c + dc)
            if 0 <= n[0] < ROWS and 0 <= n[1] < COLS and walk[n[0]][n[1]] and n not in seen:
                seen.add(n)
                queue.append(n)
    return seen


def check_design(grid, walk):
    ok = True
    seen = flood(walk)

    def need(name, p):
        """The cell and its four neighbours must be walkable and connected to the start."""
        nonlocal ok
        r, c = cell_of(p)
        around = [(r, c), (r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)]
        bad = [q for q in around if not (0 <= q[0] < ROWS and 0 <= q[1] < COLS and walk[q[0]][q[1]])]
        if bad or (r, c) not in seen:
            ok = False
            print(f"  PROBLEM {name} at {p}: non-walkable cells={len(bad)} reachable={(r, c) in seen}")

    need("start", START)
    need("exit", EXIT)
    names = set()
    for i, e in enumerate(ENEMIES, 1):
        if e["name"] in names:
            ok = False
            print("  PROBLEM duplicate enemy name", e["name"])
        names.add(e["name"])
        need(f"enemy {e['name']}", e["pos"])
    for s_ in SECRETS:
        need("secret " + s_["id"], s_["pos"])
    for l in LOOT:
        need("loot " + l["id"], l["pos"])
    for ch in CHAMBERS:
        need("chamber", ch["center"])
    for i, lm in enumerate(LANDMARKS):
        if lm["type"] in ("signpost", "campfire", "bench", "stump", "fallen_log"):
            r, c = cell_of(lm["pos"])
            if not walk[r][c]:
                print(f"  note: landmark {lm['type']} at {lm['pos']} sits on solid ground (decoration only)")
    for lamp in LAMPS:
        r, c = cell_of(lamp)
        if not walk[r][c]:
            ok = False
            print(f"  PROBLEM lamp at {lamp} is not on walkable ground")
    # every branch / trail end and zone centre must be reachable (no unreachable areas)
    for b in BRANCHES:
        need("end of " + b["name"], b["points"][-1])
    for t in TRAILS:
        need("end of " + t["name"], t["points"][-1])
    for name, (cx, cy, rx, ry) in ZONES.items():
        need("zone " + name, (cx, cy))
    total = sum(walk[r][c] for r in range(ROWS) for c in range(COLS))
    print(f"walkable cells: {total}, reachable from start: {len(seen)}")
    if total != len(seen):
        print("  NOTE: some walkable cells are not connected to the start")
        ok = False
    mandatory = sum(1 for e in ENEMIES if not e.get("optional"))
    print(f"enemies: {len(ENEMIES)} ({mandatory} count toward the exit, {len(ENEMIES) - mandatory} optional)")
    return ok


def main():
    out_tiles = ROOT / "assets" / "tilesets"
    out_tiles.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (TILE * len(TILE_NAMES), TILE))
    for i, name in enumerate(TILE_NAMES):
        atlas.paste(make_tile(name), (i * TILE, 0))
    atlas.save(out_tiles / "forest_tiles.png")
    make_props()
    grid, walk = build_grid()
    fill_pockets(grid, walk)
    ok = check_design(grid, walk)
    level = {
        "world": [W, H], "tile": TILE, "tile_names": TILE_NAMES, "solid": sorted(SOLID),
        "grid": [[IDX[n] for n in row] for row in grid],
        "start": START, "path": PATH, "exit": EXIT,
        "branches": BRANCHES, "trails": TRAILS, "chambers": CHAMBERS,
        "enemies": [{"pos": e["pos"], "name": e["name"], "optional": bool(e.get("optional")), "type": e.get("type", "slime")} for e in ENEMIES],
        "lamps": LAMPS, "pawprints": PAWPRINTS, "secrets": SECRETS, "loot": LOOT, "landmarks": LANDMARKS,
        "firefly_areas": FIREFLY_AREAS,
    }
    (ROOT / "tools" / "data").mkdir(parents=True, exist_ok=True)
    (ROOT / "tools" / "data" / "forest_grove_level.json").write_text(json.dumps(level, ensure_ascii=False))
    print("wrote tileset, props and tools/data/forest_grove_level.json;", "design check OK" if ok else "DESIGN CHECK FAILED")
    sys.exit(0 if ok else 1)


main()
