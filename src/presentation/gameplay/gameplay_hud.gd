class_name DefenderGameplayHud
extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const UiAssets = preload("res://src/presentation/art/ui_assets.gd")
const SkillButton = preload("res://src/presentation/gameplay/skill_button.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const SkillText = preload("res://src/presentation/skill_text.gd")
const ResearchText = preload("res://src/presentation/research_text.gd")
const Art = preload("res://src/presentation/art/game_art.gd")
const Meter = preload("res://src/presentation/gameplay/hud_meter.gd")
const SpellIcons = preload("res://src/presentation/art/spell_icons.gd")

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
var _moat_label: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _tactical_label: Label


func _ready() -> void:
	theme = UiTheme.create()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_status_cluster()
	_build_feedback_label()
	_build_boss_banner()
	_build_skill_buttons()
	_passthrough(self)


func _passthrough(node: Node) -> void:
	for child in node.get_children():
		if child is Control and not child is BaseButton and not child is SkillButton:
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_passthrough(child)


func _build_top_bar() -> void:
	var left := HBoxContainer.new()
	left.position = Vector2(24, 22)
	left.add_theme_constant_override("separation", 20)
	add_child(left)
	var pause := Button.new()
	pause.name = "PauseButton"
	pause.text = "II"
	pause.tooltip_text = GameApp.text("hud.pause")
	pause.custom_minimum_size = Vector2(58, 58)
	pause.pressed.connect(func() -> void: pause_requested.emit())
	left.add_child(pause)
	_stage_label = _label("", 27, Color("f0e3c5"))
	_stage_label.custom_minimum_size.x = 230
	left.add_child(_stage_label)
	var progress := HBoxContainer.new()
	progress.name = "WaveProgress"
	progress.set_anchors_preset(Control.PRESET_CENTER_TOP)
	progress.position = Vector2(-380, 22)
	progress.size = Vector2(760, 62)
	progress.add_theme_constant_override("separation", 10)
	add_child(progress)
	progress.add_child(UiAssets.image("battle", 40))
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_theme_constant_override("separation", 7)
	progress.add_child(stack)
	_enemy_label = _label("", 20, Color("e6e8df"))
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_enemy_label)
	_progress_bar = _meter(Color("bc9752"), 16)
	stack.add_child(_progress_bar)
	progress.add_child(UiAssets.image("skull", 40))
	var purse := HBoxContainer.new()
	purse.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	purse.position = Vector2(-222, 22)
	purse.size = Vector2(190, 54)
	purse.add_theme_constant_override("separation", 10)
	purse.add_child(UiAssets.image("coin", 40))
	_coin_label = _label("", 26, Color("f0d391"))
	purse.add_child(_coin_label)
	add_child(purse)


func _build_status_cluster() -> void:
	# This sits beside the near bastion, never across its silhouette. Fixed
	# dimensions keep large HP values and translated labels from moving bars.
	var cluster := VBoxContainer.new()
	cluster.name = "StatusPanel"
	cluster.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	cluster.position = Vector2(430, -160)
	cluster.size = Vector2(350, 130)
	cluster.add_theme_constant_override("separation", 8)
	add_child(cluster)
	_wall_bar = _status_meter(cluster, "health", Color("b13e3d"))
	_wall_value_label = _wall_bar.get_node("Value")
	_mana_bar = _status_meter(cluster, "mana", Color("327e9c"))
	_mana_value_label = _mana_bar.get_node("Value")
	var equipment := HBoxContainer.new()
	equipment.add_theme_constant_override("separation", 8)
	cluster.add_child(equipment)
	_weapon_icon = UiAssets.image("battle", 26)
	equipment.add_child(_weapon_icon)
	_weapon_label = _label("", 17, Color("d1d7c6"))
	_weapon_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weapon_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	equipment.add_child(_weapon_label)
	var moat_icon := UiAssets.image("tower", 24)
	moat_icon.texture = SpellIcons.texture("fire", 1)
	equipment.add_child(moat_icon)
	_moat_label = _label("", 17, Color("d1c699"))
	equipment.add_child(_moat_label)
	equipment.add_child(UiAssets.image("tower", 26))
	_defense_label = _label("", 17, Color("d1c699"))
	equipment.add_child(_defense_label)


func _status_meter(parent: Control, icon: String, color: Color) -> ProgressBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 34
	parent.add_child(row)
	row.add_child(UiAssets.image(icon, 34))
	var bar := _meter(color, 28)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var value := _label("", 17, Color.WHITE)
	value.name = "Value"
	value.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_constant_override("outline_size", 3)
	value.add_theme_color_override("font_outline_color", Color("14221f"))
	bar.add_child(value)
	return bar


func _build_feedback_label() -> void:
	feedback_label = _label("", 26, Color.WHITE)
	feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	feedback_label.position = Vector2(-420, 205)
	feedback_label.size = Vector2(840, 46)
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_constant_override("outline_size", 4)
	feedback_label.add_theme_color_override("font_outline_color", Color("17221c"))
	add_child(feedback_label)
	_tactical_label = _label("", 18, Color("d8ddcf"))
	_tactical_label.name = "TacticalReadout"
	_tactical_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_tactical_label.position = Vector2(-125, -66)
	_tactical_label.size = Vector2(420, 38)
	_tactical_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_tactical_label)


func _build_boss_banner() -> void:
	_boss_panel = PanelContainer.new()
	_boss_panel.add_theme_stylebox_override("panel", UiTheme.empty())
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-280, 114)
	_boss_panel.size = Vector2(560, 64)
	_boss_panel.visible = false
	add_child(_boss_panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	_boss_panel.add_child(stack)
	_boss_name = _label("", 23, Color("f3b1a0"))
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_boss_name)
	_boss_bar = _meter(Color("ab494d"), 18)
	stack.add_child(_boss_bar)


func _build_skill_buttons() -> void:
	var skills := HBoxContainer.new()
	skills.name = "SkillDock"
	skills.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skills.position = Vector2(-440, -158)
	skills.size = Vector2(410, 126)
	skills.alignment = BoxContainer.ALIGNMENT_END
	skills.add_theme_constant_override("separation", 20)
	add_child(skills)
	var loadout := SkillCatalog.loadout(GameApp.content.rules, GameApp.profile)
	var index := 0
	for element in ["fire", "ice", "lightning"]:
		var button := SkillButton.new()
		button.skill_id = str(loadout.get(element, ""))
		button.hotkey = str(index + 1)
		button.element = element
		button.low_mana_text = GameApp.text("feedback.no_mana")
		button.name = "Spell_" + button.skill_id
		button.pressed.connect(func() -> void: skill_selected.emit(button.skill_id))
		skills.add_child(button)
		skill_buttons[button.skill_id] = button
		index += 1


func update_snapshot(snapshot: Dictionary) -> void:
	_wall_bar.max_value = maxi(1, int(snapshot.get("wall_max_hp", 1)))
	_wall_bar.value = int(snapshot.get("wall_hp", 0))
	_wall_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.wall"), _wall_bar.value, _wall_bar.max_value]
	_wall_value_label.text = "%s / %s" % [ResearchText.compact(int(_wall_bar.value)), ResearchText.compact(int(_wall_bar.max_value))]
	_mana_bar.max_value = maxi(1, int(snapshot.get("max_mana", 1)))
	_mana_bar.value = int(snapshot.get("mana", 0))
	_mana_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.mana"), _mana_bar.value, _mana_bar.max_value]
	_mana_value_label.text = "%s / %s" % [ResearchText.compact(int(_mana_bar.value)), ResearchText.compact(int(_mana_bar.max_value))]
	_stage_label.text = "%s  %02d" % [GameApp.text("common.stage"), int(snapshot.get("stage_number", 0))]
	_enemy_label.text = GameApp.text("hud.wave_progress") % [int(snapshot.get("wave", 0)), int(snapshot.get("wave_total", 0))]
	_enemy_label.text += "   |   %s  %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("kills", 0)), int(snapshot.get("spawn_total", 0))]
	_progress_bar.max_value = maxi(1, int(snapshot.get("spawn_total", 1)))
	_progress_bar.value = int(snapshot.get("spawned", 0))
	_progress_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("spawned", 0)), int(snapshot.get("spawn_total", 0))]
	var tick_rate := float(GameApp.content.rules.get("simulation_tick_rate", 30))
	_progress_bar.tooltip_text += "\n" + GameApp.text("hud.spawn_window") % [float(snapshot.get("spawn_duration_ticks", 0)) / tick_rate, float(snapshot.get("tick", 0)) / tick_rate]
	_coin_label.text = ResearchText.compact(int(snapshot.get("coins_earned", 0)))
	var elapsed := int(float(snapshot.get("tick", 0)) / tick_rate)
	_tactical_label.text = GameApp.text("hud.tactical") % [snapshot.get("enemies", []).size(), elapsed / 60, elapsed % 60]
	var low_wall := float(_wall_bar.value) / maxf(1, _wall_bar.max_value) <= 0.25
	_wall_value_label.add_theme_color_override("font_color", Color("ffb1a1") if low_wall else Color.WHITE)
	_weapon_label.text = GameApp.text(str(snapshot.get("weapon_name_key", "weapon.basic_bow")))
	_weapon_icon.texture = Art.texture(str(snapshot.get("weapon_id", "basic_bow")))
	var defenses: Dictionary = snapshot.get("defenses", {})
	_moat_label.text = str(defenses.get("lava_moat_level", 0))
	_defense_label.text = str(defenses.get("magic_tower_level", 0))
	_defense_label.tooltip_text = "%s %d / %s %d" % [GameApp.text("hud.lava_moat"), int(defenses.get("lava_moat_level", 0)), GameApp.text("hud.magic_tower"), int(defenses.get("magic_tower_level", 0))]
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
		button.cooldown_seconds = ceili(float(cooldown) / float(GameApp.content.rules.get("simulation_tick_rate", 30)))
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
		_boss_name.text = GameApp.text(str(boss.get("name_key", "enemy.boss")))
		_boss_bar.max_value = int(boss.get("max_hp", 1))
		_boss_bar.value = int(boss.get("hp", 0))


static func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color("17221c"))
	return label


static func _meter(color: Color, height: int) -> ProgressBar:
	var bar := Meter.new()
	bar.show_percentage = false
	bar.custom_minimum_size.y = height
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.enamel = color
	return bar
