extends SceneTree
## One-off bake: terrain texture sets -> two Texture2DArrays (albedo + roughness in alpha, normal) at 1024 px with
## mipmaps, VRAM compressed, saved under assets/generated/. Re-run when the layer list changes:
##   godot --headless --path . -s tools/bake_terrain_arrays.gd

const DIR := "res://assets/textures/terrain/"
const OUT := "res://assets/generated/"
## Layer order is the terrain shader's numbering (terrain.gdshader).
const LAYERS := ["leafy_grass", "aerial_grass_rock", "rocky_trail", "forest_ground_04", "cliff_side",
	"patterned_paving", "burned_ground_01", "coast_sand_rocks_02", "mossy_cobblestone"]
const SIZE := 1024

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var albedo: Array[Image] = []
	var normal: Array[Image] = []
	for id in LAYERS:
		var a := _load(id + "_albedo.jpg")
		var r := _load(id + "_rough.jpg")
		var n := _load(id + "_normal.jpg")
		# roughness rides in the albedo's alpha channel
		a.convert(Image.FORMAT_RGBA8)
		r.convert(Image.FORMAT_L8)
		for y in SIZE:
			for x in SIZE:
				var c := a.get_pixel(x, y)
				c.a = r.get_pixel(x, y).r
				a.set_pixel(x, y, c)
		a.generate_mipmaps()
		a.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_SRGB)
		n.convert(Image.FORMAT_RGBA8)
		n.generate_mipmaps(true)
		n.compress(Image.COMPRESS_BPTC, Image.COMPRESS_SOURCE_GENERIC)
		albedo.append(a)
		normal.append(n)
		print("baked ", id)
	var ta := Texture2DArray.new()
	ta.create_from_images(albedo)
	var tn := Texture2DArray.new()
	tn.create_from_images(normal)
	print(ResourceSaver.save(ta, OUT + "terrain_albedo.res"), " ", ResourceSaver.save(tn, OUT + "terrain_normal.res"))
	quit()

func _load(file: String) -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(DIR + file))
	img.resize(SIZE, SIZE, Image.INTERPOLATE_LANCZOS)
	return img
