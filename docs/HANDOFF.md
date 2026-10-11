# Warriors of Aether: handoff

*A Dota 2-style lane battle game by Aljay Leodones. Godot 4.7.2 (Forward+), Blender 5.2 for building models.*

## Status (keep this section current)

**IMPLEMENTED, UNVERIFIED.**

Verified:
* The simulation's mechanics pass 30 headless tests.
* The game renders and plays, with bots on both sides, as seen in the screenshots under `work/shots/`.

Not yet done:
* No independent blind visual review against Dota 2 reference images.
* No sustained frame-time measurement. The sim profiles at about 2.5 ms per tick with ~150 units.

## Run it

```
"C:\Users\Lemon PC\Desktop\Godot.exe" --path A:\Python\woa
```
or open `A:\Python\woa\project.godot` in the editor and press F5.

* Tests (headless, about 1 minute): `godot --headless --path . -s tests/run_tests.gd`. Add `-- --only=<name>` for a subset.
* Screenshot capture (renders, saves, quits): `godot --path . res://src/game/main.tscn -- --capture=work/shots/x.png --t=95 --cam=-1500,-1300 [--autoplay] [--zoom=1.1]`. `--autoplay` lets a bot drive your hero too.
* Parse-check every script: `sh tools/check.sh`.
* Rebuild the building models: `"C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup --python tools/blender/buildings.py`.
* Re-bake the terrain texture arrays (needs the GPU, not headless): `godot --path . -s tests/tools/bake_terrain_arrays.gd`.

## Controls (Dota defaults)

| Key | Action |
|---|---|
| Right click | Move, attack an enemy, deny an ally below 50% HP, follow an ally |
| A, then left click | Attack-move (ground) or attack (unit) |
| S | Stop |
| H | Hold position |
| Shift | Queue the order |
| Q W E R | Abilities. Point and unit abilities show a targeting cursor; right click or Esc cancels |
| Ctrl + Q W E R, or the "+" above an ability | Learn the ability |
| Right click an ability button | Toggle autocast (Frost Quiver) |
| Z X C V B N | Items. Right click an item slot to move it between the inventory and the backpack |
| F4, the Shop button, or B with an empty slot 5 | Shop |
| J, or the button above the minimap | Glyph |
| F1 | Select your hero; press twice to centre on it |
| Space (hold) | Follow your hero |
| Screen edges, arrow keys, middle-drag | Pan the camera |
| Mouse wheel | Zoom |
| Minimap | Left click or drag moves the camera; right click moves your hero |

## Architecture

```
src/sim/      deterministic 30 Hz simulation (no nodes). Rules, numbers and sources: docs/MECHANICS.md
  sim_const   rules constants (APPROX marks unverified values)    sim_data   unit, hero, ability and item data
  sim_map     terrain levels, river, bases, ramps, trees, A* grid, lanes, camps
  sim_world   tick loop, clock, waves, regen, backdoor, respawn, invulnerability chain, glyph
  sim_orders  turning, movement and collision, attack point and backswing, chase, hold, attack-move, casting
  sim_combat  projectiles, attack classes, armor, damage, deaths, bounties, XP, kill and assist gold
  sim_ai      waves, lane creep targeting and aggro, towers, neutral camps (stacking)
  sim_vision  fog of war (raycast grid, trees and high ground block sight, day and night ranges)
  sim_abilities  Galewarden's kit, items' active abilities, attack modifier (orb) rules
  sim_shop    buying, recipes, stash, selling        sim_bot   laning bot (last-hits, denies, harass, retreat, build)
src/game/     presentation (reads the sim, never writes it except through commands)
  main        boot, 30 Hz stepping in _physics_process, event dispatch, fog texture, capture mode
  terrain_builder + terrain.gdshader   9-layer splat terrain from the sim map, river water
  foliage + foliage.gdshader           Quaternius trees (one instance per sim tree), grass and plants
  building_view + building/crystal shaders   Blender-built faction buildings
  unit_view + model_catalog            animated units, attack swings timed to the sim's attack point
  fx, camera_rig, atmosphere (day/night), fog_of_war.gdshader, input_controller
src/hero/     customisable hero body ported from beyond-heroes (HeroLook, HeroAppearance)
src/ui/       hud (bottom panel, minimap, top bar, shop, tooltips), unit_bars (health bars, gold popups), ui_kit
tests/        run_tests.gd (mechanics), tools/ (bakes, probes)
tools/        blender/buildings.py, build_wear_catalog.py, itch_dl.sh, kv.py (research), check.sh
```

## The customisable hero (your request: "very very customisable and dressable")

`HeroAppearance` drives `assets/characters/hero/hero.glb`, the body you supplied in beyond-heroes. It has 132 animations, including the full bow set and female locomotion.

* **Look** (`HeroLook`):
  * 20 shape keys: the female figure, muscle, belly, build, rear, and 15 face shapes.
  * Height, head, hands and feet size.
  * Skin, eye, lip, brow and marking colours, plus 12 skin patterns, 10 eye styles, 7 brow styles and 8 markings.
  * 16 hair styles and 8 beards, each with a length slider.
  * 13 presets (Huntress, Shieldmaiden, Moon Elf, Goblin King and more).
* **Outfit**: 143 worn pieces in 10 slots (inner garment, armor, leggings, helm, gloves, boots, 4 accessories), listed in `assets/characters/hero/wear/catalog.json`. Every piece follows the body sliders, the female shape included. Each slot can be dyed (cloth, trim, leather, metal, gold).
* Heroes are set up in `main.gd` `_spawn_heroes()`. A hero creator screen is the next UI step (see the backlog below).

## Assets and licences

See `docs/ASSET_CREDITS.md`.

## Backlog: smallest next actions first

1. Art pass on buildings:
   * Better Ancient design: floating crystal and rune ring instead of the stick arms.
   * Larger stone blocks on towers.
   * Replace the paving texture, which reads as a checkerboard.
2. Hero creator screen (sliders, style pickers, outfit and dye per slot) before the match, saved to `user://hero.json`.
3. Courier, Town Portal scroll, buyback button, secret shop, runes and Roshan (deferred features).
4. More heroes; the bot currently plays only Galewarden mid.
5. Blind visual review against Dota 2 reference captures (lemondev gauntlet) and a performance gate: a 60 s window with p95 frame time under 16.7 ms at 1080p on the RTX 4060.
