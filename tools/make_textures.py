"""Generate the white, alpha-only TGA textures PogRaid tints with SetVertexColor."""
import math, struct, os

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "PogRaid", "Media")
SIZE = 128

def write_tga(path, alpha_fn):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    px = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            a = max(0.0, min(1.0, alpha_fn(x + 0.5 - SIZE / 2, y + 0.5 - SIZE / 2)))
            px += bytes((255, 255, 255, int(round(a * 255))))
    with open(path, "wb") as f:
        f.write(header + px)

R = SIZE / 2 - 2  # outer radius, 2px margin so bilinear filtering never clips the edge

def disc(dx, dy):
    return R - math.hypot(dx, dy) + 0.5

# Thickness ~2px at the 24px role badge (128 * 2 / 24 ~ 11); also the pulse ring.
def ring(dx, dy, thick=11.0):
    d = math.hypot(dx, dy)
    return min(R - d + 0.5, d - (R - thick) + 0.5)

# Soft radial glow (behind character models, and their shadow): full in the
# middle, fading smoothly to nothing at the edge.
def glow(dx, dy):
    t = max(0.0, 1.0 - math.hypot(dx, dy) / R)
    return t * t * (3 - 2 * t)

write_tga(os.path.join(OUT, "disc.tga"), disc)
write_tga(os.path.join(OUT, "glow.tga"), glow)
write_tga(os.path.join(OUT, "ring.tga"), ring)
print("ok", os.listdir(OUT))
