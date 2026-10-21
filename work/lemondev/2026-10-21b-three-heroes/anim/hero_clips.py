"""Each hero's own clips (run 2026-10-21 b): written into tools/blender/mocap_clips.json (kept apart from the shared
sets there). The owner: melee heroes must not share animations. Sources are Mixamo files in work/downloads/mixamo/raw
(m_* downloaded this run). Options: see tools/blender/mocap_retarget.py (speed, pose, amp, upper, crouch).
  python work/lemondev/2026-10-21b-three-heroes/anim/hero_clips.py
"""
import json

SPEC = "A:/Python/woa/tools/blender/mocap_clips.json"
L, Z = "loop", "zero"

C = {}


def clip(name, src, **kw):
    d = {"src": src, "place": kw.pop("place", Z)}
    d.update(kw)
    C[name] = d


# Attack clips start about 0.5 s before their blow (test_mocap_clips: 0.2-1.0 s), so the game need not rush them.

# ---- Ser Emelrich: the white knight. Upright and proud (hand on hip), heavy two-handed blows, slow and wide.
clip("emel_idle", "gs_39_great_sword_idle", place=L, loop=True, pose={"chest": [-4, 0, 0], "head": [-3, 0, 0]})
clip("emel_run", "gs_50_great_sword_run", place=L, loop=True, run=True)
clip("emel_slash_1", "x_two_hand_sword_combo", end=32, speed=0.95)
clip("emel_slash_2", "x_two_hand_sword_combo", start=28, end=56, speed=0.95)
clip("emel_slash_3", "m_gs_power", speed=1.05)
clip("emel_cast", "gs_41_great_sword_idle", start=30, end=110, kind="cast", speed=1.3)
clip("emel_overhead", "m_gs_down")
clip("emel_sweep", "m_gs_low")
clip("emel_swing", "m_heavy_swing")
clip("emel_hit", "gs_23_great_sword_impact")
clip("emel_death_1", "m_death_knees", place="keep")
clip("emel_death_2", "mag_35_Standing_React_Death_Left", place="keep")

# ---- Araki: the samurai. High guard by the head (hasso), a low fast sprint, quick sharp cuts.
clip("araki_idle", "x_ready_idle", place=L, loop=True, pose={"spine": [6, 0, 0]}, crouch=0.05)
clip("araki_run", "mag_49_Standing_Sprint_Forward", place=L, loop=True, run=True)
clip("araki_cut_1", "x_stable_sword_inward_slash", speed=1.25)
clip("araki_cut_2", "x_stable_sword_outward_slash", speed=1.25)
clip("araki_cut_3", "x_thrust_slash", start=26, end=60, speed=1.2)
clip("araki_dash", "x_thrust_slash", end=50, speed=1.1)
clip("araki_draw", "m_withdraw_sword", kind="cast")
clip("araki_ready", "m_draw_sword", kind="cast")
clip("araki_sheath", "m_sheath_sword")
clip("araki_throw", "m_throwing", kind="cast", speed=1.2)
clip("araki_spin", "x_spinning", kind="cast")
clip("araki_hit", "mag_44_Standing_React_Small_From_Right")
clip("araki_hit_big", "mag_39_Standing_React_Large_From_Left")
clip("araki_death_1", "x_dying", place="keep")
clip("araki_death_2", "mag_36_Standing_React_Death_Right", place="keep")

# ---- Blackfire: the undead brute. Heavy breathing hunch, a lumbering run, smashing two-handed blows.
clip("bf_idle", "m_mutant_breath_idle", place=L, loop=True)
clip("bf_run", "m_mutant_run", place=L, loop=True, run=True)
clip("bf_smash", "x_smash")
clip("bf_club_1", "m_club2_combo", start=38, end=66)
clip("bf_club_2", "m_club2_combo", start=66, end=104)
clip("bf_club_3", "m_club2_combo", start=104, end=140)
clip("bf_swipe", "x_mutant_swiping", start=23, end=63)
clip("bf_grip", "m_choke_lift", kind="cast")
clip("bf_roar", "x_mutant_roaring", kind="cast")
clip("bf_hit", "axe_20_standing_react_large_from_left")
clip("bf_fall", "x_knocked_down", place="keep")
clip("bf_rise", "x_getting_up", place="keep")
clip("bf_death_1", "m_mutant_dying", place="keep")
clip("bf_death_2", "x_shoulder_hit_and_fall", place="keep")

# ---- Thyrandael: the seraph. Hovers on his wings, one-handed sword arcs, wide-armed light casts.
clip("thy_idle", "x_floating", place=L, loop=True)
clip("thy_glide", "x_floating", place=L, loop=True, lean=18, amp={"thigh.L": 0.5, "thigh.R": 0.5, "shin.L": 0.5, "shin.R": 0.5})
clip("thy_slash_1", "x_one_hand_sword_combo", start=17, end=48)
clip("thy_slash_2", "x_one_hand_sword_combo", start=46, end=78)
clip("thy_slash_3", "x_one_hand_sword_combo", start=76, end=122)
clip("thy_leap", "m_torch_04", start=52, end=80)
clip("thy_beam", "mag_11_Standing_2H_Magic_Attack_04", start=30, end=78, place=L, loop=True)
clip("thy_flash", "x_wide_arm_spell_casting", kind="cast")
clip("thy_step", "x_magic_spell_casting", kind="cast", speed=1.3)
clip("thy_judge", "mag_12_Standing_2H_Magic_Attack_05", kind="cast")
clip("thy_hit", "mag_43_Standing_React_Small_From_Left")
clip("thy_death_1", "x_flying_back_death", place="keep")
clip("thy_death_2", "mag_33_Standing_React_Death_Backward", place="keep")

# ---- Burak: the berserker with two axes. Guard up with both axes, a fast run, spinning combos.
clip("burak_idle", "axe_02_standing_block_idle", place=L, loop=True)
clip("burak_run", "m_run_fast", place=L, loop=True, run=True, upper={"src": "axe_02_standing_block_idle"},
     upper_bones="arms", upper_mix=0.75)
clip("burak_spin_high", "axe_12_standing_melee_attack_360_high", speed=1.15)
clip("burak_spin_low", "axe_13_standing_melee_attack_360_low", speed=1.15)
clip("burak_dual_1", "x_dual_weapon_combo", start=19, end=44)
clip("burak_dual_2", "x_dual_weapon_combo", start=42, end=72)
clip("burak_leap", "axe_19_standing_melee_run_jump_attack", end=60, kind="cast")

# ---- Ghorman: the troll with the club. Broad chest, brutish, swinging the club.
clip("ghor_idle", "x_orc_idle", place=L, loop=True)
clip("ghor_run", "m_run_intention", place=L, loop=True, run=True)
clip("ghor_club_1", "m_club1_combo", end=30)
clip("ghor_club_2", "m_club1_combo", start=28, end=54)
clip("ghor_club_3", "m_club1_combo", start=54, end=80)
clip("ghor_bash", "m_bash", start=34, end=70)
clip("ghor_punch", "x_mutant_punch")
clip("ghor_roar", "x_roar", kind="cast")

# ---- Caziel: the assassin. Ninja run.
clip("caz_run", "m_run_ninja", place=L, loop=True, run=True)
clip("caz_idle", "m_ninja_idle", place=L, loop=True)

# ---- Feran: the jester. Clown's ready crouch, a goofy run, sidearm flicks.
clip("feran_idle", "m_clown_idle", place=L, loop=True)
clip("feran_run", "m_run_goofy", place=L, loop=True, run=True)
clip("feran_flick", "m_throw_frisbee", start=25, end=60, kind="cast")

# ---- Azrael: scythe reaper, long sweeps.
clip("azr_reap_1", "gs_15_great_sword_slash", end=36)
clip("azr_reap_2", "mag_09_Standing_2H_Magic_Attack_02", start=23, end=63)
clip("azr_cast", "mag_10_Standing_2H_Magic_Attack_03", kind="cast")

# ---- Lord Kaileh: the lance brute. Lance held high, a heavy weighted run, thrusts and lunges.
clip("kai_idle", "x_fighting_idle", place=L, loop=True, crouch=0.04)
clip("kai_run", "m_run_weighted", place=L, loop=True, run=True, upper={"src": "x_fighting_idle"}, upper_bones="arms",
     upper_mix=0.8)
clip("kai_thrust_1", "x_slash_advance")
clip("kai_thrust_2", "m_torch_stab")
clip("kai_thrust_3", "m_upward_thrust")
clip("kai_charge", "m_run_weighted", place=L, loop=True, run=True, upper={"src": "x_slash_advance", "start": 30, "end": 34},
     upper_bones="upper", upper_mix=0.9, speed=1.25)
clip("kai_sweep", "mag_09_Standing_2H_Magic_Attack_02", kind="cast")
clip("kai_banner", "m_charge_point", kind="cast")
clip("kai_roar", "x_threatening", kind="cast")
clip("kai_hit", "axe_21_standing_react_large_from_right")
clip("kai_death_1", "m_death_back", place="keep")
clip("kai_death_2", "m_death_forward", place="keep")

# ---- Dracoxinia: the royal dragon warrior. Admires her sword, struts, wide two-handed arcs and spins.
clip("drac_idle", "m_gs_admire", place=L, loop=True)
clip("drac_run", "m_run_female", place=L, loop=True, run=True, upper={"src": "gs_00_great_sword_idle"},
     upper_bones="arms", upper_mix=0.85)
clip("drac_slash_1", "gs_17_great_sword_slash")
clip("drac_slash_2", "gs_15_great_sword_slash", start=36, end=64)
clip("drac_slash_3", "gs_27_great_sword_slash")
clip("drac_dash", "gs_34_great_sword_slide_attack", end=40, kind="cast")
# Dragon Leap (the owner swapped her old W and E for a leap and a passive, 2026-10-22): a jumping cut
clip("drac_leap", "x_jump_attack", start=15, end=60, place=Z, flat=True, airborne="auto", kind="cast")
clip("drac_rise", "mag_12_Standing_2H_Magic_Attack_05", kind="cast")
clip("drac_swap", "gs_40_great_sword_idle", start=60, kind="cast", speed=1.6)
clip("drac_blade", "ss_15_sword_and_shield_slash", end=50)
clip("drac_hit", "gs_31_great_sword_impact")
clip("drac_death_1", "mag_35_Standing_React_Death_Left", place="keep")
clip("drac_death_2", "ss_42_sword_and_shield_death", place="keep")

# ---- Gancho: the tree man. Calm tai chi stance, a light quick run, flicked thorns.
clip("gan_idle", "m_fight_idle_taichi", place=L, loop=True)
clip("gan_run", "m_run_quick", place=L, loop=True, run=True)
clip("gan_throw_1", "m_throwing", start=30, end=76, speed=1.2)
clip("gan_throw_2", "m_throw_std", end=46, speed=1.1)
clip("gan_snare", "m_throw_goalie", kind="cast")
clip("gan_seed", "x_throw_object", start=20, kind="cast")
clip("gan_forest", "m_hands_forward", kind="cast")
clip("gan_hit", "mag_41_Standing_React_Small_From_Back")
clip("gan_death_1", "m_death_std", place="keep")
clip("gan_death_2", "mag_34_Standing_React_Death_Forward", place="keep")

if __name__ == "__main__":
    spec = json.load(open(SPEC))
    for k, v in C.items():
        spec[k] = v
    with open(SPEC, "w", newline="\n") as f:
        f.write("{\n" + ",\n".join(" %s: %s" % (json.dumps(k), json.dumps(v)) for k, v in spec.items()) + "\n}\n")
    print("wrote", len(C), "hero clips;", len(spec) - 1, "in all")
