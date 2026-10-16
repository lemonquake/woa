extends SceneTree
## Azrael look variants side by side (needs a window): hood, hair and idle choices on her spirit body, with her scythe.
##   godot --path . -s tests/tools/azrael_look.gd -- --out=work/shots/azrael_look.png [--close] [--frame=40]
## The variants are the VARIANTS list below, each on her default look.

const VARIANTS := [
	{"helm": "depth_gloomthread_crown", "hair": "long", "idle": "idle_spear"},
	{"helm": "sage_hood", "hair": "long", "idle": "idle_spear"},
	{"helm": "linen_hood", "hair": "long", "idle": "idle_staff"},
	{"helm": "depth_gloomthread_crown", "hair": "pigtails", "idle": "idle_mage"},
	{"helm": "sage_hood", "hair": "braids", "idle": "idle_1h"},
]

var _n := 0
var _out := "work/shots/azrael_look.png"
var _frame := 40

func _init() -> void:
	var close := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a == "--close":
			close = true
		elif a.begins_with("--frame="):
			_frame = int(a.substr(8))
	root.size = Vector2i(1900, 950)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.15, 0.17)
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30.0
	world.add_child(cam)
	if close:
		cam.look_at_from_position(Vector3(0, 2.0, 6.2), Vector3(0, 1.85, 0), Vector3.UP)
	else:
		cam.look_at_from_position(Vector3(0, 1.6, 10.5), Vector3(0, 1.25, 0), Vector3.UP)
	var cfg := ModelCatalog.info("hero_azrael")
	var base := GameSettings.default_look("azrael")
	for j in VARIANTS.size():
		var v: Dictionary = VARIANTS[j]
		var m := (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate() as Node3D
		RepairedClips.patch(m)
		world.add_child(m)
		m.position = Vector3((j - (VARIANTS.size() - 1) * 0.5) * 1.45, float(cfg.get("float", 0.0)), 0)
		var ap := HeroAppearance.new(m)
		var lk: Dictionary = (base.look as Dictionary).duplicate()
		lk["hair"] = v.hair
		ap.apply(lk)
		var outfit: Dictionary = (base.outfit as Dictionary).duplicate()
		if String(v.helm) == "":
			outfit.erase("helm")
		else:
			outfit["helm"] = v.helm
		ap.dress(outfit, base.dyes)
		ap.set_spirit(cfg.spirit)
		var ps := ModelCatalog.weapon(String(cfg.R))
		if ps and ap.skeleton:
			var at := BoneAttachment3D.new()
			at.bone_name = "weapon.R"
			ap.skeleton.add_child(at)
			at.add_child(ps.instantiate())
		var pl: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		if pl.has_animation(String(v.idle)):
			pl.play(String(v.idle))

func _process(_dt: float) -> bool:
	_n += 1
	if _n == _frame:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://" + _out))
		print("saved ", _out)
		return true
	return false
