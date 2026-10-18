class_name Hero16Fx
extends Node
## Visuals for Roydo, the Anomaly and Blau, the Master Tactician (run 2026-10-16), driven by their sim events, the
## kit's live state (boulders, traps) and the modifiers on units. Units: metres (1 game unit = 1 cm).
##   Roydo: small rocks orbit him (more and faster as the Anomaly); Grip of the Ruler opens a gravity well on the
##   ground, a dark tether hauls the thrown unit along its arc (a violet streak behind it) and the landing implodes and
##   bursts (shockwave, glowing cracks, debris, a camera shake); Void Rush is a dark shell racing out to 650 (enemies
##   then carry a sinking violet ring, allies a rising cyan one); Dark Matter Skin flashes out as a nova with tendrils
##   to everyone it hits; the Anomaly bursts out of him in a flash, burns with violet flame and throws gravity orbs.
##   Blau: tracer shots with a muzzle flash; Bounce Shot's bullet trails a long cyan ribbon and sparks at each
##   ricochet; boulders are rocks veined with cyan light that roll (and kick up dust), settle and crumble away; his
##   trap is a ring of steel jaws on a faint ring of light (hidden from enemies once armed) that snaps shut and chains
##   its catch; turrets are built in a column of light, shoot twin bolts and glow while he pilots one.

const EVENTS := ["grip", "grip_slam", "void_rush", "dark_matter", "anomaly", "bounce_shot", "bounce_shot_move",
	"bounce_shot_bounce", "bounce_shot_hit", "boulders", "boulder_bump", "boulder_hit", "boulder_rest", "boulder_end",
	"lay_trap", "trap_spring", "trap_end", "turret_placed", "turret_expired", "pilot_in", "pilot_out"]
const PROJ := ["bullet", "turret_shot", "gravity_orb"]
const VIOLET := Color(0.62, 0.35, 1.0)
const DEEP := Color(0.35, 0.12, 0.75)
const COSMIC_CYAN := Color(0.45, 0.85, 1.0)
const MAGENTA := Color(1.0, 0.3, 0.75)
const BLAU := Color(0.35, 0.85, 1.0)
const BLAU_HOT := Color(0.85, 0.98, 1.0)

var game: Node
var fx: Fx
var fire: FireFx
var _timed: Array = []                      # {node, t, life, kind, mat, spin, follow, grow}
var _bullets := {}                          # Bounce Shot seq -> {node, trail}
var _boulders := {}                         # boulder id -> {node, rock, dust, mat, rest_t}
var _traps := {}                            # trap seq -> {node, jaws: [a, b], ring, mat, closed_t, target}
var _orbits := {}                           # Roydo unit id -> {node, rocks: [], form}
var _auras := {}                            # unit id + ":" + kind -> node
var _tethers: Array = []                    # {from, to, until, col}: dark beams redrawn as they move
var _chains: Array = []                     # {seq, target, at, until}
var _scan_i := 0
var _rock_meshes: Array = []

# ---- Shaders ---------------------------------------------------------------------------------------------------------

const WELL_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.62, 0.35, 1.0, 1.0);
uniform vec4 col2 : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float fade = 1.0;
uniform float spin = 0.0;
uniform float pull = 0.0;
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	// spiral arms winding in toward the centre
	float arms = sin(a * 4.0 + log(max(r, 0.02)) * 7.0 - spin * 6.0);
	float band = smoothstep(0.35, 1.0, arms) * smoothstep(1.0, 0.15, r) * smoothstep(0.03, 0.25, r);
	float rim = smoothstep(0.88, 0.95, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float hole = 1.0 - smoothstep(0.0, 0.32 + pull * 0.2, r);
	vec3 c = mix(col2.rgb, col.rgb, smoothstep(0.1, 0.8, r));
	ALBEDO = c * (band * 1.6 + rim * 2.2) + vec3(0.0);
	float dark = hole * 0.85;
	ALBEDO = mix(ALBEDO, vec3(0.01, 0.0, 0.03), dark);
	ALPHA = clamp((band * 0.55 + rim * 0.9 + dark * 0.75 + 0.06 * smoothstep(1.0, 0.0, r)) * fade, 0.0, 1.0);
}
"""

const SHELL_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.62, 0.35, 1.0, 1.0);
uniform float fade = 1.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float ripple = 0.5 + 0.5 * sin(UV.y * 80.0 - TIME * 14.0);
	vec3 edge = mix(col.rgb, vec3(0.5, 0.95, 1.0), smoothstep(0.6, 1.0, f));
	ALBEDO = edge * 1.8;
	ALPHA = clamp((f * 0.5 + ripple * f * 0.18) * fade, 0.0, 1.0);
}
"""

const RING_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.35, 0.85, 1.0, 1.0);
uniform float fade = 1.0;
uniform float marks = 8.0;
uniform float spin = 0.0;
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x) + spin;
	float ring = smoothstep(0.80, 0.86, r) * (1.0 - smoothstep(0.90, 0.96, r));
	float inner = smoothstep(0.55, 0.58, r) * (1.0 - smoothstep(0.60, 0.63, r)) * 0.6;
	float tick = step(0.92, cos(a * marks)) * smoothstep(0.64, 0.66, r) * (1.0 - smoothstep(0.76, 0.78, r));
	float fill = (1.0 - smoothstep(0.0, 0.9, r)) * 0.08;
	ALBEDO = col.rgb * 2.0;
	ALPHA = clamp((ring + inner + tick * 0.8 + fill) * fade, 0.0, 1.0);
}
"""

## Blau's boulders: grey-brown stone (procedural, world-locked noise on the rock) split by veins of cyan light that
## pulse; `fade` sinks them into dust at the end, `heat` flares the veins when they hit something.
const BOULDER_CODE := """
shader_type spatial;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float fade = 1.0;
uniform float heat = 0.0;
varying vec3 lp;
float h3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float n3(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1,0,0)), f.x), mix(h3(i + vec3(0,1,0)), h3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(h3(i + vec3(0,0,1)), h3(i + vec3(1,0,1)), f.x), mix(h3(i + vec3(0,1,1)), h3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm3(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * n3(p); p *= 2.1; a *= 0.5; } return v; }
void vertex() { lp = VERTEX; }
void fragment() {
	float m = fbm3(lp * 3.0 + 3.0);
	vec3 rock = texture(tex, UV).rgb * (0.62 + 0.25 * m);
	float vein = smoothstep(0.03, 0.0, abs(fbm3(lp * 0.9 + 7.0) - 0.5));
	float pulse = 0.65 + 0.35 * sin(TIME * 3.0 + lp.y * 8.0);
	ALBEDO = rock;
	ROUGHNESS = 0.9;
	EMISSION = vec3(0.3, 0.85, 1.0) * vein * (pulse * 2.2 + heat * 5.0) * fade;
	if (fade < 0.999) {
		float d = n3(lp * 5.0);
		if (d > fade * 1.1) { discard; }
	}
}
"""

static var _well: Shader
static var _shell: Shader
static var _ring: Shader
static var _boulder_shader: Shader

static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s

func _mat(kind: String) -> ShaderMaterial:
	if _well == null:
		_well = _shader(WELL_CODE)
		_shell = _shader(SHELL_CODE)
		_ring = _shader(RING_CODE)
		_boulder_shader = _shader(BOULDER_CODE)
	var m := ShaderMaterial.new()
	m.shader = {"well": _well, "shell": _shell, "ring": _ring, "boulder": _boulder_shader}[kind]
	return m

func _disc(at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 2.0)
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = at + Vector3(0, 0.07, 0)
	return mi

func _timed_add(node: Node3D, life: float, kind := "", mat: Material = null, spin := 0.0, follow := -1, grow := 0.0) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "kind": kind, "mat": mat, "spin": spin, "follow": follow,
		"grow": grow})

## A rough rock mesh: a sphere pushed in and out by noise (three variants, shared).
func _rock_mesh(i: int) -> ArrayMesh:
	if _rock_meshes.is_empty():
		for v in 3:
			var noise := FastNoiseLite.new()
			noise.seed = 31 + v * 7
			noise.frequency = 1.4
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.height = 2.0
			sph.radial_segments = 18
			sph.rings = 10
			var arrays := sph.get_mesh_arrays()
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for k in verts.size():
				var p := verts[k]
				var d := 1.0 + 0.28 * noise.get_noise_3dv(p * 1.3) + 0.1 * noise.get_noise_3dv(p * 4.0)
				verts[k] = Vector3(p.x * d * 1.05, p.y * d * 0.9, p.z * d)
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for k in idx.size():
				st.add_vertex(verts[idx[k]])
			st.generate_normals()
			_rock_meshes.append(st.commit())
	return _rock_meshes[i % _rock_meshes.size()]

## Blau's boulders: the Quaternius nature kit's medium rocks (CC0, the map's own rocks), centred on their middle so
## they roll about it. {mesh, center, size}
var _boulder_meshes: Array = []
var _rock_tex: Texture2D

func _boulder_mesh(i: int) -> Dictionary:
	if _boulder_meshes.is_empty():
		_rock_tex = load("res://assets/nature/Rocks_Diffuse.png")
		for n in ["Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3"]:
			var ps := load("res://assets/nature/%s.gltf" % n) as PackedScene
			if ps == null:
				continue
			var inst := ps.instantiate()
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			if not mis.is_empty():
				var mesh: Mesh = (mis[0] as MeshInstance3D).mesh
				var bb := mesh.get_aabb()
				_boulder_meshes.append({"mesh": mesh, "center": bb.get_center(), "size": maxf(bb.size.x, bb.size.z)})
			inst.free()
	if _boulder_meshes.is_empty():
		return {}
	return _boulder_meshes[i % _boulder_meshes.size()]

func _rock(radius: float, mat: Material, variant := 0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _rock_mesh(variant)
	mi.material_override = mat
	mi.scale = Vector3.ONE * radius
	return mi

func _unit_hand(uid: int, side := "R") -> Vector3:
	var v := fx._view_of(uid)
	if v == null:
		return Vector3.ZERO
	return v.hand_point(side)

## Blau's rifle muzzle (the "muzzle" bone), else his hands.
func muzzle(uid: int) -> Vector3:
	var v := fx._view_of(uid)
	if v == null:
		return Vector3.ZERO
	if v.skeleton:
		var bi := v.skeleton.find_bone("muzzle")
		if bi >= 0:
			return v.skeleton.global_transform * v.skeleton.get_bone_global_pose(bi).origin
	return v.hand_point("R")

# ---- Events -----------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"grip":
			var at := fx.ground3(e.pos)
			var r := float(e.radius) * View.S
			var wm := _mat("well")
			var well := _disc(at, r, wm)
			_timed_add(well, float(e.dur) + 0.35, "well", wm, 1.4)
			var core := FireFx.embers(r * 0.6, 60.0, 0.6, -0.4, 0.05, VIOLET)
			core.position = at + Vector3(0, 0.3, 0)
			add_child(core)
			fire.timed(core, float(e.dur))
			fx.flash_light(at + Vector3(0, 1.0, 0), VIOLET, 2.5, r * 2.0, float(e.dur))
			var tid := int(e.target)
			if tid >= 0:
				_tethers.append({"from": int(e.u), "to": tid, "until": Time.get_ticks_msec() / 1000.0 + float(e.dur),
					"col": COSMIC_CYAN if bool(e.ally) else VIOLET})
				var tv := fx._view_of(tid)
				if tv:
					var follow := Node3D.new()
					add_child(follow)
					follow.add_child(FireFx.core(0.16, VIOLET, 4.0))
					var tr := Trail3D.make(follow, Color(0.7, 0.45, 1.0, 0.85), 0.22, 0.35)
					add_child(tr)
					_timed.append({"node": follow, "t": 0.0, "life": float(e.dur) + 0.05, "kind": "chest", "mat": null,
						"spin": 0.0, "follow": tid, "grow": 0.0, "trail": tr})
		"grip_slam":
			var at2 := fx.ground3(e.pos)
			var r2 := float(e.radius) * View.S
			_collapse(at2 + Vector3(0, 0.8, 0), 0.9)
			fx.shockwave(at2 + Vector3(0, 0.05, 0), r2, VIOLET, 0.5, 0.3, 3.5)
			fx.force_wall(at2, 0.3, r2, 1.4, DEEP, 0.4)
			fx.crack(at2, r2 * 0.7, Color(0.7, 0.4, 1.0), 2.5)
			fx.flash_light(at2 + Vector3(0, 1.5, 0), Color(0.75, 0.55, 1.0), 6.0, r2 * 2.5, 0.35)
			if fx._seen(View.to2(at2)):
				fx.debris(at2, 10, Color(0.24, 0.2, 0.22), 5.0, 1.0)
				fx._shake(View.to2(at2), 0.35, 0.35)
				var burst := FireFx.embers(r2 * 0.4, 260.0, 0.9, 3.5, 0.06, VIOLET)
				burst.position = at2 + Vector3(0, 0.4, 0)
				add_child(burst)
				fire.timed(burst, 0.25)
			for id in e.get("hits", []):
				fx.impact(fx._chest(int(id), 0.55), VIOLET, 0.35)
		"void_rush":
			var vu: SimUnit = w.get_unit(int(e.u))
			var at3 := fx.ground3(e.pos)
			var r3 := float(e.radius) * View.S
			var sm := _mat("shell")
			var shell := MeshInstance3D.new()
			var sph := SphereMesh.new()
			sph.radius = 1.0
			sph.height = 1.2
			shell.mesh = sph
			shell.material_override = sm
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(shell)
			shell.global_position = at3
			shell.scale = Vector3.ONE * 0.3
			_timed_add(shell, 0.55, "grow", sm, 0.0, -1, r3)
			fx.shockwave(at3 + Vector3(0, 0.05, 0), r3, DEEP, 0.55, 0.25, 3.0)
			fx.flash_light(at3 + Vector3(0, 1.2, 0), VIOLET, 4.0, r3 * 1.5, 0.3)
			if vu:
				fx.sparks(fx._chest(vu.id, 0.6), Vector3.UP, 12, COSMIC_CYAN, 4.0)
			for id in e.get("foes", []):
				fx.impact(fx._chest(int(id), 0.5), DEEP, 0.3)
		"dark_matter":
			var du: SimUnit = w.get_unit(int(e.u))
			if du == null or not fx._seen(du.pos):
				return
			var c := fx._chest(du.id, 0.55)
			var g := fx.ground3(du.pos)
			_collapse(c, 0.45)
			fx.shockwave(g + Vector3(0, 0.05, 0), float(e.radius) * View.S, Color(0.45, 0.15, 0.85), 0.4, 0.12, 3.0)
			fx.flash_light(c, MAGENTA, 3.5, 6.0, 0.2)
			for id in e.get("hits", []):
				var tc := fx._chest(int(id), 0.55)
				fx.lightning(c, tc, Color(0.75, 0.4, 1.0), 0.3, 0.07, 12)
				_collapse(tc, 0.22)
			var dv := fx._view_of(du.id)
			if dv:
				dv.flash()
		"anomaly":
			var au: SimUnit = w.get_unit(int(e.u))
			if au == null:
				return
			var ac := fx._chest(au.id, 0.6)
			var ag := fx.ground3(au.pos)
			_collapse(ac, 0.42)
			fx.shockwave(ag + Vector3(0, 0.05, 0), 3.5, MAGENTA, 0.55, 0.3, 4.0)
			fx.force_wall(ag, 0.4, 3.0, 2.2, Color(0.8, 0.25, 0.85), 0.5)
			fx.crack(ag, 2.2, Color(1.0, 0.35, 0.7), 3.0)
			fx.flash_light(ac, MAGENTA, 8.0, 9.0, 0.45)
			if fx._seen(au.pos):
				fx._shake(au.pos, 0.3, 0.4)
				var b := FireFx.embers(0.6, 300.0, 1.0, 4.0, 0.07, MAGENTA)
				b.position = ac
				add_child(b)
				fire.timed(b, 0.3)
		"bounce_shot":
			var n := Node3D.new()
			add_child(n)
			n.add_child(FireFx.core(0.07, BLAU_HOT, 5.0))
			n.add_child(FireFx.core(0.13, BLAU, 1.2))
			n.add_child(FireFx.light(BLAU, 1.5, 3.5))
			var from: Vector2 = e.from
			n.global_position = fx.ground3(from, 1.35)
			var tr2 := Trail3D.make(n, Color(0.45, 0.9, 1.0, 0.9), 0.14, 0.7)
			add_child(tr2)
			_bullets[int(e.seq)] = {"node": n, "trail": tr2}
			var mz := muzzle(int(e.u))
			if mz != Vector3.ZERO:
				_muzzle_flash(mz, BLAU, 1.6)
		"bounce_shot_move":
			var bl = _bullets.get(int(e.seq))
			if bl != null:
				var bn: Node3D = View.live(bl.node)
				if is_instance_valid(bn):
					bn.global_position = fx.ground3(e.pos, 1.35)
				if bool(e.done):
					(bl.trail as Trail3D).stop()
					if is_instance_valid(bn):
						fx.impact(bn.global_position, BLAU, 0.25)
						fire.timed(bn, 0.0)
					_bullets.erase(int(e.seq))
		"bounce_shot_bounce":
			var p3 := fx.ground3(e.pos, 1.35)
			var nrm: Vector2 = e.normal
			fx.sparks(p3, Vector3(nrm.x, 0.4, -nrm.y), 10, BLAU_HOT, 6.0)
			fx.flash_light(p3, BLAU, 3.0, 3.5, 0.15)
			fx.impact(p3, BLAU, 0.28)
			if String(e.what) == "tree" or String(e.what) == "boulder" or String(e.what) == "wall":
				fx.debris(p3, 3, Color(0.35, 0.3, 0.25), 3.0, 0.5, "chip")
		"bounce_shot_hit":
			var hc := fx._chest(int(e.u), 0.55)
			fx.impact(hc, BLAU_HOT, 0.4)
			fx.sparks(hc, Vector3.UP, 7, BLAU, 4.0)
		"boulders":
			var bu: SimUnit = w.get_unit(int(e.u))
			if bu:
				fx.flash_light(fx._chest(bu.id, 0.6), BLAU, 3.0, 4.0, 0.25)
			for m in e.get("made", []):
				_make_boulder(int(m.id), m.pos)
		"boulder_bump":
			var bb = _boulders.get(int(e.id))
			if bb != null and fx._seen(e.pos):
				var bp := fx.ground3(e.pos, 0.4)
				fx.debris(bp, 3, Color(0.3, 0.27, 0.24), 2.5, 0.5)
				(bb.mat as ShaderMaterial).set_shader_parameter("heat", 1.0)
				bb.heat = 1.0
		"boulder_hit":
			var hp := fx._chest(int(e.u), 0.45)
			fx.impact(hp, BLAU, 0.45)
			fx.sparks(hp, Vector3.UP, 8, Color(0.75, 0.95, 1.0), 4.5)
			var bb2 = _boulders.get(int(e.id))
			if bb2 != null:
				(bb2.mat as ShaderMaterial).set_shader_parameter("heat", 1.0)
				bb2.heat = 1.0
		"boulder_rest":
			var br = _boulders.get(int(e.id))
			if br != null:
				var dust: GPUParticles3D = View.live(br.dust)
				if is_instance_valid(dust):
					dust.emitting = false
				if fx._seen(e.pos):
					var puff := FireFx.smoke(0.5, 30.0, 0.6, 0.9, 0.4, 0.35)
					puff.position = fx.ground3(e.pos, 0.1)
					add_child(puff)
					fire.timed(puff, 0.2)
		"boulder_end":
			var be = _boulders.get(int(e.id))
			if be != null:
				be.ending = 0.0
				if fx._seen(e.pos):
					fx.debris(fx.ground3(e.pos, 0.5), 8, Color(0.3, 0.27, 0.24), 3.0, 0.8)
		"lay_trap":
			var lu: SimUnit = w.get_unit(int(e.u))
			if lu:
				var from3 := fx.ground3(e.pos)
				fx.shockwave(from3 + Vector3(0, 0.05, 0), 0.9, BLAU, 0.35, 0.15, 2.0)
				fx.sparks(from3 + Vector3(0, 0.3, 0), Vector3.UP, 8, BLAU, 3.0)
				var lv := fx._view_of(lu.id)
				if lv and lv.anim and lv.anim.has_animation("blau_jump_air"):
					lv._play("blau_jump_air", true, 1.4, 0.08)
					lv._state = "hop"
				if lv and game.get("caziel_fx") != null:
					game.caziel_fx._ghost(lv, from3, (Vector2(e.to) - Vector2(e.pos)).angle() + PI, 0.0, 0.5)
		"trap_spring":
			var tp = _traps.get(int(e.seq))
			if tp != null:
				tp.closed_t = 0.0
				tp.target = int(e.u)
			var sp := fx.ground3(e.pos, 0.2)
			fx.sparks(sp, Vector3.UP, 12, Color(1.0, 0.9, 0.7), 5.0)
			fx.impact(sp, BLAU, 0.35)
			if bool(e.held):
				_chains.append({"seq": int(e.seq), "target": int(e.u), "at": e.pos,
					"until": Time.get_ticks_msec() / 1000.0 + float(e.dur)})
		"trap_end":
			var te = _traps.get(int(e.seq))
			if te != null:
				te.fading = 0.0
		"turret_placed":
			var tat := fx.ground3(e.pos)
			fx.shockwave(tat + Vector3(0, 0.05, 0), 1.6, BLAU, 0.5, 0.2, 3.0)
			fx.sparks(tat + Vector3(0, 0.6, 0), Vector3.UP, 16, BLAU_HOT, 5.0)
			fx.flash_light(tat + Vector3(0, 1.0, 0), BLAU, 4.0, 5.0, 0.6)
			var col := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.9
			cyl.bottom_radius = 0.9
			cyl.height = 3.0
			cyl.cap_top = false
			cyl.cap_bottom = false
			col.mesh = cyl
			var cm := _mat("shell")
			cm.set_shader_parameter("col", BLAU)
			col.material_override = cm
			col.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(col)
			col.global_position = tat + Vector3(0, 1.5, 0)
			_timed_add(col, 0.7, "fade", cm, 2.0)
			var tv2 := fx._view_of(int(e.turret))
			if tv2 and tv2.model:
				tv2._pop_t = 0.0
		"turret_expired":
			var tu: SimUnit = w.get_unit(int(e.turret))
			if tu and fx._seen(tu.pos):
				var tc2 := fx._chest(tu.id, 0.5)
				fx.sparks(tc2, Vector3.UP, 10, BLAU, 3.5)
				var smk := FireFx.smoke(0.3, 25.0, 0.7, 1.4, 0.8, 0.4)
				smk.position = tc2
				add_child(smk)
				fire.timed(smk, 0.6)
		"pilot_in", "pilot_out":
			var pu: SimUnit = w.get_unit(int(e.u))
			var pt: SimUnit = w.get_unit(int(e.turret))
			var at4 := fx.ground3(pt.pos if pt else (pu.pos if pu else Vector2.ZERO))
			fx.shockwave(at4 + Vector3(0, 0.05, 0), 1.2, BLAU, 0.35, 0.18, 2.5)
			fx.flash_light(at4 + Vector3(0, 1.2, 0), BLAU_HOT, 3.0, 4.0, 0.3)
			fx.sparks(at4 + Vector3(0, 1.0, 0), Vector3.UP, 10, BLAU_HOT, 4.0)

## A gravity collapse: a black sphere with a burning violet rim that swells for a moment and is crushed to nothing,
## then a flash (Roydo's slams, the Anomaly's birth, his orbs). The rim keeps it from reading as a flat black ball.
const COLLAPSE_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, cull_back, shadows_disabled;
uniform vec4 rim : source_color = vec4(0.85, 0.4, 1.0, 1.0);
uniform float k = 0.0;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	ALBEDO = mix(vec3(0.01, 0.0, 0.02), rim.rgb * 2.5, f);
	ALPHA = clamp(0.55 + f * 0.6, 0.0, 1.0) * (1.0 - k * 0.3);
}
"""
static var _collapse_shader: Shader

func _collapse(at: Vector3, size: float, col := Color(0.85, 0.4, 1.0)) -> void:
	if _collapse_shader == null:
		_collapse_shader = _shader(COLLAPSE_CODE)
	var m := ShaderMaterial.new()
	m.shader = _collapse_shader
	m.set_shader_parameter("rim", col)
	var s := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = size * 0.7
	sph.height = size * 1.4
	s.mesh = sph
	s.material_override = m
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(s)
	s.global_position = at
	s.scale = Vector3.ONE * 0.5
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE, 0.06)
	tw.tween_property(s, "scale", Vector3.ONE * 0.03, 0.14).set_ease(Tween.EASE_IN)
	tw.tween_callback(fx.impact.bind(at, col, size * 0.9))
	tw.tween_callback(s.queue_free)

func _muzzle_flash(at: Vector3, col: Color, size := 1.0) -> void:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	var core := FireFx.core(0.06 * size, Color(1.0, 0.95, 0.8), 6.0)
	n.add_child(core)
	n.add_child(FireFx.light(col, 2.2 * size, 3.0))
	_timed_add(n, 0.07, "flash")
	fx.sparks(at, Vector3.UP, 3, Color(1.0, 0.85, 0.5), 3.0)

func _make_boulder(id: int, pos: Vector2) -> void:
	var n := Node3D.new()
	add_child(n)
	var m := _mat("boulder")
	var full := SimKits3.BOULDER_R * View.S
	var rock := MeshInstance3D.new()
	var bm := _boulder_mesh(id)
	if bm.is_empty():
		rock = _rock(full, m, id)
	else:
		# a pivot at the rock's middle; the mesh hangs off it so it turns about its centre
		var mesh_i := MeshInstance3D.new()
		mesh_i.mesh = bm.mesh
		mesh_i.material_override = m
		mesh_i.position = -(bm.center as Vector3)
		rock.add_child(mesh_i)
		m.set_shader_parameter("tex", _rock_tex)
		rock.set_meta("unit", 2.0 / float(bm.size))
	n.add_child(rock)
	rock.position = Vector3(0, full * 0.82, 0)
	rock.rotation = Vector3(0.0, float(id) * 1.7, 0.0)
	var dust := FireFx.smoke(0.45, 22.0, 0.55, 0.8, 0.35, 0.3)
	dust.position = Vector3(0, 0.15, 0)
	n.add_child(dust)
	n.global_position = fx.ground3(pos)
	_boulders[id] = {"node": n, "rock": rock, "dust": dust, "mat": m, "heat": 0.0, "ending": -1.0, "grow": 0.0}
	rock.scale = Vector3.ONE * 0.01

func _make_trap(seq: int, pos: Vector2) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	n.global_position = fx.ground3(pos, 0.02)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.32, 0.34, 0.38)
	steel.metallic = 0.9
	steel.roughness = 0.35
	var base := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.42
	tor.outer_radius = 0.5
	base.mesh = tor
	base.material_override = steel
	n.add_child(base)
	var jaws: Array = []
	for side in 2:
		var hinge := Node3D.new()
		n.add_child(hinge)
		hinge.rotation.y = PI * side
		var jaw := Node3D.new()
		hinge.add_child(jaw)
		jaw.position = Vector3(0, 0.03, 0)
		for k in 7:
			var a := -PI * 0.5 + PI * (float(k) + 0.5) / 7.0
			var tooth := MeshInstance3D.new()
			var pr := PrismMesh.new()
			pr.size = Vector3(0.09, 0.2, 0.04)
			tooth.mesh = pr
			tooth.material_override = steel
			tooth.position = Vector3(cos(a) * 0.46, 0.1, sin(a) * 0.46)
			tooth.rotation.y = -a
			jaw.add_child(tooth)
		hinge.rotation.z = 0.0
		jaws.append(hinge)
	var rm := _mat("ring")
	rm.set_shader_parameter("col", BLAU)
	var ring := _disc(Vector3.ZERO, 0.85, rm)
	ring.reparent(n, false)
	ring.position = Vector3(0, 0.03, 0)
	var t := {"node": n, "jaws": jaws, "ring": ring, "mat": rm, "closed_t": -1.0, "target": -1, "fading": -1.0}
	_traps[seq] = t
	return t

# ---- Projectiles (Fx.projectile hands these styles over) ---------------------------------------------------------------

## The node for one of this kit's projectile styles: {node, trail, h0, start}.
func make_projectile(style: String, src: SimUnit) -> Dictionary:
	var node := Node3D.new()
	var trail: Trail3D = null
	var h0 := 1.4
	var start := Vector3.INF
	match style:
		"bullet":
			node.add_child(FireFx.core(0.05, BLAU_HOT, 9.0))
			trail = Trail3D.make(node, Color(0.85, 0.95, 1.0, 0.85), 0.045, 0.09)
			h0 = 1.45
			var mz := muzzle(src.id)
			if mz != Vector3.ZERO:
				start = mz
				_muzzle_flash(mz, Color(1.0, 0.85, 0.55), 1.0)
		"turret_shot":
			node.add_child(FireFx.core(0.07, BLAU_HOT, 8.0))
			node.add_child(FireFx.core(0.13, BLAU, 2.0))
			trail = Trail3D.make(node, Color(0.4, 0.85, 1.0, 0.85), 0.08, 0.14)
			h0 = 1.05
			var tv := fx._view_of(src.id)
			if tv:
				start = tv.global_position + Vector3(0, 1.05, 0) + tv.global_transform.basis.z * -0.4
				_muzzle_flash(start, BLAU, 1.2)
		"gravity_orb":
			node.add_child(FireFx.core(0.08, Color(0.06, 0.0, 0.1), 0.3))
			node.add_child(FireFx.core(0.12, MAGENTA, 1.4))
			node.add_child(FireFx.embers(0.08, 30.0, 0.35, 0.2, 0.025, MAGENTA))
			node.add_child(FireFx.light(MAGENTA, 1.2, 2.5))
			trail = Trail3D.make(node, Color(0.9, 0.3, 1.0, 0.7), 0.09, 0.22)
			h0 = 1.9
			var hp := _unit_hand(src.id, "R")
			if hp != Vector3.ZERO:
				start = hp
	return {"node": node, "trail": trail, "h0": h0, "start": start}

func projectile_end(style: String, at: Vector3, hit: bool) -> void:
	match style:
		"bullet":
			if hit:
				fx.impact(at, Color(1.0, 0.92, 0.75), 0.18)
				fx.sparks(at, Vector3.UP, 3, Color(1.0, 0.85, 0.55), 3.0)
		"turret_shot":
			fx.impact(at, BLAU, 0.24 if hit else 0.14)
		"gravity_orb":
			_collapse(at, 0.35)
			if hit:
				fx.sparks(at, Vector3.UP, 6, MAGENTA, 3.0)

# ---- Per frame --------------------------------------------------------------------------------------------------------

func update(w: SimWorld, alpha: float, dt: float) -> void:
	_scan_i += 1
	if _scan_i % 4 == 0:
		_scan(w)
	var now := Time.get_ticks_msec() / 1000.0
	for i in range(_timed.size() - 1, -1, -1):
		var t: Dictionary = _timed[i]
		t.t = float(t.t) + dt
		var n: Node3D = View.live(t.node)
		if not is_instance_valid(n) or float(t.t) >= float(t.life):
			if t.has("trail") and is_instance_valid(t.trail):
				(t.trail as Trail3D).stop()
			if is_instance_valid(n):
				fire.timed(n, 0.0)
			_timed.remove_at(i)
			continue
		var k := float(t.t) / float(t.life)
		var follow := int(t.follow)
		if follow >= 0:
			var fv := fx._view_of(follow)
			if fv:
				if String(t.kind) == "chest":
					n.global_position = fv.global_position + Vector3(0, fv.bar_height * 0.5, 0)
				else:
					n.global_position = Vector3(fv.global_position.x, fx.ground_y(View.to2(fv.global_position)) + 0.07,
						fv.global_position.z)
		var m: ShaderMaterial = t.mat
		if m:
			var fade := clampf(minf(float(t.t) / 0.12, (float(t.life) - float(t.t)) / 0.3), 0.0, 1.0)
			m.set_shader_parameter("fade", fade)
			if String(t.kind) == "well":
				m.set_shader_parameter("spin", float(t.t))
				m.set_shader_parameter("pull", k)
		if String(t.kind) == "grow":
			var s := lerpf(0.3, float(t.grow), 1.0 - pow(1.0 - k, 3.0))
			n.scale = Vector3(s, s * 0.55, s)
		elif String(t.kind) == "flash":
			n.scale = Vector3.ONE * (1.0 + k * 1.5)
		if float(t.spin) != 0.0:
			n.rotation.y += float(t.spin) * dt
	_update_tethers(now)
	_update_boulders(w, dt)
	_update_traps(w, dt, now)
	_update_orbits(w, now, dt)
	_update_chains(now)

func _update_tethers(now: float) -> void:
	if Engine.get_frames_drawn() % 3 != 0:
		return
	for i in range(_tethers.size() - 1, -1, -1):
		var t: Dictionary = _tethers[i]
		if now >= float(t.until):
			_tethers.remove_at(i)
			continue
		var a := _unit_hand(int(t.from), "R")
		var b := fx._chest(int(t.to), 0.55)
		if a != Vector3.ZERO and b != Vector3.ZERO:
			fx.lightning(a, b, t.col, 0.1, 0.06, 12)

func _update_boulders(w: SimWorld, dt: float) -> void:
	var live := {}
	for b in w.abilities.kits3.boulders:
		live[int(b.id)] = b
	for id in _boulders.keys():
		var v: Dictionary = _boulders[id]
		var n: Node3D = View.live(v.node)
		if not is_instance_valid(n):
			_boulders.erase(id)
			continue
		var rock: MeshInstance3D = v.rock
		var full := SimKits3.BOULDER_R * View.S
		var unit := float(rock.get_meta("unit", 1.0))
		if float(v.grow) < 1.0:
			v.grow = minf(1.0, float(v.grow) + dt / 0.18)
			rock.scale = Vector3.ONE * full * unit * (0.2 + 0.8 * float(v.grow))
		if float(v.heat) > 0.0:
			v.heat = maxf(0.0, float(v.heat) - dt * 3.0)
			(v.mat as ShaderMaterial).set_shader_parameter("heat", float(v.heat))
		if float(v.ending) >= 0.0:
			v.ending = float(v.ending) + dt
			var f := 1.0 - float(v.ending) / 0.8
			(v.mat as ShaderMaterial).set_shader_parameter("fade", maxf(0.0, f))
			rock.position.y = full * 0.82 - float(v.ending) * 0.4
			if f <= 0.0:
				fire.timed(n, 0.0)
				_boulders.erase(id)
			continue
		var b = live.get(id)
		if b == null:
			continue
		var p2: Vector2 = b.pos
		n.global_position = fx.ground3(p2)
		n.visible = game.sees_cell(p2) or game.own_team(int(b.team))
		var vel: Vector2 = b.vel
		if vel.length() > 1.0:
			# rolling: turn about the axis across the motion (sim x -> view x, sim y -> view -z)
			var axis := Vector3(vel.x, 0.0, -vel.y).normalized().cross(Vector3.UP)
			rock.rotate(axis.normalized(), -vel.length() * View.S * dt / full)

func _update_traps(w: SimWorld, dt: float, now: float) -> void:
	var seen := {}
	for e in w.effects:
		if String(e.kind) != "blau_trap":
			continue
		var seq := int(e.seq)
		seen[seq] = true
		var t: Dictionary = _traps.get(seq, {})
		if t.is_empty():
			t = _make_trap(seq, e.pos)
		var n: Node3D = View.live(t.node)
		if is_instance_valid(n):
			n.visible = w.abilities.kits3.trap_visible(game.player_team, e)
			var armed := w.time >= float(e.arm_at)
			var rm: ShaderMaterial = t.mat
			rm.set_shader_parameter("fade", (0.45 + 0.25 * sin(now * 4.0)) if armed else 0.9)
			rm.set_shader_parameter("spin", now * 0.5)
			for j in 2:
				# open jaws lie flat
				(t.jaws[j] as Node3D).rotation.z = 0.0
	for seq in _traps.keys():
		var t: Dictionary = _traps[seq]
		var n: Node3D = View.live(t.node)
		if not is_instance_valid(n):
			_traps.erase(seq)
			continue
		if float(t.closed_t) >= 0.0:
			# sprung: the jaws snap up and shut over 0.12 s, the trap stays while its catch is held
			n.visible = true
			t.closed_t = float(t.closed_t) + dt
			var c := clampf(float(t.closed_t) / 0.12, 0.0, 1.0)
			for j in 2:
				var hinge: Node3D = t.jaws[j]
				hinge.rotation.z = c * PI * 0.45
			var tv := fx._view_of(int(t.target))
			if tv and float(t.closed_t) < 3.0:
				n.global_position = Vector3(tv.global_position.x, fx.ground_y(View.to2(tv.global_position)) + 0.02,
					tv.global_position.z)
			if float(t.closed_t) > 3.0:
				t.fading = maxf(float(t.fading), 0.0)
		elif not seen.has(seq) and float(t.fading) < 0.0:
			t.fading = 0.0
		if float(t.fading) >= 0.0:
			t.fading = float(t.fading) + dt
			n.scale = Vector3.ONE * maxf(0.01, 1.0 - float(t.fading) / 0.4)
			if float(t.fading) >= 0.4:
				n.queue_free()
				_traps.erase(seq)

## Roydo's orbiting rocks: four small stones on tilted orbits round his chest; six, larger and faster, as the Anomaly.
func _update_orbits(w: SimWorld, now: float, _dt: float) -> void:
	for id in _orbits.keys():
		var o: Dictionary = _orbits[id]
		var n: Node3D = View.live(o.node)
		var v := fx._view_of(int(id))
		var u: SimUnit = w.get_unit(int(id))
		if not is_instance_valid(n) or v == null or u == null:
			if is_instance_valid(n):
				n.queue_free()
			_orbits.erase(id)
			continue
		n.visible = v.visible and u.alive
		if not n.visible:
			continue
		var big := String(v.key) == "hero_anomaly"
		if big != bool(o.form):
			n.queue_free()
			_orbits.erase(id)
			continue
		n.global_position = v.global_position + Vector3(0, v.bar_height * (0.5 if big else 0.55), 0)
		var rocks: Array = o.rocks
		for j in rocks.size():
			var r: Node3D = rocks[j]
			var sp := (1.4 if big else 0.9) * (1.0 + 0.15 * j)
			var a := now * sp + TAU * j / rocks.size()
			var rad := (1.25 if big else 0.85) + 0.08 * sin(now * 1.7 + j)
			var tilt := 0.35 * sin(j * 1.9)
			r.position = Vector3(cos(a) * rad, sin(a) * rad * tilt + 0.15 * sin(now * 2.0 + j), sin(a) * rad)
			r.rotation += Vector3(0.9, 1.3, 0.4) * 0.02

func _update_chains(now: float) -> void:
	if Engine.get_frames_drawn() % 4 != 0:
		return
	for i in range(_chains.size() - 1, -1, -1):
		var c: Dictionary = _chains[i]
		if now >= float(c.until):
			_chains.remove_at(i)
			continue
		var tv := fx._view_of(int(c.target))
		if tv == null or not tv.visible:
			continue
		var base := fx.ground3(View.to2(tv.global_position), 0.1)
		for k in 3:
			var a := TAU * k / 3.0 + now * 0.3
			var anchor := base + Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9)
			fx.lightning(anchor, tv.global_position + Vector3(0, 0.6, 0), Color(0.55, 0.9, 1.0), 0.14, 0.03, 6)

func _scan(w: SimWorld) -> void:
	var want := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView):
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive:
			continue
		if String(u.def.id) == "roydo" and not _orbits.has(id) and v.visible:
			_make_orbit(id, String(v.key) == "hero_anomaly")
		if not v.visible:
			continue
		for m in u.modifiers:
			var f := String(m.get("fx", ""))
			if f in ["void_rush", "void_rush_buff", "anomaly", "piloted", "ensnare"]:
				want[str(id) + ":" + f] = id
	for k in _auras.keys():
		if not want.has(k):
			var old: Node3D = View.live(_auras[k])
			if is_instance_valid(old):
				fire.timed(old, 0.0)
			_auras.erase(k)
	for k in want:
		if not _auras.has(k):
			_auras[k] = _make_aura(String(k).split(":")[1], int(want[k]))
	for k in _auras:
		var a: Node3D = View.live(_auras[k])
		var v2 := fx._view_of(int(want.get(k, -1)))
		if is_instance_valid(a) and v2:
			a.global_position = Vector3(v2.global_position.x, fx.ground_y(View.to2(v2.global_position)) + 0.06,
				v2.global_position.z)

func _make_orbit(id: int, big: bool) -> void:
	var n := Node3D.new()
	add_child(n)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.09, 0.12)
	mat.roughness = 0.55
	mat.metallic = 0.3
	mat.emission_enabled = true
	mat.emission = MAGENTA if big else VIOLET
	mat.emission_energy_multiplier = 0.22
	mat.rim_enabled = true
	mat.rim = 0.6
	var rocks: Array = []
	for j in (6 if big else 4):
		var r := _rock(0.05 + 0.02 * (j % 3) + (0.03 if big else 0.0), mat, j)
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(r)
		rocks.append(r)
		if j % 2 == 0:
			var tr := Trail3D.make(r, Color(0.7, 0.45, 1.0, 0.35) if not big else Color(1.0, 0.35, 0.8, 0.45), 0.04, 0.4)
			add_child(tr)
	_orbits[id] = {"node": n, "rocks": rocks, "form": big}

func _make_aura(kind: String, uid: int) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	match kind:
		"void_rush":
			var rm := _mat("ring")
			rm.set_shader_parameter("col", DEEP)
			rm.set_shader_parameter("marks", 5.0)
			var d := _disc(Vector3.ZERO, 0.75, rm)
			d.reparent(n, false)
			d.position = Vector3(0, 0.05, 0)
			var motes := FireFx.embers(0.5, 14.0, 0.9, -0.6, 0.035, DEEP)
			motes.position = Vector3(0, 1.6, 0)
			n.add_child(motes)
		"void_rush_buff":
			var rm2 := _mat("ring")
			rm2.set_shader_parameter("col", COSMIC_CYAN)
			rm2.set_shader_parameter("marks", 6.0)
			var d2 := _disc(Vector3.ZERO, 0.7, rm2)
			d2.reparent(n, false)
			d2.position = Vector3(0, 0.05, 0)
			var up := FireFx.embers(0.45, 12.0, 0.9, 1.0, 0.03, COSMIC_CYAN)
			up.position = Vector3(0, 0.2, 0)
			n.add_child(up)
		"anomaly":
			var fl := FireFx.flames(0.45, 0.55, 26.0, 0.6, 1.2, "void", 1.4)
			fl.position = Vector3(0, 0.2, 0)
			n.add_child(fl)
			n.add_child(FireFx.embers(0.6, 18.0, 1.2, 1.2, 0.05, MAGENTA))
			var l := FireFx.light(MAGENTA, 1.6, 5.0)
			l.position = Vector3(0, 1.4, 0)
			n.add_child(l)
		"piloted":
			var rm3 := _mat("ring")
			rm3.set_shader_parameter("col", BLAU)
			rm3.set_shader_parameter("marks", 12.0)
			var d3 := _disc(Vector3.ZERO, 1.0, rm3)
			d3.reparent(n, false)
			d3.position = Vector3(0, 0.05, 0)
			var l2 := FireFx.light(BLAU, 2.0, 4.0)
			l2.position = Vector3(0, 1.3, 0)
			n.add_child(l2)
		"ensnare":
			var rm4 := _mat("ring")
			rm4.set_shader_parameter("col", Color(0.55, 0.9, 1.0))
			rm4.set_shader_parameter("marks", 3.0)
			var d4 := _disc(Vector3.ZERO, 0.6, rm4)
			d4.reparent(n, false)
			d4.position = Vector3(0, 0.05, 0)
	return n
