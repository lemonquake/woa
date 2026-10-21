"""Hand remnants (run 2026-10-18 d, the owner's report: "remnants of hands when animating"): mesh that sits at a hand
or forearm in the body's own pose but does not move with that arm, so it is left floating by the hip when the arm
lifts (or torn into a sheet between the two).

For every built body (a GLB on the hero skeleton) it lifts both arms out to the side (and bends the elbows), then
reports, per side:
  * left: vertices that started within reach of the hand or forearm (closer to it than to any trunk or leg bone, and
    within --reach of the bone) and moved less than a third of the way the wrist moved;
  * torn: faces with one vertex that went with the arm and one that stayed (an edge stretched over 3x);
and renders the lifted pose front and back with those vertices red (--png).
  blender -b --factory-startup --python tools/blender/remnant_check.py -- --glb=assets/characters/heroes17/ezee.glb
      [--png=out.png] [--reach=0.12]
"""
import bpy
import math
import os
import sys

import bmesh
import numpy as np
from mathutils import Matrix, Vector

ARGV = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def arg(name, default=None):
    for a in ARGV:
        if a.startswith("--" + name + "="):
            return a.split("=", 1)[1]
    return default


GLB = os.path.abspath(arg("glb"))
PNG = os.path.abspath(arg("png")) if arg("png") else ""
REACH = float(arg("reach", 0.12))
WEIGHTS = arg("weights", "")                 # also render the rest pose with arm weights coloured (left red, right blue)

ARM = {s: ("upper_arm." + s, "forearm." + s, "hand." + s, "weapon." + s) for s in ("L", "R")}
TRUNK = ("hips", "spine", "chest", "neck", "head", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R")


def seg_dist(p, a, b):
    ab = b - a
    t = np.clip(((p - a) @ ab) / max(1e-9, ab @ ab), 0.0, 1.0)
    return np.linalg.norm(p - (a + t[:, None] * ab), axis=1)


def weight_render(arm, meshes, png, height):
    """The rest pose with each vertex coloured by its arm weights: left arm red, right arm blue, the rest grey."""
    for m in meshes:
        names = {g.index: g.name for g in m.vertex_groups}
        cols = np.zeros((len(m.data.vertices), 4), dtype=np.float32)
        for v in m.data.vertices:
            l = sum(g.weight for g in v.groups if names[g.group] in ARM["L"])
            r = sum(g.weight for g in v.groups if names[g.group] in ARM["R"])
            cols[v.index] = (0.6 + 0.4 * l - 0.5 * r, 0.6 - 0.5 * (l + r), 0.6 + 0.4 * r - 0.5 * l, 1.0)
        ca = m.data.color_attributes.new("armw", 'BYTE_COLOR', 'POINT')
        ca.data.foreach_set("color", np.clip(cols, 0, 1).ravel())
        m.data.color_attributes.active_color = ca
    shoot(png, height)
    for m in meshes:
        m.data.color_attributes.remove(m.data.color_attributes["armw"])


def shoot(png, height):
    sc = bpy.context.scene
    sc.render.engine = 'BLENDER_WORKBENCH'
    sc.display.shading.light = 'STUDIO'
    sc.display.shading.color_type = arg('color', 'VERTEX')
    sc.render.resolution_x = int(arg('res', 520))
    sc.render.resolution_y = int(int(arg('res', 520)) * 600 / 520)
    cam = bpy.data.objects.get("cam")
    if cam is None:
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        bpy.context.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = 'ORTHO'
    cam.data.ortho_scale = height * float(arg('zoom', 1.3))
    tiles = []
    for i, yaw in enumerate((0, 180, 90)):
        a = math.radians(yaw)
        hz = height * float(arg('aimz', 0.55))
        pos = Vector((math.sin(a) * 6, -math.cos(a) * 6, hz))
        cam.location = pos
        cam.rotation_euler = (Vector((0, 0, hz)) - pos).to_track_quat('-Z', 'Y').to_euler()
        p = png[:-4] + "_%d.png" % i
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        tiles.append(p)
    print("PNG", ";".join(tiles), flush=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=GLB)
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    meshes = [o for o in bpy.data.objects if o.type == 'MESH' and any(m.type == 'ARMATURE' for m in o.modifiers)]
    if arm.animation_data:
        arm.animation_data.action = None
    arm.data.pose_position = 'POSE'
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    mw = arm.matrix_world
    J = {b.name: (np.array(mw @ b.head_local), np.array(mw @ b.tail_local)) for b in arm.data.bones}
    height = max(J["head"][1][2], 1.0)
    reach = REACH * height / 1.8
    dg = bpy.context.evaluated_depsgraph_get()
    rest = {}
    for m in meshes:
        e = m.evaluated_get(dg)
        me = e.to_mesh()
        co = np.array([mw.inverted() @ (e.matrix_world @ v.co) for v in me.vertices]) if False else \
            np.array([(e.matrix_world @ v.co)[:] for v in me.vertices])
        e.to_mesh_clear()
        rest[m.name] = co
    if WEIGHTS:
        weight_render(arm, meshes, os.path.abspath(WEIGHTS), height)
    wrist0 = {s: np.array((mw @ arm.pose.bones["hand." + s].head)[:]) for s in ("L", "R")}
    # lift: each arm out to the side and up a little, the elbow bent forward; about the bones' world axes so it works
    # on any rest
    for s, sx in (("L", 1.0), ("R", -1.0)):
        for bn, target in (("upper_arm." + s, Vector((sx, 0.0, 0.25))), ("forearm." + s, Vector((sx * 0.6, -0.8, 0.3))),
                           ("hand." + s, Vector((sx * 0.6, -0.8, 0.3)))):
            pb = arm.pose.bones[bn]
            bpy.context.view_layer.update()
            cur = (mw @ pb.tail) - (mw @ pb.head)
            q = cur.normalized().rotation_difference(target.normalized())
            head = mw @ pb.head
            M = mw @ pb.matrix
            R = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head)
            pb.matrix = mw.inverted() @ (R @ M)
            bpy.context.view_layer.update()
    wrist1 = {s: np.array((mw @ arm.pose.bones["hand." + s].head)[:]) for s in ("L", "R")}
    dg = bpy.context.evaluated_depsgraph_get()
    total = {"L": [0, 0], "R": [0, 0]}
    for m in meshes:
        e = m.evaluated_get(dg)
        me = e.to_mesh()
        co1 = np.array([(e.matrix_world @ v.co)[:] for v in me.vertices])
        e.to_mesh_clear()
        co0 = rest[m.name]
        if len(co0) != len(co1):
            continue
        moved = np.linalg.norm(co1 - co0, axis=1)
        trunk_d = np.min(np.stack([seg_dist(co0, *J[b]) for b in TRUNK if b in J], axis=1), axis=1)
        bad = np.zeros(len(co0), dtype=bool)
        for s in ("L", "R"):
            d = np.minimum(seg_dist(co0, *J["forearm." + s]), seg_dist(co0, *J["hand." + s]))
            near = (d < reach) & (d < trunk_d)
            # the forearm's own surface near the elbow moves less than the wrist does: compare with how far the
            # point on the arm nearest it moved
            ab = J["hand." + s][1] - J["upper_arm." + s][0]
            t = np.clip(((co0 - J["upper_arm." + s][0]) @ ab) / (ab @ ab), 0.0, 1.0)
            expect = np.linalg.norm(wrist1[s] - wrist0[s]) * t
            left = near & (moved < expect * 0.33) & (t > 0.55)
            total[s][0] += int(left.sum())
            bad |= left
        # torn faces: an edge that grew over 3x (and by more than 4 cm)
        bm = bmesh.new()
        bm.from_mesh(m.data)
        ed = np.array([(e_.verts[0].index, e_.verts[1].index) for e_ in bm.edges])
        bm.free()
        if len(ed):
            l0 = np.linalg.norm(co0[ed[:, 0]] - co0[ed[:, 1]], axis=1)
            l1 = np.linalg.norm(co1[ed[:, 0]] - co1[ed[:, 1]], axis=1)
            torn = (l1 > l0 * 3.0) & (l1 - l0 > 0.04 * height / 1.8)
            for s in ("L", "R"):
                side = (co0[ed[:, 0], 0] > 0) if s == "L" else (co0[ed[:, 0], 0] <= 0)
                total[s][1] += int((torn & side).sum())
            bad[ed[torn].ravel()] = True
        if PNG:
            ca = m.data.color_attributes.new("remnant", 'BYTE_COLOR', 'POINT')
            cols = np.where(bad[:, None], [[1.0, 0.05, 0.05, 1.0]], [[0.62, 0.62, 0.62, 1.0]]).astype(np.float32)
            ca.data.foreach_set("color", cols.ravel())
            m.data.color_attributes.active_color = ca
    name = os.path.basename(GLB)
    print("REMNANTS %-22s left L %5d R %5d   torn edges L %4d R %4d" % (name, total["L"][0], total["R"][0],
          total["L"][1], total["R"][1]), flush=True)
    if PNG:
        shoot(PNG, height)


main()
