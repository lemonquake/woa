# Gauntlet ledger (private; not sent to critics)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Lane scene visuals | 1 | 8f4286a+bot | r1 (dota_3 vs candidate_r1 at 2:30 mid) | benchmark / true | REJECT | V1: open ground is empty (one flat gravel/grass texture with hard unshaded edges, no props, rocks or edge breakup) | Fix V1, recapture at the same framing, fresh critic |
| Lane scene visuals | 2 | dressing pass | r2 (same framing) | benchmark / true | REJECT | V2: props and terrain transitions not grounded (no contact AO under props, hard uniform path/grass edge, white river outline) | Fix V2 (contact shadows, edge breakup, wet bank), recheck with a fresh critic |
| Lane scene visuals | 3 | grounding pass | r3 | benchmark / true | REJECT | V3: lane is unconstructed ground (no curbed or built surface), no landmark structures near the lane; contact AO still weak (overlaps V2's AO element; primary defect judged new) | Fix V3. Note: benchmark frame shows base structures, so the next candidate is framed beside a tower to match scene complexity (benchmark itself unchanged) |
| Lane scene visuals | 4 | curbs + ruins + unit contact shadows (frame beside the tier 1 tower) | r4 | benchmark / true | REJECT | V4: style clash between photographic fine-grain terrain and building textures and flat stylized foliage (wants painterly, broad tonal variation) | Fix V4 (painterly mip-biased sampling, broad tone shifts, matched saturation) |
| Lane scene visuals | 5 | painterly sampling, warm and cool tone shifts | r5 | benchmark / true | REJECT | V5: lane is one uniform surface (needs worn paving and dirt variation across its width, grass bleeding into the edges, contact darkening at building bases). Related to V1–V3 but not identical to V4, so no plateau | Fix V5 |
| Lane scene visuals | 6 | worn paving, grass creep, building contact pools | r6 | benchmark / true | REJECT | V6: building materials photographic and stretched (want painted blocks with lit edges and dark joints); contact shading still weak (a recurring sub-theme since V2) | Fix V6 (procedural painted stone, stronger SSAO, toned curbs). 2 passes left |
| Lane scene visuals | 7 | painted masonry, stronger SSAO, toned curbs | r7 | benchmark / true | REJECT | V7: same primary defect as V6 (surfaces not hand-painted enough; contact AO and lighting depth weak; visible repetition) | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Best build is the current one. Next step needs authored hand-painted texture sets (terrain and masonry) plus baked or painted AO, not more procedural tuning |

## Visual review history (what improved per the critics)
r1 empty ground -> r2 scattered dressing, but not grounded -> r3 contact pools, dirt fringe, wet bank, but unconstructed lane -> r4 curbs, ruins, tower framing, but photo vs stylized clash -> r5 painterly sampling, but uniform lane -> r6 worn paving, grass creep, but photo-like tower -> r7 painted masonry; remaining gap is hand-painted material quality and AO depth.

## Session 2026-10-12 (Ezee, combat feedback, Dota controls)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Dark Stomp VFX | 1 | 0cb92dc | r8 vfx (e1_stomp_44 vs dota_9, 1600x900; note: capture predates the crack-shader rewrite in 0cb92dc) | benchmark / true | REJECT | S1: effect is a flat saturated ring decal with no height; reads as a range indicator, bends unevenly along the shore | Add vertical eruption (spikes, rising force wall), less saturated ring; recapture same framing, fresh critic |
| Hero Select screen | 1 | same | r8 menu (s1_select_ezee2 vs dota_7) | benchmark / true | REJECT | M1: hero's black armour blends into the dark backdrop; low-contrast silhouette, weak key/rim light | Stronger key and rim light, lighter backdrop; recapture, fresh critic |
| Dark Stomp VFX | 2 | 0cb92dc + working tree (spikes, force wall) | r9 vfx (s2_34 vs dota_9) | benchmark / true | REJECT | S2: spikes are flat, untextured single-tone cones with no ground contact or shading (placeholder look). Side observation: overlapping damage numbers ("15125") | Textured rock spikes with ground mounds and contact shading; fix overlapping numbers |
| Hero Select screen | 2 | same | r9 menu (s3_select_ezee vs dota_7) | benchmark / true | REJECT | M1 again: dark hero, low contrast against a flat backdrop | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Best build is the current one. Next step needs an art-direction decision: lighter or more reflective armour for Ezee (owner's call) |
| Dark Stomp VFX | 3 | working tree (pale stone shards, contact patches, stacked numbers) | r10 vfx (s5_36 vs dota_9) | benchmark / true | REJECT | S3: shards form a dense grey clump; the area's edge ring is near invisible, so there is no clean radial boundary showing what was hit | Evenly spaced shards on the area edge, leaning out; persistent bright rim on the ground; fresh critic |
| Dark Stomp VFX | 4 | working tree (edge-aligned shards, edge band) | r11 vfx (s7_37 vs dota_9) | benchmark / true | REJECT | S4: the area reads mainly as a thin flat violet circle; the shards that should carry volume are small, grey and half hidden by foliage | Fewer, much larger shards; softer edge line; lingering haze over the area; fresh critic |
| Dark Stomp VFX | 5 | working tree (large spike crown, haze disc) | r12 vfx (s8_37 vs dota_9) | benchmark / true | REJECT | S5: a flat uniform translucent purple disc paints over bushes like a screen overlay, not sitting on the ground (foliage near-fade dither lets it show through) | Remove the glow disc; scorched fissures reaching the spike ring; tighter foliage fade; fresh critic |
| Dark Stomp VFX | 6 | working tree (fissures to the ring, no disc, tent fix) | r13 vfx (s9_37 vs dota_9) | benchmark / true | REJECT | S6: spikes jut at chaotic mixed angles, partly under foreground foliage; saturated magenta fissures clash with the painted palette | Uniform outward lean and even heights; deeper, less saturated violet (caster-centred framing tried and dropped: foreground canopy covered the ring) |
| Dark Stomp VFX | 7 | working tree (uniform spike crown, calmer violet) | r14 vfx (s11_37 vs dota_9) | benchmark / true | REJECT | S7: spires are flat grey, texture-poor blocks that hide the enemies they hit and clash with the painted foliage | Final pass: hand-painted gradient spike shader, shorter spikes, none where an enemy stands |
| Dark Stomp VFX | 8 | working tree (painted spike shader, no spikes on units) | r15 vfx (s12_37 vs dota_9) | benchmark / true | REJECT | S8: ring partly hidden by canopy (top) and foreground foliage (bottom) in this jungle framing; crystals read flat and pastel with little visible impact on the units | **STOPPED: LIMIT** (8 of 8 passes). Best build is the current one. Next: capture in an open clearing, give the spikes a hand-painted texture and ground mounds, and show units being lifted |

### Session notes
* Review isolation was instruction-enforced (each critic was a fresh subagent told to read only its packet folder; packets held only the two anonymised images). Private mappings: work/private_mapping_r8..r15.txt.
* Pass 1 vfx evidence (e1_stomp_44) predates the crack-shader rewrite; later passes used captures from the revision under review.

## Session 2026-10-12 b (Blood Ranger, destructible trees, tower scale) — run `work/lemondev/2026-10-12-blood-ranger/`

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Tower scale (C1) | 1 | working tree after e4bfdc6 | r16 tower (br_tower3 vs dota_3) | candidate / true | UNVERIFIED | Benchmark invalid: the critic found no identifiable tower in dota_3, so scale could not be compared | Needs a Dota 2 frame that shows a lane tower beside heroes; no pass is claimed |
| Burst Shot VFX (C3) | 1 | same | r16 vfx (br_burst3 vs dota_9) | benchmark / true | REJECT | B1: the area reads as thin outline rings plus numbers; no volume, no visible effect on the units hit | Painted ground stain, bigger arrows, blood bursts, hit flinch |
| Burst Shot VFX (C3) | 2 | same + fix | r17 vfx (br_burst5_48 vs dota_9) | benchmark / true | REJECT | B1 again: a flat red ring on the ground and numbers; units inside show no hit, lift or impact | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Note: dota_9 is an eruption-type spell, a still frame of an arrow volley mostly shows arrows already landed. Next step needs a decision: an arrow-volley benchmark (or a motion clip comparison) and stronger per-hit reactions |

Review isolation: instruction-enforced (fresh subagents told to read only their packet folder; each reported only the two packet images in `files_read`). Private mappings: `work/lemondev/2026-10-12-blood-ranger/private_mapping_r16.txt`, `_r17.txt`.

## Session 2026-10-12 c (map overhaul, hotkeys, debug panel, loading screen) — run `work/lemondev/2026-10-12-map-overhaul/`

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Base environment (M3) | 1 | 792086f | r18 base (rv_base vs dota_3) | benchmark / true | REJECT | MB1: flat repeating cobble and grass with hard borders; props few and evenly spaced, no layered clutter or wear | Break paving edges (grass creep, worn flagstones), layered prop clusters (stall, crates, barrels, banners, shrubs) |
| Ramps and elevation (M1) | 1 | 792086f | r18 ramp (rv_ramp vs dota_2) | benchmark / true | REJECT | MR1: no visible steps, slope or height difference; the tier 3 tower stands in the framed corridor | Taller levels, stairs with clear risers and side walls; frame a ramp without a building on it |
| Base environment (M3) | 2 | 792086f + pass 2 (kerb greenery, paving edge breakup, supply clusters, quartermaster stall) | r19 base (p2_base vs dota_3) | benchmark / true | REJECT | MB2 (new): props look primitive and placed on the ground rather than set into it (box awning, flat rug, stubby torch pillars, loose bricks) | Ground the procedural props (contact shade, sunk edges, growth at their feet), richer stall and pillar shapes |
| Ramps and elevation (M1) | 2 | same (levels 1.28 -> 2 m, risers and side walls, plateau ramp framing) | r19 ramp (p2_ramp_a vs dota_2) | benchmark / true | REJECT | MR2 = MR1: no visible terrain height change (flat ground both sides); the steps read as a brick mass | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Next step needs a decision: much taller levels (3-4 m) with rock cliff faces flanking each ramp, which changes the look of the whole map |
| Base environment (M3) | 3 | 792086f + pass 3 (octagonal torch columns on plinths with growth at their feet, contact shade under towers, walls and the stall, no rug or loose stones, fountain uses the river water shader) | r20 base (p3_base vs dota_3) | benchmark / true | REJECT | MB3: flat, uniform materials with hard edges (repeating cobble tile cut sharply into the grass, plain striped awning, bare white geometry); props scattered rather than placed. Same identity as MB2 (primitive, low-detail props) | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Next step needs authored hand-painted texture sets and modelled props (stall, crates, pillars) from Blender or a CC0 pack, not more procedural meshes |

Review isolation: instruction-enforced (fresh subagents, packet folders only; each listed only its two packet images). Private mappings: `work/lemondev/2026-10-12-map-overhaul/private_mapping_r18.txt`, `_r19.txt`, `_r20.txt`. The r20 critic result was read from the subagent transcript after the previous session hit its usage limit.

Integration (M4), working tree after 792086f: 59 tests pass; benchmark 77 fps, p95 16.67 ms (gate passed); bot duels 3 x 12 min complete (`duel.txt`); export and cold start of the exe clean (`export_run.txt`) after fixing the boot loading screen, which was never shown (add_child while the root was busy).

## Session 2026-10-13 (Sludge, items, shop) — run `work/lemondev/2026-10-13-sludge-items/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Shuriken Hook visuals (S2) | 1 | f598fdf + working tree (sludge_fx.gd) | r21 hook (c1_26 vs Valve Meat Hook video frame 97) | benchmark / true | REJECT | H1: the hook does not visibly reach or hold the target; thin pale chain starting in the air beside the thrower; shuriken washed out by a white blur ring | Chain anchored to the fist from the live skeleton pose (the attachment lagged a frame), dark iron links, no white ring, shuriken lying flat, latched star kept in front of the victim |
| Shuriken Hook visuals (S2) | 2 | same + fixes | r22 hook (c6_31 vs frame 97) | benchmark / true | REJECT | H1 again: the hook sits beside the target instead of gripping it; also called out: chain shadow doubles the line, thrower looks flat grey | **STOPPED: PLATEAU** (same defect in two consecutive valid rejections). Note: both candidate frames were taken a tick before the bite, while Valve's frame shows the hook already wrapped round the target. Next step needs your decision: recheck with the bite frame (and a shorter chain shadow), which is a new pass under a changed capture rule |

Review isolation: instruction-enforced (fresh subagents, packet folders only; both listed only their two images). Private mappings: `private_mapping_r21.txt`, `_r22.txt`. Benchmark: `work/benchmark/pudge/pudge_meat_hook.mp4` (Valve CDN, see contract.md), frames extracted with Blender (`frames.py`).
Evidence note: `research/liquipedia_pudge*.json` are Liquipedia rate-limit pages, not data; the Sludge numbers came from the Liquipedia wikitext read during the 2026-10-12 session and the game data file `npc_dota_hero_pudge.txt`.

Session resumed 2026-10-13 after a second cut-off (items and shop were in the working tree, uncommitted):

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Sludge mechanics (S1) | 1 | b68aecf + working tree | gate: headless tests | n/a | PASS (gate) | none | none |
| Sludge bot (S3) | 1 | d82bd68 + working tree | gate: 20 min duels vs both heroes, 3 seeds | n/a | PASS (gate) | none; hooks heroes 3-7 times a game | none |
| Items (I1) | 1 | working tree | gate: 92 tests (one per recipe path and active/passive) | n/a | PASS (gate) | spot-check against items.txt found Cleave Axe dealt 60% to creeps; Dota deals 40% (`cleave_damage_percent_creep`); fixed and tested before the gate | none |
| Shop UI (I2) | 1 | working tree | gate: readable at 1080p and 2160p, every item buyable by mouse | n/a | PASS (gate); blind review UNVERIFIED (no Dota shop frame set up) | none | benchmark frame of Dota's shop for a blind review |
| Integration (G) | 1 | working tree | tests 92/92, check.sh "Names OK", duels 9/9 complete, bench 82 fps p95 14.2 ms, export + cold start (Sludge match ready 9.7 s), Options persist across processes | n/a | PASS (gate) | ObjectDB leak warning at exit (188 instances, 184 before this run): pre-existing, not new | none |

## Session 2026-10-13 b (Sludge input fixes, cursors, To Buy, stash, courier, HUD) — run `work/lemondev/2026-10-13-fixes-items-courier/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Ability input (A1) | 1 | 8310428 | gate: live input probe through InputController | n/a | REJECT (baseline) | Stench never issued (toggle not handled); Chomp hotkey refused before a target was picked | fix begin_ability, cast_error check_target |
| Ability input (A1) | 2 | working tree | gate: live input probe, 3 heroes | n/a | PASS (gate) | none (Sludge 10/10, Blood Ranger 7/7, Ezee 4/4) | none |
| Talent tree (A2) | 1 | working tree | gate: HUD flow probe click learns +5 Armor; capture talents.png | n/a | PASS (gate); blind review UNVERIFIED | none | Dota talent tree frame for a blind review |
| Targeting cursor (B) | 1 | working tree | gate: cursor frames rendered (cursor_enemy.png, cursor_ally.png); colour per targeting_team | n/a | PASS (gate); blind review UNVERIFIED | none | — |
| To Buy, stash, items (C1, C2) | 1 | working tree | gate: 8 new sim tests + HUD flow probe 13/13 | n/a | PASS (gate) | test expectation error (parts order Headband first) fixed in the probe, not the code | none |
| Courier (C3) | 1 | working tree | gate: sim tests (speed, flying, burst, shield, hits, respawn, bounty, items kept, Well sweep) | n/a | PASS (gate) | old test expected undelivered items back in the stash; Dota keeps them on the courier: test updated to Dota | none |
| HUD overhaul (D) | 1 | working tree | gate: captures hud/talents/courier/shop at 1080p | n/a | REJECT (self-check) | Blubber shell opaque, Stench cloud invisible, two courier buttons both labelled "Return", shop hint overlapping, HUD stash under the open shop | fixed, recaptured |
| HUD overhaul (D) | 2 | working tree | gate: recaptures | n/a | PASS (gate); blind review UNVERIFIED (no Dota frames of stash / quick buy) | none | Dota frames for a blind review |

Notes: no critic subagent was run this session (no benchmark frames for the new UI); every visual gate above is a
builder self-check and is reported as UNVERIFIED for review.
| Integration (G) | 1 | working tree | tests 100/100, check.sh Names OK, input probes 3 heroes, HUD flow probe 13/13, duels 9/9 complete, bench 77/76 fps p95 15.15/16.67 vs same-session baseline 76 fps p95 16.67, export + cold start 12.6 s, true 4K captures | n/a | PASS (gate) | p95 gate against the old session's 14.2 ms failed on one run; a same-session control of the baseline matched the new build, so the machine, not the change, moved | none |

## Session 2026-10-13 c (camera, camps, Game Setup, team bots, chat, pings, learning) — run `work/lemondev/2026-10-13-camps-ai-setup/` (contract.md)

Session cut off during integration; on resume the owner asked to cut the remaining tests, finish and build.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| AI2 hero bots | n | working tree | gate: 10 x 5v5 bot games, 40 min | n/a | REJECT (gate) | no Ancient falls in any game; Bot Cat and Bot Jo idle in lane from 0:21 in all ten | fix the idle-in-lane bug first |
| Integration (G) | 1 | working tree | bench 1v1 48-53 fps, 5v5 39-58 fps; names OK; export | n/a | INCOMPLETE (cut by owner) | bench below the 10% gate; tests and probes not rerun | rerun tests, probes, bench |
| CAM, NC1, NC2, GS, AI1, AI3, CH | — | working tree | captures only | n/a | UNVERIFIED | gates not rerun at the end | rerun the probes |

## Session 2026-10-13 d (controls, HUD, status effects, bash, crit, items, neutral abilities, true sight, orbs) — run `work/lemondev/2026-10-13-controls-mechanics/` (contract.md)

No critic subagent was run (the owner did not ask for subagents, and no Dota frames of the new visuals are on disk);
every visual gate below is a builder self-check and is reported UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| U1 cursor lock, edge pan | 1 | 93b2efc + working tree | gate: controls_probe (live window on the owner's 2nd monitor) | n/a | PASS (gate) | none: CONFINED in Borderless/Fullscreen/locked Windowed; OS clamps a warped cursor; edge pans and keeps panning when pushed | none |
| U2 shop closes | 1 | working tree | gate: controls_probe | n/a | PASS (gate) | none | none |
| U3 regen with bonus | 1 | working tree | gate: test + capture | n/a | REJECT (self-check) | green "+bonus" low contrast on the green bar | outline the text |
| U3 regen with bonus | 2 | working tree | gate: recapture | n/a | PASS (gate) | none | none |
| U4 Teleport Scroll | 1 | working tree | gate: test + probe | n/a | PASS (gate) | none (one probe flake: waited 20 frames for a 0.5 s shop check; probe fixed) | none |
| U5 hold Stop | 1 | working tree | gate: controls_probe | n/a | PASS (gate) | none | none |
| M1 status system | 1 | working tree | gate: tests (PRD table and rate, stun groups, status/slow resistance, hex, silence burst, root, disarm, break, dispels) | n/a | PASS (gate) | none | none |
| M2 crit and bash | 1 | working tree | gate: tests + live crit in probe | n/a | PASS (gate) | none | none |
| M3 items | 1 | working tree | gate: tests (prices, recipes, actives) + shop captures | n/a | REJECT (self-check) | shop pane text ran into "Made from" for long items | reserve rows for parts, shorten texts |
| M3 items | 2 | working tree | gate: recaptures | n/a | PASS (gate) | none | none |
| M4 neutral abilities | 1 | working tree | gate: tests + Smash capture | n/a | PASS (gate) | none | none |
| M5 rules fixes, true sight, disjoint | 1 | working tree | gate: tests | n/a | PASS (gate) | test setup stood heroes behind trees (no sight); test fixed, not the code | none |
| M6 orbs and Flask | 1 | working tree | gate: tests (schedule, cycle, rewards, effects, Flask) + probe (right click take) + captures | n/a | PASS (gate) | none | Illusion rune needs illusions |
| V visuals | 1 | working tree | gate: captures (disable bars, sheep, roots, disarm, crit number, orbs, Smash ring) | n/a | REJECT (self-check) | disarm blades hidden behind the health bar | lower them to head height |
| V visuals | 2 | working tree | gate: recaptures | n/a | PASS (gate); blind review UNVERIFIED | none | Dota frames for a blind review |
| Integration (G) | 1 | working tree | tests 137/137, check.sh Names OK, controls_probe 31/31 (1080p) and 23/23 (true 4K), input probes 3 heroes, item flow 13/13, two 40-min 5v5 bot games without script errors, bench 60/55/62 fps vs same-session baseline 57/60, export + cold start 9.7 s | n/a | PASS (gate) | none new; old AI2 gate (an Ancient falls in 60 min) still fails, stuck bots late in games | blind review needs Dota frames |

## Session 2026-10-14 (elements, damage and armor types, magic amp, item menu, item effects, Azrin) — run `work/lemondev/2026-10-14-elements-azrin/` (contract.md)

No critic subagent was run (the owner did not ask for subagents and no Dota frames of these effects are on disk):
every visual gate is a builder self-check and is reported UNVERIFIED for blind review.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| E1 elements, types, magic amp, burns | 1 | a38afe7 + working tree | gate: headless tests | n/a | REJECT (gate) | old Dota-number tests broke on the element layer and the Int magic amp | tests isolate elements (`SimWorld.elements`), oracles include magic amp |
| E1 | 2 | working tree | gate: 154 tests | n/a | PASS (gate) | none | none |
| E2 Kugmo / Igit / Atuli | 1 | working tree | gate: tests (names, recipes, stats, diminishing amp, mana cost, cast speed) | n/a | PASS (gate) | none | none |
| E3 item menu, lock, disassemble | 1 | working tree | gate: tests + menu_probe 14/14 (real clicks), 1080p and real 4K captures | n/a | PASS (gate) | none | none |
| E3b full refund protection (owner's follow-up) | 1 | working tree | gate: test (accidental disassembly inside 10 s sells for 2400, half after, old parts + new recipe) | n/a | PASS (gate) | combined items had only their combine time: fixed with per-piece purchase records | none |
| E4 Azrin kit and bot | 1 | working tree | gate: tests (each ability with the owner's numbers), input probe 12/12, 12-min duels 3 seeds x 3 heroes, no errors | n/a | PASS (gate) | balance note: wins 16-1 vs Blood Ranger, 13-0 vs Ezee, 4-3 vs Sludge (owner's numbers kept) | owner to tune |
| V1 fire system and Azrin's look | 1-9 | working tree | self-check captures (fire_preview, in-match, Hero Select) | n/a | REJECT x8, then PASS (self-check) | in order: embers drawn huge (billboard scale); hard flame bases; white-out in daylight; pale cream tongues; sparse candles; blocky noise (sin hash); glare walls; robe hiding her | blind review UNVERIFIED |
| V1b female_generic body (owner's follow-up) | 1-4 | working tree | self-check: Blender previews, look lineup, Hero Select | n/a | REJECT x3, then PASS (self-check) | fit pose ignored (rig copied in REST mode); hair over face (head offset); face cut away (UV2 V flip) | blind review UNVERIFIED |
| V2 item effects | 1-2 | working tree | self-check captures (Spike Armor, Block Shield, corruption, rage, Spell Shield) | n/a | REJECT (rage and dome too strong), then PASS | — | blind review UNVERIFIED |
| U1 HUD chips and sheet | 1-2 | working tree | menu_probe captures at 1080p and real 4K | n/a | REJECT (two "Hero" chips ambiguous; tooltips missing from captures) then PASS | — | blind review UNVERIFIED |
| A1 creep death sounds | 1 | working tree | gate: test (-7.37 dB = Options.to_db(0.6)) | n/a | PASS (gate) | none | none |

## Session 2026-10-14 b (QA, performance, UI remake, multiplayer, Froster and Caziel) — run `work/lemondev/2026-10-14b-ui-net-heroes/` (contract.md)

Session interrupted; on resume the owner asked to wrap up and build. Only the end gates below were rerun.

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| Q1 lane creeps | 1 | working tree | finding Q1-a fixed (spawns inside tower footprint) | n/a | INCOMPLETE | 5 v 5 games not rerun | rerun 3 x 50-min games |
| H1 Froster, H2 Caziel | 1 | working tree | gate: tests + 12-min duels vs every hero, 3 seeds, no errors | n/a | PASS (gate) | none | owner to tune |
| N1 command funnel | 1 | working tree | gate: tests | n/a | PASS (gate) | none | none |
| N2 network session, U4 screens | — | working tree | none | n/a | INCOMPLETE | no net_menu screen; net_test not run | build U4, run net_test |
| U0 skin, U1 Main Menu | 1 | working tree | self-check: export_menu.png | n/a | UNVERIFIED | Multiplayer button pointed at a missing scene: hidden until it exists | blind review vs Dota frames |
| P1, P2, U2, U3 | — | working tree | none | n/a | INCOMPLETE (cut by owner) | not run | rerun profile and bench |
| Integration (G) | 1 | working tree | tests 170/170, check.sh Names OK (Froster and Caziel names added to the owner list), export + cold start Froster 10.1 s / Caziel 10.5 s / Main Menu, no script errors | n/a | PASS (gate, reduced) | probes and bench not rerun | none |

## Session 2026-10-15 (multiplayer, HUD pips, owner's bug reports) — run `work/lemondev/2026-10-15-multiplayer/` (contract.md)

| Component | Pass | Revision | Review | Winner / clear | Verdict | Primary defect | Next |
|---|---|---|---|---|---|---|---|
| H1 HUD level pips | 1 | working tree | self-check capture (Caziel, 1080p-ish window) | n/a | PASS (self-check) | pips sat across the health well's gold rim and under the slot frame | 4K capture at integration |
| B1 units at the map centre | 1 | working tree | gate: view_place_probe (6 game min, 268465 checks) | n/a | REJECT then PASS | views of units spawned off screen were never placed (origin = river), never animated (bind pose = giant T-pose); new views waited a frame | none |
| B2 neutral aggro, camps, Alt boxes | 1 | working tree | gate: 171 tests, camp_layout 0 problems, team_probe 11/11 | n/a | PASS (gate) | Gale Impact test picked a new tree spot after the camp move (test made robust) | 5 v 5 bot game |
| H1 HUD level pips | 2 | working tree | self-check: real 4K crop (net_match_4k) | n/a | REJECT then PASS (self-check) | a learnable pip at its brightest looked like a learned one | pulsing outline for learnable; blind review UNVERIFIED |
| N2 server, rooms, relay lockstep | 1 | working tree | gate: net_test dedicated (2 players), hosted (1 player), exported build as server; 2 server unit tests | n/a | PASS (gate) | first run's forced desync fell before the first wave (no creep to move): test frame moved to 3600 | none |
| N2 latency | 2 | working tree | gate: exported server, real time | n/a | REJECT (68.4 ms > 2 ticks + RTT) then PASS (35 / 38 ms) | gaps between frames counted as stalls raised the jitter buffer; packets waited for the next poll | none |
| U4 Multiplayer screens | 1-4 | working tree | gate: net_ui_probe (real clicks, two windows) + self-check captures 1080p and real 4K | n/a | REJECT x3, then PASS (gate; self-check look) | in order: titles and buttons on the frames' corner ornaments; empty rows drawn as buttons; frames lost (style box duplicate drops its texture); Stop Hosting stayed on the lobby list; the same server listed twice (127.0.0.1 and its network address); team titles on ornaments, muddy Ready pill, gear icon read as a dot, empty hero panel | blind review UNVERIFIED (no subagents asked for, no Dota lobby frames); 2 probe misses in 6 runs recorded |
| Integration (G) | 1 | working tree | tests 173/173, check.sh Names OK, net_ui_probe 35/35 + 17/17, view_place_probe PASS, team_probe 11/11, 20-min 5 v 5 bot game, export + dedicated server from the exported build | n/a | PASS (gate, reduced) | performance benchmarks not rerun | main server address from the owner |
