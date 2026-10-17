"""Tile the cells mocap_retarget.py rendered (<clip>__<view>_<frame>.png) into contact sheets: one row per clip (two
rows: front-left and side views), several clips per page, the clip name and its report line on top.
  python tools/mocap_sheet.py <cells dir> <out dir> [--per=6] [--only=regex]
"""
import os
import re
import sys

from PIL import Image, ImageDraw

cells, out = sys.argv[1], sys.argv[2]
per = 6
only = ""
for a in sys.argv[3:]:
    if a.startswith("--per="):
        per = int(a[6:])
    elif a.startswith("--only="):
        only = a[7:]
os.makedirs(out, exist_ok=True)
rep = {}
rp = os.path.join(cells, "report.txt")
if os.path.exists(rp):
    for line in open(rp):
        if line.strip():
            rep[line.split()[0]] = line.strip()
clips = {}
for f in os.listdir(cells):
    m = re.match(r"(.+)__(\d)_(\d\d)\.png$", f)
    if m and (not only or re.search(only, m.group(1))):
        clips.setdefault(m.group(1), []).append((int(m.group(2)), int(m.group(3)), f))
names = sorted(clips)
W = H = None
for page in range(0, len(names), per):
    group = names[page:page + per]
    rows = []
    for n in group:
        fs = sorted(clips[n])
        views = sorted({v for v, _, _ in fs})
        imgs = {(v, k): Image.open(os.path.join(cells, f)).convert("RGB") for v, k, f in fs}
        w, h = next(iter(imgs.values())).size
        ncol = max(k for _, k, _ in fs) + 1
        row = Image.new("RGB", (w * ncol, h * len(views) + 22), (30, 30, 34))
        d = ImageDraw.Draw(row)
        d.text((6, 4), rep.get(n, n), fill=(255, 255, 160))
        for (v, k), im in imgs.items():
            row.paste(im, (k * w, 22 + views.index(v) * h))
        rows.append(row)
    sheet = Image.new("RGB", (max(r.width for r in rows), sum(r.height for r in rows)), (0, 0, 0))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height
    p = os.path.join(out, "sheet_%02d.png" % (page // per))
    sheet.save(p)
    print(p, ", ".join(group))
