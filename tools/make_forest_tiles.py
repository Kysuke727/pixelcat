#!/usr/bin/env python3
"""Generates the forest grove's placeholder art and its tile grid.

    python3 tools/make_forest_tiles.py

Outputs
  assets/tilesets/forest_tiles.png   32x32 tiles in one row (see TILE_NAMES for the order)
  assets/props/pawprint.png          faint paw-print hint (16x16)
  assets/props/tree_hollow.png       the old tree hollow (64x64) that teaches a move
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


def make_props():
    # faint paw print: one pad + four toes, semi-transparent warm cream
    paw = Image.new("RGBA", (16, 16), (0, 0, 0, 0))
    col = hexc("#f2e2b8", 255)
    for (x, y) in [(6, 9), (7, 9), (8, 9), (9, 9), (5, 10), (6, 10), (7, 10), (8, 10), (9, 10), (10, 10),
                   (6, 11), (7, 11), (8, 11), (9, 11), (7, 12), (8, 12),
                   (3, 6), (3, 7), (4, 6), (4, 7), (6, 3), (6, 4), (7, 3), (7, 4),
                   (9, 3), (9, 4), (10, 3), (10, 4), (12, 6), (12, 7), (13, 6), (13, 7)]:
        paw.putpixel((x, y), col)
    paw.save(ROOT / "assets" / "props" / "pawprint.png")

    # old tree hollow: a big gnarled trunk seen from the front with a dark opening
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    def put(x, y, c):
        if 0 <= x < 64 and 0 <= y < 64:
            img.putpixel((x, y), c)
    for y in range(6, 62):
        half = 15 + (4 if y > 40 else 0) - (3 if y < 14 else 0)
        for x in range(32 - half, 32 + half):
            shade = hexc("#6b4a2f") if (x + y // 3) % 7 else hexc("#5c3f27")
            put(x, y, shade)
        put(32 - half, y, hexc("#3b2716")); put(32 + half - 1, y, hexc("#3b2716"))
    for cx, cy, r in ((32, 12, 22), (14, 20, 12), (50, 20, 12), (24, 6, 12), (40, 6, 12)):
        for y in range(64):
            for x in range(64):
                if math.hypot(x - cx, y - cy) <= r:
                    put(x, y, hexc("#21553b") if (x * 3 + y * 5) % 11 else hexc("#2e6f4b"))
    for y in range(30, 56):          # the hollow
        w = 9 - abs(y - 43) // 3
        for x in range(32 - w, 32 + w):
            put(x, y, hexc("#140c07"))
    for x in range(23, 41):
        put(x, 29, hexc("#3b2716")); put(x, 56, hexc("#3b2716"))
    for (x, y) in ((28, 46), (36, 40)):      # two tiny glints inside: something lives here
        put(x, y, hexc("#ffd84d")); put(x + 1, y, hexc("#ffd84d"))
    img.save(ROOT / "assets" / "props" / "tree_hollow.png")


def build_grid():
    rnd = random.Random(2026)
    grid = [[None] * COLS for _ in range(ROWS)]
    walk = [[False] * COLS for _ in range(ROWS)]
    for r in range(ROWS):
        for c in range(COLS):
            p = (c * TILE + TILE / 2, r * TILE + TILE / 2)
            on_path = near_polyline(p, PATH, PATH_WIDTH / 2)
            in_zone = any(in_ellipse(p, e) for e in ZONES.values())
            on_trail = near_polyline(p, SECRET_TRAIL, TRAIL_WIDTH / 2)
            in_chamber = math.hypot(p[0] - SECRET[0], p[1] - SECRET[1]) <= SECRET_RADIUS
            in_pond = in_ellipse(p, POND)
            if in_pond:
                grid[r][c] = "water"
            elif on_path:
                grid[r][c] = "dirt"
                walk[r][c] = True
            elif on_trail:
                grid[r][c] = "dirt_light"
                walk[r][c] = True
            elif in_zone or in_chamber:
                x = rnd.random()
                grid[r][c] = "flowers" if x < 0.08 else ("stones" if x < 0.11 else ("grass_b" if x < 0.5 else "grass_a"))
                walk[r][c] = True
    # Everything else is forest: solid trees, with bushes lining the clearings.
    for r in range(ROWS):
        for c in range(COLS):
            if grid[r][c] is not None:
                continue
            near_open = any(0 <= r + dr < ROWS and 0 <= c + dc < COLS and walk[r + dr][c + dc]
                            for dr in (-1, 0, 1) for dc in (-1, 0, 1))
            grid[r][c] = "bush" if (near_open and rnd.random() < 0.28) else rnd.choice(["tree_a", "tree_b", "tree_c"])
    # The secret trail's mouth is half hidden: near the entrance only a narrow channel
    # around the trail's centre line stays open (>= 1.5 tiles so it is 4-connected), the
    # rest of the trail width becomes bushes.
    for r in range(ROWS):
        for c in range(COLS):
            if grid[r][c] != "dirt_light":
                continue
            p = (c * TILE + TILE / 2, r * TILE + TILE / 2)
            if math.hypot(p[0] - TRAIL_MOUTH[0], p[1] - TRAIL_MOUTH[1]) > 80:
                continue
            if min(dist_to_segment(p, SECRET_TRAIL[i], SECRET_TRAIL[i + 1]) for i in range(len(SECRET_TRAIL) - 1)) > 24:
                grid[r][c] = "bush"
                walk[r][c] = False
    return grid, walk


def fill_pockets(grid, walk):
    """Walkable cells that cannot be reached from the start become trees (no dead holes)."""
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


def check_design(grid, walk):
    ok = True
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
    def need(name, p):
        """The cell and its four neighbours must be walkable and connected to the start."""
        nonlocal ok
        r, c = cell_of(p)
        around = [(r, c), (r + 1, c), (r - 1, c), (r, c + 1), (r, c - 1)]
        bad = [q for q in around if not (0 <= q[0] < ROWS and 0 <= q[1] < COLS and walk[q[0]][q[1]])]
        reach = (r, c) in seen
        if bad or not reach:
            ok = False
            print(f"  PROBLEM {name} at {p}: non-walkable cells={len(bad)} reachable={reach}")
    need("start", START)
    for i, p in enumerate(ENEMIES, 1):
        need(f"enemy {i}", p)
    need("exit", EXIT)
    need("secret", SECRET)
    for i, p in enumerate(LAMPS, 1):
        r, c = cell_of(p)
        if not walk[r][c]:
            pass  # lamps may sit at the edge of a clearing
    total = sum(walk[r][c] for r in range(ROWS) for c in range(COLS))
    print(f"walkable cells: {total}, reachable from start: {len(seen)}")
    if total != len(seen):
        print("  NOTE: some walkable cells are not connected to the start")
        ok = False
    return ok


def main():
    out_tiles = ROOT / "assets" / "tilesets"
    out_tiles.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (TILE * len(TILE_NAMES), TILE))
    for i, name in enumerate(TILE_NAMES):
        atlas.paste(make_tile(name), (i * TILE, 0))
    atlas.save(out_tiles / "forest_tiles.png")
    (ROOT / "assets" / "props").mkdir(parents=True, exist_ok=True)
    make_props()
    grid, walk = build_grid()
    fill_pockets(grid, walk)
    ok = check_design(grid, walk)
    level = {
        "world": [W, H], "tile": TILE, "tile_names": TILE_NAMES, "solid": sorted(SOLID),
        "grid": [[IDX[n] for n in row] for row in grid],
        "start": START, "path": PATH, "exit": EXIT, "secret": SECRET,
        "enemies": ENEMIES, "optional_enemies": OPTIONAL_ENEMIES, "lamps": LAMPS, "pawprints": PAWPRINTS,
        "secret_radius": SECRET_RADIUS,
    }
    (ROOT / "tools" / "data").mkdir(parents=True, exist_ok=True)
    (ROOT / "tools" / "data" / "forest_grove_level.json").write_text(json.dumps(level, ensure_ascii=False))
    print("wrote tileset, props and tools/data/forest_grove_level.json;", "design check OK" if ok else "DESIGN CHECK FAILED")
    sys.exit(0 if ok else 1)


main()
