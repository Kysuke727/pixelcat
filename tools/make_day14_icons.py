#!/usr/bin/env python3
"""Compact, transparent 64x64 icons sampled from the approved PixelCat sprite sketch.
Pure stdlib. The compressed data stores 32x32 RGBA pixels extracted from the reference.
"""
from pathlib import Path
import base64, zlib, struct, math

SOURCES = {
"crafting_yarn": "eNrtljFKhDEQhfdSIt5DL2AhFoKF4AUs7Ow8gq0IYmlh5R7ARryDF3Al8gLf8hgm+X9w/RsTGDbJn8l782aS7Go12mij7aI9HJ4WtyVx7w+Oy+ftXdk8rcv361u197Obavr2V9jgyoQpfHAxfdO69dHlLniUk/29qu/Xx2M19eEgfIw5eIif/H+TW+0Hrpu+EbvnINpcDWItZZjRtDdxo4H4aN7zMKUvsZBP+c3hoDXELx9wfdzDBzfmjxxGDs9X55Uj2F4LxM45YK6Fj5+fm4wLOC/XF9tf+oxjLdLv6U/s8SxFHaQhWBqD7xy0xjG1F77ZveRnGM0i96wW1FcOHNtz4BqSgwyfuvE4XQf28rz26jFqiS9+rdyjUYZN/JzjDN9rxO8+9piqPfQCz7nHemLecbMYWjH38P0ceN5jTF7rHjvvETb3vou6+73ld2iGb2/u1tf31xhrcXCdPRd+llzf1juPL/FrfXwDtKb3xmT1M1XHfofHNxg8sHs6wCNy6MW8xP+pJf9TjTbaf2g/5HjDZw==",
"crafting_wood": "eNrtVjFOw0AQTJuKn1CkQJFoUMpIoeAVgChoEEqbJr+gSk9LzVfo+AClyZwy0TBZrx3iBCH5pNWdffbO7Nzu2oNBP/rR/bgdn1dPk4sK8ylxgQn7eLkv9rl6OAkPYLzeTX/gwni9nF0WDl3yoMbw/fW22MFWDuCGNebHq1F1qL4eq8/v85vtM8qD8746ROfqfhlftE8NYODWFh9aqb7qF37cd6Q9niv2fL1dN+FjP8on4sKi+PVa4+VcOKwtw8de5J9+Im1dZ3JUDjBoiXPMsD1mzSW12vNdx6drGHtAG93Vn9aVY3tsqjNm4vEe383i1xynf9eY992Iy1pRTsode+OzYVWX7x4r36/F3ejNs804g0+G73WuPTyLN9I5qvs6fPrQXu2aOS77b4TrPLUWvP96zrNnqA4eP3xksSquxtS25uhLNaHWWDfhlhg2dZflu+Jr79YZeDT4zHC53udb6zWvc1OczHvi/fb7zvxVXF97b6O2Xf5TeP3y3N2O+T+F2mQfUkxw+Yt/yab87Uc//uv4Bk1WVjM=",
"crafting_stone": "eNrtl81qwkAUhX2nLgt2WajgpnQj9EncF8Slgg+gS5cFC120K5cu9XEiJ3DCyeWkmfwoFDJwMclM5jtz752bcTQa2tDS29vza6Z2b/bldC7Z+mOV7Tbb3Cbjl8JuxT5+H0umWvgMmvrwjfrZsauMet6ns6wvX6eyVQN+28RC2U25ykdOtIlDH2zkAGw5XzTSgJh14Sub1oTfNu4Yi7XCIj81DhjztT8Uprlcl+tkO36qDzAGWlUD7p0G3WNgsgbRoo46Pvoxb2QrXw3PNcfoZ9434T89POZjlE0+NKlPXH5Rp+ph3qtV1SP0/X7+FPOAw3mdJhdf1UB2jBvjFWsS844adL7Id2zVADb3cGpdYt6RV8Wu48d1Ow0uH5SPvhgLx0Yf1qnx5bzMk+j7VD6vqSPGnVxl0Kf6ftV+cfuB78Z8Ul3kxhqtNUjX4mL6136M+8WdtdwZSPekxiLy23wP3PdJa0KsB6oTY2Nc+zgXYV7nU/et1drT5TyUGqvhH8LQ/lO7Avvlaes=",
}

def make_png(pixels, w=64, h=64):
    raw = b"".join(b"\x00" + pixels[y*w*4:(y+1)*w*4] for y in range(h))
    def chunk(tag, data):
        return struct.pack(">I",len(data))+tag+data+struct.pack(">I",zlib.crc32(tag+data)&0xffffffff)
    return b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,8,6,0,0,0))+chunk(b"IDAT",zlib.compress(raw,9))+chunk(b"IEND",b"")

def scale_to_64(src):
    assert len(src)==32*32*4
    out = bytearray()
    for y in range(32):
        row=bytearray()
        for x in range(32):
            px=src[(y*32+x)*4:(y*32+x+1)*4]
            row.extend(px*2)
        out.extend(row)
        out.extend(row)
    return bytes(out)

dest=Path("/workspace/pixelcat-day14/assets/objects/items")
dest.mkdir(parents=True,exist_ok=True)
for name,blob in SOURCES.items():
    data=zlib.decompress(base64.b64decode(blob))
    (dest/(name+".png")).write_bytes(make_png(scale_to_64(data)))

# Small pixel-art cat teaser icon: wooden wand + pink ribbon at its upper end.
w=h=32
px=bytearray(32*32*4)
def put(x,y,c):
    if 0<=x<32 and 0<=y<32: px[(y*32+x)*4:(y*32+x+1)*4]=bytes(c)
def stroke(a,b,c,size=1):
    x1,y1=a;x2,y2=b
    n=max(abs(x2-x1),abs(y2-y1))*3+1
    for j in range(n+1):
        x=round(x1+(x2-x1)*j/n);y=round(y1+(y2-y1)*j/n)
        for xx in range(x-size//2,x-size//2+size):
            for yy in range(y-size//2,y-size//2+size):put(xx,yy,c)
stroke((8,27),(23,7),(99,56,46,255),4)
stroke((8,27),(23,7),(222,151,98,255),2)
stroke((23,7),(17,5),(143,72,98,255),2)
stroke((17,5),(12,9),(255,161,196,255),3)
stroke((12,9),(9,15),(255,161,196,255),3)
stroke((9,15),(14,19),(255,161,196,255),3)
stroke((14,19),(19,16),(255,161,196,255),3)
(dest/"cat_teaser.png").write_bytes(make_png(scale_to_64(bytes(px))))
for p in dest.glob("*.png"):
    if p.stem.startswith("crafting_") or p.stem=="cat_teaser":
        print(p.name,p.stat().st_size)
