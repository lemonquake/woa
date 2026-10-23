extends "res://tools/anim/clip_kit.gd"
## Dracoxinia's own moves (run 2026-10-23, the owner: "make it by yourself ... a perfect run ... no clipping, no weird
## twists"): a royal one-handed sword style for her long crystal blade. Model space: she faces +Z, her left is +X.
##   drac_h_idle   standing tall, weight on her back foot, left hand on her hip, the blade resting low before her
##   drac_h_run    a light, quick run, feet planted (no sliding), the blade trailing low behind her right side
##   drac_h_cut_1  a forehand cut from over her right shoulder down across to her left hip, stepping in
##   drac_h_cut_2  a backhand sweep from her left side across at chest height, turning through it
##   drac_h_cut_3  a lunging thrust, the blade level, her left arm thrown back
##   drac_h_hit    a flinch: her body jolts back from the blow and she settles into her stance again
##   drac_h_swap   Change Sword (and Dragon Leap's take-off): the blade raised upright before her face, then lowered
##   drac_h_dash   Dragon Dash: low and leaning into the dash, the blade swept back along her right side
##   drac_h_stagger / drac_h_recover   pushed: thrown back on her heels, arms out, the sword kept; then back to her stance

const BODY := "res://assets/characters/heroes17/dracoxinia.glb"
const WEAPON := "dracoxinia_sword_pink"                # held on weapon.R (kept out of the body by the grip planner)

const RUN_T := 0.62                          # one cycle (two steps)
const RUN_V := 3.1                           # metres a second the feet push the ground back
const STANCE := 0.34                         # share of the cycle each foot is on the ground
const BALL_Y := 0.035

func clips() -> Dictionary:
	return {
		"drac_h_idle": {"length": 3.2, "loop": true, "pose": keyed(_idle_keys(), 3.2, true)},
		"drac_h_run": {"length": RUN_T, "loop": true, "ground_speed": RUN_V, "pose": _run},
		"drac_h_cut_1": {"length": 1.0, "hits": [[0.43, 0.5]], "pose": keyed(_cut_1(), 1.0, false)},
		"drac_h_cut_2": {"length": 1.0, "hits": [[0.43, 0.5]], "pose": keyed(_cut_2(), 1.0, false)},
		"drac_h_cut_3": {"length": 1.0, "hits": [[0.43, 0.5]], "pose": keyed(_cut_3(), 1.0, false)},
		"drac_h_hit": {"length": 0.6, "hits": [[0.1, 0.16]], "pose": keyed(_hit(), 0.6, false)},
		"drac_h_swap": {"length": 1.0, "hits": [[0.28, 0.34]], "release": 0.3, "pose": keyed(_swap(), 1.0, false)},
		"drac_h_dash": {"length": 0.6, "loop": true, "hits": [[0.08, 0.12]], "release": 0.1,
			"pose": keyed(_dash(), 0.6, true)},
		"drac_h_stagger": {"length": 0.9, "pose": keyed(_stagger(), 0.9, false)},
		"drac_h_recover": {"length": 0.7, "pose": keyed(_recover(), 0.7, false)},
	}

# ---- Idle ------------------------------------------------------------------------------------------------------------

## The stance every other move starts from and returns to.
func stance() -> Dictionary:
	return {
		"hips": Vector3(-0.015, -0.03, -0.005), "pelvis": Vector3(3, -9, -2),
		"spine": Vector3(-1, 4, 1), "chest": Vector3(-4, 5, 0), "neck": Vector3(2, 0, 0), "head": Vector3(3, 2, -3),
		"clav.L": Vector3(0, 0, 0), "clav.R": Vector3(0, 0, 0),
		"leg.L": {"ankle": Vector3(0.17, 0.207, 0.10), "pole": Vector3(0.3, 0, 1), "foot": Vector3(0, 14, 0), "toe": 0.0},
		"leg.R": {"ankle": Vector3(-0.13, 0.207, -0.08), "pole": Vector3(-0.35, 0, 1), "foot": Vector3(0, -20, 0), "toe": 0.0},
		"arm.L": {"hand": Vector3(0.31, 1.04, -0.02), "pole": Vector3(1.0, 0.1, -0.4), "wrist": Vector3(0, 0, -25)},
		"sword": {"grip": Vector3(-0.30, 1.08, 0.14), "blade": Vector3(-0.62, -0.50, 0.60), "edge": Vector3(0, -1, 0),
			"pole": Vector3(-0.8, -0.4, -0.4)},
	}

func _idle_keys() -> Array:
	var s := stance()
	var inhale := merge(s, {"hips": Vector3(-0.012, -0.026, -0.005), "chest": Vector3(-5.5, 5, 0),
		"clav.L": Vector3(0, 0, 1.5), "clav.R": Vector3(0, 0, -1.5), "head": Vector3(2, 3, -3.5),
		"sword": {"grip": Vector3(-0.28, 1.09, 0.165)}})
	var settle := merge(s, {"hips": Vector3(-0.02, -0.032, -0.006), "pelvis": Vector3(3, -10, -2.6),
		"head": Vector3(3.5, 0, -2), "sword": {"blade": Vector3(-0.64, -0.48, 0.60)}})
	return [[0.0, s], [1.1, inhale], [2.1, settle]]

# ---- Run -------------------------------------------------------------------------------------------------------------

## The ball of a planted foot rolls back at the run's speed; the ankle sits over it, turned by the foot's pitch.
func _stance_foot(ph: float, x: float) -> Dictionary:
	var travel := RUN_V * RUN_T * STANCE
	var zb := 0.30 - travel * (ph / STANCE)
	var w := ph / STANCE
	var pitch: float = hermite([[0.0, -6.0], [0.2, 0.0], [0.55, 0.0], [1.0, 44.0]], w, 30.0, 130.0)
	var ab: Vector3 = rig.rest_pos("toe.L") - rig.rest_pos("foot.L")
	ab.x = 0.0
	var ankle := Vector3(x, BALL_Y, zb) - ab.rotated(Vector3.RIGHT, deg_to_rad(pitch))
	return {"ankle": ankle, "pitch": pitch, "toe": maxf(0.0, pitch) * 0.85}

func _foot(ph: float, x: float) -> Dictionary:
	ph = fposmod(ph, 1.0)
	if ph <= STANCE:
		return _stance_foot(ph, x)
	var u := (ph - STANCE) / (1.0 - STANCE)
	var a := _stance_foot(STANCE, x)
	var b := _stance_foot(0.0, x)
	# the slopes at both ends match the planted foot's, so lifting off and landing do not jerk
	var e := 0.002
	var va: Vector3 = (a.ankle - (_stance_foot(STANCE - e, x).ankle as Vector3)) / e * (1.0 - STANCE)
	var vb: Vector3 = ((_stance_foot(e, x).ankle as Vector3) - b.ankle) / e * (1.0 - STANCE)
	var pa: float = (float(a.pitch) - float(_stance_foot(STANCE - e, x).pitch)) / e * (1.0 - STANCE)
	var pb: float = (float(_stance_foot(e, x).pitch) - float(b.pitch)) / e * (1.0 - STANCE)
	# a low, light swing: the heel lifts behind and the knee comes through without rising high (her skirt's panels
	# hang from her thighs, and a high knee or heel throws them out like sticks)
	var ankle: Vector3 = hermite([[0.0, a.ankle], [0.24, Vector3(x, 0.36, -0.30)], [0.5, Vector3(x, 0.37, -0.02)],
		[0.74, Vector3(x, 0.31, 0.24)], [0.9, Vector3(x, 0.245, 0.26)], [1.0, b.ankle]], u, va, vb)
	var pitch: float = hermite([[0.0, a.pitch], [0.24, 58.0], [0.5, 30.0], [0.74, 0.0], [0.9, -8.0], [1.0, b.pitch]],
		u, pa, pb)
	var toe: float = hermite([[0.0, a.toe], [0.2, 8.0], [0.6, 0.0], [1.0, 0.0]], u, 0.0, 0.0)
	return {"ankle": ankle, "pitch": pitch, "toe": toe}

func _run(t: float) -> Dictionary:
	var ph := fposmod(t / RUN_T, 1.0)
	var c1 := cos(TAU * ph)                   # +1 as her left foot lands
	var side := cos(TAU * (ph - 0.16))        # +1 at the middle of her left foot's stance
	var bob := cos(2.0 * TAU * (ph - 0.13))   # +1 at the bottom of each step
	var fl := _foot(ph, 0.088)
	var fr := _foot(ph + 0.5, -0.088)
	var arm := 0.5 + 0.5 * cos(TAU * (ph - 0.5))   # her left arm: 1 forward (her right foot forward)
	var front := Vector3(0.16, 1.25, 0.19)
	var back := Vector3(0.34, 1.16, -0.13)
	var lh := back.lerp(front, arm) + Vector3(-0.02, 0.035, 0.0) * sin(PI * arm)
	var rs := 0.5 + 0.5 * c1                  # her sword arm swings a little with the left leg
	return {
		"hips": Vector3(0.012 * side, -0.07 - 0.026 * bob, 0.0),
		"pelvis": Vector3(9.0, -7.0 * c1, 3.0 * side),
		"spine": Vector3(2.0, 5.0 * c1, -1.5 * side),
		"chest": Vector3(3.0 + 1.2 * bob, 6.0 * c1, -1.0 * side),
		"neck": Vector3(-5.0, -2.0 * c1, 0.0),
		"head": Vector3(-8.0, -2.5 * c1, 0.5 * side),
		"clav.L": Vector3(0, -3.0 * (arm - 0.5), 0),
		"clav.R": Vector3(0, 0, -2.0),
		"leg.L": {"ankle": fl.ankle, "pole": Vector3(0.12, 0, 1), "foot": Vector3(fl.pitch, 4, 0), "toe": fl.toe},
		"leg.R": {"ankle": fr.ankle, "pole": Vector3(-0.12, 0, 1), "foot": Vector3(fr.pitch, -4, 0), "toe": fr.toe},
		"arm.L": {"hand": lh, "pole": Vector3(0.5, -0.2, -1.0), "wrist": Vector3(0, 0, -10), "chest": true},
		"sword": {"grip": Vector3(-0.29, 1.08, -0.06 + 0.05 * (rs - 0.5)), "blade": Vector3(-0.72, -0.52, -0.46),
			"edge": Vector3(0, -1, 0.2), "pole": Vector3(-0.7, -0.3, -0.6), "chest": true},
	}

# ---- Attacks ---------------------------------------------------------------------------------------------------------

## Ready: knees bent, the blade up before her (every cut passes through it on its way back to the stance; each cut
## begins and ends in the stance, so idle, run and cuts blend into each other without the blade swinging round).
func ready() -> Dictionary:
	return merge(stance(), {
		"hips": Vector3(-0.01, -0.07, -0.01), "pelvis": Vector3(6, -14, 0), "spine": Vector3(2, 4, 0),
		"chest": Vector3(2, 6, 0), "neck": Vector3(-2, 2, 0), "head": Vector3(-3, 3, 0),
		"leg.L": {"ankle": Vector3(0.16, 0.207, 0.18), "pole": Vector3(0.3, 0, 1), "foot": Vector3(0, 10, 0)},
		"leg.R": {"ankle": Vector3(-0.15, 0.207, -0.16), "pole": Vector3(-0.4, 0, 1), "foot": Vector3(0, -24, 0)},
		"arm.L": {"hand": Vector3(0.32, 1.16, 0.14), "pole": Vector3(0.35, -1, -0.25), "wrist": Vector3(0, 0, -5)},
		"sword": {"grip": Vector3(-0.2, 1.17, 0.24), "blade": Vector3(-0.1, 0.55, 0.83), "edge": Vector3(0.2, 0.8, -0.5),
			"pole": Vector3(-0.8, -0.5, -0.3)},
	})

## Forehand: the blade drawn back over her right shoulder, then down across her body to her left hip.
func _cut_1() -> Array:
	var r := ready()
	var wind := merge(r, {"pelvis": Vector3(4, -24, 0), "spine": Vector3(-2, -8, 2), "chest": Vector3(-6, -14, 3),
		"head": Vector3(-2, 14, 0), "hips": Vector3(-0.03, -0.06, -0.03),
		"arm.L": {"hand": Vector3(0.20, 1.24, 0.30), "pole": Vector3(1, -0.3, 0)},
		"sword": {"grip": Vector3(-0.22, 1.50, -0.02), "blade": Vector3(-0.15, 0.55, -0.82), "edge": Vector3(0, 1, 0.6),
			"pole": Vector3(-1, -0.2, 0.2)}})
	var mid := merge(wind, {"pelvis": Vector3(8, -4, 0), "spine": Vector3(2, 6, 0), "chest": Vector3(2, 8, 0),
		"head": Vector3(-2, 4, 0), "hips": Vector3(0.0, -0.08, 0.04),
		"leg.L": {"ankle": Vector3(0.17, 0.207, 0.34)},
		"sword": {"grip": Vector3(-0.15, 1.42, 0.30), "blade": Vector3(0.15, 0.55, 0.82), "edge": Vector3(0.4, -0.3, 0.6),
			"pole": Vector3(-1, -0.3, -0.2)}})
	var hit := merge(mid, {"pelvis": Vector3(12, 12, 0), "spine": Vector3(4, 10, -2), "chest": Vector3(6, 12, -3),
		"head": Vector3(0, -8, 0), "hips": Vector3(0.03, -0.11, 0.08),
		"leg.L": {"ankle": Vector3(0.18, 0.207, 0.40), "foot": Vector3(0, 6, 0)},
		"arm.L": {"hand": Vector3(0.34, 1.12, -0.06), "pole": Vector3(1, 0, -0.5)},
		"sword": {"grip": Vector3(0.05, 1.06, 0.42), "blade": Vector3(0.55, -0.35, 0.76), "edge": Vector3(0.5, -0.6, -0.1),
			"pole": Vector3(-0.6, -0.6, -0.4)}})
	var follow := merge(hit, {"pelvis": Vector3(12, 18, 0), "chest": Vector3(6, 14, -3),
		"sword": {"grip": Vector3(0.16, 1.00, 0.44), "blade": Vector3(0.88, -0.36, -0.22), "edge": Vector3(-0.1, -0.5, -0.8)}})
	var s := stance()
	# on the way up the blade swings out round her right side, clear of her body
	var out := merge(s, {"pelvis": Vector3(3, -16, 0), "chest": Vector3(-4, -6, 2),
		"sword": {"grip": Vector3(-0.36, 1.30, 0.20), "blade": Vector3(-0.92, 0.30, 0.20), "edge": Vector3(0, 1, 0)}})
	return [[0.0, s], [0.12, out], [0.24, wind], [0.36, mid], [0.46, hit], [0.6, follow], [0.82, r], [1.0, s]]

## Backhand: the blade carried back past her left side, then swept level across before her.
func _cut_2() -> Array:
	var r := ready()
	var wind := merge(r, {"pelvis": Vector3(6, 20, 0), "spine": Vector3(0, 12, 0), "chest": Vector3(0, 20, -2),
		"head": Vector3(-3, -16, 0), "hips": Vector3(0.02, -0.08, -0.01),
		"arm.L": {"hand": Vector3(0.34, 1.20, -0.12), "pole": Vector3(0.5, -1, -0.4)},
		"sword": {"grip": Vector3(0.08, 1.25, 0.42), "blade": Vector3(0.70, 0.30, -0.65), "edge": Vector3(-0.2, 0.2, -1),
			"pole": Vector3(-0.2, -1, 0.4)}})
	var mid := merge(wind, {"pelvis": Vector3(8, -2, 0), "spine": Vector3(2, 0, 0), "chest": Vector3(2, -2, 0),
		"head": Vector3(-3, 0, 0), "leg.R": {"ankle": Vector3(-0.17, 0.207, -0.10)},
		"sword": {"grip": Vector3(-0.02, 1.22, 0.42), "blade": Vector3(0.62, 0.10, 0.78), "edge": Vector3(-0.8, 0, 0.6),
			"pole": Vector3(-0.6, -0.8, 0.2)}})
	var hit := merge(mid, {"pelvis": Vector3(9, -18, 0), "spine": Vector3(3, -10, 0), "chest": Vector3(3, -14, 2),
		"head": Vector3(-3, 16, 0), "hips": Vector3(-0.03, -0.09, 0.03),
		"arm.L": {"hand": Vector3(0.32, 1.14, 0.10), "pole": Vector3(0.5, -1, -0.3)},
		"sword": {"grip": Vector3(-0.30, 1.22, 0.36), "blade": Vector3(-0.45, 0.05, 0.89), "edge": Vector3(-0.9, 0, -0.45),
			"pole": Vector3(-0.8, -0.5, 0.1)}})
	var follow := merge(hit, {"pelvis": Vector3(9, -26, 0), "chest": Vector3(3, -18, 2),
		"sword": {"grip": Vector3(-0.38, 1.18, 0.16), "blade": Vector3(-0.95, 0.0, -0.1), "edge": Vector3(-0.1, 0, -1)}})
	# the blade is raised on her left side first, so it goes round her and not through her
	var lift := merge(r, {"pelvis": Vector3(6, 6, 0), "chest": Vector3(0, 8, -1),
		"sword": {"grip": Vector3(-0.04, 1.30, 0.42), "blade": Vector3(0.30, 0.90, 0.30), "edge": Vector3(-1, 0, 0.3),
			"pole": Vector3(-0.2, -1, 0.4)}})
	var s := stance()
	return [[0.0, s], [0.17, lift], [0.27, wind], [0.38, mid], [0.46, hit], [0.6, follow], [0.82, r], [1.0, s]]

## Thrust: the blade drawn back level by her right hip, then driven straight ahead in a long lunge.
func _cut_3() -> Array:
	var r := ready()
	var wind := merge(r, {"pelvis": Vector3(4, -26, 0), "spine": Vector3(0, -10, 0), "chest": Vector3(-2, -12, 0),
		"head": Vector3(-2, 22, 0), "hips": Vector3(-0.02, -0.09, -0.05),
		"leg.R": {"ankle": Vector3(-0.16, 0.207, -0.22)},
		"arm.L": {"hand": Vector3(0.40, 1.22, 0.10), "pole": Vector3(0.5, -1, -0.3)},
		"sword": {"grip": Vector3(-0.30, 1.18, -0.16), "blade": Vector3(0.05, 0.05, 1.0), "edge": Vector3(0, 1, 0),
			"pole": Vector3(-0.6, -0.2, -0.8)}})
	var hit := merge(r, {"pelvis": Vector3(14, -10, 0), "spine": Vector3(4, -4, 0), "chest": Vector3(4, -8, 0),
		"head": Vector3(-8, 14, 0), "hips": Vector3(0.0, -0.15, 0.14),
		"leg.L": {"ankle": Vector3(0.18, 0.207, 0.56), "foot": Vector3(-4, 8, 0), "pole": Vector3(0.3, 0.2, 1)},
		"leg.R": {"ankle": Vector3(-0.15, 0.207, -0.30), "foot": Vector3(10, -24, 0), "toe": 10.0},
		"arm.L": {"hand": Vector3(0.40, 1.20, -0.14), "pole": Vector3(0.5, -0.6, -0.8), "wrist": Vector3(0, 0, 10)},
		"sword": {"grip": Vector3(-0.12, 1.26, 0.56), "blade": Vector3(0.08, 0.02, 1.0), "edge": Vector3(0, 1, 0),
			"pole": Vector3(-1, -0.3, 0)}})
	var follow := merge(hit, {"hips": Vector3(0.0, -0.14, 0.12), "sword": {"grip": Vector3(-0.12, 1.25, 0.54)}})
	var s := stance()
	return [[0.0, s], [0.28, wind], [0.46, hit], [0.6, follow], [0.82, r], [1.0, s]]

# ---- Hit, Change Sword, Dragon Dash ------------------------------------------------------------------------------------

func _hit() -> Array:
	var s := stance()
	var jolt := merge(s, {"hips": Vector3(-0.02, -0.05, -0.05), "pelvis": Vector3(-2, -6, 0), "spine": Vector3(-6, 2, 3),
		"chest": Vector3(-9, 2, 4), "neck": Vector3(-4, 0, 0), "head": Vector3(-8, -10, 6),
		"arm.L": {"hand": Vector3(0.34, 1.14, 0.06), "pole": Vector3(1, -0.2, -0.4)},
		"sword": {"grip": Vector3(-0.32, 1.12, 0.10)}})
	var back := merge(s, {"hips": Vector3(-0.02, -0.045, -0.03), "chest": Vector3(-5, 4, 2), "head": Vector3(-2, -4, 2)})
	return [[0.0, s], [0.12, jolt], [0.32, back], [0.6, s]]

func _swap() -> Array:
	var s := stance()
	var up := merge(s, {"hips": Vector3(-0.01, -0.035, 0.0), "pelvis": Vector3(2, -4, 0), "chest": Vector3(-6, 2, 0),
		"head": Vector3(-4, 2, 0), "arm.L": {"hand": Vector3(0.31, 1.06, 0.0)},
		"sword": {"grip": Vector3(-0.10, 1.30, 0.32), "blade": Vector3(0.0, 1.0, 0.12), "edge": Vector3(-1, 0, 0),
			"pole": Vector3(-0.8, -0.6, 0.0)}})
	var hold := merge(up, {"chest": Vector3(-7, 2, 0), "sword": {"grip": Vector3(-0.10, 1.32, 0.33)}})
	return [[0.0, s], [0.24, up], [0.42, hold], [1.0, s]]

func _dash() -> Array:
	var d := merge(stance(), {"hips": Vector3(0.0, -0.16, 0.04), "pelvis": Vector3(18, -6, 0), "spine": Vector3(6, 2, 0),
		"chest": Vector3(6, 4, 0), "neck": Vector3(-8, 0, 0), "head": Vector3(-14, 0, 0),
		"leg.L": {"ankle": Vector3(0.16, 0.207, 0.34), "pole": Vector3(0.2, 0.2, 1), "foot": Vector3(-4, 6, 0)},
		"leg.R": {"ankle": Vector3(-0.14, 0.24, -0.40), "pole": Vector3(-0.2, 0, 1), "foot": Vector3(30, -10, 0), "toe": 26.0},
		"arm.L": {"hand": Vector3(0.36, 1.18, 0.16), "pole": Vector3(1, -0.4, -0.2)},
		"sword": {"grip": Vector3(-0.34, 1.10, -0.02), "blade": Vector3(-0.70, 0.38, -0.60), "edge": Vector3(0, -1, 0),
			"pole": Vector3(-0.7, -0.4, -0.5)}})
	var d2 := merge(d, {"hips": Vector3(0.0, -0.15, 0.04), "chest": Vector3(5, 5, 0),
		"sword": {"blade": Vector3(-0.70, 0.34, -0.62)}})
	return [[0.0, d], [0.3, d2]]

## Pushed back: on her heels, arms out for balance (held while she slides or flies), then she gathers herself.
func reeling() -> Dictionary:
	return merge(stance(), {"hips": Vector3(0.0, -0.08, -0.08), "pelvis": Vector3(-8, 0, 0), "spine": Vector3(-8, 0, 0),
		"chest": Vector3(-10, 0, 0), "neck": Vector3(6, 0, 0), "head": Vector3(10, 0, 0),
		"leg.L": {"ankle": Vector3(0.16, 0.207, 0.22), "foot": Vector3(-12, 10, 0)},
		"leg.R": {"ankle": Vector3(-0.15, 0.207, -0.24), "foot": Vector3(0, -20, 0)},
		"arm.L": {"hand": Vector3(0.42, 1.30, 0.10), "pole": Vector3(0.6, -0.6, -0.4), "wrist": Vector3(0, 0, 0)},
		"sword": {"grip": Vector3(-0.34, 1.24, 0.24), "blade": Vector3(-0.30, 0.55, 0.78)}})

func _stagger() -> Array:
	var s := stance()
	var r := reeling()
	return [[0.0, s], [0.18, r], [0.9, merge(r, {"chest": Vector3(-11, 1, 0), "head": Vector3(9, 2, 0)})]]

func _recover() -> Array:
	var r := merge(reeling(), {"chest": Vector3(-11, 1, 0), "head": Vector3(9, 2, 0)})
	return [[0.0, r], [0.7, stance()]]
