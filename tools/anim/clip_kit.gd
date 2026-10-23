extends RefCounted
## Shared helpers for the hand-made clip sets (tools/anim/clips_<hero>.gd): key poses eased into each other, merges,
## a planted-foot run cycle and small curves. A set extends this, sets BODY and returns its clips from clips().

var rig                                     # HandRig (tools/anim/hand_rig.gd) on the set's own body

## `over` laid onto a copy of `base`, dictionaries merged deeply (a key pose changes only what it names).
static func merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over:
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out

static func _flat(d: Dictionary, pre: String, out: Dictionary) -> void:
	for k in d:
		var v = d[k]
		if v is Dictionary:
			_flat(v, pre + String(k) + "/", out)
		else:
			out[pre + String(k)] = v

static func _unflat(f: Dictionary) -> Dictionary:
	var out := {}
	for path in f:
		var parts := String(path).split("/")
		var cur := out
		for i in parts.size() - 1:
			if not cur.has(parts[i]):
				cur[parts[i]] = {}
			cur = cur[parts[i]]
		cur[parts[parts.size() - 1]] = f[path]
	return out

## A pose at time t from key poses [[time, controls], ...] (each a full pose: build them with merge). Between keys a
## cubic Hermite curve whose slopes come from the neighbouring keys (Catmull-Rom on uneven times), flat at the first
## and last key of a one-shot clip (the move eases out of its start and into its end); a loop wraps round.
## Directions (names ending in "blade", "edge", "pole") are renormalised.
static func keyed(keys: Array, length: float, loop: bool) -> Callable:
	var times: Array = []
	var flats: Array = []
	var n := keys.size()
	if loop:
		# wrapped copies: two keys before the first and two after the last
		for k in [n - 2, n - 1]:
			times.append(float(keys[posmod(k, n)][0]) - length)
			flats.append(keys[posmod(k, n)][1])
	for k in keys:
		times.append(float(k[0]))
		flats.append(k[1])
	if loop:
		for k in [0, 1]:
			times.append(float(keys[k % n][0]) + length)
			flats.append(keys[k % n][1])
	var ff: Array = []
	for f in flats:
		var o := {}
		_flat(f, "", o)
		ff.append(o)
	return func(t: float) -> Dictionary:
		if loop:
			t = fposmod(t, length)
		var m := times.size()
		var i := 0
		while i < m - 2 and t >= float(times[i + 1]):
			i += 1
		var j := i + 1
		var t0: float = times[i]
		var t1: float = times[j]
		var has_p := i > 0
		var has_n := j < m - 1
		var tp: float = times[i - 1] if has_p else t0
		var tn: float = times[j + 1] if has_n else t1
		var u := clampf((t - t0) / maxf(0.0001, t1 - t0), 0.0, 1.0)
		var a: Dictionary = ff[i]
		var b: Dictionary = ff[j]
		var p: Dictionary = ff[i - 1] if has_p else a
		var q: Dictionary = ff[j + 1] if has_n else b
		var h := t1 - t0
		var out := {}
		for path in a:
			var va = a[path]
			var vb = b.get(path, va)
			if not (va is float or va is int or va is Vector3):
				out[path] = va if u < 0.5 else vb
				continue
			var vp = p.get(path, va)
			var vq = q.get(path, vb)
			var ma = (vb - vp) / maxf(0.0001, t1 - tp) * h if has_p else (vb - va) * 0.0
			var mb = (vq - va) / maxf(0.0001, tn - t0) * h if has_n else (vb - va) * 0.0
			var u2 := u * u
			var u3 := u2 * u
			var v = va * (2.0 * u3 - 3.0 * u2 + 1.0) + ma * (u3 - 2.0 * u2 + u) + vb * (-2.0 * u3 + 3.0 * u2) \
				+ mb * (u3 - u2)
			if v is Vector3 and (String(path).ends_with("blade") or String(path).ends_with("edge") \
					or String(path).ends_with("pole")):
				v = (v as Vector3).normalized()
			out[path] = v
		return _unflat(out)

## Cubic Hermite through points [[u, value], ...] (u rising 0..1) with the end slopes given (value per unit u).
static func hermite(pts: Array, u: float, m_start, m_end):
	var n := pts.size()
	var i := 0
	while i < n - 2 and u >= float(pts[i + 1][0]):
		i += 1
	var u0 := float(pts[i][0])
	var u1 := float(pts[i + 1][0])
	var h := u1 - u0
	var s := clampf((u - u0) / maxf(0.0001, h), 0.0, 1.0)
	var a = pts[i][1]
	var b = pts[i + 1][1]
	var ma
	var mb
	if i == 0:
		ma = m_start * h
	else:
		ma = (b - pts[i - 1][1]) / (u1 - float(pts[i - 1][0])) * h
	if i + 1 == n - 1:
		mb = m_end * h
	else:
		mb = (pts[i + 2][1] - a) / (float(pts[i + 2][0]) - u0) * h
	var s2 := s * s
	var s3 := s2 * s
	return a * (2.0 * s3 - 3.0 * s2 + 1.0) + ma * (s3 - 2.0 * s2 + s) + b * (-2.0 * s3 + 3.0 * s2) + mb * (s3 - s2)

static func ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

## Turn a direction about an axis (degrees).
static func turn(v: Vector3, axis: Vector3, deg: float) -> Vector3:
	return v.rotated(axis.normalized(), deg_to_rad(deg))
