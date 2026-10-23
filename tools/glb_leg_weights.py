"""Skirt panels and leg plates that a stride must not stretch (run 2026-10-23).

tools/blender/hero_body.py's hanging-cloth rule gives a skirt's vertices a share of the hips. On Dracoxinia it also
caught the plates on the backs of her calves (loose pieces wholly below the knee), so every stride stretched them back
toward the hips, and her long side panels mix hips, thigh and shin vertex by vertex, so a stride stretched their tips
into long thin strips (20-30 times their length). This gives each skirt panel one smooth hips-to-thigh blend (no shin)
and each plate below the knee its shin and foot alone, inside the GLB's own buffers: the file keeps every other byte
(materials, textures, the skeleton).

    python tools/glb_leg_weights.py assets/characters/heroes17/dracoxinia.glb [--dry]

A plate: all of it below the knees (a knee guard: up to 3 cm above), a third or more on a shin or foot. A panel: a piece hanging from no higher than
just above the hips to below the knee, a sixth or more on the hips and under a quarter on the shins. Rebuilding the body
with hero_body.py loses the fix: run this again after.
"""
import json
import struct
import sys

import numpy as np

COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    data = open(path, "rb").read()
    magic, ver, length = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67, "not a GLB"
    off = 12
    chunks = []
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunks.append([ctype, bytearray(data[off + 8:off + 8 + clen])])
        off += 8 + clen
    gltf = json.loads(chunks[0][1].decode("utf8"))
    return gltf, chunks


def view(gltf, binbuf, acc_i):
    acc = gltf["accessors"][acc_i]
    bv = gltf["bufferViews"][acc["bufferView"]]
    dt = COMP[acc["componentType"]]
    n = NCOMP[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or np.dtype(dt).itemsize * n
    count = acc["count"]
    if stride == np.dtype(dt).itemsize * n:
        arr = np.frombuffer(binbuf, dtype=dt, count=count * n, offset=start).reshape(count, n)
        return arr, start, stride
    rows = [np.frombuffer(binbuf, dtype=dt, count=n, offset=start + i * stride) for i in range(count)]
    return np.array(rows), start, stride


def pieces(index, nverts):
    parent = np.arange(nverts)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    tri = index.reshape(-1, 3)
    for a, b, c in tri:
        for x, y in ((a, b), (b, c)):
            rx, ry = find(x), find(y)
            if rx != ry:
                parent[rx] = ry
    return np.array([find(i) for i in range(nverts)])


def main():
    path = sys.argv[1]
    dry = "--dry" in sys.argv
    gltf, chunks = load(path)
    binbuf = chunks[1][1]
    skin = gltf["skins"][0]
    jname = [gltf["nodes"][j].get("name", "") for j in skin["joints"]]
    ji = {n: i for i, n in enumerate(jname)}
    # knee height: the shin joints' rest translation chain is awkward to rebuild here; the inverse bind matrices give
    # each joint's rest position directly
    ibm, _, _ = view(gltf, binbuf, skin["inverseBindMatrices"])
    def rest(name):
        m = ibm[ji[name]].reshape(4, 4).T
        inv = np.linalg.inv(m)
        return inv[:3, 3]
    knee_y = min(rest("shin.L")[1], rest("shin.R")[1])
    hip_y = rest("thigh.L")[1]
    ankle_y = min(rest("foot.L")[1], rest("foot.R")[1])
    J = {n: ji[n] for n in ("hips", "spine", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R", "toe.L", "toe.R")}
    legs = {J[n] for n in ("shin.L", "shin.R", "foot.L", "foot.R", "toe.L", "toe.R")}
    hipset = {J["hips"], J["spine"]}
    thighs = {J["thigh.L"], J["thigh.R"]}
    total = 0
    for mesh in gltf["meshes"]:
        for prim in mesh["primitives"]:
            at = prim["attributes"]
            if "JOINTS_0" not in at or "WEIGHTS_0" not in at or "indices" not in prim:
                continue
            pos, _, _ = view(gltf, binbuf, at["POSITION"])
            joints, jstart, jstride = view(gltf, binbuf, at["JOINTS_0"])
            weights, wstart, wstride = view(gltf, binbuf, at["WEIGHTS_0"])
            idx, _, _ = view(gltf, binbuf, prim["indices"])
            roots = pieces(idx.reshape(-1), len(pos))
            w = weights.astype(np.float64).copy()
            jn = joints.astype(np.int64).copy()
            for r in np.unique(roots):
                vs = np.where(roots == r)[0]
                share = lambda js: sum(w[v, k] for v in vs for k in range(4) if int(jn[v, k]) in js) / len(vs)
                hips_s, thigh_s, leg_s = share(hipset), share(thighs), share(legs)
                y0, y1 = pos[vs, 1].min(), pos[vs, 1].max()
                if y1 < knee_y + 0.03 and leg_s >= 0.3:
                    # rule 1: a plate wholly below the knee follows the shin and foot alone
                    if hips_s + thigh_s < 0.01:
                        continue
                    move = hipset | (thighs if y1 < knee_y - 0.06 else set())
                    for v in vs:
                        moved = 0.0
                        best_k, best_w = -1, -1.0
                        for k in range(4):
                            j = int(jn[v, k])
                            if j in move and w[v, k] > 0.0:
                                moved += w[v, k]
                                w[v, k] = 0.0
                            elif j in legs and w[v, k] > best_w:
                                best_k, best_w = k, w[v, k]
                        if moved > 0.0 and best_k >= 0:
                            w[v, best_k] += moved
                    total += 1
                    continue
                # rule 2: a skirt panel (hangs from the hips past the knee, moved mostly by the hips and thighs):
                # one smooth blend over the whole piece, the hips at its top easing to 40% thigh at its hem, so a
                # stride swings it without stretching it
                if not (hips_s >= 0.15 and leg_s < 0.25 and y0 < knee_y + 0.12 and y1 < hip_y + 0.15):
                    continue
                cx = pos[vs, 0].mean()
                for v in vs:
                    f = min(1.0, max(0.0, (hip_y - pos[v, 1]) / max(0.05, hip_y - ankle_y)))
                    t = 0.10 + 0.30 * f
                    if abs(cx) < 0.06:
                        row = [(J["hips"], 1.0 - t), (J["thigh.L"], t * 0.5), (J["thigh.R"], t * 0.5), (J["spine"], 0.0)]
                    else:
                        side = "thigh.L" if cx > 0 else "thigh.R"
                        row = [(J["hips"], 1.0 - t), (J[side], t), (J["spine"], 0.0), (J["shin.L"], 0.0)]
                    for k in range(4):
                        jn[v, k], w[v, k] = row[k]
                total += 1
                print("panel of %d vertices, height %.2f..%.2f, centre x %.2f: smooth hips-thigh blend" % (
                    len(vs), y0, y1, cx))
            if not dry:
                ow = w.astype(np.float32) if weights.dtype == np.float32 else w.astype(weights.dtype)
                oj = jn.astype(joints.dtype)
                for i in range(len(ow)):
                    binbuf[wstart + i * wstride: wstart + i * wstride + ow.itemsize * 4] = ow[i].tobytes()
                    binbuf[jstart + i * jstride: jstart + i * jstride + oj.itemsize * 4] = oj[i].tobytes()
    print("%d pieces changed" % total)
    if dry or total == 0:
        return
    js = json.dumps(gltf, separators=(",", ":")).encode("utf8")
    js += b" " * ((4 - len(js) % 4) % 4)
    chunks[0][1] = bytearray(js)
    body = b"".join(struct.pack("<II", len(c[1]), c[0]) + bytes(c[1]) for c in chunks)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


if __name__ == "__main__":
    main()
