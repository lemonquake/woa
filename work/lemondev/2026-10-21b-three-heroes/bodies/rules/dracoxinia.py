# Dracoxinia's paint (paint_prep.py rules), the owner's theme: pink and really shiny gold, royalty. Gold on every
# ridge, edge, spike and border; glossy pink enamel on the plate faces and skirt panels; deep magenta dragon scales in
# the recesses (the suit under the plates); pearl horns; the helm's eye slits glow. Rest pose, T-pose, faces -Y.
MATS = [
    {"name": "gold", "c1": (1.0, 0.60, 0.16), "c2": (1.0, 0.80, 0.36), "scale": 60, "rough": (0.05, 0.15), "metal": 1.0, "wear": 0.35, "dirt": 0.45, "wear_rough": 0.05},
    {"name": "pink", "c1": (0.82, 0.10, 0.36), "c2": (0.97, 0.25, 0.52), "scale": 25, "rough": (0.16, 0.28), "metal": 0.35, "wear": 0.25, "dirt": 0.5},
    {"name": "scales", "c1": (0.20, 0.015, 0.09), "c2": (0.62, 0.09, 0.32), "scale": 40, "pattern": "scales", "scale_cells": 260.0, "rough": (0.3, 0.45), "metal": 0.25, "wear": 0.2, "dirt": 0.6},
    {"name": "pearl", "c1": (0.86, 0.70, 0.74), "c2": (1.0, 0.90, 0.88), "scale": 30, "stretch": (1, 1, 4), "rough": (0.18, 0.3), "metal": 0.1, "wear": 0.2, "dirt": 0.35},
    {"name": "glow", "c1": (1.0, 0.75, 0.92), "c2": (1.0, 0.9, 1.0), "scale": 10, "rough": (0.2, 0.2), "wear": 0.0, "dirt": 0.0},
]
AO = 0.8
preview = [[1.0, 0.78, 0.25], [0.95, 0.35, 0.6], [0.45, 0.05, 0.22], [0.95, 0.88, 0.88], [1.0, 1.0, 1.0]]
GOLD, PINK, SCALES, PEARL, GLOW = range(5)


def weights(F, np):
    n = F["n"]
    h, r1, r2, conv, bump = F["h"], F["r1"], F["r2"], F["conv"], F["bump"]
    x, y, nr = F["x"], F["y"], F["nr"]
    sp = F["spread"]
    ax = np.abs(x)
    lab = np.full(n, GOLD)
    # big smooth panels (skirt, breastplate, plate faces): pink enamel
    flat = sp((np.abs(conv) < 0.45).astype(float), 6) > 0.68
    lab[flat] = PINK
    # recesses: the scaled suit between the plates
    lab[sp((r2 < -0.0006).astype(float), 2) > 0.55] = SCALES
    # every edge and ridge stays gold, so each pink panel has a gold border
    edge = sp((conv > 0.7).astype(float), 1) > 0.4
    lab[edge & (lab != SCALES)] = GOLD
    # horns (two arcs over the helm) in pearl, gold at the roots
    horn = (h > 0.875) & (ax > 0.035) & (ax < 0.125) & (np.abs(y + 0.0) < 0.07)
    lab[horn & (h > 0.885)] = PEARL
    # the helm's crest and brow: gold, the mask pink; the eye slits glow
    lab[(h > 0.86) & (ax < 0.012)] = GOLD
    eyes = (h > 0.835) & (h < 0.86) & (ax > 0.008) & (ax < 0.032) & (nr[:, 1] < -0.3) & (r2 < -0.0008)
    lab[eyes] = GLOW
    W = np.zeros((n, len(MATS)))
    W[np.arange(n), lab] = 1.0
    W = sp(W, 1)
    return W, [m["name"] for m in MATS]
