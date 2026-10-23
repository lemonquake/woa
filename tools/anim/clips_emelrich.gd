extends "res://tools/anim/clip_kit.gd"
## Ser Emelrich's own moves (run 2026-10-23; his idle, run, cast and hit used to come from the same great sword pack as
## Ezee's). A heavy knight with a two-metre great sword: he carries it on his right shoulder and swings it two-handed.
## Model space: he faces +Z, his left is +X. His legs are short and his torso long, so his stride is short and quick.
##   emel_h_idle    feet wide and planted, the great sword resting on his right shoulder, his left fist at his side
##   emel_h_run     a heavy, rolling run with the sword on his shoulder, his left arm pumping
##   (_cut_1, _cut_2, _cut_3: two-handed cuts, written but not built: see clips())
##   emel_h_cast    the sword raised upright before him in both hands
##   emel_h_hit     a flinch under a blow, then back to his stance

const BODY := "res://assets/characters/heroes17/emelrich.glb"
const WEAPON := "heavy_greatsword"                # held on weapon.R (kept out of the body by the grip planner)

const RUN_T := 0.56
const RUN_V := 2.8
const STANCE := 0.30

func clips() -> Dictionary:
	return {
		"emel_h_idle": {"length": 3.4, "loop": true, "pose": keyed(_idle_keys(), 3.4, true)},
		"emel_h_run": {"length": RUN_T, "loop": true, "ground_speed": RUN_V, "pose": _run},
		# the two-handed cuts are not built yet: with his short arms and the long handle they still bend his wrists past
		# the audit's limit (run 2026-10-23); he swings his own two-handed combo meanwhile (ModelCatalog.MOCAP)
		"emel_h_cast": {"length": 1.0, "hits": [[0.3, 0.36]], "release": 0.32, "pose": keyed(_cast(), 1.0, false)},
		"emel_h_hit": {"length": 0.6, "hits": [[0.1, 0.16]], "pose": keyed(_hit(), 0.6, false)},
	}

## The great sword on his right shoulder, held by the grip in his right hand.
const SHOULDER := {"grip": Vector3(-0.24, 1.36, 0.24), "blade": Vector3(-0.12, 0.62, -0.78), "edge": Vector3(1, 0, 0),
	"pole": Vector3(-0.6, -1, -0.1)}

func stance() -> Dictionary:
	return {
		"hips": Vector3(0.0, -0.035, 0.0), "pelvis": Vector3(4, -6, 0),
		"spine": Vector3(1, 3, 0), "chest": Vector3(-3, 3, 0), "neck": Vector3(0, 0, 0), "head": Vector3(2, 0, 0),
		"clav.L": Vector3(0, 0, 0), "clav.R": Vector3(0, 0, 0),
		"leg.L": {"ankle": Vector3(0.30, 0.077, 0.10), "pole": Vector3(0.4, 0, 1), "foot": Vector3(0, 12, 0), "toe": 0.0},
		"leg.R": {"ankle": Vector3(-0.30, 0.077, -0.10), "pole": Vector3(-0.4, 0, 1), "foot": Vector3(0, -18, 0), "toe": 0.0},
		"arm.L": {"hand": Vector3(0.44, 1.02, 0.08), "pole": Vector3(0.6, 0, -1), "wrist": Vector3(0, 0, 0)},
		"sword": SHOULDER.duplicate(),
		"grip2": {"gap": 0.19, "pole": Vector3(0.8, -0.6, 0), "w": 0.0},
	}

func _idle_keys() -> Array:
	var s := stance()
	var inhale := merge(s, {"hips": Vector3(0.0, -0.03, 0.0), "chest": Vector3(-4.5, 3, 0), "clav.L": Vector3(0, 0, 1.5),
		"clav.R": Vector3(0, 0, -1.5), "head": Vector3(1, 2, 0), "sword": {"grip": Vector3(-0.24, 1.37, 0.245)}})
	var shift := merge(s, {"hips": Vector3(-0.012, -0.038, 0.0), "pelvis": Vector3(4, -7, -1.5), "head": Vector3(2.5, -3, 0)})
	return [[0.0, s], [1.2, inhale], [2.3, shift]]

# ---- Run -------------------------------------------------------------------------------------------------------------

func _stance_foot(ph: float, x: float) -> Dictionary:
	var travel := RUN_V * RUN_T * STANCE
	var zb := 0.25 - travel * (ph / STANCE)
	var w := ph / STANCE
	var pitch: float = hermite([[0.0, -3.0], [0.2, 0.0], [0.55, 0.0], [1.0, 40.0]], w, 15.0, 120.0)
	var ab: Vector3 = rig.rest_pos("toe.L") - rig.rest_pos("foot.L")
	ab.x = 0.0
	var ball_y: float = rig.rest_pos("toe.L").y
	var ankle := Vector3(x, ball_y, zb) - ab.rotated(Vector3.RIGHT, deg_to_rad(pitch))
	return {"ankle": ankle, "pitch": pitch, "toe": maxf(0.0, pitch) * 0.85}

func _foot(ph: float, x: float) -> Dictionary:
	ph = fposmod(ph, 1.0)
	if ph <= STANCE:
		return _stance_foot(ph, x)
	var u := (ph - STANCE) / (1.0 - STANCE)
	var a := _stance_foot(STANCE, x)
	var b := _stance_foot(0.0, x)
	var e := 0.002
	var va: Vector3 = (a.ankle - (_stance_foot(STANCE - e, x).ankle as Vector3)) / e * (1.0 - STANCE)
	var vb: Vector3 = ((_stance_foot(e, x).ankle as Vector3) - b.ankle) / e * (1.0 - STANCE)
	var pa: float = (float(a.pitch) - float(_stance_foot(STANCE - e, x).pitch)) / e * (1.0 - STANCE)
	var pb: float = (float(_stance_foot(e, x).pitch) - float(b.pitch)) / e * (1.0 - STANCE)
	var y0: float = rig.rest_pos("foot.L").y
	var ankle: Vector3 = hermite([[0.0, a.ankle], [0.24, Vector3(x, y0 + 0.17, -0.26)], [0.5, Vector3(x, y0 + 0.19, -0.02)],
		[0.76, Vector3(x, y0 + 0.12, 0.18)], [0.9, Vector3(x, y0 + 0.05, 0.19)], [1.0, b.ankle]], u, va, vb)
	var pitch: float = hermite([[0.0, a.pitch], [0.24, 50.0], [0.5, 22.0], [0.76, -2.0], [0.9, -6.0], [1.0, b.pitch]],
		u, pa, pb)
	var toe: float = hermite([[0.0, a.toe], [0.2, 8.0], [0.6, 0.0], [1.0, 0.0]], u, 0.0, 0.0)
	return {"ankle": ankle, "pitch": pitch, "toe": toe}

func _run(t: float) -> Dictionary:
	var ph := fposmod(t / RUN_T, 1.0)
	var c1 := cos(TAU * ph)
	var side := cos(TAU * (ph - 0.16))
	var bob := cos(2.0 * TAU * (ph - 0.13))
	var fl := _foot(ph, 0.22)
	var fr := _foot(ph + 0.5, -0.22)
	var arm := 0.5 + 0.5 * cos(TAU * (ph - 0.5))
	var front := Vector3(0.30, 1.22, 0.30)
	var back := Vector3(0.46, 1.04, -0.12)
	var lh := back.lerp(front, arm) + Vector3(0.0, 0.04, 0.0) * sin(PI * arm)
	return {
		"hips": Vector3(0.025 * side, -0.05 - 0.022 * bob, 0.0),
		"pelvis": Vector3(8.0, -8.0 * c1, 4.0 * side),
		"spine": Vector3(2.0, 5.0 * c1, -2.0 * side),
		"chest": Vector3(2.0 + 1.0 * bob, 6.0 * c1, -1.5 * side),
		"neck": Vector3(-4.0, -1.5 * c1, 0.0),
		"head": Vector3(-6.0, -1.5 * c1, 0.5 * side),
		"clav.L": Vector3(0, -3.0 * (arm - 0.5), 0), "clav.R": Vector3(0, 0, 0),
		"leg.L": {"ankle": fl.ankle, "pole": Vector3(0.25, 0, 1), "foot": Vector3(fl.pitch, 6, 0), "toe": fl.toe},
		"leg.R": {"ankle": fr.ankle, "pole": Vector3(-0.25, 0, 1), "foot": Vector3(fr.pitch, -6, 0), "toe": fr.toe},
		"arm.L": {"hand": lh, "pole": Vector3(0.6, -0.2, -1.0), "wrist": Vector3(0, 0, 0), "chest": true},
		"sword": merge(SHOULDER, {"grip": Vector3(-0.24, 1.36 + 0.012 * bob, 0.24), "chest": true}),
	}

# ---- Attacks ---------------------------------------------------------------------------------------------------------

## Halfway between the shoulder and the guard: the sword lifted off the shoulder and out to his right, his left hand on
## its way to the handle (the blade goes round him, never through his chest or head).
func lift() -> Dictionary:
	return merge(stance(), {"hips": Vector3(0.0, -0.05, 0.0), "pelvis": Vector3(5, -8, 0), "chest": Vector3(0, 2, 0),
		"arm.L": {"hand": Vector3(0.26, 1.16, 0.40), "pole": Vector3(0.8, -0.6, -0.2)},
		"sword": {"grip": Vector3(-0.34, 1.34, 0.36), "blade": Vector3(-0.45, 0.88, -0.05), "edge": Vector3(1, 0.4, 0),
			"pole": Vector3(-0.8, -0.6, 0)},
		"grip2": {"gap": 0.19, "pole": Vector3(0.8, -0.6, 0), "w": 0.35}})

## Both hands on the grip, the blade up before him.
func guard() -> Dictionary:
	return merge(stance(), {"hips": Vector3(0.0, -0.06, 0.0), "pelvis": Vector3(6, -8, 0), "chest": Vector3(2, 4, 0),
		"sword": {"grip": Vector3(-0.06, 1.22, 0.42), "blade": Vector3(0.0, 0.93, 0.36), "edge": Vector3(0, 0.4, -0.9),
			"pole": Vector3(-0.8, -0.6, 0)},
		"grip2": {"gap": 0.19, "pole": Vector3(0.8, -0.6, 0), "w": 1.0}})

func _cut_1() -> Array:
	var s := stance()
	var g := guard()
	var up := merge(g, {"pelvis": Vector3(0, -6, 0), "spine": Vector3(-4, 2, 0), "chest": Vector3(-8, 2, 0), "head": Vector3(-4, 0, 0),
		"hips": Vector3(0.0, -0.04, -0.03),
		"sword": {"grip": Vector3(-0.08, 1.80, 0.12), "blade": Vector3(0.05, 0.40, -0.92), "edge": Vector3(0, 1, 0.4),
			"pole": Vector3(-1, 0.2, 0)}, "grip2": {"pole": Vector3(1, 0.2, 0)}})
	var mid := merge(up, {"pelvis": Vector3(10, -2, 0), "spine": Vector3(4, 2, 0), "chest": Vector3(4, 2, 0), "head": Vector3(0, 0, 0),
		"hips": Vector3(0.0, -0.08, 0.06), "leg.L": {"ankle": Vector3(0.30, 0.077, 0.30)},
		"sword": {"grip": Vector3(-0.04, 1.66, 0.46), "blade": Vector3(0.0, 0.92, 0.38), "edge": Vector3(0, 0.4, -0.9),
			"pole": Vector3(-1, -0.3, 0)}, "grip2": {"pole": Vector3(1, -0.3, 0)}})
	var hit := merge(mid, {"pelvis": Vector3(18, -2, 0), "spine": Vector3(10, 2, 0), "chest": Vector3(8, 2, 0), "head": Vector3(-10, 0, 0),
		"hips": Vector3(0.0, -0.14, 0.10), "leg.L": {"ankle": Vector3(0.30, 0.077, 0.38)},
		"sword": {"grip": Vector3(0.08, 1.04, 0.50), "blade": Vector3(0.72, -0.35, 0.60), "edge": Vector3(0.3, -0.9, -0.3),
			"pole": Vector3(-1, -0.6, 0)}, "grip2": {"pole": Vector3(1, -0.6, 0)}})
	var follow := merge(hit, {"sword": {"grip": Vector3(0.14, 1.00, 0.44), "blade": Vector3(0.88, -0.38, 0.12)}})
	var l := lift()
	return [[0.0, s], [0.09, l], [0.18, g], [0.34, up], [0.45, mid], [0.56, hit], [0.72, follow], [0.88, g], [0.99, l],
		[1.1, s]]

func _cut_2() -> Array:
	var s := stance()
	var g := guard()
	var wind := merge(g, {"pelvis": Vector3(6, -30, 0), "spine": Vector3(2, -12, 0), "chest": Vector3(2, -16, 0),
		"head": Vector3(-2, 24, 0), "hips": Vector3(-0.03, -0.08, -0.02),
		"sword": {"grip": Vector3(-0.30, 1.20, 0.24), "blade": Vector3(-0.75, 0.25, -0.62), "edge": Vector3(0, 0.3, 1),
			"pole": Vector3(-0.4, -1, -0.4)}, "grip2": {"pole": Vector3(0.6, -1, 0.2)}})
	var hit := merge(g, {"pelvis": Vector3(10, 10, 0), "spine": Vector3(4, 8, 0), "chest": Vector3(4, 10, 0),
		"head": Vector3(-4, -14, 0), "hips": Vector3(0.03, -0.12, 0.06), "leg.L": {"ankle": Vector3(0.32, 0.077, 0.24)},
		"sword": {"grip": Vector3(0.06, 1.12, 0.56), "blade": Vector3(0.45, 0.05, 0.89), "edge": Vector3(1, 0, -0.5),
			"pole": Vector3(-0.6, -1, 0)}, "grip2": {"pole": Vector3(0.6, -1, -0.2)}})
	var follow := merge(hit, {"pelvis": Vector3(10, 26, 0), "chest": Vector3(4, 16, 0),
		"sword": {"grip": Vector3(0.24, 1.12, 0.40), "blade": Vector3(0.92, 0.0, 0.38), "edge": Vector3(0.4, 0, -1)}})
	var l := lift()
	return [[0.0, s], [0.09, l], [0.18, g], [0.38, wind], [0.55, hit], [0.72, follow], [0.88, g], [0.99, l], [1.1, s]]

func _cut_3() -> Array:
	var s := stance()
	var g := guard()
	var low := merge(g, {"pelvis": Vector3(10, -24, 0), "spine": Vector3(6, -10, 0), "chest": Vector3(4, -12, 0),
		"head": Vector3(-6, 20, 0), "hips": Vector3(-0.02, -0.13, -0.02), "leg.R": {"ankle": Vector3(-0.32, 0.077, -0.18)},
		"sword": {"grip": Vector3(-0.30, 0.98, 0.30), "blade": Vector3(-0.55, -0.45, -0.70), "edge": Vector3(0, -1, 0.3),
			"pole": Vector3(-0.6, -0.4, -0.6)}, "grip2": {"pole": Vector3(0.6, -0.8, 0)}})
	var hit := merge(g, {"pelvis": Vector3(2, 14, 0), "spine": Vector3(-4, 8, 0), "chest": Vector3(-6, 12, 0),
		"head": Vector3(-6, -12, 0), "hips": Vector3(0.02, -0.06, 0.05), "leg.L": {"ankle": Vector3(0.32, 0.077, 0.26)},
		"sword": {"grip": Vector3(0.02, 1.46, 0.50), "blade": Vector3(0.50, 0.70, 0.50), "edge": Vector3(0.5, 0.4, -0.8),
			"pole": Vector3(-1, -0.4, 0)}, "grip2": {"pole": Vector3(1, -0.6, 0)}})
	var follow := merge(hit, {"pelvis": Vector3(2, 20, 0), "chest": Vector3(-8, 16, 0),
		"sword": {"grip": Vector3(0.10, 1.58, 0.36), "blade": Vector3(0.62, 0.70, -0.30)}})
	var l := lift()
	return [[0.0, s], [0.09, l], [0.18, g], [0.38, low], [0.55, hit], [0.72, follow], [0.88, g], [0.99, l], [1.1, s]]

func _cast() -> Array:
	var s := stance()
	var g := guard()
	var raise := merge(g, {"chest": Vector3(-6, 2, 0), "head": Vector3(-6, 0, 0),
		"sword": {"grip": Vector3(-0.04, 1.40, 0.42), "blade": Vector3(0.0, 1.0, 0.1), "edge": Vector3(-1, 0, 0)}})
	var l := lift()
	return [[0.0, s], [0.09, l], [0.18, g], [0.32, raise], [0.55, raise], [0.78, g], [0.89, l], [1.0, s]]

func _hit() -> Array:
	var s := stance()
	var jolt := merge(s, {"hips": Vector3(0.0, -0.05, -0.04), "pelvis": Vector3(-1, -8, 0), "spine": Vector3(-5, 0, 2),
		"chest": Vector3(-8, 0, 3), "head": Vector3(-6, -10, 4), "arm.L": {"hand": Vector3(0.46, 1.10, 0.14)}})
	return [[0.0, s], [0.12, jolt], [0.6, s]]
