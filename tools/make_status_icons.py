#!/usr/bin/env python3
"""Generates the 10x10 pixel status icons used by the top-left HUD strip.

    python3 tools/make_status_icons.py

Output: assets/ui/icon_hunger.png, icon_mood.png, icon_energy.png, icon_hp.png, icon_shield.png (transparent).
They are shown at 2x with nearest-neighbour filtering. To use hand-drawn art
just overwrite those PNGs (keep them square; any size works).
"""
from pathlib import Path
from PIL import Image

PALETTE = {
    ".": None,
    "O": "#7a4a5e",   # outline
    "P": "#f07aa0",   # pink
    "H": "#ffd0de",   # highlight
    "K": "#b9794a",   # kibble
    "B": "#f2a65a",   # bowl
    "C": "#ffe0b8",   # bowl highlight
    "Y": "#ffd84d",   # bolt
    "W": "#fff3a8",   # bolt highlight
    "R": "#e8576a",   # hp heart
    "r": "#ffc4cc",   # hp heart highlight
    "S": "#6fa8e8",   # shield
    "s": "#d6ecff",   # shield highlight
}

ICONS = {
    "hp": [
        "..........",
        ".OOO..OOO.",
        "ORRROOORRO",
        "ORrrRRRRRO",
        "ORrRRRRRRO",
        ".ORRRRRRO.",
        "..ORRRRO..",
        "...ORRO...",
        "....OO....",
        "..........",
    ],
    "shield": [
        "..........",
        ".OOOOOOOO.",
        ".OSSSSSSO.",
        ".OSsSSSSO.",
        ".OSsSSSSO.",
        ".OSSSSSSO.",
        "..OSSSSO..",
        "...OSSO...",
        "....OO....",
        "..........",
    ],
    "hunger": [
        "..........",
        "...K.K....",
        "..KKKKK...",
        ".OOOOOOOO.",
        "OBBBBBBBBO",
        "OBCCBBBBBO",
        ".OBBBBBBO.",
        "..OOOOOO..",
        "..........",
        "..........",
    ],
    "mood": [
        "..........",
        ".OOO..OOO.",
        "OPPPOOPPPO",
        "OPHHPPPPPO",
        "OPHPPPPPPO",
        ".OPPPPPPO.",
        "..OPPPPO..",
        "...OPPO...",
        "....OO....",
        "..........",
    ],
    "energy": [
        "......OO..",
        ".....OYYO.",
        "....OYYO..",
        "...OYWYO..",
        "..OYYYYYO.",
        "..OOOYYO..",
        "....OYYO..",
        "...OYYO...",
        "...OYO....",
        "...OO.....",
    ],
}

out_dir = Path(__file__).resolve().parent.parent / "assets" / "ui"
out_dir.mkdir(parents=True, exist_ok=True)
for name, rows in ICONS.items():
    assert len(rows) == 10 and all(len(r) == 10 for r in rows), name
    img = Image.new("RGBA", (10, 10), (0, 0, 0, 0))
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            colour = PALETTE[ch]
            if colour:
                img.putpixel((x, y), Image.new("RGB", (1, 1), colour).getpixel((0, 0)) + (255,))
    img.save(out_dir / f"icon_{name}.png")
    print("wrote", f"icon_{name}.png")
