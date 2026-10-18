extends Control
## Hero Select: pick your hero. The heroes stand in a grid of portrait cards on the left; the chosen one stands on the
## lit stage (drag to turn it); the panel on the right gives its role, story, starting stats and abilities (hover an
## ability for its numbers). Back returns to the Main Menu, Customize look opens the Hero Creator, Play goes on to Game
## Setup (the teams and bots), then the Hotkeys screen and the match.

const U = preload("res://src/ui/ui_kit.gd")
const MATCH := "res://src/game/main.tscn"
const CREATOR := "res://src/ui/hero_creator.tscn"
const SETUP := "res://src/ui/game_setup.tscn"
const MENU := "res://src/ui/main_menu.tscn"

const INFO := {
	"blood_ranger": {"title": "the Blood Ranger", "role": "Ranged  ·  Agility  ·  Carry, Nuker, Escape",
		"story": "She hunted the Black Sun's beasts until the hunt hunted her back. Now the blood she spills keeps her standing, and every arrow she looses is a promise kept."},
	"ezee": {"title": "the Dark Paladin", "role": "Melee  ·  Strength  ·  Initiator, Disabler, Durable",
		"story": "Once a knight of the Ancient Light, Ezee broke his word to win a war the light was losing. The shadow he bargained with still answers when he calls, and it is always hungry."},
	"azrin": {"title": "the Flamemander", "role": "Ranged  ·  Intelligence  ·  Nuker, Disabler, Pusher",
		"story": "Azrin was a temple smith who fed the forge one prayer too many, and the fire answered. Now she floats above the flames she was born from, and every spell she casts calls another spirit of fire to her side."},
	"sludge": {"title": "the Butcher", "role": "Melee  ·  Strength  ·  Disabler, Initiator, Durable, Nuker",
		"story": "Sludge works the fields after every battle, hauling the fallen away on his chain. Nothing he catches gets away, and everything he eats makes him bigger."},
	"froster": {"title": "the Winter Master", "role": "Ranged  ·  Intelligence  ·  Disabler, Nuker, Initiator",
		"story": "Froster walked out of the northern ice the year the sun did not rise. Cold follows him like a hound: it slows his enemies, cracks their armor, and in the end it stops their hearts."},
	"tock": {"title": "the Clockmaker", "role": "Ranged  ·  Intelligence  ·  Support, Disabler, Escape",
		"story": "Tock built clocks for kings until he built one that ran backwards. Now he carries a few spare seconds in his pocket: he hands them to his friends, takes them from his enemies, and keeps one to step back in time when a fight goes wrong."},
	"kragg": {"title": "the Magnet Knight", "role": "Melee  ·  Strength  ·  Initiator, Disabler, Durable",
		"story": "Lightning struck Kragg's shield on the day he swore to hold the bridge, and it never let go. Iron leaps to him, foes stumble toward him, and the more they fight him the harder they are pulled in."},
	"roydo": {"title": "the Anomaly", "role": "Melee  ·  Intelligence  ·  Initiator, Disabler, Durable",
		"story": "Roydo fell out of the night sky in a burning stone and stood up unhurt. He bends this world's gravity like clay: he throws his enemies where he wants them, turns their blows back on them, and when a fight goes their way he stops looking like a man at all."},
	"blau": {"title": "the Master Tactician", "role": "Ranged  ·  Agility  ·  Carry, Pusher, Escape",
		"story": "Blau never fights on ground he has not chosen. A rifle, a bag of snares, a few rolling stones and a turret he can build in seconds: by the time his enemies see the trap, every shot he fires is already bouncing toward them."},
	"azrael": {"title": "the Death Dealer", "role": "Melee  ·  Agility  ·  Carry, Initiator, Escape",
		"story": "Azrael comes for the dead. She drifts over the battlefield in a black robe, a soul of white flame with eyes like coals, and gathers what is left of the fallen into her scythe. When she opens her wings, the light goes out for everyone near her."},
	# the five heroes of hero_ideas.txt (2026-10-18 e; kits since run 2026-10-18 f)
	"airah": {"title": "the Wind Goddess", "role": "Ranged  ·  Intelligence  ·  Support, Disabler, Initiator",
		"story": "Airah moves everyone. Her wind drags enemies into walls, carries her friends out of danger and stops arrows in the air, and when she calls up a hurricane, nobody inside it stands where they want to."},
	"burak": {"title": "the Berserker", "role": "Melee  ·  Strength  ·  Carry, Durable",
		"story": "Burak gets stronger the more he is hurt. He throws an axe, leaps after it, and the angrier he gets the faster he swings, until stuns barely slow him down. In Berserk he fights now and pays later, unless he takes someone down first."},
	"emelrich": {"title": "the Heavy Sword", "role": "Melee  ·  Strength  ·  Initiator, Disabler, Durable",
		"story": "Ser Emelrich is slow, and he does not need to be fast. Every swing of his great sword can be seen coming, and every one that lands ends the fight. He turns his shield toward danger and lines his enemies up for the next blow."},
	"feran": {"title": "the Jester", "role": "Ranged  ·  Intelligence  ·  Support, Disabler, Nuker",
		"story": "Feran Mock belongs to nobody. Juggled knives, a box full of nasty jokes and a trick for swapping places: chaos, but chaos he can steer. When the fight gets crowded he shuffles everyone round and fills the air with knives."},
	"ghorman": {"title": "the Beast King", "role": "Melee  ·  Strength  ·  Initiator, Jungler, Pusher",
		"story": "Ghorman rules the wild. He tames the creeps of the forest and the lanes, and the more beasts follow him the harder he hits. When he roars they all charge, and when he becomes the beast himself, his pack grows with him."},
	"caziel": {"title": "the Void Assassin", "role": "Melee  ·  Agility  ·  Carry, Escape, Finisher",
		"story": "No one hires Caziel. He chooses the name himself, and the shadows carry him to it. He is never seen until the last blow, and the last blow never misses."},
}

var stage: HeroStage
var _cards := {}
var _right: VBoxContainer
var _tip: PanelContainer
var _tip_label: RichTextLabel
var _cust: Button
var _capture_path := ""
var _frames := 0

func _ready() -> void:
	theme = U.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	GameSettings.load_hero()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--capture=") and not OS.get_cmdline_user_args().has("--match") and not OS.get_cmdline_args().has("--match"):
			_capture_path = a.substr(10)
		elif a.begins_with("--pick="):
			GameSettings.select(a.substr(7))
		elif a == "--match":
			get_tree().change_scene_to_file.call_deferred(MATCH)
			return
	_build_stage()
	_build_ui()
	_select(GameSettings.selected, false)
	await get_tree().process_frame
	await get_tree().process_frame
	LoadingScreen.close(get_tree())

func _build_stage() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	svc.add_child(vp)
	stage = HeroStage.new()
	stage.mode = "select"
	vp.add_child(stage)

func _label(text: String, size: int, col: Color, kind := "body") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", U.font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6 if size >= 24 else 3)
	return l

func _build_ui() -> void:
	# soft dark veils left and right so the panels sit over the stage cleanly
	for side in [0, 1]:
		var veil := TextureRect.new()
		var gt := GradientTexture2D.new()
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		g.colors = PackedColorArray([Color(0.01, 0.012, 0.02, 0.88), Color(0.01, 0.012, 0.02, 0.5), Color(0, 0, 0, 0)])
		gt.gradient = g
		gt.width = 128
		gt.height = 4
		if side == 1:
			gt.fill_from = Vector2(1, 0)
			gt.fill_to = Vector2(0, 0)
		veil.texture = gt
		veil.stretch_mode = TextureRect.STRETCH_SCALE
		veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
		veil.anchor_bottom = 1.0
		if side == 0:
			veil.offset_right = 760
		else:
			veil.anchor_left = 1.0
			veil.anchor_right = 1.0
			veil.offset_left = -820
		add_child(veil)
	var head := Control.new()
	head.position = Vector2(56, 34)
	head.size = Vector2(700, 90)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.draw.connect(func():
		U.text(head, "Choose your hero", Vector2(4, 46), 44, U.GOLD, "title")
		U.art_rect(head, "divider", Rect2(0, 62, 520, 30)))
	add_child(head)
	# the hero grid: portrait cards, four a row
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(60, 132)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	add_child(grid)
	for id in GameSettings.HEROES:
		var card := _card(id)
		grid.add_child(card)
		_cards[id] = card
	var hint := _label("Drag the hero to turn it", 15, U.TEXT_DIM)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -80
	hint.offset_top = -132
	add_child(hint)
	# the info panel
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -640
	panel.offset_right = -40
	panel.offset_top = 40
	panel.offset_bottom = -126
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 10)
	_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_right)
	# bottom bar
	var bar := HBoxContainer.new()
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_left = 60
	bar.offset_right = -40
	bar.offset_top = -100
	bar.offset_bottom = -30
	bar.add_theme_constant_override("separation", 16)
	add_child(bar)
	var back := _button("Back", "", 170, func(): _go(MENU))
	bar.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	_cust = _button("Customize look", "", 240, func():
		GameSettings.save()
		get_tree().change_scene_to_file(CREATOR))
	bar.add_child(_cust)
	var play := _button("Play", "GoldButton", 300, _on_play)
	play.add_theme_font_size_override("font_size", 32)
	bar.add_child(play)
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.custom_minimum_size = Vector2(400, 0)
	_tip.add_theme_stylebox_override("panel", U.box("panel_tip", 16))
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.custom_minimum_size = Vector2(380, 0)
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.add_theme_font_override("normal_font", U.font("body"))
	_tip_label.add_theme_font_override("bold_font", U.font("title"))
	_tip_label.add_theme_font_size_override("normal_font_size", 15)
	_tip_label.add_theme_font_size_override("bold_font_size", 19)
	_tip.add_child(_tip_label)
	add_child(_tip)

func _button(text: String, variation: String, w: float, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 64)
	b.focus_mode = Control.FOCUS_NONE
	if variation != "":
		b.theme_type_variation = variation
	else:
		b.add_theme_font_override("font", U.font("title"))
		b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func():
		Options.click()
		cb.call())
	return b

## A hero's card: the portrait in a gold frame, its name on a plate at the foot, its colour glowing when chosen.
func _card(id: String) -> Control:
	var d := SimData.unit(id)
	var c := Control.new()
	c.custom_minimum_size = Vector2(150, 196)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.set_meta("hover", false)
	c.mouse_entered.connect(func():
		c.set_meta("hover", true)
		c.queue_redraw())
	c.mouse_exited.connect(func():
		c.set_meta("hover", false)
		c.queue_redraw())
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			Options.click()
			_select(id, true))
	c.draw.connect(func():
		var r := Rect2(Vector2.ZERO, c.size)
		var picked := GameSettings.selected == id
		var hov: bool = c.get_meta("hover")
		var acc: Color = HeroStage.ACCENTS.get(id, U.GOLD)
		if picked:
			U.art_rect(c, "glow_gold", r.grow(26), Color(acc, 0.85))
		var pt := U.hero_portrait(id)
		var inner := r.grow(-6)
		if pt:
			var ts := pt.get_size()
			var src := Rect2(ts.x * 0.12, 0, ts.x * 0.76, ts.x * 0.76 * inner.size.y / inner.size.x)
			c.draw_texture_rect_region(pt, inner, src, Color.WHITE if picked or hov else Color(0.72, 0.72, 0.75))
		U.art_rect(c, "hero_card", r, acc.lerp(Color.WHITE, 0.55) if picked else (Color(1.15, 1.1, 1.0) if hov else Color.WHITE))
		var nm := String(d.get("name", id))
		U.text_c(c, nm, Vector2(r.size.x * 0.5, r.size.y - 16), 18 if nm.length() < 11 else 15, U.GOLD if picked else U.TEXT, "title"))
	return c

func _select(id: String, flourish: bool) -> void:
	GameSettings.select(id)
	GameSettings.save()
	for k in _cards:
		(_cards[k] as Control).queue_redraw()
	stage.show_hero(id, {}, flourish)
	_fill_right(id)
	if _cust:
		_cust.disabled = id in GameSettings.OWN_BODY
		_cust.tooltip_text = "%s has a fixed look and cannot be customized" % String(SimData.unit(id).name) if _cust.disabled else ""

func _fill_right(id: String) -> void:
	for c in _right.get_children():
		c.queue_free()
	var d := SimData.unit(id)
	var info: Dictionary = INFO[id]
	var acc: Color = HeroStage.ACCENTS.get(id, U.GOLD)
	_right.add_child(_label(String(d.name).to_upper(), 48, U.GOLD, "title"))
	_right.add_child(_label(String(info.title), 22, acc.lightened(0.2), "title"))
	_right.add_child(_label(String(info.role), 16, U.TEXT, "bold"))
	var story := Label.new()
	story.text = String(info.story)
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.custom_minimum_size = Vector2(540, 0)
	story.add_theme_font_size_override("font_size", 16)
	story.add_theme_color_override("font_color", U.TEXT_DIM)
	_right.add_child(story)
	_right.add_child(_divider())
	var str0 := float(d.str)
	var agi0 := float(d.agi)
	var int0 := float(d["int"])
	var prim: float = {"str": str0, "agi": agi0, "int": int0}[String(d.primary)]
	# the three attributes with their icons, the primary one in gold
	var attrs := HBoxContainer.new()
	attrs.add_theme_constant_override("separation", 26)
	for a in [["str", "attributes/strength", str0, float(d.str_gain), Color(0.95, 0.4, 0.35)],
			["agi", "attributes/agility", agi0, float(d.agi_gain), Color(0.45, 0.95, 0.5)],
			["int", "attributes/intelligence", int0, float(d.int_gain), Color(0.45, 0.7, 1.0)]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := TextureRect.new()
		ic.texture = U.icon(String(a[1]))
		ic.custom_minimum_size = Vector2(30, 30)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = a[4]
		row.add_child(ic)
		var primary := String(d.primary) == String(a[0])
		row.add_child(_label("%d  +%.1f" % [int(a[2]), float(a[3])], 19, U.GOLD if primary else U.TEXT, "title" if primary else "bold"))
		attrs.add_child(row)
	_right.add_child(attrs)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 5)
	var stats := [
		["Health", str(int(float(d.hp) + str0 * SimConst.STR_HP))],
		["Mana", str(int(float(d.mana) + int0 * SimConst.INT_MANA))],
		["Damage", "%d - %d" % [int(float(d.dmg_min) + prim), int(float(d.dmg_max) + prim)]],
		["Armor", "%.1f" % (float(d.armor) + agi0 * SimConst.AGI_ARMOR)],
		["Attack range", str(int(d.range)) + ("  (melee)" if float(d.projectile_speed) <= 0.0 else "")],
		["Move speed", str(int(d.move_speed))],
		["Attack time", "%.1f s" % float(d.bat)],
		["Element", String(SimConst.ELEMENT_NAMES[int(d.get("element", 0))])],
	]
	for st in stats:
		grid.add_child(_label(String(st[0]), 14, U.TEXT_DIM, "bold"))
		grid.add_child(_label(String(st[1]), 16, U.TEXT, "bold"))
	_right.add_child(grid)
	_right.add_child(_divider())
	_right.add_child(_label("Abilities", 22, U.GOLD, "title"))
	for aid in d.abilities:
		_right.add_child(_ability_row(String(aid)))
	# the innate skill (always learned, from level 1)
	if String(d.get("innate", "")) != "":
		_right.add_child(_ability_row(String(d.innate)))

func _divider() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(540, 26)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): U.art_rect(c, "divider", Rect2(0, 2, c.size.x, 22)))
	return c

func _ability_row(aid: String) -> Control:
	var a := SimData.ability(aid)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(64, 64)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.draw.connect(func():
		var r := Rect2(Vector2.ZERO, slot.size)
		slot.draw_rect(r.grow(-3), Color(0.03, 0.035, 0.05))
		var ic := U.ability_icon(aid)
		if ic:
			slot.draw_texture_rect(ic, r.grow(-6), false)
		U.skin(slot, "slot_ability", r.grow(3), Color.WHITE, false))
	row.add_child(slot)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	var kind := {"autocast_attack": "Attack modifier", "point": "Point target", "passive": "Passive", "unit": "Unit target",
		"no_target": "No target", "toggle": "Toggle", "innate": "Innate"}
	var head := _label("%s   [%s]   %s%s" % [String(a.name), String(a.key), String(kind.get(String(a.behavior), "")),
		"   Ultimate" if a.has("required_level") else ""], 17, U.GOLD, "bold")
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var desc := Label.new()
	desc.text = String(a.desc)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(450, 0)
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", U.TEXT)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)
	row.mouse_entered.connect(func(): _show_tip(aid))
	row.mouse_exited.connect(func(): _tip.visible = false)
	return row

func _show_tip(aid: String) -> void:
	var a := SimData.ability(aid)
	var lines := ["[b]%s[/b]" % String(a.name)]
	for k in a.values:
		var parts := []
		for val in a.values[k]:
			var fv := float(val)
			parts.append(("%d%%" % roundi(fv * 100.0)) if fv > 0.0 and fv < 1.0 and (String(k).contains("slow") or String(k).contains("chance") or String(k).contains("mult") or String(k).ends_with("pct") or String(k) == "lifesteal" or String(k).contains("loss") or String(k).contains("threshold") or String(k).contains("evasion")) else str(val))
		lines.append("%s: [color=#e8d9a8]%s[/color]" % [String(k).replace("_", " ").capitalize(), " / ".join(parts)])
	if String(a.behavior) != "passive" and String(a.behavior) != "innate":
		lines.append("[color=#8fb0ff]Mana %s   Cooldown %s s[/color]" % [" / ".join(a.mana.map(func(x): return str(x))),
			" / ".join(a.cooldown.map(func(x): return str(x)))])
	var dt := String(a.get("damage_type", ""))
	if dt != "":
		lines.append("Damage type: " + dt.capitalize())
	_tip_label.text = "\n".join(lines)
	_tip.visible = true

func _process(_dt: float) -> void:
	if _tip.visible:
		_tip.position = get_viewport().get_mouse_position() + Vector2(-440, 18)
	if _capture_path != "":
		_frames += 1
		if _frames == int(OS.get_environment("WOA_FRAMES") if OS.get_environment("WOA_FRAMES") != "" else "70"):
			var img := get_viewport().get_texture().get_image()
			var path := ProjectSettings.globalize_path("res://" + _capture_path)
			DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			img.save_png(path)
			print("captured ", path)
			get_tree().quit()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		stage.dragging = e.pressed
	elif e is InputEventMouseMotion and stage.dragging:
		stage.drag((e as InputEventMouseMotion).relative.x)

func _go(path: String) -> void:
	GameSettings.save()
	get_tree().change_scene_to_file(path)

## Play: Game Setup comes next (who plays on each team), then the Hotkeys screen ("Are you good to go?") and the match.
func _on_play() -> void:
	_go(SETUP)
