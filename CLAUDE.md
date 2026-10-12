# Warriors of Aether: rules for every agent

Godot 4.7.2 Dota 2-style game. Start with `docs/HANDOFF.md` (status, run commands, architecture) and
`docs/MECHANICS.md` (rules and sources).

## Naming rule (strict, applies to every name and every piece of player-visible text)

Read `lemondev/references/naming.md` before you name anything: heroes, abilities, items, units, buildings, teams,
places, menu items, buttons, tabs, settings, tooltips, loading text, tips, errors, outfit pieces, presets, and new
code identifiers.

* Use ordinary words that say what the thing is or does, one to three words: *Bracer, Mini-Axe, Jump Knife, Spell
  Shield, Footman, Options, Sell*. Old DotA and Warcraft III names are the model: simple, but still cool.
* Never invent "epic" compound words (Galewarden, Emberwarden, Crownfall, Ashenfall, Deepwarden, Sunfruit), never use
  lore titles ("X of the Y", "the Crimson Huntress"), never glue on fake-epic suffixes (-warden, -fall, -forged,
  -bound, -keeper, -caller, -walker, -weaver, -bane, -shard), and never use the banned words listed in the rule
  (aether, ashen, ember, gale, crown, gloom, rune, sigil, veil, rift, void, arcane, mystic, eternal, dread...).
* Menus and UI use plain product language: Play, Options, Audio, Video, Shop, Back, "Loading terrain".
* Never copy Dota's names for heroes, abilities or items; rename them plainly.
* Names the owner chose are never changed (list in the rule file: Warriors of Aether, Ancient Light, Black Sun,
  Blood Ranger, Ezee the Dark Paladin, Sludge, Mini-Axe, Vegan Picker and the heroes' ability names).
* Run `python tools/check_names.py` (also part of `sh tools/check.sh`). It must print "Names OK".
* List every new name in `docs/HANDOFF.md` so the owner can veto it.

## Other house rules

* Use the lemondev Gauntlet Loop (`lemondev/SKILL.md`, ledger in `work/lemondev/ledger.md`).
* Mechanics and numbers follow Dota 2 exactly; names, art and heroes are original.
* Windows Python writes CRLF: run `python tools/normalize_eol.py` before commits.
