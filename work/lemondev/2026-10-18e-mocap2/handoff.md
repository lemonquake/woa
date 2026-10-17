# Run 2026-10-18 e: handoff (mocap for the remaining clips and the five new heroes, pickable heroes, Airah, joins)

State: IMPLEMENTED; component gates measured (below); no blind critic review (none asked for). Owner's requests in
contract.md, plus mid-run: "use the base_female.glb" for Airah and "build the game now with all the new 5 heroes
pickable by the player, then continue your work" (a build was exported at 05:00 with them pickable, then the work
continued; the final build replaces it).

## Gates (numbers)
* Joins (`tests/tools/anim_joins.gd`, every crossfade the game makes and every loop seam; FAIL = over 12 degrees in a
  1/60 s frame beyond the clips' own motion, finger bones at 40%): baseline `joins_before.txt` 563 failures (worst 76);
  final `joins_final.txt` 23 (worst 16). Same final clips with the old fixed blends (`--fixed`): 584 (worst 63).
  Passes in order: r1 adaptive gap rule 99 -> r4 weapon runs 78 -> r6 simulated candidate blends 53 -> r7 fresh
  collision sets 49 -> r8 cap floors 42 -> r9 finger weight 20 -> r11 cached frames 24 -> final (back leap only for
  Blood Ranger) 23.
* Remnants (`tools/blender/remnant_check.py`, arms lifted; left / torn): Airah 11+7 / 623+1340 -> 0+0 / 0+0 (new body
  on base_female); Emelrich 0+19 / 0+143 -> 0+0 / 0+25; Burak 0+0 / 0+4 -> 0 / 0; Beast Form unchanged (0 / 127+462,
  not reachable in a match). Rejected rebuilds: the arm split (`remnants_r1/`: Emelrich's plate scattered, Burak's belt
  flying off, Airah shredded) and `--reach=1` (`remnants_r2/`: the Beast's hands and mace left at the hips).
* Body collision with every fix applied (`collide_applied3.txt`): every motion-capture clip on every body 1.7 cm or
  less except Sludge's death_from_front (hook 4.2 cm into the floor). The push and hit clips are now in the plan.
* Tests 251/251 (`test_new_heroes_and_blends` new); check.sh Names OK.
* Blend cost: 0.58 ms a hero clip change (simulated), 0.21 ms for creeps (gap rule). Teamfight bench: 19.7 ms with the
  blends, 17.5 / 20.6 ms without (run-to-run spread larger than the difference).

## Traps found
* Mixamo toes curl past 140 degrees and flip their bend direction in one frame in falls (now a hinge, clamped, rate
  limited in `mocap_retarget.py clean_turns`).
* The library's hip offsets were in the hero's metres on every body: short legs sank into the floor (now scaled by
  `MocapClips.leg_scale`, the run speed too).
* Collision sets go stale whenever a clip changes; they lay arm tracks over the clip (a loop seam looked broken until
  `body_collide --fix` ran again).
* A longer crossfade is not always smoother: a limb swinging near half a turn away from the old pose during the blend
  makes the ease take the short way round and flip; `AnimBlend` simulates candidates instead of stretching blindly.
* Airah's sculpt garments (top, briefs) do not fit another body; generating them from the base skin with plane cuts
  gives clean edges and full cover.

## Not done / next
* 23 joins a little over the limit (`joins_final.txt`): Burak's run into his battle cry (16), Blau's and Roydo's runs into
  casts and pushes (their own clips), Azrael's glide into her second slash, Beast Form's old clips.
* The five heroes' kits (hero_ideas.txt); Beast Form's body and mocap; Airah's wind effects.
* Blind critic review; a video look at the joins in a live match (judged from stills and measurements here).
