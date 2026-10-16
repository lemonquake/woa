extends SceneTree
## Snap check for the run 2026-10-16 models (Roydo, the Anomaly, Blau, the turret): every clip, every bone, frame by
## frame at 30 fps (headless). A "pop" is a joint whose rotation relative to its parent turns more than 45 degrees
## between two frames (a visible snap of that joint, not just a fast swing of the whole limb); a "flip" more than 90.
## Finger tips (the rig's *_leaf bones, which skin nothing) are skipped. Elbows and knees bent backwards: each joint's
## natural bend axis is learned from all of the model's clips (the way it bends most), and a frame counts when the
## joint is bent more than 12 degrees the other way.
##   godot --headless --path . -s tests/tools/anim_pops16.gd [-- --out=work/.../anim_pops16.txt]

const MODELS := ["roydo", "anomaly", "blau", "blau_turret"]
const FPS := 30.0
const POP := 45.0
const FLIP := 90.0

var _out := ""
var lines: Array = []

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	_run.call_deferred()

func say(s: String) -> void:
	lines.append(s)
	print(s)

func _run() -> void:
	var total_pops := 0
	var total_flips := 0
	var total_hyper := 0
	for m in MODELS:
		var scene := load("res://assets/characters/heroes16/%s.glb" % m) as PackedScene
		var inst := scene.instantiate() as Node3D
		root.add_child(inst)
		var ap: AnimationPlayer = inst.find_children("*", "AnimationPlayer", true, false)[0]
		var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		say("== %s (%d clips, %d bones)" % [m, ap.get_animation_list().size(), sk.get_bone_count()])
		for clip in ap.get_animation_list():
			var anim := ap.get_animation(clip)
			var n := int(ceil(anim.length * FPS))
			var prev: Array = []
			var worst := 0.0
			var worst_bone := ""
			var pops := 0
			var flips := 0
			var hyper := 0
			ap.play(clip)
			for f in range(n + 1):
				ap.seek(minf(anim.length, f / FPS), true)
				ap.advance(0.0)
				var cur: Array = []
				for b in sk.get_bone_count():
					cur.append(sk.get_bone_pose_rotation(b))
				if not prev.is_empty():
					for b in sk.get_bone_count():
						if sk.get_bone_name(b).contains("leaf"):
							continue
						var q1: Quaternion = prev[b]
						var q2: Quaternion = cur[b]
						var ang := rad_to_deg(q1.angle_to(q2))
						if ang > worst:
							worst = ang
							worst_bone = sk.get_bone_name(b)
						if ang > FLIP:
							flips += 1
						elif ang > POP:
							pops += 1
				prev = cur
				_sample_joints(sk, clip)
			total_pops += pops
			total_flips += flips
			var flag := "" if pops == 0 and flips == 0 else "   <-- pops %d, flips %d" % [pops, flips]
			say("  %-24s %5.2f s  largest joint turn in one frame %5.1f deg (%s)%s" % [clip, anim.length, worst, worst_bone, flag])
		var bad := _judge_joints()
		for k in bad:
			say("  bent backwards: %s %d frames" % [k, bad[k]])
			total_hyper += int(bad[k])
		_samples.clear()
		inst.queue_free()
	say("\nTOTAL pops (>45 deg / frame) %d, flips (>90) %d, frames with an elbow or knee bent backwards %d" % [total_pops, total_flips, total_hyper])
	if _out != "":
		var f := FileAccess.open(_out, FileAccess.WRITE)
		f.store_string("\n".join(lines) + "\n")
	quit()

const JOINTS := ["lowerarm_l", "lowerarm_r", "calf_l", "calf_r"]
var _samples := {}                         # joint -> [[clip, rotation vector (axis * angle, degrees)], ...]

func _sample_joints(sk: Skeleton3D, clip: String) -> void:
	for j in JOINTS:
		var b := sk.find_bone(j)
		if b < 0:
			continue
		var q := sk.get_bone_rest(b).basis.get_rotation_quaternion().inverse() * sk.get_bone_pose_rotation(b)
		var ang := rad_to_deg(q.get_angle())
		if ang > 180.0:
			ang -= 360.0
		var axis := q.get_axis() if absf(ang) > 0.01 else Vector3.ZERO
		if not _samples.has(j):
			_samples[j] = []
		(_samples[j] as Array).append([clip, axis * ang])

## The natural axis of each joint (the sum of its strong bends), then the frames bent more than 12 degrees against it.
func _judge_joints() -> Dictionary:
	var out := {}
	for j in _samples:
		var acc := Vector3.ZERO
		for smp in _samples[j]:
			var v: Vector3 = smp[1]
			if v.length() > 20.0:
				acc += v
		if acc.length() < 1.0:
			continue
		var nat := acc.normalized()
		for smp in _samples[j]:
			var v2: Vector3 = smp[1]
			if v2.dot(nat) < -12.0:
				var k := "%s in %s" % [j, smp[0]]
				out[k] = int(out.get(k, 0)) + 1
	return out
