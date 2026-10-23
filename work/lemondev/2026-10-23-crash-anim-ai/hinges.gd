extends SceneTree
## The elbow and knee hinge axes of the hero rig, read from motion-capture clips: each frame's forearm / shin turn
## against its rest pose as an axis and angle (in the bone's own rest frame), averaged over frames bent > 25 deg.

func _init() -> void:
	var lib: AnimationLibrary = load("res://assets/characters/hero/mocap/hero_mocap.res")
	var n: Node = (load("res://assets/characters/heroes17/dracoxinia.glb") as PackedScene).instantiate()
	var sk: Skeleton3D = n.find_children("*", "Skeleton3D", true, false)[0]
	for bone in ["forearm.L", "forearm.R", "shin.L", "shin.R"]:
		var bi := sk.find_bone(bone)
		var rest := sk.get_bone_rest(bi).basis.get_rotation_quaternion()
		var acc := Vector3.ZERO
		var cnt := 0
		var spread := 0.0
		var axes: Array = []
		for clip in ["drac_run", "kai_run", "araki_run", "emel_run", "greatsword_run", "araki_cut_1", "emel_slash_1",
				"bf_club_1", "thy_slash_1", "kai_thrust_1", "araki_idle", "drac_idle"]:
			if not lib.has_animation(clip):
				continue
			var a: Animation = lib.get_animation(clip)
			var t := a.find_track(NodePath("Skeleton3D:" + bone), Animation.TYPE_ROTATION_3D)
			if t < 0:
				continue
			for k in a.track_get_key_count(t):
				var q: Quaternion = a.track_get_key_value(t, k)
				var d := rest.inverse() * q
				if d.w < 0.0:
					d = -d
				var ang := d.get_angle()
				if ang < deg_to_rad(25.0):
					continue
				var ax := d.get_axis()
				acc += ax * ang
				axes.append(ax)
				cnt += 1
		var mean := acc.normalized()
		for ax: Vector3 in axes:
			spread = maxf(spread, rad_to_deg(ax.angle_to(mean)))
		print(bone, " hinge(local) ", mean, " frames ", cnt, " worst off ", snappedf(spread, 0.1), " deg")
		# also: the rest frame axes in model space
		var g := sk.get_bone_global_rest(bi).basis
		print("   model-space hinge ", (g * mean).normalized(), "  bone Y ", g.y.normalized())
	quit()
