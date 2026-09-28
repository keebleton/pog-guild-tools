"""Make PogRaid/Media/logo.tga (128x128 RGBA) from a source image, keeping its own transparency.
The addon draws a round plate and ring behind it. Usage: python tools_make_logo.py <image>"""
import os, struct, sys
from PIL import Image

SRC = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "PogRaid", "Media", "logo.tga")
SIZE = 128

img = Image.open(SRC).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
pixels = img.get_flattened_data() if hasattr(img, "get_flattened_data") else img.getdata()
header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
px = bytearray()
for (R, G, B, A) in pixels:
    px += bytes((B, G, R, A))
with open(OUT, "wb") as f:
    f.write(header + px)
print("wrote", OUT)
