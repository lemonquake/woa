# Custom UI: how it works and where it is going

*For every agent working on this game. Read this before you touch anything players see in the interface.*

## Why this exists

The owner's goal (2026-10-20): players will be able to change how the interface looks, with **free and paid custom
UIs**. Borders, skins and other interface pieces will be swappable at any time. Some will ship free, some will be sold.
The 2026-10-20 d run built the first piece: the **icon border pack**, used for skill and item icons. Every later
customisable piece should follow the same pattern, so the game ends up with **one way** of shipping, choosing and
loading interface art.

So the rule for all interface work is this: **never hard-wire a look that a player might one day want to change.**
Draw it through a loader that reads the selected pack, and fall back to the default when the pack is missing.

## What is customisable today, and what is not

| Piece | Customisable now? | Where it lives |
|---|---|---|
| Skill and item icon borders | **Yes**: packs, chosen in Options > Game > Icon border | `src/ui/icon_border.gd`, `assets/ui/borders/` |
| Skill and item art | Fixed (owner-made art, `assets/ui/art/`) | `UiKit.icon_path`, `UiKit.item_icon` |
| The interface skin (frames, buttons, panels, HUD console, top bar, minimap frame, bars, tabs, sliders, social cards) | No. One fixed skin, 168 pieces | `assets/ui/skin/` + `skin.json`, `UiKit.skin_*` |
| Colours (gold, text, team colours, HP, mana) | No. `const` values in `UiKit` | `src/ui/ui_kit.gd` top |
| Fonts (Cinzel titles, Lato body and bold) | No. Fixed paths | `UiKit.font()` |
| Theme for Godot controls | No. Built once from the skin and cached | `UiKit.theme()` |
| Mouse cursors (targeting) | No | `src/game/targeting_cursor.gd` |
| Menu click sound | No | `src/core/options_agent.gd` (`ui_click.wav`) |
| Player picture and its frame | Picture yes (Edit profile); frame no | `src/ui/avatar.gd`, skin `soc_avatar`, `ring_portrait` |
| Rank emblems | No | `src/ui/rank_emblem.gd` (+ `rank_metal.gdshader`) |
| HUD layout (where slots sit) | No. Hard-coded rects | `hud.gd` `BottomPanel._layout()` and others |
| Loading screen, main menu backdrop, logo | No | `loading_screen.gd`, `main_menu.gd`, skin `logo`, `menu_banner` |

**Not built at all:** player accounts, a store, payments, ownership ("entitlements"), downloads of packs. See
"Free and paid" below before you build any of them.

## The pack pattern (copy this for every new customisable piece)

A **pack** is a folder that holds one manifest (`<kind>.json`) and its images.

1. **Two places, one id.** Shipped packs go in `res://assets/ui/<kind>s/<id>/`. Packs added later go in
   `user://<kind>s/<id>/`, whether downloaded, bought or made by a player. On Windows that is
   `%APPDATA%/Godot/app_userdata/Warriors of Aether/`. A user pack with the same id as a shipped one replaces it.
2. **The manifest describes everything.** That means a display `name`, the pixel `scale` (texture pixels per drawn
   pixel), and per piece: the file, nine-slice margins, offsets and any optional extras. The code must not guess
   sizes from file names.
3. **There is always a default.** Its id is `default`, it ships with the game and it is complete. A missing pack, a
   missing piece or a broken file falls back to the default (or to a named sibling piece) and never to nothing or a
   crash. Warn with `push_warning`; never `assert`.
4. **The choice is an Options key** holding the pack id as a string, such as `icon_border`. `Options` keeps string
   keys only when their default is a string, and `_sanitize()` cleans them with `validate_filename()`. Changing the
   key takes effect on the next frame drawn. Never require a restart.
5. **Load once, cache, and offer `reload()`.** Use `ResourceLoader` for `res://`. Use `Image.load_from_file` +
   `ImageTexture` for `user://`, because nothing there is imported. Keep the cache keyed by pack id.
6. **Draw only through the loader.** Screens never `load()` a pack's PNGs themselves.
7. **The generator lives in `tools/`.** The default pack is made by a script, as `tools/icon_borders.py` and
   `tools/ui_skin.py` are. The pack format is documented in that script's header, so anyone (or any agent) can make a
   new pack.
8. **Packaging.** The export keeps `*.json` (`export_presets.cfg` include filter). `res://` PNGs ship as imported
   textures, so after adding or changing one, run `godot --headless --path . --import`, and commit the `.import` files.
9. **Name packs plainly.** Pack names are player-visible text, so the naming rule applies
   (`lemondev/references/naming.md`): *Default, Plain, Gold, Silver, Stone, Dark*. Never *Emberforged* or
   *Crown of Dawn*. List every new pack name in `docs/HANDOFF.md`.

## Icon borders: the reference implementation

### Files

* `src/ui/icon_border.gd` (`IconBorder`, static): finding, loading and drawing packs.
* `src/ui/icon_frame.gd` (`IconFrame`): a Control that shows a framed icon in menus (Hero Select, a lobby, Options).
* `tools/icon_borders.py`: generates `assets/ui/borders/default/` and `assets/ui/borders/plain/`. Run
  `python tools/icon_borders.py [--preview out.png]`, then `godot --headless --path . --import`.
* `tests/tools/icon_border_sheet.gd`: draws every pack through the real engine code at 1x or 2x (4K scale). Run
  `godot --path . -s tests/tools/icon_border_sheet.gd -- --out=x.png --scale=2`.
* `tests/tools/ui_smooth_probe.gd`: among other checks, switches packs, tests the fallback, writes a pack into
  `user://borders/`, loads it, then deletes it.

### border.json

```json
{"name": "Default", "scale": 4, "ref": 64, "min": 0.5, "max": 1.6,
 "pieces": {
   "skill":   {"file": "skill.png",   "margins": [14, 14, 14, 14], "outset": 3, "shine": "shine.png"},
   "passive": {"file": "passive.png", "margins": [15, 15, 15, 15], "outset": 3, "shine": "shine.png"},
   "item":    {"file": "item.png",    "margins": [11, 11, 11, 11], "outset": 2, "shine": "shine.png"}}}
```

* **Kinds**: `skill` is an active ability. `passive` covers abilities whose `behavior` is `passive` or `innate` (see
  `IconBorder.ability_kind`). `item` is any item. `ultimate` is optional and not used by the game yet; it is reserved
  for packs that want a special ultimate frame. A kind the pack lacks falls back to `skill`; with no `skill` piece
  either, no frame is drawn.
* **Image**: a square frame drawn at `ref` x `scale` pixels (Default: 64 x 4 = 256 px), RGBA, with a transparent
  centre. The rim sits in the outer `margins`, and the image is nine-sliced, so it stretches to any icon shape (item
  tiles are wider than tall).
* **Scaling**: for an icon of size `s`, `k = clamp(s / ref, min, max)`. Margins and outset are multiplied by `k`, and
  the frame is drawn at `icon_rect.grow(outset * k)`. So a 28 px icon gets a rim half the reference width, while a
  96 px icon gets a heavier one, capped at 1.6x.
* **outset**: how far the frame reaches outside the icon, so the rim covers the icon's edge without eating its art.
* **shine** (optional): stretched over the whole icon, under the frame (Default: light from above, a darker foot).

### Drawing API

```gdscript
IconBorder.draw_icon(ci, tex, rect, "skill" | "passive" | "item", art_tint, frame_tint)   # backing + art + shine + frame
IconBorder.draw_item(ci, tex, slot_rect, art_tint, frame_tint) -> Rect2                   # item art filling its slot
IconBorder.draw(ci, rect, kind, frame_tint)          # frame only, over art you drew (used when a cooldown sweep goes between)
IconBorder.item_rect(slot) / draw_cover(ci, tex, r)  # the "cover" crop: art fills the slot's shape and is never stretched
IconBorder.ability_kind(aid) / outset(kind, size) / ids() / pack_name(id) / current() / reload()
IconFrame.make(tex, kind, size)                      # the same thing as a Control
```

A hover or lit state brightens `frame_tint` (`Color(1.25, 1.2, 1.05)`), and a disabled one dims `art_tint`.
**Every** skill or item icon in the game goes through these calls: HUD abilities, innate, unit skills, inventory,
backpack, stash, Teleport slot, courier, To Buy, the whole shop, the talent tree, Hero Select, the ranked pick, the
multiplayer lobby and the Options preview. A new screen that shows such an icon must use them too. The buff bar's
status icons are deliberately left out: they are status effects, not skill or item tiles. Give them their own kind
if they ever become customisable.

### Making a new border pack

* **By code**: add a `build_<id>()` to `tools/icon_borders.py`, reusing `frame()` (metal bands, chamfer or radius,
  inner shadow, studs, glow line) and the matcaps from `tools/ui_skin.py` (`GOLD`, `STEEL`, `BRONZE`, `DARKMETAL`).
* **By hand** (an artist or image generation): make 256x256 RGBA PNGs with a transparent centre and a rim within
  the outer ~56 px (14 drawn px x 4). Write `border.json`, drop the folder in `user://borders/<id>/` to try it, then
  move it to `assets/ui/borders/<id>/` to ship it.
* **Check it**: run `icon_border_sheet.gd` at `--scale=1` and `--scale=2`, and look at a real HUD and shop capture
  (`tests/tools/ui_probe.gd -- --hero=sludge --out=dir`). At 22-32 px the frame must still read and must not cover
  the art. A frame must never sit inside another frame.

## Rules for every interface change (so custom UI stays possible)

* **Interface art is loaded by name through a loader**: `UiKit.skin(...)`, `UiKit.box(...)`, `UiKit.art(...)`,
  `UiKit.skin_tex(...)`, `IconBorder.*`. Never `load("res://assets/ui/skin/x.png")` in a screen, because the skin will
  become a pack (see the roadmap below).
* **Colours come from `UiKit`** (`U.GOLD`, `U.TEXT`, `U.TEXT_DIM`, `U.DAWN`, `U.DUSK`...), never fresh
  `Color(...)` literals for theme colours. Literals for one-off effects (a flash, a shadow) are fine.
* **Fonts come from `UiKit.font("title" | "bold" | "body")`.**
* **Screen changes**: use `Options.go(get_tree(), path)`, never `change_scene_to_file`. It fades, unpauses, and
  opens the loading screen for the match. (Automated runs with `--capture` or `--bench` change at once.)
* **Every popup** closes on a click outside it and on Esc (`UiKit.is_esc(e)`), and fades in with
  `UiKit.pop_in(node)`. Every screen with a Back button keeps it in `_back_btn` and goes back on Esc in
  `_unhandled_key_input`. In-match menus report `blocks_input()` so game keys wait while they are up.
* **Buttons click by themselves**: `OptionsAgent` connects every `BaseButton` added to the tree. Set
  `button.set_meta("silent", true)` to opt out.
* **"Menu animations"** (Options key `ui_motion`) must turn off any new interface motion.
* **Keep hit-testing and drawing on the same rects** (the HUD draws itself and tests clicks on `_item_rects`,
  `_abil_rects`, `_talent_panel`...). A future layout pack has to feed both.
* **The naming rule applies to every label and pack name.** Run `python tools/check_names.py` (it must print
  "Names OK").

## Roadmap: making the rest customisable

These are suggestions, in the order that gives players the most for the least risk. Each step is its own component in
the Gauntlet Loop, with a blind before/after review at matched game state; the pattern is
`tests/tools/ui_probe.gd`. The owner decides what ships, and what is free or paid.

1. **Skin packs**, the biggest win. `skin.json` already is a manifest: piece name, size, nine-slice `margins`,
   `content` margins, `kind`.
   * Turn `UiKit.SKIN_DIR` into the current pack folder (Options key, for example `ui_skin`, default `default`).
   * Move today's `assets/ui/skin/` to `assets/ui/skins/default/`, or keep the path as the default's folder.
   * `UiKit` caches `_skin`, `_skin_tex`, `_skin_boxes` and `_theme`. Switching must clear all four, rebuild
     `theme()`, and re-apply it to open screens (screens set `theme = U.theme()` in `_ready`). Simplest: switch only
     from Options, then rebuild the current screen with `Options.go(tree, current_scene.scene_file_path)`.
   * A pack may hold any subset of the 168 pieces. Missing pieces come from the default.
   * The HUD console art comes in 7 widths (`hud_console`, `hud_console_5..10`) for heroes with up to 10 abilities.
     A skin pack must provide all of them or fall back.
   * Generators: `tools/ui_skin.py` and `tools/ui_skin_social.py`. Add parameters (metal, enamel colour, gem colour)
     rather than copying the file.
2. **Palette in the skin pack.** Change `UiKit`'s colour `const`s into `static var`s filled from the pack's
   `palette` block (gold, gold_dim, text, text_dim, panel_top, panel_bot, hp, mana, dawn, dusk). Keep `DAWN` and
   `DUSK` readable as team colours and keep text contrast. Make this its own step because `const` is used in default
   arguments in places, which `static var` cannot do: grep for `:= U.` and `= UiKit.` in parameter lists first.
3. **Fonts in the skin pack.** Font files plus the title weight. Licences matter: only fonts that allow embedding
   (OFL like Cinzel and Lato). Record each in `docs/ASSET_CREDITS.md`.
4. **Cursor packs** (`targeting_cursor.gd`; enemy, ally and default cursors with hot spots).
5. **Sound packs for the interface** (click, error, open/close). Ambience and effects stay out of this.
6. **Profile cosmetics**: avatar frames (`soc_avatar`, `ring_portrait`), profile banners, name colours. These show
   to *other players* (profiles, forums, the ranked pick), which makes them the natural first paid items. The profile
   save (`Ranked.me()` in `user://ranked.json`) would record which one is worn. Store an id there, never art.
7. **HUD layout packs**: positions and sizes of the bottom panel's parts, minimap side, top bar. This is the riskiest,
   because drawing and click rects must move together and Dota players rely on muscle memory. Do it last, with the
   probes extended to click every slot in every layout.

## Free and paid: what exists and what must not be faked

Today there is **no** account system, store, payment or ownership check. Multiplayer has a lobby server address
(`src/net/main_server.json`) but no logins. Before building anything paid, keep these facts in front of you and in
front of the owner:

* **Anything on the player's computer can be copied.** A pack in `user://`, a PNG in the `.pck`, a flag in a JSON
  save: a player can copy or edit all of these. A check that runs only in the game client stops nobody. Paid
  ownership must be decided by a **server** the owner controls, or by a platform that does it (Steam inventory or
  DLC, itch.io, Epic). Free packs need none of this.
* **Never take payment details inside the game.** Payments go through a provider's own checkout (Steam, itch.io, a
  Stripe-hosted page...). The game only learns "player X owns item Y" from the server. Agents must never write code
  that collects card numbers, and must never create store accounts, keys or prices themselves. Those are the owner's.
* **Paid art must not sit in a public repository.** If the GitHub repo is public, committing a paid pack gives it
  away. Check the repository's visibility with the owner before committing any art meant for sale.
* **Plan ownership as data, not code.** Give each cosmetic a stable id, a kind (`border`, `skin`, `cursor`,
  `avatar_frame`...), a display name, and `free` / `paid`. Shipped free packs need no check. Paid packs, once a
  server exists, would be downloaded into `user://<kind>s/<id>/` (or as a resource pack loaded with
  `ProjectSettings.load_resource_pack`) after the server confirms ownership. `IconBorder` already loads
  `user://borders/<id>/` with no code change.
* **Options pickers should list what the player has.** Today `IconBorder.ids()` lists every pack found. Later, filter
  it by ownership and show locked ones greyed with a plain label ("Locked", "Get it in the Shop"). Never show a
  price the owner did not set.
* **Multiplayer**: other players' cosmetics (avatar frames, banners) would travel as ids in the lobby data, and each
  client draws them only if it has the pack (otherwise the default). Never send art over the lockstep channel, and
  never let cosmetics touch the simulation (`src/sim/` stays deterministic and cosmetic-free).

If the owner asks for a store, start with a written plan (PLAN ONLY in Gauntlet terms): server, provider, item list,
what is free. Get the owner's go-ahead before any code that touches money.

## Testing checklist for any custom UI work

* `python tools/check_names.py`, which must print "Names OK" (pack names are player-visible).
* `sh tools/check.sh` (parse-checks every script).
* `godot --path . -s tests/tools/ui_smooth_probe.gd -- --hero=sludge --nolearn --out=dir` with
  `WOA_RANKED_FILE=user://probe_ranked.json`. It must report 34+ passed, 0 failed; extend it for new pack kinds
  (switch, fallback, user pack).
* `godot --path . -s tests/tools/ui_probe.gd -- --hero=sludge --out=dir`: HUD, talents, courier and shop captures
  in a fixed game state (compare before and after at the same state, or the review is invalid).
* `tests/tools/icon_border_sheet.gd --scale=2` for 4K-scale frames. This monitor is 1080p, so a 3840x2160 window
  cannot be opened here.
* `godot --path . -s tests/tools/ranked_probe.gd -- --out=dir` (51 checks through Ranked, profiles, menus).
* Export, then cold-start `build/WarriorsOfAether.exe -- --match --capture=x.png --t=95 --hero=azrael --lvl=18` and
  look at the capture: it proves the pack shipped in the `.pck`.
* Full suite: `godot --headless --path . -s tests/run_tests.gd` (327 passed, 0 failed on 2026-10-20 d).

## Known gaps (2026-10-20 d)

* The innate skill's frame is thin at 28 px (the last blind review's note). A pack could add a `min` override per
  kind.
* Item key tags (`Alt+Q`) still cover a corner of the art. They are slimmer than before.
* Only two border packs exist (Default, Plain). Skin, palette, fonts, cursors, sounds, cosmetics and layout are still
  fixed (see the roadmap).
* There is no Dota 2 screenshot in the repository as a visual benchmark; reviews compared against the game's own
  previous look.
