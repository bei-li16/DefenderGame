class_name DefenderGameplayHud
extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const SkillButton = preload("res://src/presentation/gameplay/skill_button.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const SkillText = preload("res://src/presentation/skill_text.gd")
const Art = preload("res://src/presentation/art/game_art.gd")

# Battle HUD (architecture §6.3 HudView): top stage bar with spawn progress,
# bottom-left wall/mana cluster, boss banner, and the circular skill buttons.
# Pure view: reads snapshots, emits intents (pause / skill selection) back to
# the gameplay scene which owns input, world drawing and overlays.

signal pause_requested
signal skill_selected(skill_id)

var feedback_label: Label
var skill_buttons: Dictionary = {}
var _stage_label: Label
var _enemy_label: Label
var _progress_bar: ProgressBar
var _coin_label: Label
var _wall_bar: ProgressBar
var _mana_bar: ProgressBar
var _wall_value_label: Label
var _mana_value_label: Label
var _weapon_label: Label
var _weapon_icon: TextureRect
var _defense_label: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label


func _ready() -> void:
	theme = UiTheme.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_status_cluster()
	_build_feedback_label()
	_build_boss_banner()
	_build_skill_buttons()


func _build_top_bar() -> void:
	var top_margin := MarginContainer.new()
	top_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_left", 24)
	top_margin.add_theme_constant_override("margin_right", 24)
	top_margin.add_theme_constant_override("margin_top", 18)
	add_child(top_margin)
	var top_panel := PanelContainer.new()
	top_panel.custom_minimum_size.y = 82
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top_panel)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)
	top_panel.add_child(top_row)
	var pause := Button.new()
	pause.text = "Ⅱ"
	pause.custom_minimum_size = Vector2(64, 54)
	pause.mouse_filter = Control.MOUSE_FILTER_STOP
	pause.pressed.connect(func() -> void: pause_requested.emit())
	top_row.add_child(pause)
	_stage_label = _hud_label(GameApp.text("common.stage"), 28, Color("ffd166"), 170)
	top_row.add_child(_stage_label)
	_enemy_label = _hud_label("", 21, Color.WHITE, 200)
	top_row.add_child(_enemy_label)
	# Classic Defender II stage progress bar: fills as waves spawn, sword to skull.
	var progress_stack := HBoxContainer.new()
	progress_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_stack.add_theme_constant_override("separation", 8)
	top_row.add_child(progress_stack)
	progress_stack.add_child(_hud_label("⚔", 24, Color("b9d7ea"), 34))
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(240, 22)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_stack.add_child(_progress_bar)
	progress_stack.add_child(_hud_label("💀", 24, Color("ff8d7a"), 40))
	_coin_label = _hud_label("", 24, Color("ffd166"), 150)
	top_row.add_child(_coin_label)


func _build_status_cluster() -> void:
	# Bottom-left status cluster: red wall HP bar over blue Mana bar with icons,
	# matching the classic layout; weapon/defense readouts sit right of it.
	var status_margin := MarginContainer.new()
	status_margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_margin.position = Vector2(24, -180)
	status_margin.size = Vector2(430, 160)
	status_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status_margin)
	var status_stack := VBoxContainer.new()
	status_stack.add_theme_constant_override("separation", 8)
	status_margin.add_child(status_stack)
	var wall_row := HBoxContainer.new()
	wall_row.add_theme_constant_override("separation", 8)
	wall_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_stack.add_child(wall_row)
	wall_row.add_child(_hud_label("🏰", 24, Color.WHITE, 36))
	var wall_stack := VBoxContainer.new()
	wall_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wall_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall_row.add_child(wall_stack)
	_wall_value_label = Label.new()
	_wall_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wall_value_label.add_theme_font_size_override("font_size", 16)
	_wall_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wall_stack.add_child(_wall_value_label)
	_wall_bar = ProgressBar.new()
	_wall_bar.custom_minimum_size = Vector2(360, 24)
	_wall_bar.show_percentage = false
	_wall_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wall_bar.add_theme_stylebox_override("fill", _bar_fill(Color("c0392b")))
	wall_stack.add_child(_wall_bar)
	var mana_row := HBoxContainer.new()
	mana_row.add_theme_constant_override("separation", 8)
	mana_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_stack.add_child(mana_row)
	mana_row.add_child(_hud_label("🔮", 24, Color.WHITE, 36))
	var mana_stack := VBoxContainer.new()
	mana_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mana_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mana_row.add_child(mana_stack)
	_mana_value_label = Label.new()
	_mana_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_value_label.add_theme_font_size_override("font_size", 16)
	_mana_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mana_stack.add_child(_mana_value_label)
	_mana_bar = ProgressBar.new()
	_mana_bar.custom_minimum_size = Vector2(360, 24)
	_mana_bar.show_percentage = false
	_mana_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mana_bar.add_theme_stylebox_override("fill", _bar_fill(Color("2e86de")))
	mana_stack.add_child(_mana_bar)
	var weapon_row := HBoxContainer.new()
	weapon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_theme_constant_override("separation", 8)
	status_stack.add_child(weapon_row)
	_weapon_icon = TextureRect.new()
	_weapon_icon.custom_minimum_size = Vector2(28, 28)
	_weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_weapon_icon)
	_weapon_label = _hud_label("", 18, Color("b9d7ea"), 392)
	_weapon_label.size.y = 32
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_row.add_child(_weapon_label)
	_defense_label = _hud_label("", 17, Color("f2bd76"), 430)
	_defense_label.size.y = 32
	_defense_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_stack.add_child(_defense_label)


func _build_feedback_label() -> void:
	feedback_label = Label.new()
	feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	feedback_label.position = Vector2(-300, 120)
	feedback_label.size = Vector2(600, 60)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 34)
	feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feedback_label)


func _build_boss_banner() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-320, 118)
	_boss_panel.size = Vector2(640, 80)
	_boss_panel.visible = false
	add_child(_boss_panel)
	var boss_stack := VBoxContainer.new()
	_boss_panel.add_child(boss_stack)
	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", Color("ff7697"))
	boss_stack.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	boss_stack.add_child(_boss_bar)


func _build_skill_buttons() -> void:
	var skills_margin := MarginContainer.new()
	skills_margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skills_margin.position = Vector2(-640, -160)
	skills_margin.size = Vector2(610, 130)
	add_child(skills_margin)
	var skills := HBoxContainer.new()
	skills.alignment = BoxContainer.ALIGNMENT_END
	skills.add_theme_constant_override("separation", 18)
	skills_margin.add_child(skills)
	var hotkeys := {"fire": "1", "ice": "2", "lightning": "3"}
	var loadout := SkillCatalog.loadout(GameApp.content.rules, GameApp.profile)
	for definition in [
		["fire", "🔥"],
		["ice", "❄"],
		["lightning", "⚡"]
	]:
		var button := SkillButton.new()
		button.skill_id = str(loadout.get(definition[0], ""))
		button.glyph = str(definition[1])
		button.hotkey = str(hotkeys.get(str(definition[0]), ""))
		button.low_mana_text = GameApp.text("feedback.no_mana")
		button.name = "Spell_" + button.skill_id
		button.pressed.connect(func() -> void: skill_selected.emit(button.skill_id))
		skills.add_child(button)
		skill_buttons[button.skill_id] = button


func update_snapshot(snapshot: Dictionary) -> void:
	_wall_bar.max_value = maxi(1, int(snapshot.get("wall_max_hp", 1)))
	_wall_bar.value = int(snapshot.get("wall_hp", 0))
	_wall_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.wall"), int(snapshot.get("wall_hp", 0)), int(snapshot.get("wall_max_hp", 0))]
	_wall_value_label.text = "%s  %d / %d" % [GameApp.text("hud.wall"), int(snapshot.get("wall_hp", 0)), int(snapshot.get("wall_max_hp", 0))]
	_mana_bar.max_value = maxi(1, int(snapshot.get("max_mana", 1)))
	_mana_bar.value = int(snapshot.get("mana", 0))
	_mana_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.mana"), int(snapshot.get("mana", 0)), int(snapshot.get("max_mana", 0))]
	_mana_value_label.text = "%s  %d / %d" % [GameApp.text("hud.mana"), int(snapshot.get("mana", 0)), int(snapshot.get("max_mana", 0))]
	_stage_label.text = "%s  %02d" % [GameApp.text("common.stage"), int(snapshot.get("stage_number", 0))]
	_enemy_label.text = "%s  %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("kills", 0)), int(snapshot.get("spawn_total", 0))]
	_progress_bar.max_value = maxi(1, int(snapshot.get("spawn_total", 1)))
	_progress_bar.value = int(snapshot.get("spawned", 0))
	_progress_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("spawned", 0)), int(snapshot.get("spawn_total", 0))]
	_coin_label.text = "◆  %d" % int(snapshot.get("coins_earned", 0))
	_weapon_label.text = "%s: %s" % [GameApp.text("hud.weapon"), GameApp.text(str(snapshot.get("weapon_name_key", "weapon.basic_bow")))]
	_weapon_icon.texture = Art.texture(str(snapshot.get("weapon_id", "basic_bow")))
	var defenses: Dictionary = snapshot.get("defenses", {})
	_defense_label.text = "%s  %s %d  ·  %s %d" % [
		GameApp.text("hud.defenses"), GameApp.text("hud.lava_moat"), int(defenses.get("lava_moat_level", 0)),
		GameApp.text("hud.magic_tower"), int(defenses.get("magic_tower_level", 0))
	]
	_update_skill_buttons(snapshot)
	_update_boss_bar(snapshot)


func _update_skill_buttons(snapshot: Dictionary) -> void:
	var selected := str(snapshot.get("selected_skill", ""))
	var cooldowns: Dictionary = snapshot.get("skill_cooldowns", {})
	var mana := int(snapshot.get("mana", 0))
	for skill_id in skill_buttons.keys():
		var button: SkillButton = skill_buttons[skill_id]
		var cooldown := int(cooldowns.get(skill_id, 0))
		var definition: Dictionary = snapshot.get("skill_definitions", {}).get(skill_id, _skill_definition(skill_id))
		var max_cooldown := maxi(1, int(definition.get("cooldown_ticks", 1)))
		var mana_cost := int(definition.get("mana_cost", 0))
		button.tier = int(definition.get("tier", 1))
		button.mana_cost = mana_cost
		button.tooltip_text = GameApp.text(str(definition.get("name_key", ""))) + "\n" + SkillText.summary(definition, GameApp.text, int(GameApp.content.rules.get("simulation_tick_rate", 30)))
		button.set_state(float(cooldown) / float(max_cooldown), mana >= mana_cost, selected == skill_id)


func _skill_definition(skill_id: String) -> Dictionary:
	for skill in GameApp.content.rules.get("skills", []):
		if skill is Dictionary and str(skill.get("id", "")) == skill_id:
			return skill
	return {}


func _update_boss_bar(snapshot: Dictionary) -> void:
	var boss: Dictionary = {}
	for enemy in snapshot.get("enemies", []):
		if enemy.get("tags", []).has("boss"):
			boss = enemy
			break
	_boss_panel.visible = not boss.is_empty()
	if not boss.is_empty():
		_boss_name.text = "⚠  " + GameApp.text(str(boss.get("name_key", "enemy.boss"))) + "  ⚠"
		_boss_bar.max_value = int(boss.get("max_hp", 1))
		_boss_bar.value = int(boss.get("hp", 0))


static func _hud_label(value: String, font_size: int, color: Color, width: float) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


static func _bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	return style
