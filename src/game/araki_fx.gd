class_name ArakiFx
extends Node
## Araki's visuals (run 2026-10-19 c). One-shot effects come from his sim events; the thrown bomb and its demon cloud
## are drawn from the sim's live effects every frame (they can never be left behind), auras from modifiers.
## Units: metres (1 game unit = 1 cm).
##   Blur Strike: see-through echoes of him hang along the dash (the same body, frozen mid-cut, fading), a green-white
##   streak and a scorched line on the ground, a crossed cut on everything slashed, a flash where he leaves and lands.
##   Djin Bomb: a black bomb with a spitting green fuse thrown on an arc; it bursts in green fire into a swirling cloud
##   of dark smoke with a demon's two burning eyes and maw light inside; the cloud thins away when it ends.
##   Ghosts of the Will: the ghosts are units (UnitView's ghost shader); a green puff where each appears, their swing
##   played when they strike, a green cut on the target, and a wisp where they vanish.
##   The Blur: a green shockwave, his katana glows and green streaks trail him while it lasts.
##   Senryukai: an enemy carrying many stacks smoulders with green sparks.

const EVENTS := ["blur_strike", "djin_bomb", "djin_smoke", "djin_smoke_end", "ghosts_call", "ghost_spawn",
	"ghost_strike", "ghost_hit", "ghost_poof", "the_blur"]
const GREEN := Color(0.5, 1.0, 0.35)
const PALE := Color(0.85, 1.0, 0.8)
const DARK := Color(0.08, 0.12, 0.1)
const ECHOES := 4                           # echoes along a Blur Strike
const ECHO_LIFE := 0.45

var game: Node
var fx: Fx
var fire: FireFx

var _bombs := {}                            # cloud seq -> {node, from, to, t0, land}
var _clouds := {}                           # cloud seq -> {node, disc, eyes}
var _timed: Array = []                      # {node, t, life, mat, grow}
var _later: Array = []                      # {at, call}: effects that wait a moment (cuts along a dash)
var _echo_pool: Array = []                  # echo bodies, reused: {root, anim, mat, t, busy}
var _auras := {}                            # unit id ":" kind -> node
var _glowing := {}                          # unit id -> true while The Blur lights its katana
var _scan_i := 0
var _clock := 0.0

# ---- Shaders --------------------------------------------------------------------------------------------------------

## A streak of light: brightest down its middle, soft at its ends (UV.x across, UV.y along).
const STREAK_CODE := """
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.55, 1.0, 0.4, 1.0);
uniform float fade = 1.0;
uniform float glow = 2.0;
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float core = pow(across, 3.0);
	float ends = smoothstep(0.0, 0.12, UV.y) * smoothstep(0.0, 0.12, 1.0 - UV.y);
	ALBEDO = mix(col.rgb, vec3(1.0), core * 0.55) * glow;
	ALPHA = clamp(core * ends * fade * 1.2, 0.0, 1.0);
}
"""

## The ground under the demon cloud: dark smoke turning slowly, green light in its arms, soft at the edge.
const CLOUD_CODE := """
shader_type spatial;
render_mode blend_mix, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 col : source_color = vec4(0.45, 1.0, 0.35, 1.0);
uniform float fade = 1.0;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r = length(q);
	float a = atan(q.y, q.x);
	float swirl = a * 2.0 + r * 5.0 - TIME * 1.3;
	vec2 p = vec2(cos(swirl), sin(swirl)) * r * 3.0;
	float smoke = n(p * 1.7 + TIME * 0.3) * 0.6 + n(p * 3.9 - TIME * 0.2) * 0.4;
	float arms = smoothstep(0.55, 0.95, sin(a * 3.0 + log(max(r, 0.04)) * 5.0 - TIME * 2.5) * 0.5 + 0.5);
	float edge = 1.0 - smoothstep(0.75, 1.0, r);
	ALBEDO = mix(vec3(0.015, 0.02, 0.018), col.rgb * 0.9, arms * smoke * 0.2);
	ALPHA = clamp((0.5 + smoke * 0.35) * edge * fade, 0.0, 0.88);
}
"""

static var _shaders := {}

func _mat(kind: String) -> ShaderMaterial:
	if _shaders.is_empty():
		for k in ["streak", "cloud"]:
			var s := Shader.new()
			s.code = STREAK_CODE if k == "streak" else CLOUD_CODE
			_shaders[k] = s
	var m := ShaderMaterial.new()
	m.shader = _shaders[kind]
	return m

## A flat quad `size` metres (x across, y along) at height `lift`, its length along sim direction `dir`.
func _flat(centre: Vector2, size: Vector2, dir: Vector2, mat: Material, lift := 0.06) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	q.orientation = PlaneMesh.FACE_Y
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = fx.ground3(centre, lift)
	mi.rotation.y = atan2(dir.x, -dir.y)
	return mi

func _timed_add(node: Node3D, life: float, mat: ShaderMaterial = null, grow := 0.0) -> void:
	_timed.append({"node": node, "t": 0.0, "life": life, "mat": mat, "grow": grow, "scale": node.scale})

func _puff(at: Vector3, size := 1.0, dark := false) -> void:
	var sm := FireFx.smoke(0.3 * size, 40.0 * size, 0.8 * size, 0.9, 0.7, 0.75 if dark else 0.45)
	if dark:
		_tint_smoke(sm)
	sm.one_shot = true
	sm.explosiveness = 0.9
	add_child(sm)
	sm.global_position = at
	fire.timed(sm, 1.4)
	var e := FireFx.embers(0.3 * size, 50.0 * size, 0.8, 1.6, 0.05, GREEN)
	e.one_shot = true
	e.explosiveness = 0.95
	add_child(e)
	e.global_position = at
	fire.timed(e, 1.0)

## Smoke the colour of the demon's cloud (green-black instead of the usual grey).
func _tint_smoke(sm: GPUParticles3D) -> void:
	var q := sm.draw_pass_1 as QuadMesh
	if q and q.material is ShaderMaterial:
		(q.material as ShaderMaterial).set_shader_parameter("tint", Color(0.03, 0.07, 0.04))

## A crossed cut of light on a unit (Blur Strike, a ghost's blow), turned to the blow's direction.
func _cut(uid: int, dir: Vector2, size := 1.0) -> void:
	var v := fx._view_of(uid)
	if v == null:
		return
	var c := fx._chest(uid, 0.55)
	var p2 := View.to2(c)
	for k in [-0.75, 0.75]:
		var m := _mat("streak")
		m.set_shader_parameter("glow", 2.6)
		var q := _flat(p2, Vector2(0.16 * size, 1.7 * size), dir.rotated(k), m, 0.0)
		q.global_position = c
		_timed_add(q, 0.32, m, 0.35)
	fx.sparks(c, Vector3.UP, 9, PALE, 4.5)
	fx.impact(c, GREEN, 0.32 * size)
	v.flash()

# ---- Echoes ---------------------------------------------------------------------------------------------------------

## A see-through body of Araki frozen in a cut (pooled: built once, reused).
func _echo() -> Dictionary:
	for e in _echo_pool:
		if not bool(e.busy):
			return e
	if _echo_pool.size() >= ECHOES * 3:
		return {}
	var root := Node3D.new()
	add_child(root)
	var model := ModelCatalog.scene("hero_araki").instantiate() as Node3D
	RepairedClips.patch(model)
	model.rotation.y = PI
	root.add_child(model)
	var w := ModelCatalog.weapon("araki_katana")
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if w and not sks.is_empty():
		var sk := sks[0] as Skeleton3D
		var bi := sk.find_bone("weapon.R")
		if bi >= 0:
			var ba := BoneAttachment3D.new()
			ba.bone_name = "weapon.R"
			sk.add_child(ba)
			ba.add_child(w.instantiate())
	var mat := ShaderMaterial.new()
	mat.shader = load("res://src/game/ghost.gdshader")
	mat.set_shader_parameter("col", Color(0.55, 1.0, 0.5))
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var anims := model.find_children("*", "AnimationPlayer", true, false)
	var e := {"root": root, "anim": anims[0] if not anims.is_empty() else null, "mat": mat, "t": 0.0, "busy": false}
	root.visible = false
	_echo_pool.append(e)
	return e

func _show_echo(at: Vector2, facing: float, pose_k: float) -> void:
	var e := _echo()
	if e.is_empty():
		return
	var root: Node3D = e.root
	root.global_position = fx.ground3(at, 0.0)
	root.rotation.y = View.yaw(facing)
	root.visible = true
	var ap: AnimationPlayer = e.anim
	if ap:
		var cfg := ModelCatalog.info("hero_araki")
		var clips: Array = cfg.get("attack", ["gs_1"])
		var clip := String(clips[int(pose_k * 10.0) % clips.size()])
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(ModelCatalog.strike_time(clip) * (0.6 + 0.6 * pose_k), true)
			ap.pause()
	e.busy = true
	e.t = 0.0

func _update_echoes(dt: float) -> void:
	for e in _echo_pool:
		if not bool(e.busy):
			continue
		e.t = float(e.t) + dt
		var k := float(e.t) / ECHO_LIFE
		(e.mat as ShaderMaterial).set_shader_parameter("fade", clampf(1.0 - k, 0.0, 1.0))
		if k >= 1.0:
			e.busy = false
			(e.root as Node3D).visible = false

# ---- Events ---------------------------------------------------------------------------------------------------------

func event(e: Dictionary) -> void:
	var w: SimWorld = game.world
	match String(e.t):
		"blur_strike":
			_blur_strike(e)
		"djin_bomb":
			var seq := int(e.seq)
			var bomb := _make_bomb()
			var from: Vector2 = e.from
			_bombs[seq] = {"node": bomb, "from": fx.ground3(from, 1.5), "to": fx.ground3(e.pos, 0.2), "t0": _clock,
				"land": float(e.land)}
		"djin_smoke":
			var p: Vector2 = e.pos
			var at := fx.ground3(p, 0.3)
			if fx._seen(p):
				fire.burst(at, 1.1, "shadowflame", 1.2)
				fx.shockwave(fx.ground3(p, 0.05), float(e.radius) * View.S * 1.1, GREEN, 0.5, 0.25, 2.5)
				fx.flash_light(at + Vector3(0, 1.0, 0), GREEN, 6.0, 9.0, 0.35)
				_puff(at, 2.2, true)
				fx._shake(p, 0.18, 0.25)
		"djin_smoke_end":
			var p2: Vector2 = e.pos
			if fx._seen(p2):
				_puff(fx.ground3(p2, 0.8), 2.6, true)
		"ghosts_call":
			var cu: SimUnit = w.get_unit(int(e.u))
			if cu and fx._seen(cu.pos):
				fx.shockwave(fx.ground3(cu.pos, 0.05), 1.6, GREEN, 0.45, 0.16, 2.2)
				fx.flash_light(fx._chest(cu.id, 0.6), GREEN, 3.0, 5.0, 0.3)
		"ghost_spawn":
			var g: SimUnit = w.get_unit(int(e.ghost))
			if g and fx._seen(g.pos):
				_puff(fx.ground3(g.pos, 1.0), 0.7)
		"ghost_strike":
			var gv := fx._view_of(int(e.ghost))
			if gv:
				gv.on_attack_start(0.25)
		"ghost_hit":
			var t: SimUnit = w.get_unit(int(e.target))
			var g2: SimUnit = w.get_unit(int(e.ghost))
			if t and fx._seen(t.pos):
				var dir := (t.pos - g2.pos).normalized() if g2 and g2.pos.distance_to(t.pos) > 1.0 else Vector2.RIGHT
				_cut(t.id, dir, 0.8)
		"ghost_poof":
			var gp: Vector2 = e.pos
			if fx._seen(gp):
				_puff(fx.ground3(gp, 1.1), 0.8)
		"the_blur":
			var bu: SimUnit = w.get_unit(int(e.u))
			if bu and fx._seen(bu.pos):
				var c := fx._chest(bu.id, 0.55)
				fire.burst(c, 0.6, "shadowflame", 0.9)
				fx.shockwave(fx.ground3(bu.pos, 0.05), 3.2, GREEN, 0.55, 0.22, 3.0)
				fx.force_wall(fx.ground3(bu.pos), 0.4, 3.0, 1.8, GREEN, 0.4)
				fx.flash_light(c, GREEN, 6.0, 7.0, 0.4)

## Blur Strike: echoes along the dash, the streak, the scorch, a flash at each end, then the cuts in order of the path.
func _blur_strike(e: Dictionary) -> void:
	var w: SimWorld = game.world
	var from: Vector2 = e.from
	var to: Vector2 = e.to
	if not fx._seen(from) and not fx._seen(to):
		return
	var dir := (to - from).normalized() if to.distance_to(from) > 1.0 else Vector2.RIGHT
	var length := from.distance_to(to) * View.S
	var mid := (from + to) * 0.5
	for k in ECHOES:
		var f := float(k + 1) / float(ECHOES + 1)
		_show_echo(from.lerp(to, f * 0.92), dir.angle(), f)
	var sm := _mat("streak")
	sm.set_shader_parameter("glow", 2.4)
	var streak := _flat(mid, Vector2(0.55, length + 0.6), dir, sm, 1.05)
	_timed_add(streak, 0.35, sm)
	var gm := _mat("streak")
	gm.set_shader_parameter("col", Color(0.3, 0.9, 0.25))
	gm.set_shader_parameter("glow", 1.1)
	var scorch := _flat(mid, Vector2(1.1, length + 0.4), dir, gm, 0.05)
	_timed_add(scorch, 0.9, gm)
	for k in 5:
		var p := from.lerp(to, (float(k) + 0.5) / 5.0)
		var em := FireFx.embers(0.25, 30.0, 0.7, 1.2, 0.045, GREEN)
		em.one_shot = true
		em.explosiveness = 0.9
		add_child(em)
		em.global_position = fx.ground3(p, 0.8)
		fire.timed(em, 1.0)
	fx.flash_light(fx.ground3(from, 1.0), GREEN, 3.5, 5.0, 0.25)
	fx.flash_light(fx.ground3(to, 1.0), PALE, 4.5, 6.0, 0.3)
	_puff(fx.ground3(from, 0.6), 0.8, true)
	var hero_hit := false
	for id in e.hits:
		var t: SimUnit = w.get_unit(int(id))
		if t == null:
			continue
		if t.is_hero():
			hero_hit = true
		var along := clampf(from.distance_to(t.pos) / maxf(1.0, from.distance_to(to)), 0.0, 1.0)
		var uid := int(id)
		_later.append({"at": _clock + along * 0.12, "call": func(): _cut(uid, dir, 1.0)})
	if hero_hit and fx._seen(to):
		fx._shake(to, 0.12, 0.18)
	if bool(e.get("again", false)):
		_later.append({"at": _clock + 0.15, "call": func():
			var au: SimUnit = game.world.get_unit(int(e.u))
			if au:
				fx.edge_ring(fx.ground3(au.pos, 0.06), 1.0, GREEN, 0.5)})

# ---- Every frame ----------------------------------------------------------------------------------------------------

func update(w: SimWorld, _alpha: float, dt: float) -> void:
	_clock += dt
	_scan_i += 1
	if _scan_i % 4 == 0:
		_scan(w)
	for i in range(_later.size() - 1, -1, -1):
		if _clock >= float(_later[i].at):
			var c: Callable = _later[i].call
			_later.remove_at(i)
			c.call()
	for i in range(_timed.size() - 1, -1, -1):
		var t: Dictionary = _timed[i]
		t.t = float(t.t) + dt
		var n: Node3D = View.live(t.node)
		if n == null or float(t.t) >= float(t.life):
			if n != null:
				n.queue_free()
			_timed.remove_at(i)
			continue
		var k := float(t.t) / float(t.life)
		if t.mat:
			(t.mat as ShaderMaterial).set_shader_parameter("fade", clampf(1.0 - k, 0.0, 1.0))
		if float(t.grow) > 0.0:
			n.scale = (t.scale as Vector3) * (1.0 + k * float(t.grow))
	_update_echoes(dt)
	_update_bombs(w)
	_follow_auras(w)

func _make_bomb() -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var ball := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.16
	sp.height = 0.32
	ball.mesh = sp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.06, 0.06, 0.07)
	m.metallic = 0.6
	m.roughness = 0.35
	m.emission_enabled = true
	m.emission = Color(0.2, 0.6, 0.15)
	m.emission_energy_multiplier = 0.4
	ball.material_override = m
	n.add_child(ball)
	var fuse := FireFx.embers(0.04, 40.0, 0.35, 0.6, 0.035, GREEN)
	fuse.position = Vector3(0, 0.2, 0)
	n.add_child(fuse)
	var l := FireFx.light(GREEN, 1.2, 2.5)
	l.position = Vector3(0, 0.25, 0)
	n.add_child(l)
	return n

## The bombs in flight and the demon clouds, from the sim's live "djin_smoke" effects.
func _update_bombs(w: SimWorld) -> void:
	var seen := {}
	for e in w.effects:
		if String(e.get("kind", "")) != "djin_smoke":
			continue
		var seq := int(e.seq)
		seen[seq] = true
		var popped := w.time >= float(e.start)
		if not popped and _bombs.has(seq):
			var b: Dictionary = _bombs[seq]
			var bn: Node3D = View.live(b.node)
			if bn:
				var k := clampf((_clock - float(b.t0)) / maxf(0.05, float(b.land)), 0.0, 1.0)
				bn.global_position = (b.from as Vector3).lerp(b.to, k) + Vector3(0, sin(k * PI) * 2.2, 0)
				bn.rotation.x += 0.25
				bn.visible = fx._seen(e.pos)
		if popped:
			if _bombs.has(seq):
				var old: Node3D = View.live(_bombs[seq].node)
				if old:
					old.queue_free()
				_bombs.erase(seq)
			if not _clouds.has(seq):
				_clouds[seq] = _make_cloud(e)
			var cl: Dictionary = _clouds[seq]
			var cn: Node3D = View.live(cl.node)
			if cn:
				cn.visible = fx._seen(e.pos)
				var left := float(e.end) - w.time
				(cl.disc as ShaderMaterial).set_shader_parameter("fade", clampf(minf(left / 0.6, (w.time - float(e.start)) / 0.3), 0.0, 1.0))
				var eyes: Node3D = View.live(cl.eyes)
				if eyes:
					eyes.position.y = 1.6 + sin(_clock * 1.7) * 0.15
					eyes.rotation.y += 0.01
	for seq in _bombs.keys():
		if not seen.has(seq):
			var bn2: Node3D = View.live(_bombs[seq].node)
			if bn2:
				bn2.queue_free()
			_bombs.erase(seq)
	for seq in _clouds.keys():
		if seen.has(seq):
			continue
		var cn2: Node3D = View.live(_clouds[seq].node)
		if cn2:
			for p in cn2.find_children("*", "GPUParticles3D", true, false):
				(p as GPUParticles3D).emitting = false
			var disc: MeshInstance3D = View.live(_clouds[seq].disc_node)
			if disc:
				disc.visible = false
			var eyes2: Node3D = View.live(_clouds[seq].eyes)
			if eyes2:
				eyes2.visible = false
			fire.timed(cn2, 2.2)
		_clouds.erase(seq)

## The demon cloud: a turning disc of dark smoke, smoke rising over it, green embers, and the demon's eyes and maw
## glowing in the middle.
func _make_cloud(e: Dictionary) -> Dictionary:
	var r := float(e.radius) * View.S
	var n := Node3D.new()
	add_child(n)
	n.global_position = fx.ground3(e.pos, 0.0)
	var dm := _mat("cloud")
	var disc := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(r * 2.1, r * 2.1)
	q.orientation = PlaneMesh.FACE_Y
	disc.mesh = q
	disc.material_override = dm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.08
	n.add_child(disc)
	for k in 3:
		var sm := FireFx.smoke(r * (0.4 + 0.2 * k), 14.0 + 4.0 * k, 2.0 + 0.5 * k, 2.6, 0.55, 0.7)
		_tint_smoke(sm)
		sm.position = Vector3(0, 0.3, 0)
		n.add_child(sm)
	var em := FireFx.embers(r * 0.8, 26.0, 1.6, 1.2, 0.05, GREEN)
	em.position = Vector3(0, 0.2, 0)
	n.add_child(em)
	var eyes := Node3D.new()
	eyes.position = Vector3(0, 1.6, 0)
	n.add_child(eyes)
	for sx in [-0.22, 0.22]:
		var eye := FireFx.core(0.055, Color(0.45, 1.0, 0.2), 3.6)
		eye.position = Vector3(sx, 0.0, 0.0)
		eye.scale = Vector3(1.9, 0.55, 1.0)
		eyes.add_child(eye)
	var maw := FireFx.flames(0.12, 0.3, 14.0, 0.5, 0.5, "shadowflame", 1.0)
	maw.position = Vector3(0, -0.35, 0)
	eyes.add_child(maw)
	var l := FireFx.light(GREEN, 1.2, r * 1.0)
	l.position = Vector3(0, 1.4, 0)
	n.add_child(l)
	return {"node": n, "disc": dm, "disc_node": disc, "eyes": eyes}

# ---- Auras (from the modifiers on units) --------------------------------------------------------------------------------

func _scan(w: SimWorld) -> void:
	var want := {}
	var glow := {}
	for id in game.views:
		var v = game.views[id]
		if not (v is UnitView) or not v.visible:
			continue
		var u: SimUnit = w.get_unit(id)
		if u == null or not u.alive or u.modifiers.is_empty():
			continue
		for m in u.modifiers:
			var f := String(m.get("fx", ""))
			match f:
				"the_blur":
					want[str(id) + ":blur"] = id
					glow[id] = true
				"blur_again":
					want[str(id) + ":again"] = id
				"senryukai":
					var n := int(m.get("charges", 0))
					if n >= 4:
						want[str(id) + (":stacks_high" if n >= 10 else ":stacks")] = id
	for k in _auras.keys():
		if not want.has(k):
			var old: Node3D = View.live(_auras[k])
			if old:
				for p in old.find_children("*", "GPUParticles3D", true, false):
					(p as GPUParticles3D).emitting = false
				fire.timed(old, 1.2)
			_auras.erase(k)
	for k in want:
		if not _auras.has(k):
			_auras[k] = _make_aura(String(k).split(":")[1])
	for id in _glowing.keys():
		if not glow.has(id):
			var v2 := fx._view_of(int(id))
			if v2:
				v2.set_weapon_glow(false)
			_glowing.erase(id)
	for id in glow:
		if not _glowing.has(id):
			var v3 := fx._view_of(int(id))
			if v3:
				v3.set_weapon_glow(true, GREEN)
			_glowing[id] = true

func _follow_auras(_w: SimWorld) -> void:
	for k in _auras:
		var a: Node3D = View.live(_auras[k])
		var v := fx._view_of(int(String(k).split(":")[0]))
		if a == null or v == null:
			continue
		a.global_position = Vector3(v.global_position.x, fx.ground_y(View.to2(v.global_position)) + 0.05, v.global_position.z)

func _make_aura(kind: String) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	match kind:
		"blur":
			# streaks that trail him as he moves, rising green sparks, a soft light
			for k in 3:
				var dot := Node3D.new()
				n.add_child(dot)
				dot.position = Vector3(cos(k * TAU / 3.0) * 0.35, 0.6 + k * 0.4, sin(k * TAU / 3.0) * 0.35)
				var tr := Trail3D.make(dot, Color(0.55, 1.0, 0.45, 0.6), 0.07, 0.28)
				add_child(tr)
			var em := FireFx.embers(0.45, 22.0, 0.7, 1.3, 0.04, GREEN)
			em.position = Vector3(0, 0.3, 0)
			n.add_child(em)
			var l := FireFx.light(GREEN, 1.1, 3.5)
			l.position = Vector3(0, 1.3, 0)
			n.add_child(l)
		"again":
			var em2 := FireFx.embers(0.5, 12.0, 0.5, 0.5, 0.035, PALE)
			n.add_child(em2)
		"stacks", "stacks_high":
			var hot := kind == "stacks_high"
			var em3 := FireFx.embers(0.3, 8.0 if not hot else 18.0, 0.7, 0.9, 0.035, GREEN)
			em3.position = Vector3(0, 1.0, 0)
			n.add_child(em3)
			if hot:
				var l2 := FireFx.light(GREEN, 0.6, 2.0)
				l2.position = Vector3(0, 1.2, 0)
				n.add_child(l2)
	return n
