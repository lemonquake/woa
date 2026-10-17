"""Azrael's new body source (2026-10-17 f): the owner's azrael.glb (a rigged dress-and-armour model with two swords)
made into the Death Dealer before tools/blender/hero_body.py binds it to the hero skeleton.

  * the two swords are dropped (her weapon is the great scythe, assets/weapons/scythe.glb);
  * the dress, gloves and cape go black (the red cloth keeps its folds as near-black with a cold sheen);
  * the gold armour plates become dark steel with pale silver edges;
  * the hair turns silver-white, the skin a touch cooler, the lips dark wine.

Writes <out>/azrael_src.blend (+ its recoloured textures next to it); feed that to hero_body.py:
  blender -b --factory-startup --python tools/blender/azrael_prep.py -- --src=work/downloads/sf_heroes/azrael.glb
          --out=work/azrael_src
"""
import bpy
import os
import sys
import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OPT = {a.split("=", 1)[0][2:]: a.split("=", 1)[1] for a in ARGS if a.startswith("--") and "=" in a}
SRC = OPT.get("src", "A:/Python/woa/work/downloads/sf_heroes/azrael.glb")
OUT = os.path.abspath(OPT.get("out", "A:/Python/woa/work/azrael_src"))


def log(*a):
    print("[azrael_prep]", *a, flush=True)


def hsv(rgb):
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
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h * 60.0, s, mx


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def hue_near(h, centre, width):
    d = np.abs(((h - centre) + 180.0) % 360.0 - 180.0)
    return 1.0 - smooth(width * 0.6, width, d)


def uv_mask(objs, w, h):
    """Texels covered by the UV triangles of these meshes (the skin piece shares the outfit's atlas)."""
    mask = np.zeros((h, w), dtype=bool)
    for o in objs:
        me = o.data
        uv = me.uv_layers.active.data
        me.calc_loop_triangles()
        for t in me.loop_triangles:
            p = np.array([uv[i].uv[:] for i in t.loops], dtype=np.float64) * np.array([w, h])
            x0, y0 = np.floor(p.min(0)).astype(int)
            x1, y1 = np.ceil(p.max(0)).astype(int)
            x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, w - 1), min(y1, h - 1)
            if x1 < x0 or y1 < y0:
                continue
            xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a, b, c = p
            d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
            if abs(d) < 1e-12:
                continue
            l1 = ((b[1] - c[1]) * (xs - c[0]) + (c[0] - b[0]) * (ys - c[1])) / d
            l2 = ((c[1] - a[1]) * (xs - c[0]) + (a[0] - c[0]) * (ys - c[1])) / d
            e = 1.5 / max(1.0, abs(d) ** 0.5)
            inside = (l1 >= -e) & (l2 >= -e) & (1.0 - l1 - l2 >= -e)
            mask[y0:y1 + 1, x0:x1 + 1] |= inside
    return mask


SKIN = None                                    # flat mask of the skin texels, set before the atlas is recoloured


def outfit(rgb):
    """The body atlas (dress, armour and skin share it)."""
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    # red cloth -> black: keep the folds (value) but crush it, with a faint cold blue-violet sheen
    notskin = 1.0 - SKIN.astype(np.float32) if SKIN is not None else np.ones(len(rgb), dtype=np.float32)
    red = hue_near(h, 355.0, 28.0) * smooth(0.30, 0.45, s)
    cloth = np.stack([v * 0.15, v * 0.15, v * 0.19], 1) + 0.012
    # gold and cream armour -> dark steel; the brightest edges stay a pale silver
    gold = hue_near(h, 38.0, 30.0) * smooth(0.06, 0.16, s) * (1.0 - red) * notskin
    steel_v = 0.10 + 0.55 * smooth(0.35, 0.95, lum) ** 1.6
    steel = np.stack([steel_v * 0.92, steel_v * 0.95, steel_v * 1.05], 1)
    out = rgb * (1.0 - red - gold)[:, None] + cloth * red[:, None] + steel * gold[:, None]
    # the skin piece's texels: a touch paler and cooler
    skin = (1.0 - notskin) * (1.0 - red)
    pale = np.stack([lum * 0.98, lum * 0.97, lum * 1.0], 1)
    out = out * (1.0 - 0.3 * skin)[:, None] + pale * (0.3 * skin)[:, None]
    log("  atlas: cloth %.1f%%, armour %.1f%%" % (100.0 * float((red > 0.5).mean()), 100.0 * float((gold > 0.5).mean())))
    return out


def hair(rgb):
    lum = rgb @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    v = np.clip(0.30 + lum * 0.85, 0.0, 1.0)
    return np.stack([v * 0.93, v * 0.95, v * 1.0], 1)


def face(rgb):
    h, s, v = hsv(rgb)
    lum = rgb @ np.array([0.30, 0.59, 0.11], dtype=np.float32)
    lips = hue_near(h, 355.0, 22.0) * smooth(0.35, 0.5, s)
    pale = np.stack([lum * 0.98, lum * 0.97, lum * 1.0], 1)
    wine = np.stack([v * 0.42, v * 0.08, v * 0.14], 1)
    out = rgb * 0.7 + pale * 0.3
    return out * (1.0 - lips)[:, None] + wine * lips[:, None]


def recolour(img, fn, name):
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(-1, 4)
    px[:, :3] = np.clip(fn(px[:, :3]), 0.0, 1.0)
    new = bpy.data.images.new(name, w, h, alpha=True)
    new.pixels[:] = px.ravel()
    new.filepath_raw = os.path.join(OUT, name + ".png")
    new.file_format = 'PNG'
    new.save()
    new.filepath = new.filepath_raw
    log("  wrote", new.filepath_raw)
    return new


os.makedirs(OUT, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
for o in list(bpy.data.objects):
    mats = " ".join(s.material.name for s in o.material_slots if s.material) if o.type == 'MESH' else ""
    if o.type == 'MESH' and ("Weapon" in mats or o.name.startswith("Icosphere")):
        log("dropped", o.name, mats)
        bpy.data.objects.remove(o, do_unlink=True)

# the hair bones' rest pose in the download is broken (heads at the origin): the hair only sits on her head through
# the armature's pose. Bake what is shown into the meshes and make that pose the rest, so every piece is bound where
# it is seen.
arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
skinned = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
for o in skinned:
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    for m in [m for m in o.modifiers if m.type == 'ARMATURE']:
        bpy.ops.object.modifier_apply(modifier=m.name)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active = arm
arm.select_set(True)
bpy.ops.object.mode_set(mode='POSE')
bpy.ops.pose.select_all(action='SELECT')
bpy.ops.pose.armature_apply(selected=False)
bpy.ops.object.mode_set(mode='OBJECT')
for o in skinned:
    m = o.modifiers.new("Armature", 'ARMATURE')
    m.object = arm
log("baked the shown pose into %d pieces and made it the rest pose" % len(skinned))

done = {}
RULES =(("_Hair_", hair, "azrael_hair"), ("_Face_", face, "azrael_face"), ("_Skin_", outfit, "azrael_outfit"),
         ("DSword_005_MI", outfit, "azrael_outfit"))
for m in bpy.data.materials:
    if not m.node_tree or not m.users or "Weapon" in m.name:
        continue
    rule = next((r for r in RULES if r[0] in m.name), None)
    if rule is None:
        continue
    bsdf = next((n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED'), None)
    if bsdf is None or not bsdf.inputs["Base Color"].links:
        continue
    node = bsdf.inputs["Base Color"].links[0].from_node
    if node.type != 'TEX_IMAGE' or node.image is None:
        continue
    key = node.image.name
    if key not in done and rule[1] is outfit:
        users = [o for o in bpy.data.objects if o.type == 'MESH' and any(s.material and "_Skin_" in s.material.name
                                                                        for s in o.material_slots)]
        w, h = node.image.size
        SKIN = uv_mask(users, w, h).ravel()
        log("  skin texels %.1f%% (%s)" % (100.0 * float(SKIN.mean()), [o.name for o in users]))
    if key not in done:
        done[key] = recolour(node.image, rule[1], rule[2])
    node.image = done[key]
    log("material", m.name, "->", done[key].name)

path = os.path.join(OUT, "azrael_src.blend")
bpy.ops.wm.save_as_mainfile(filepath=path)
log("saved", path)
