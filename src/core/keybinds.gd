class_name Keybinds
extends RefCounted
## The player's hotkeys: one key or key combination (Ctrl + key, Alt + key, Ctrl + Alt + key, or Mouse 4 / 5 with
## those modifiers) per action, edited on the Hotkeys screen before a match and saved to user://keybinds.json together
## with named templates. Shift is never part of a hotkey: as in Dota it queues the order (Shift + any hotkey queues it).
## Fixed: Ctrl + an ability's hotkey learns it (unless that combination is itself bound), Alt + click pings,
## Ctrl + 1..9 sets a control group.
##
## A binding is an int: a Godot keycode, or MOUSE_BASE + a mouse button index, OR'ed with KEY_MASK_CTRL / KEY_MASK_ALT.

const PATH := "user://keybinds.json"
const MOUSE_BASE := 1 << 24
const MODS := KEY_MASK_CTRL | KEY_MASK_ALT

## [action, label, group, default binding]. The order is the order shown on the Hotkeys screen.
const ACTIONS := [
	["ability_1", "Ability 1", "Abilities", KEY_Q],
	["ability_2", "Ability 2", "Abilities", KEY_W],
	["ability_3", "Ability 3", "Abilities", KEY_E],
	["ability_4", "Ability 4 (ultimate)", "Abilities", KEY_R],
	["item_1", "Item slot 1", "Items", KEY_Z],
	["item_2", "Item slot 2", "Items", KEY_X],
	["item_3", "Item slot 3", "Items", KEY_C],
	["item_4", "Item slot 4", "Items", KEY_V],
	["item_5", "Item slot 5", "Items", KEY_B],
	["item_6", "Item slot 6", "Items", KEY_N],
	["tp", "Teleport", "Items", KEY_T],
	["attack", "Attack", "Orders", KEY_A],
	["stop", "Stop (hold: hard stop)", "Orders", KEY_S],
	["hold", "Hold position", "Orders", KEY_H],
	["select_hero", "Select hero (twice: centre)", "Units", KEY_F1],
	["select_courier", "Select courier", "Units", KEY_F2],
	["courier_deliver", "Courier: deliver items", "Units", KEY_F3],
	["follow_hero", "Follow hero (hold)", "Camera", KEY_SPACE],
	["camera_up", "Pan camera up", "Camera", KEY_UP],
	["camera_down", "Pan camera down", "Camera", KEY_DOWN],
	["camera_left", "Pan camera left", "Camera", KEY_LEFT],
	["camera_right", "Pan camera right", "Camera", KEY_RIGHT],
	["shop", "Open shop", "Interface", KEY_F4],
	["glyph", "Fortify", "Interface", KEY_J],
	["scoreboard", "Scoreboard (hold)", "Interface", KEY_TAB],
	["debug", "Debug panel", "Interface", KEY_F9],
]

## Keys an action may never take: they open menus or are modifiers.
const RESERVED := [KEY_ESCAPE, KEY_F10, KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META, KEY_CAPSLOCK]
const MODIFIER_KEYS := [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]

## Why a binding cannot be used ("" = it can): menu keys, control groups, system shortcuts.
static func refuse(b: int) -> String:
	var base := b & ~MODS
	if base in RESERVED:
		return "%s is reserved (menus and modifiers)" % name_of(base)
	if b & KEY_MASK_CTRL and not (b & KEY_MASK_ALT) and base >= KEY_1 and base <= KEY_9:
		return "Ctrl + 1-9 set control groups"
	if b & KEY_MASK_ALT and base in [KEY_F4, KEY_TAB]:
		return "%s is a system shortcut" % name_of(b)
	return ""

static var binds := {}                     # action -> binding
static var templates := {}                 # template name -> {action: binding}
static var _loaded := false

static func defaults() -> Dictionary:
	var d := {}
	for a in ACTIONS:
		d[a[0]] = a[3]
	return d

## Built-in templates the player can start from (they cannot be overwritten or deleted).
static func builtin_templates() -> Dictionary:
	var dota := defaults()
	# items on Alt-free keys near the left hand, abilities unchanged
	var near := defaults()
	near.merge({"item_1": KEY_1, "item_2": KEY_2, "item_3": KEY_3, "item_4": KEY_4, "item_5": KEY_5, "item_6": KEY_6,
		"tp": KEY_G, "courier_deliver": KEY_F, "select_courier": KEY_F2}, true)
	# abilities on the home row
	var home := defaults()
	home.merge({"ability_1": KEY_Q, "ability_2": KEY_W, "ability_3": KEY_E, "ability_4": KEY_D, "item_1": KEY_Z,
		"item_2": KEY_X, "item_3": KEY_C, "item_4": KEY_V, "item_5": KEY_F, "item_6": KEY_G, "tp": KEY_T,
		"hold": KEY_R}, true)
	return {"Default (Dota)": dota, "Items on 1-6": near, "Ultimate on D": home}

static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	binds = defaults()
	templates = {}
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		return
	binds.merge(_clean(data.get("current", {})), true)
	var t = data.get("templates", {})
	if t is Dictionary:
		for name in t:
			var m := defaults()
			m.merge(_clean(t[name]), true)
			templates[String(name)] = m

static func save() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"current": binds, "templates": templates}, "\t"))

## Keep only known actions with integer bindings (JSON numbers come back as floats).
static func _clean(d) -> Dictionary:
	var out := {}
	if not (d is Dictionary):
		return out
	var known := defaults()
	for k in d:
		if known.has(String(k)) and (d[k] is float or d[k] is int):
			var v := int(d[k])
			if v < 0:
				v = MOUSE_BASE - v             # older saves stored mouse buttons as negative numbers
			out[String(k)] = v
	return out

static func key(action: String) -> int:
	load_all()
	return int(binds.get(action, 0))

## Set an action's binding. Another action holding that key swaps to this action's old key, so nothing is ever left
## without a key. Returns the action that was swapped ("" if none).
static func assign(action: String, binding: int) -> String:
	load_all()
	var old := key(action)
	var other := ""
	for a in binds:
		if a != action and int(binds[a]) == binding:
			other = a
			binds[a] = old
	binds[action] = binding
	return other

static func apply_template(name: String) -> void:
	load_all()
	var all := builtin_templates()
	all.merge(templates, true)
	if all.has(name):
		binds = defaults()
		binds.merge(all[name], true)

static func save_template(name: String) -> void:
	load_all()
	templates[name] = binds.duplicate()
	save()

static func delete_template(name: String) -> void:
	load_all()
	templates.erase(name)
	save()

## The action an input event triggers exactly (key and Ctrl / Alt state; Shift is ignored) or "".
static func action_for(e: InputEvent) -> String:
	load_all()
	return _lookup(binding_of(e))

static func action_for_binding(b: int) -> String:
	load_all()
	return _lookup(b)

static func _lookup(b: int) -> String:
	if b == 0:
		return ""
	for a in ACTIONS:
		if int(binds.get(a[0], 0)) == b:
			return a[0]
	return ""

## What an event does: {action, learn}. An exact binding wins; otherwise Ctrl + an ability's hotkey learns it.
static func match_event(e: InputEvent) -> Dictionary:
	load_all()
	var b := binding_of(e)
	var act := _lookup(b)
	if act != "" or b == 0 or not (b & KEY_MASK_CTRL):
		return {"action": act, "learn": false}
	var plain := _lookup(b & ~KEY_MASK_CTRL)
	if plain.begins_with("ability_"):
		return {"action": plain, "learn": true}
	return {"action": "", "learn": false}

## The binding an event represents (0 if it cannot be bound, e.g. a bare modifier key).
static func binding_of(e: InputEvent) -> int:
	var mods := 0
	if e is InputEventWithModifiers:
		var m := e as InputEventWithModifiers
		if m.ctrl_pressed:
			mods |= KEY_MASK_CTRL
		if m.alt_pressed:
			mods |= KEY_MASK_ALT
	if e is InputEventKey:
		var k := e as InputEventKey
		var code := int(k.keycode) if k.keycode != KEY_NONE else int(k.physical_keycode)
		if code in MODIFIER_KEYS:
			return 0
		return code | mods
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index in [MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			return (MOUSE_BASE + int(mb.button_index)) | mods
	return 0

## Whether an action's key (with its modifiers) is held right now: follow, scoreboard, camera pans.
static func held(action: String) -> bool:
	var b := key(action)
	if b == 0:
		return false
	if b & KEY_MASK_CTRL and not Input.is_key_pressed(KEY_CTRL):
		return false
	if b & KEY_MASK_ALT and not Input.is_key_pressed(KEY_ALT):
		return false
	var base := b & ~MODS
	if base >= MOUSE_BASE:
		return Input.is_mouse_button_pressed(base - MOUSE_BASE)
	return Input.is_key_pressed(base)

static func label(action: String) -> String:
	for a in ACTIONS:
		if a[0] == action:
			return a[1]
	return action

## Short display name of a binding: "Q", "F1", "Ctrl + Q", "Alt + Mouse 4".
static func name_of(b: int) -> String:
	if b == 0:
		return "-"
	var pre := ""
	if b & KEY_MASK_CTRL:
		pre += "Ctrl + "
	if b & KEY_MASK_ALT:
		pre += "Alt + "
	var base := b & ~MODS
	if base >= MOUSE_BASE:
		match base - MOUSE_BASE:
			MOUSE_BUTTON_XBUTTON1: return pre + "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return pre + "Mouse 5"
		return pre + "Mouse %d" % (base - MOUSE_BASE)
	var s := OS.get_keycode_string(base)
	return pre + (s if s != "" else "Key %d" % base)

static func key_name(action: String) -> String:
	return name_of(key(action))

## The current key of an ability slot given its default letter ("Q", "W", "E", "R" in the ability data).
static func ability_key_name(letter: String) -> String:
	var i := "QWER".find(letter)
	return key_name("ability_%d" % (i + 1)) if i >= 0 else letter
