class_name OrbView
extends Node3D
## Orbs on the map (SimOrbs): a glowing shape floating over a ring on the ground, turning and bobbing, with a light,
## coloured by kind. Shown only where your team has vision (Dota shows runes in sight only). Rebuilt from the sim's
## list every frame, so nothing outlives the orb it shows.

const COLORS := {"gold": Color(1.0, 0.78, 0.25), "rejuvenation": Color(0.78, 0.4, 1.0), "wisdom": Color(0.7, 0.45, 1.0),
	"speed": Color(1.0, 0.3, 0.2), "damage": Color(0.25, 0.45, 1.0), "stealth": Color(0.55, 0.85, 0.95),
	"healing": Color(0.35, 1.0, 0.35), "magic": Color(1.0, 0.35, 0.95), "shield": Color(1.0, 0.95, 0.6)}

var game: Node
var fx: Fx
var _nodes := {}                            # orb id -> Node3D

func frame(_dt: float) -> void:
	var w: SimWorld = game.world
	var seen := {}
	var t := Time.get_ticks_msec() / 1000.0
	for o in w.orbs.orbs:
		var id := int(o.id)
		seen[id] = true
		var n: Node3D = _nodes.get(id)
		if n == null:
			n = _make(String(o.kind))
			add_child(n)
			_nodes[id] = n
		var p: Vector2 = o.pos
		n.visible = game.sees_cell(p)
		n.global_position = fx.ground3(p)
		var core: Node3D = n.get_child(0)
		core.position.y = 0.95 + 0.12 * sin(t * 2.4 + id)
		core.rotation.y = t * 1.6
		var motes: Node3D = core.get_node_or_null("Motes")
		if motes:
			motes.rotation.y = -t * 4.0
	for id in _nodes.keys():
		if not seen.has(id):
			(_nodes[id] as Node).queue_free()
			_nodes.erase(id)

func _make(kind: String) -> Node3D:
	var col: Color = COLORS.get(kind, Color(1, 1, 1))
	var root := Node3D.new()
	var core := Node3D.new()
	root.add_child(core)
	var mi := MeshInstance3D.new()
	match kind:
		"gold":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.26
			cyl.bottom_radius = 0.26
			cyl.height = 0.07
			mi.mesh = cyl
			mi.rotation.x = PI * 0.5
		"rejuvenation":
			# a purple heart of light in a glassy rim-lit shell, a tilted halo turning round it
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			mi.mesh = sm
			var shell := MeshInstance3D.new()
			var sh := SphereMesh.new()
			sh.radius = 0.3
			sh.height = 0.6
			shell.mesh = sh
			var smat := ShaderMaterial.new()
			smat.shader = _shell_shader()
			smat.set_shader_parameter("col", col)
			shell.material_override = smat
			shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			core.add_child(shell)
			var halo := MeshInstance3D.new()
			var hm := TorusMesh.new()
			hm.inner_radius = 0.36
			hm.outer_radius = 0.39
			hm.rings = 48
			hm.ring_segments = 6
			halo.mesh = hm
			halo.rotation = Vector3(0.55, 0.0, 0.3)
			halo.material_override = fx._glow(col.lightened(0.3), 5.0)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			core.add_child(halo)
		_:
			var pm := PrismMesh.new()
			pm.size = Vector3(0.36, 0.42, 0.36)
			mi.mesh = pm
			var low := MeshInstance3D.new()
			low.mesh = pm
			low.rotation.z = PI
			low.position.y = -0.42
			low.material_override = fx._glow(col, 3.5)
			low.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			core.add_child(low)
			mi.position.y = 0.0
	mi.material_override = fx._glow(col.lightened(0.45), 8.0) if kind == "rejuvenation" else fx._glow(col, 3.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.add_child(mi)
	# three small motes circling the orb
	var motes := Node3D.new()
	motes.name = "Motes"
	core.add_child(motes)
	for i in 3:
		var m := fx._sphere(0.05, fx._glow(col.lightened(0.4), 6.0))
		var a := i * TAU / 3.0
		m.position = Vector3(cos(a) * 0.42, 0.1 * sin(a * 2.0), sin(a) * 0.42)
		motes.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 1.4
	l.omni_range = 3.2
	core.add_child(l)
	# a faint ring on the ground under it
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.5
	ring.mesh = tm
	ring.scale = Vector3(1, 0.05, 1)
	ring.position.y = 0.06
	var rm := fx._glow(Color(col.r, col.g, col.b, 0.6), 2.0)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return root

static var _shell: Shader

## The Rejuvenation Orb's shell: clear in the middle, glowing purple at the rim, with slow swirling bands.
static func _shell_shader() -> Shader:
	if _shell == null:
		_shell = Shader.new()
		_shell.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;
uniform vec4 col : source_color = vec4(0.78, 0.4, 1.0, 1.0);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec3 p = normalize((INV_VIEW_MATRIX * vec4(VERTEX, 0.0)).xyz);
	float bands = 0.5 + 0.5 * sin(p.y * 9.0 + atan(p.z, p.x) * 2.0 - TIME * 2.2);
	ALBEDO = col.rgb * (rim * 2.6 + bands * 0.35 * (1.0 - rim));
	ALPHA = 1.0;
}
"""
	return _shell

## The orb under a screen point (-1 if none): within 40 px of where it floats.
func pick(cam: Camera3D, screen: Vector2) -> int:
	var best := -1
	var bd := 40.0
	for id in _nodes:
		var n: Node3D = View.live(_nodes[id])
		if not n.visible:
			continue
		var p3 := n.global_position + Vector3(0, 0.95, 0)
		if cam.is_position_behind(p3):
			continue
		var d := cam.unproject_position(p3).distance_to(screen)
		if d < bd:
			bd = d
			best = int(id)
	return best
