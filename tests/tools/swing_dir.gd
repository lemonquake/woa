extends SceneTree
## Which way a weapon's head moves during a clip's hit, in the weapon's own frame (grip at the origin, +Y along the
## shaft): for orienting blades that must lead the swing (Azrael's scythe).
##   godot --headless --path . -s tests/tools/swing_dir.gd -- [--clips=gs_1,gs_2,gs_3,gs_4] [--head=1.3]

var _n := 0

func _process(_dt: float) -> bool:
	_n += 1
	if _n == 3:
		_measure()
		return true
	return false

func _measure() -> void:
	var clips := ["gs_1", "gs_2", "gs_3", "gs_4", "gs_heavy"]
	var head := 1.3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clips="):
			clips = Array(a.substr(8).split(","))
		elif a.begins_with("--head="):
			head = float(a.substr(7))
	var m := (load("res://assets/characters/hero/hero.glb") as PackedScene).instantiate() as Node3D
	RepairedClips.patch(m)
	root.add_child(m)
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var pl: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	pl.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var bi := sk.find_bone("weapon.R")
	for c in clips:
		if not pl.has_animation(c):
			print(c, ": missing")
			continue
		var meta := ModelCatalog.clip(String(c))
		var hits: Array = meta.get("hits", [[0.3, 0.4]])
		var t0 := float(hits[0][0])
		var t1 := float(hits[0][1])
		var sums := Vector3.ZERO
		var n := 0
		pl.play(c)
		var steps := 8
		var prev := Vector3.INF
		for k in steps + 1:
			var t := lerpf(t0 - 0.05, t1, float(k) / steps)
			pl.seek(t, true)
			pl.advance(0.0)
			var pose := sk.get_bone_global_pose(bi)
			var p := pose * Vector3(0, head, 0)
			if prev != Vector3.INF:
				var v := p - prev
				sums += pose.basis.inverse() * v
				n += 1
			prev = p
		var d := sums / maxf(1, n)
		print("%s: head moves in weapon frame x %+.3f  y %+.3f  z %+.3f" % [c, d.x, d.y, d.z])
