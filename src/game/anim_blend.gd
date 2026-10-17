class_name AnimBlend
extends RefCounted
## Crossfade times that do not snap (run 2026-10-18 e; the owner: "if they connect properly"). AnimationPlayer eases
## each bone's turn from the old clip into the new one over the blend time, so a big pose gap squeezed into a short
## blend whips a limb round in a frame or two (an idle with the sword low into a slash that starts with it raised:
## 170 degrees in 0.06 s). time() measures the gap between the pose the model is in and the new clip's first frame
## (every bone's turn in skeleton space, so a weapon at the end of the arm counts its whole chain) and stretches the
## blend (see time_from), within the caller's cap (an attack must still land on its attack point).
## tests/tools/anim_joins.gd measures every join the game makes with the same rule.

const RATE := 600.0                         # degrees per second a crossfade may add to a bone's own motion
const MAX := 0.4                            # seconds: the longest crossfade

const FINGER := 0.4                         # finger bones count this much of their snap (small, fast joints: a hand
                                            # closes in about 0.15 s, so a 140 degree grip change in 0.25 s is natural)

static var _tracks := {}                    # Animation instance id -> PackedInt32Array (bone -> rotation track or -1)
static var _weights := {}                   # Skeleton3D instance id -> PackedFloat32Array
static var _frames := {}                    # "clip:start:speed:frames" -> [local turns per frame, skeleton-space turns]

## Each bone's share of the snap score: FINGER for finger bones, 1 for the rest.
static func weights(sk: Skeleton3D) -> PackedFloat32Array:
	var id := sk.get_instance_id()
	if _weights.has(id):
		return _weights[id]
	var w := PackedFloat32Array()
	w.resize(sk.get_bone_count())
	for b in sk.get_bone_count():
		var n := sk.get_bone_name(b).to_lower()
		w[b] = FINGER if n.contains("index") or n.contains("middle") or n.contains("ring_") or n.contains("pinky") 			or n.contains("thumb") or n.contains("finger") else 1.0
	_weights[id] = w
	return w

## The rotation track of each of the skeleton's bones in `a` (-1: the clip leaves that bone alone).
static func _map(sk: Skeleton3D, a: Animation) -> PackedInt32Array:
	var id := a.get_instance_id()
	if _tracks.has(id):
		return _tracks[id]
	var m := PackedInt32Array()
	m.resize(sk.get_bone_count())
	m.fill(-1)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var b := sk.find_bone(String(a.track_get_path(t)).get_slice(":", 1))
		if b >= 0:
			m[b] = t
	_tracks[id] = m
	return m

## The largest turn (degrees, skeleton space) between the pose `from` (each bone's local turn) and clip `a` at time t.
static func gap_from(sk: Skeleton3D, from: Array, a: Animation, t: float) -> float:
	var m := _map(sk, a)
	var n := sk.get_bone_count()
	var gc: Array[Quaternion] = []
	var gt: Array[Quaternion] = []
	gc.resize(n)
	gt.resize(n)
	var worst := 0.0
	for b in n:
		var lc: Quaternion = from[b]
		var lt := a.rotation_track_interpolate(m[b], t) if m[b] >= 0 else lc
		var p := sk.get_bone_parent(b)
		gc[b] = lc if p < 0 else gc[p] * lc
		gt[b] = lt if p < 0 else gt[p] * lt
		worst = maxf(worst, gc[b].angle_to(gt[b]))
	return rad_to_deg(worst)

## Clip `a`'s pose at time t (each bone's local turn; bones it leaves alone keep their current turn).
static func clip_pose(sk: Skeleton3D, a: Animation, t: float) -> Array:
	var m := _map(sk, a)
	var p: Array = []
	for b in sk.get_bone_count():
		p.append(a.rotation_track_interpolate(m[b], t) if m[b] >= 0 else sk.get_bone_pose_rotation(b))
	return p

## The model's current pose (each bone's local turn).
static func pose(sk: Skeleton3D) -> Array:
	var p: Array = []
	for b in sk.get_bone_count():
		p.append(sk.get_bone_pose_rotation(b))
	return p

## The blend to use for playing clip `a` from time t (at `speed`) on a model now in pose `from`, between `base` and
## `cap` (and MAX). simulate (heroes): each candidate crossfade is played out at 30 frames a second, the old pose held
## and the clip's frames eased in the way AnimationPlayer blends (each bone's local turn), and the one whose worst frame
## adds least to the clip's own motion wins (a longer blend is not always smoother: when a limb swings nearly half a
## turn away from the old pose during the blend, the ease takes the short way round and flips; a shorter blend is done
## before it gets there). Otherwise (creeps): long enough that no bone turns faster than RATE over the gap.
static func time_from(sk: Skeleton3D, from: Array, a: Animation, t: float, base: float, cap := MAX, speed := 1.0,
		simulate := true) -> float:
	if sk == null or a == null:
		return base
	var hi := maxf(base, minf(cap, MAX))
	if not simulate:
		var need := base
		for i in 3:
			var g := 0.0
			for k in 4:
				g = maxf(g, gap_from(sk, from, a, minf(a.length, t + need * speed * k / 3.0)))
			need = clampf(g / RATE, base, hi)
		return need
	var m := _map(sk, a)
	var n := sk.get_bone_count()
	var dt := 1.0 / 30.0
	var frames := int(ceil(hi / dt)) + 2
	var par := PackedInt32Array()
	par.resize(n)
	for b in n:
		par[b] = sk.get_bone_parent(b)
	# the clip's local and skeleton-space turns per frame (cached per clip, start and speed: they do not depend on
	# the pose it starts from, apart from bones it leaves alone, which keep the pose they had the first time)
	var ck := "%d:%d:%d:%d" % [a.get_instance_id(), roundi(t * 30.0), roundi(speed * 20.0), frames]
	var cached: Array = _frames.get(ck, [])
	if cached.is_empty():
		var bl0: Array = []
		var bg0: Array = []
		for k in frames + 1:
			var tt := minf(a.length, t + k * dt * speed)
			var l: Array[Quaternion] = []
			var g: Array[Quaternion] = []
			l.resize(n)
			g.resize(n)
			for b in n:
				l[b] = a.rotation_track_interpolate(m[b], tt) if m[b] >= 0 else (from[b] as Quaternion)
				g[b] = l[b] if par[b] < 0 else g[par[b]] * l[b]
			bl0.append(l)
			bg0.append(g)
		var own0: Array = [PackedFloat32Array()]
		for k in range(1, frames + 1):
			var o := PackedFloat32Array()
			o.resize(n)
			for b in n:
				o[b] = (bg0[k - 1][b] as Quaternion).angle_to(bg0[k][b])
			own0.append(o)
		cached = [bl0, bg0, own0]
		if _frames.size() > 512:
			_frames.clear()
		_frames[ck] = cached
	var bl: Array = cached[0]
	var own_k: Array = cached[2]
	var wt := weights(sk)
	var best := base
	var best_score := INF
	for cand in [base, 0.08, 0.12, 0.16, 0.2, 0.25, 0.3, 0.4]:
		var c := float(cand)
		if c < base - 1e-4 or c > hi + 1e-4:
			continue
		var score := 0.0
		var prev: Array[Quaternion] = []
		prev.resize(n)
		var steps := mini(frames, int(ceil(c / dt)) + 1)
		for k in steps + 1:
			var w := clampf(k * dt / c, 0.0, 1.0) if c > 0.0 else 1.0
			var g: Array[Quaternion] = []
			g.resize(n)
			var l: Array[Quaternion] = bl[k]
			var own: PackedFloat32Array = own_k[k]
			for b in n:
				var q := (from[b] as Quaternion).slerp(l[b], w)
				g[b] = q if par[b] < 0 else g[par[b]] * q
				if k > 0:
					score = maxf(score, (prev[b].angle_to(g[b]) - own[b]) * wt[b])
			prev = g
		if score < best_score - deg_to_rad(1.0):
			best_score = score
			best = c
	return best

static func time(sk: Skeleton3D, a: Animation, t: float, base: float, cap := MAX, speed := 1.0, simulate := true) -> float:
	if sk == null or a == null:
		return base
	return time_from(sk, pose(sk), a, t, base, cap, speed, simulate)
