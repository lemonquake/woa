"""Texture colour operations shared by the Blender tools (hero_body.py, extract_prop.py)."""
import numpy as np


def log(*a):
    print("[texops]", *a, flush=True)


def hue_remap(img, HUE="", GRAY=1.0):
    """--hue=from:to:width[:sat[:val]]: colours whose hue lies within width of `from` take the hue `to` (fully over
    the inner 65% of the band, fading out to its edge); saturation and value are multiplied by sat and val there.
    Greys and blacks are untouched (GRAY scales the brightness of unsaturated texels)."""
    parts = [float(x) for x in HUE.split(":")] if HUE else [0.0, 0.0, 0.0001]
    h0, h1, wdt = parts[0] / 360.0, parts[1] / 360.0, parts[2] / 360.0
    sat = parts[3] if len(parts) > 3 else 1.0
    val = parts[4] if len(parts) > 4 else 1.0
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    rgb = px[:, :3]
    mx = rgb.max(1)
    mn = rgb.min(1)
    d = mx - mn
    h = np.zeros(len(rgb), dtype=np.float32)
    nz = d > 1e-6
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    i = nz & (mx == r)
    h[i] = ((g[i] - b[i]) / d[i]) % 6.0
    i = nz & (mx == g)
    h[i] = (b[i] - r[i]) / d[i] + 2.0
    i = nz & (mx == b)
    h[i] = (r[i] - g[i]) / d[i] + 4.0
    h = h / 6.0
    sv = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    dist = np.abs(((h - h0) + 0.5) % 1.0 - 0.5)
    # hues within the band are pulled onto the target (full pull over the inner 65%, fading out to the edge), so a
    # spread of purples all lands on one red instead of rotating into magenta and orange
    f = np.clip((1.0 - dist / wdt) / 0.35, 0.0, 1.0) * nz
    pull = ((h1 - h) + 0.5) % 1.0 - 0.5
    h2 = (h + pull * f) % 1.0
    s2 = np.clip(sv * (1.0 + (sat - 1.0) * f), 0.0, 1.0)
    v2 = np.clip(mx * (1.0 + (val - 1.0) * f), 0.0, 1.0)
    grey = sv < 0.12
    v2 = np.where(grey, np.clip(mx * GRAY, 0.0, 1.0), v2)
    f = np.where(grey & (GRAY != 1.0), 1.0, f)
    hh = h2 * 6.0
    c = v2 * s2
    x = c * (1.0 - np.abs(hh % 2.0 - 1.0))
    m = v2 - c
    out = np.zeros_like(rgb)
    seg = np.floor(hh).astype(np.int32) % 6
    for k_, (a_, b_, c_) in enumerate(((c, x, 0), (x, c, 0), (0, c, x), (0, x, c), (x, 0, c), (c, 0, x))):
        sel = seg == k_
        out[sel, 0] = (a_[sel] if hasattr(a_, "__len__") else a_)
        out[sel, 1] = (b_[sel] if hasattr(b_, "__len__") else b_)
        out[sel, 2] = (c_[sel] if hasattr(c_, "__len__") else c_)
    out += m[:, None]
    px[:, :3] = np.where(f[:, None] > 0, out, rgb)
    img.pixels[:] = px.ravel()
    log("  hue remap %s on %.1f%% of texels" % (HUE, 100.0 * float((f > 0).mean())))
