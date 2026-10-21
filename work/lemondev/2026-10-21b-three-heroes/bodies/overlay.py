"""Grid over rest_look renders (ortho, square): python -I overlay.py <png> <view front|back> <bounds mn x,y,z> <mx x,y,z> [scale=1.05] [cz]
x every 0.02 (labels each 0.1), height fraction h every 0.02."""
import sys, numpy as np
from PIL import Image, ImageDraw
png, view = sys.argv[1], sys.argv[2]
mn = np.array([float(v) for v in sys.argv[3].split(",")]); mx = np.array([float(v) for v in sys.argv[4].split(",")])
k = float(sys.argv[5]) if len(sys.argv) > 5 else 1.05
im = Image.open(png).convert("RGB"); S = im.size[0]; d = ImageDraw.Draw(im)
H = mx[2] - mn[2]; size = H * k; c = (mn + mx) / 2
cz = float(sys.argv[6]) if len(sys.argv) > 6 else c[2]
sign = 1 if view == "front" else -1
def X(x): return (0.5 + sign * (x - c[0]) / size) * S
def Z(h): return (0.5 - (mn[2] + h * H - cz) / size) * S
for gx in np.arange(-0.4, 0.4001, 0.02):
    major = abs(gx * 10 - round(gx * 10)) < 1e-6
    d.line([(X(gx), 0), (X(gx), S)], fill=(255, 70, 70) if major else (150, 110, 110), width=1)
    if major: d.text((X(gx) + 2, 2), "x%.1f" % gx, fill=(255, 255, 0))
for gh in np.arange(0, 1.0001, 0.02):
    major = abs(gh * 10 - round(gh * 10)) < 1e-6
    d.line([(0, Z(gh)), (S, Z(gh))], fill=(60, 160, 255) if major else (100, 110, 150), width=1)
    d.text((2, Z(gh) + 1), "%.2f" % gh, fill=(120, 255, 255))
im.save(png.replace(".png", "_grid.png"))
