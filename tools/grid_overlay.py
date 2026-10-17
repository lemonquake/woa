"""Draw the measuring grid on grid_render.py's images (plain Python with Pillow).

Run: python tools/grid_overlay.py <out_prefix> [--step=0.05] [--marks=<json of name -> [x, y, z]>]
Grid lines every step (labels every 2 steps) in model units; marks (joint guesses) are drawn as dots on both views.
"""
import json
import math
import sys
from PIL import Image, ImageDraw, ImageFont

prefix = sys.argv[1]
opt = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in sys.argv[2:] if a.startswith("--") and "=" in a}
step = float(opt.get("step", "0.05"))
dec = max(2, int(math.ceil(-math.log10(step))) + 1)
marks = json.load(open(opt["marks"])) if "marks" in opt else {}
info = json.load(open(prefix + ".json"))
try:
    font = ImageFont.truetype("arial.ttf", 13)
except OSError:
    font = ImageFont.load_default()
for view, v in info["views"].items():
    im = Image.open("%s_%s.png" % (prefix, view)).convert("RGB")
    d = ImageDraw.Draw(im)
    W, H = v["w"], v["h"]
    def px(u, z):
        return ((u - v["u0"]) / (v["u1"] - v["u0"]) * W, (v["z1"] - z) / (v["z1"] - v["z0"]) * H)
    k0 = math.floor(v["u0"] / step)
    k1 = math.ceil(v["u1"] / step)
    for k in range(k0, k1 + 1):
        u = k * step
        x, _ = px(u, 0)
        col = (255, 60, 60) if k == 0 else ((90, 200, 255) if k % 2 == 0 else (70, 90, 110))
        d.line([(x, 0), (x, H)], fill=col, width=1)
        if k % 2 == 0:
            d.text((x + 2, 2), "%.*f" % (dec, u), fill=(255, 255, 120), font=font)
    k0 = math.floor(v["z0"] / step)
    k1 = math.ceil(v["z1"] / step)
    for k in range(k0, k1 + 1):
        z = k * step
        _, y = px(0, z)
        col = (255, 60, 60) if k == 0 else ((90, 200, 255) if k % 2 == 0 else (70, 90, 110))
        d.line([(0, y), (W, y)], fill=col, width=1)
        if k % 2 == 0:
            d.text((2, y - 14), "%.*f" % (dec, z), fill=(255, 255, 120), font=font)
    for name, p in marks.items():
        u = p[0] if v["axis"] == "x" else p[1]
        x, y = px(u, p[2])
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 40, 200))
        d.text((x + 5, y - 6), name, fill=(255, 120, 230), font=font)
    im.save("%s_%s_grid.png" % (prefix, view))
print("grid drawn on", prefix)
