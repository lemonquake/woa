extends SceneTree
## Renders a hero look in several outfits side by side (needs a window): for choosing a hero's default look.
##   godot --path . -s tests/tools/look_lineup.gd -- --hero=azrin --out=work/shots/lineup.png [--anim=idle_mage]
## The outfits tried are the OUTFITS list below, each on the hero's default look.

const OUTFITS := [
	{},
	{"armor": "ember_dragonhide", "gloves": "silk_glove", "boots": "sage_boots"},
	{"armor": "tc_sanguine_leathers", "leggings": "magister_silks", "boots": "sage_boots", "helm": "seers_circlet"},
	{"inner_garment": "silk_undershirt", "armor": "tc_arcanist_vestments", "boots": "sage_boots"},
	{"armor": "magister_robe", "gloves": "silk_glove", "helm": "seers_circlet"},
	{"inner_garment": "silk_undershirt", "leggings": "magister_silks", "gloves": "silk_glove", "boots": "sage_boots",
		"helm": "seers_circlet", "accessory_1": "sunforged_medallion"},
]

var _n := 0
var _out := "work/shots/lineup.png"

func _init() -> void:
	var hero := "azrin"
	var anim := "idle_mage"
	var only: Array = []
	var dist := 9.6
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			hero = a.substr(7)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--anim="):
			anim = a.substr(7)
		elif a.begins_with("--only="):
			only = Array(a.substr(7).split(",")).map(func(x): return int(x))
		elif a.begins_with("--dist="):
			dist = float(a.substr(7))
	root.size = Vector2i(1800, 900)
	var world := Node3D.new()
	root.add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.19, 0.2)
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	world.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 32.0
	world.add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.3 + (9.6 - dist) * 0.04, dist), Vector3(0, 1.0 + (9.6 - dist) * 0.06, 0), Vector3.UP)
	var base := GameSettings.default_look(hero)
	var picks: Array = only if not only.is_empty() else range(OUTFITS.size())
	for j in picks.size():
		var i: int = picks[j]
		var m := (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate() as Node3D
		world.add_child(m)
		m.position = Vector3((j - (picks.size() - 1) * 0.5) * 1.15, 0, 0)
		var ap := HeroAppearance.new(m)
		ap.apply(base.look)
		ap.dress(OUTFITS[i], base.dyes)
		var pl: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		if pl.has_animation(anim):
			pl.play(anim)

func _process(_dt: float) -> bool:
	_n += 1
	if _n == 40:
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://" + _out))
		print("saved ", _out)
		return true
	return false
