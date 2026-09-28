"""Build dist/PogGuildTools-<version>.zip for CurseForge: just the PogRaid folder, nothing else
(the folder keeps its name: saved data and the addon itself are tied to it).
Also writes dist/PogRaid-icon-400.png (project avatar). Double-click 'Package for CurseForge.bat'."""
import os, re, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "PogRaid")
DIST = os.path.join(ROOT, "dist")
os.makedirs(DIST, exist_ok=True)

toc = open(os.path.join(ADDON, "PogRaid.toc"), encoding="utf-8").read()
version = re.search(r"^## Version:\s*(\S+)", toc, re.M).group(1)
listed = [l.strip() for l in toc.splitlines() if l.strip().endswith(".lua")]
missing = [f for f in listed if not os.path.exists(os.path.join(ADDON, f))]
if missing:
    raise SystemExit("files listed in the .toc are missing: " + ", ".join(missing))

out = os.path.join(DIST, f"PogGuildTools-{version}.zip")
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder, _, files in os.walk(ADDON):
        for name in sorted(files):
            if name.endswith((".lua", ".toc", ".tga", ".blp", ".ogg")):
                full = os.path.join(folder, name)
                z.write(full, os.path.join("PogRaid", os.path.relpath(full, ADDON)))
print("built", out)
with zipfile.ZipFile(out) as z:
    for n in z.namelist():
        print("   ", n)

try:
    from PIL import Image
    logo = Image.open(os.path.join(ADDON, "Media", "logo.tga")).convert("RGBA")
    canvas = Image.new("RGBA", (400, 400), (22, 24, 30, 255))
    face = logo.resize((360, 360), Image.LANCZOS)
    canvas.alpha_composite(face, (20, 22))
    canvas.save(os.path.join(DIST, "PogRaid-icon-400.png"))
    print("built", os.path.join(DIST, "PogRaid-icon-400.png"))
except ImportError:
    print("(pip install pillow to also build the 400x400 project icon)")
