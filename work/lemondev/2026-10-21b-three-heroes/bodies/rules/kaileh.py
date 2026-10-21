# Lord Kaileh's paint (paint_prep.py rules): dark brushed steel plate with gold trim, dark leather straps and belt,
# a crimson loincloth, a brown fur collar, weathered skin, a dark beard. Regions are polygons and bands in (x, h)
# read off the rest-pose front / back renders with a grid (look/kfeat_*_grid.png); h = height fraction, x in model
# units (the model faces -Y; its right hand is at -x). Geometry then refines them: plate edges and studs turn gold.
MATS = [
    {"name": "skin", "c1": (0.27, 0.145, 0.095), "c2": (0.40, 0.23, 0.155), "scale": 35, "rough": (0.42, 0.6), "wear": 0.05, "dirt": 0.5},
    {"name": "steel", "c1": (0.09, 0.095, 0.105), "c2": (0.19, 0.195, 0.21), "scale": 90, "stretch": (1, 1, 14), "rough": (0.34, 0.55), "metal": 1.0, "wear": 1.8, "dirt": 0.6, "wear_rough": 0.15},
    {"name": "gold", "c1": (0.74, 0.50, 0.17), "c2": (0.93, 0.70, 0.30), "scale": 70, "rough": (0.16, 0.3), "metal": 1.0, "wear": 0.35, "dirt": 0.55},
    {"name": "leather", "c1": (0.11, 0.065, 0.04), "c2": (0.21, 0.12, 0.065), "scale": 120, "rough": (0.48, 0.72), "wear": 0.7, "dirt": 0.45},
    {"name": "cloth", "c1": (0.24, 0.025, 0.035), "c2": (0.40, 0.05, 0.06), "scale": 80, "stretch": (1, 1, 6), "rough": (0.75, 0.95), "wear": 0.3, "dirt": 0.55},
    {"name": "fur", "c1": (0.09, 0.06, 0.045), "c2": (0.30, 0.21, 0.13), "scale": 160, "stretch": (1, 1, 5), "rough": (0.8, 1.0), "wear": 0.1, "dirt": 0.7},
    {"name": "beard", "c1": (0.16, 0.10, 0.075), "c2": (0.26, 0.17, 0.12), "scale": 220, "rough": (0.6, 0.8), "wear": 0.2, "dirt": 0.3},
    {"name": "trousers", "c1": (0.09, 0.08, 0.075), "c2": (0.16, 0.14, 0.12), "scale": 90, "stretch": (1, 1, 4), "rough": (0.7, 0.9), "wear": 0.4, "dirt": 0.5},
]
AO = 0.95
preview = [[0.85, 0.6, 0.5], [0.35, 0.4, 0.5], [1.0, 0.75, 0.2], [0.35, 0.2, 0.1], [0.7, 0.05, 0.08], [0.55, 0.45, 0.3],
           [0.1, 0.08, 0.06], [0.2, 0.2, 0.25]]
SKIN, STEEL, GOLD, LEATHER, CLOTH, FUR, BEARD, TROUSERS = range(8)


def inpoly(x, y, poly, np):
    P = np.array(poly, float)
    inside = np.zeros(len(x), bool)
    j = len(P) - 1
    for i in range(len(P)):
        xi, yi = P[i]
        xj, yj = P[j]
        c = ((yi > y) != (yj > y)) & (x < (xj - xi) * (y - yi) / ((yj - yi) + 1e-12) + xi)
        inside ^= c
        j = i
    return inside


def band(x, y, a, b, w, np):
    a, b = np.array(a, float), np.array(b, float)
    p = np.c_[x, y]
    ab = b - a
    t = np.clip(((p - a) @ ab) / (ab @ ab), 0, 1)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1) < w / 2


def mirror(poly):
    return [(-px, py) for px, py in poly]


def weights(F, np):
    n = F["n"]
    h, b, br, r1, conv, bump = F["h"], F["bone"], F["brad"], F["r1"], F["conv"], F["bump"]
    x, ny = F["x"], F["nr"][:, 1]
    sp = F["spread"]
    front = ny < 0.0
    has = lambda *k: np.array([any(s in nm for s in k) for nm in b])
    hand = has("Hand") & ~has("ForeArm")
    fore = has("ForeArm")
    arm = np.isin(b, ["LeftArm", "RightArm"])
    leg = np.isin(b, ["LeftLeg", "RightLeg"])
    foot = has("Foot", "Toe")
    upleg = has("UpLeg")
    ax = np.abs(x)
    lab = np.full(n, LEATHER)
    # ---- trunk and head
    lab[h > 0.87] = SKIN                                                       # head
    lab[(h > 0.835) & (ax < 0.045)] = SKIN                                     # neck
    lab[(h > 0.866) & (h < 0.903) & (ax < 0.042) & front & (bump > 0.02)] = BEARD
    chest = (h > 0.69) & (h < 0.845) & (ax < 0.125)
    lab[chest] = SKIN
    # fur collar (front, round the neck) and the fur over the back
    lab[(h > 0.83) & (h < 0.945) & (ax > 0.042) & (ax < 0.125) & front] = FUR
    back_fur = inpoly(x, h, [(-0.13, 0.945), (0.13, 0.945), (0.13, 0.86), (0.03, 0.79), (0.0, 0.775), (-0.03, 0.79),
                              (-0.13, 0.86)], np) & ~front
    lab[back_fur] = FUR
    lab[(h > 0.68) & (h < 0.80) & (ax < 0.135) & ~front & ~back_fur & (lab != FUR)] = SKIN   # bare back
    # straps (bandoliers) over the chest and back
    straps = (front & (band(x, h, (-0.105, 0.845), (0.07, 0.69), 0.034, np) | band(x, h, (0.095, 0.835), (-0.06, 0.70), 0.03, np))) | \
             (~front & band(x, h, (-0.06, 0.84), (0.115, 0.675), 0.04, np))
    lab[straps & (h < 0.86)] = LEATHER
    # shoulders: vertical plates beside the collar, pauldrons, upper-arm plates
    lab[(h > 0.78) & (h < 0.935) & (ax > 0.115) & (ax < 0.165) & (front | (h > 0.845))] = STEEL
    paul = (ax > 0.13) & (h > 0.735) & (h < 0.915) & (has('Shoulder') | arm) & ~((ax < 0.17) & (h < 0.80) & front & (lab == FUR))
    paul &= front | (ax > 0.158) | (h > 0.84)
    lab[paul] = STEEL
    lab[arm & (h < 0.745) & (h > 0.62)] = SKIN                                  # biceps
    lab[arm & (h < 0.745) & (h > 0.6) & (ax > 0.235)] = STEEL                   # outer arm plates
    lab[arm & (h > 0.705) & (ax > 0.16) & (F['nr'][:, 2] < -0.3)] = STEEL                   # plate undersides
    # forearms: steel bracers over leather wraps; hands bare
    lab[fore] = STEEL
    lab[fore & (h < 0.585) & (br < 0.04)] = LEATHER
    lab[hand | ((h < 0.56) & (ax > 0.2))] = SKIN
    lab[(arm | fore) & (h > 0.665) & (h < 0.742) & (ax < 0.232) & (F['nr'][:, 2] > -0.3) & (bump < 0.05)] = SKIN   # biceps over the elbow
    # belt, buckle, loincloth
    belt = (h > 0.62) & (h < 0.70) & (ax < 0.17)
    lab[belt] = LEATHER
    lab[(h > 0.585) & (h < 0.625) & (ax < 0.17) & ~front] = CLOTH               # sash over the back
    lab[inpoly(x, h, [(-0.065, 0.695), (0.065, 0.695), (0.07, 0.64), (0.0, 0.585), (-0.07, 0.64)], np) & front & (r1 > -0.0005)] = GOLD
    loin_f = inpoly(x, h, [(-0.07, 0.625), (0.06, 0.625), (0.05, 0.40), (0.0, 0.29), (-0.05, 0.40)], np) & front
    lab[loin_f & (ax < 0.07)] = CLOTH
    loin_b = (h > 0.37) & (h < 0.6) & (ax < 0.15) & ~front & (br > 0.07)
    lab[loin_b] = CLOTH
    # legs: dark trousers, leather straps, steel knees and greaves, boots
    lab[upleg & (h < 0.6) & ~loin_f & ~loin_b] = TROUSERS
    lab[(upleg | has('Hips')) & (h > 0.38) & (h < 0.62) & (br > 0.088) & front & ~loin_f] = LEATHER   # hanging flaps
    lab[upleg & (h > 0.383) & (h < 0.425) & front] = LEATHER                     # thigh strap
    lab[(h > 0.25) & (h < 0.365) & front & (ax > 0.05)] = STEEL                 # knee cops
    lab[leg & front & (h < 0.30)] = STEEL                                       # greaves
    lab[leg & ~front & (h < 0.36)] = LEATHER                                    # wraps behind
    lab[foot | (h < 0.11)] = LEATHER                                            # boots
    lab[(h < 0.11) & front & (ny < -0.35)] = STEEL                              # boot caps
    # ---- gold trim: plate edges, studs, spikes
    steel = lab == STEEL
    edge = sp((conv > 1.2).astype(float), 1) > 0.5
    lab[steel & edge] = GOLD
    stud = (r1 > 0.003) & (conv > 1.4) & ~np.isin(lab, [SKIN, BEARD, FUR, CLOTH])
    lab[stud] = GOLD
    W = np.zeros((n, len(MATS)))
    W[np.arange(n), lab] = 1.0
    W = sp(W, 1)
    return W, [m["name"] for m in MATS]
