extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const MenuBackdrop = preload("res://src/presentation/menus/menu_backdrop.gd")
const ResearchTree = preload("res://src/presentation/menus/research_tree.gd")
const Progression = preload("res://src/core/rules/progression.gd")

var _content_panel: PanelContainer
var _content_margin: MarginContainer
var _coins_label: Label
var _crystals_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _stage_label: Label
var _loadout_row: HBoxContainer
var _settings_note: Label

const WEAPON_GLYPHS := {
	"basic_bow": "🏹",
	"power_bow": "💪",
	"hurricane_bow": "🌀",
	"phantom_bow": "👻"
}


func _ready() -> void:
	theme = UiTheme.create()
	GameApp.audio.play_music("menu", float(GameApp.settings.get("music_volume", 0.65)))
	_build_layout()
	_show_main_navigation()


func _build_layout() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	move_child(backdrop, 0)

	var outer := MarginContainer.new()
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 52)
	outer.add_theme_constant_override("margin_right", 52)
	outer.add_theme_constant_override("margin_top", 34)
	outer.add_theme_constant_override("margin_bottom", 34)
	add_child(outer)
	var vertical := VBoxContainer.new()
	vertical.add_theme_constant_override("separation", 24)
	outer.add_child(vertical)

	# Original-style top bar: stage label, loadout strip (equipped bow + battle
	# spells), then stacked coin/crystal purses and the level progress.
	var top := PanelContainer.new()
	top.custom_minimum_size.y = 118
	vertical.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)
	top.add_child(top_row)
	_stage_label = Label.new()
	_stage_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stage_label.add_theme_font_size_override("font_size", 32)
	_stage_label.add_theme_color_override("font_color", Color("ffd166"))
	top_row.add_child(_stage_label)
	_loadout_row = HBoxContainer.new()
	_loadout_row.add_theme_constant_override("separation", 8)
	_loadout_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout_row.alignment = BoxContainer.ALIGNMENT_CENTER
	top_row.add_child(_loadout_row)
	var assets := VBoxContainer.new()
	assets.alignment = BoxContainer.ALIGNMENT_CENTER
	assets.add_theme_constant_override("separation", 6)
	top_row.add_child(assets)
	_coins_label = Label.new()
	_crystals_label = Label.new()
	assets.add_child(_make_asset_pill("◆", Color("ffd166"), _coins_label))
	assets.add_child(_make_asset_pill("✦", Color("8fd3ff"), _crystals_label))
	var level_stack := VBoxContainer.new()
	level_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	level_stack.add_theme_constant_override("separation", 4)
	top_row.add_child(level_stack)
	_xp_label = Label.new()
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_font_size_override("font_size", 20)
	level_stack.add_child(_xp_label)
	# Status-page style level bar: Lv N [====] into/needed.
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(170, 14)
	_xp_bar.show_percentage = false
	level_stack.add_child(_xp_bar)
	_refresh_header()

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 30)
	vertical.add_child(body)

	var identity := PanelContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.custom_minimum_size.x = 620
	body.add_child(identity)
	var identity_margin := MarginContainer.new()
	identity_margin.add_theme_constant_override("margin_left", 46)
	identity_margin.add_theme_constant_override("margin_right", 46)
	identity_margin.add_theme_constant_override("margin_top", 54)
	identity_margin.add_theme_constant_override("margin_bottom", 48)
	identity.add_child(identity_margin)
	var identity_stack := VBoxContainer.new()
	identity_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_stack.add_theme_constant_override("separation", 18)
	identity_margin.add_child(identity_stack)
	var crest := Label.new()
	crest.text = "♜  ✦  ♜"
	crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crest.add_theme_font_size_override("font_size", 72)
	crest.add_theme_color_override("font_color", Color("e9b44c"))
	identity_stack.add_child(crest)
	var heading := Label.new()
	heading.text = GameApp.text("app.title")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", Color("ffe2a8"))
	identity_stack.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = GameApp.text("app.subtitle")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color("9bc5e6"))
	identity_stack.add_child(subtitle)
	var rule := HSeparator.new()
	rule.custom_minimum_size.y = 16
	identity_stack.add_child(rule)
	var hint := Label.new()
	hint.text = GameApp.text("controls.hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color("98aabd"))
	identity_stack.add_child(hint)

	_content_panel = PanelContainer.new()
	_content_panel.custom_minimum_size.x = 600
	_content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_content_panel)
	_content_margin = MarginContainer.new()
	_content_margin.add_theme_constant_override("margin_left", 28)
	_content_margin.add_theme_constant_override("margin_right", 28)
	_content_margin.add_theme_constant_override("margin_top", 26)
	_content_margin.add_theme_constant_override("margin_bottom", 26)
	_content_panel.add_child(_content_margin)


func _show_main_navigation() -> void:
	var stack := _new_content_stack(GameApp.text("menu.continue"))
	var current_stage := int(GameApp.profile.get("highest_unlocked_stage", 1))
	var continue_button := _button(GameApp.text("menu.continue") + "  ·  %s %02d" % [GameApp.text("common.stage"), current_stage], 76)
	continue_button.pressed.connect(func() -> void: GameApp.start_stage("stage_%03d" % current_stage))
	stack.add_child(continue_button)
	for entry in [
		["menu.stage", Callable(self, "_show_stage_select")],
		["menu.upgrades", Callable(self, "_show_upgrades")],
		["menu.honors", Callable(self, "_show_honors")],
		["menu.saves", Callable(self, "_show_save_data")],
		["menu.settings", Callable(self, "_show_settings")],
		["menu.tutorial", Callable(self, "_show_tutorial")]
	]:
		var button := _button(GameApp.text(entry[0]), 62)
		button.pressed.connect(entry[1])
		stack.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(spacer)
	var quit_button := _button(GameApp.text("menu.quit"), 56)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(quit_button)


func _show_stage_select() -> void:
	var stack := _new_content_stack(GameApp.text("menu.stage"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var unlocked := int(GameApp.profile.get("highest_unlocked_stage", 1))
	var best_results: Dictionary = GameApp.profile.get("best_results", {})
	for stage in GameApp.content.rules.get("stages", []):
		var number := int(stage.get("number", 0))
		var stage_id := str(stage.get("id", ""))
		var label := "%s %02d  ·  %s" % [GameApp.text("common.stage"), number, GameApp.text(str(stage.get("name_key", "")))]
		if bool(stage.get("boss", false)):
			label += "  ⚠ " + GameApp.text("common.boss")
		var best: Dictionary = best_results.get(stage_id, {})
		if not best.is_empty():
			label += "\n★ %d%%  ·  %s %d" % [int(best.get("wall_percent", 0)), GameApp.text("result.kills"), int(best.get("kills", 0))]
		if number > unlocked:
			label += "\n🔒 " + GameApp.text("menu.locked")
		var reward: Dictionary = stage.get("clear_reward", {})
		label += "\n◆ %d   %s %d" % [int(reward.get("coins", 0)), GameApp.text("common.xp"), int(reward.get("xp", 0))]
		var stage_button := _button(label, 96)
		stage_button.disabled = number > unlocked
		stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_button.pressed.connect(func() -> void: GameApp.start_stage(stage_id))
		grid.add_child(stage_button)
	_add_back_button(stack)


func _show_upgrades() -> void:
	var pages: Array = GameApp.content.rules.get("research_pages", [])
	_show_research_page(str(pages[0].get("id", "attack")) if not pages.is_empty() else "")


# The page rebuilds after every purchase, so the highlighted node and the view
# offset must be passed back in; otherwise selection snaps to the first entry.
func _show_research_page(page_id: String, selected_id: String = "", saved_scroll: int = 0) -> void:
	var page_title := GameApp.text("menu.upgrades")
	for page in GameApp.content.rules.get("research_pages", []):
		if str(page.get("id", "")) == page_id:
			page_title = GameApp.text(str(page.get("name_key", page_id)))
			break
	var stack := _new_content_stack(page_title)
	var page_tabs := HBoxContainer.new()
	page_tabs.add_theme_constant_override("separation", 8)
	for page in GameApp.content.rules.get("research_pages", []):
		var page_button := _button(GameApp.text(str(page.get("name_key", page.get("id", "")))), 48)
		page_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_page := str(page.get("id", ""))
		page_button.disabled = selected_page == page_id
		page_button.pressed.connect(func() -> void: _show_research_page(selected_page))
		page_tabs.add_child(page_button)
	stack.add_child(page_tabs)
	# Asset purses (参考 top bar): coin and crystal pills.
	var wallet_row := HBoxContainer.new()
	wallet_row.add_theme_constant_override("separation", 14)
	stack.add_child(wallet_row)
	var wallet_coins := Label.new()
	wallet_coins.text = str(int(GameApp.profile.get("coins", 0)))
	wallet_row.add_child(_make_asset_pill("◆", Color("ffd166"), wallet_coins))
	var wallet_crystals := Label.new()
	wallet_crystals.text = str(int(GameApp.profile.get("crystals", 0)))
	wallet_row.add_child(_make_asset_pill("✦", Color("8fd3ff"), wallet_crystals))
	var operation_error := Label.new()
	operation_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	operation_error.add_theme_color_override("font_color", Color("ff8d7a"))
	stack.add_child(operation_error)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	# Tree layout (classic research pages): prerequisite chains linked by arrows.
	var tree := ResearchTree.new()
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tree)
	var page_definitions: Array = []
	for definition in GameApp.content.rules.get("upgrades", []):
		if not page_id.is_empty() and str(definition.get("page", "")) != page_id:
			continue
		page_definitions.append(definition)

	# Bottom detail panel: name, description, current→next effect and the
	# upgrade button, mirroring the classic research page detail area.
	var detail := PanelContainer.new()
	detail.custom_minimum_size.y = 132
	stack.add_child(detail)
	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 16)
	detail.add_child(detail_row)
	var detail_info := VBoxContainer.new()
	detail_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_row.add_child(detail_info)
	var detail_name := Label.new()
	detail_name.add_theme_font_size_override("font_size", 26)
	detail_info.add_child(detail_name)
	var detail_body := Label.new()
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_body.add_theme_font_size_override("font_size", 18)
	detail_info.add_child(detail_body)
	# Bottom-right purchase block (参考 detail panel): price above the button.
	var detail_right := VBoxContainer.new()
	detail_right.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_right.add_theme_constant_override("separation", 4)
	detail_row.add_child(detail_right)
	var detail_price := Label.new()
	detail_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_price.add_theme_font_size_override("font_size", 22)
	detail_price.add_theme_color_override("font_color", Color("ffd166"))
	detail_right.add_child(detail_price)
	var detail_button := _button("", 64)
	detail_button.custom_minimum_size = Vector2(180, 64)
	detail_right.add_child(detail_button)

	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	var definitions_by_id := {}
	for definition in page_definitions:
		definitions_by_id[str(definition.get("id", ""))] = definition

	var refresh_detail := func() -> void:
		var upgrade_id := tree.selected()
		var definition: Dictionary = definitions_by_id.get(upgrade_id, {})
		if definition.is_empty():
			return
		var level := int(upgrades.get(upgrade_id, 0))
		var max_level := int(definition.get("max_level", 0))
		var effect_per_level := int(definition.get("effect_per_level", 0))
		var current_effect := level * effect_per_level
		var effect_text := GameApp.text("upgrade.effect_current") % current_effect
		if level < max_level:
			effect_text = GameApp.text("upgrade.effect_next") % [current_effect, (level + 1) * effect_per_level]
		var prerequisite_names: Array[String] = []
		var prerequisites_met := true
		for prerequisite in definition.get("prerequisites", []):
			var prerequisite_id := str(prerequisite)
			prerequisite_names.append(_upgrade_display_name(prerequisite_id))
			if int(upgrades.get(prerequisite_id, 0)) <= 0:
				prerequisites_met = false
		var prerequisite_text := GameApp.text("upgrade.none") if prerequisite_names.is_empty() else ", ".join(prerequisite_names)
		detail_name.text = "%s   %s%d / %d" % [GameApp.text(str(definition.get("name_key", upgrade_id))), GameApp.text("common.level"), level, max_level]
		detail_name.add_theme_color_override("font_color", _upgrade_color(upgrade_id))
		detail_body.text = "%s\n%s  ·  %s: %s" % [
			GameApp.text(str(definition.get("description_key", ""))),
			effect_text,
			GameApp.text("upgrade.prerequisites"),
			prerequisite_text
		]
		var price := GameApp.upgrade_service.price_for_level(definition, level)
		detail_price.text = GameApp.text("common.max") if level >= max_level else "◆ %d" % price
		detail_button.text = GameApp.text("common.upgrade") if level < max_level else GameApp.text("common.max")
		detail_button.disabled = level >= max_level or int(GameApp.profile.get("coins", 0)) < price or not prerequisites_met

	tree.node_selected.connect(func(_upgrade_id: String) -> void: refresh_detail.call())
	detail_button.pressed.connect(func() -> void:
		var upgrade_id := tree.selected()
		var purchase_result := GameApp.purchase_upgrade(upgrade_id)
		if not bool(purchase_result.get("ok", false)):
			operation_error.text = GameApp.text("feedback.save_failed")
			return
		_refresh_header()
		_show_research_page(page_id, upgrade_id, scroll.scroll_vertical)
	)
	tree.build(page_definitions, upgrades, int(GameApp.profile.get("coins", 0)), selected_id)
	refresh_detail.call()
	_add_back_button(stack)
	if saved_scroll > 0:
		# Layout must run once before the scrollbar range exists to clamp into.
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = saved_scroll


# One-line effective stats for the loadout icon tooltips.
func _weapon_summary(definition: Dictionary) -> String:
	return "%s: %d  ·  %s: %.1f/s  ·  %s: %d  ·  %s: %d" % [
		GameApp.text("weapon.damage"), _weapon_effective_damage(definition),
		GameApp.text("weapon.fire_rate"), _weapon_effective_fire_rate(definition),
		GameApp.text("weapon.projectiles"), _weapon_effective_stat(definition, "projectile_count", "hurricane_mastery"),
		GameApp.text("weapon.pierce"), _weapon_effective_stat(definition, "pierce", "phantom_mastery")
	]


func _weapon_effective_damage(definition: Dictionary) -> int:
	return _weapon_effective_stat(definition, "damage", "strength")


# Shots per second at the 30 tick/s simulation rate, matching run_model's
# fire_cooldown = max(min_interval_ticks, interval_ticks - agility * effect).
func _weapon_effective_fire_rate(definition: Dictionary) -> float:
	var agility_bonus := _weapon_mastery_bonus("agility")
	var interval := maxi(int(definition.get("min_interval_ticks", 4)), int(definition.get("interval_ticks", 10)) - agility_bonus)
	var tick_rate := float(maxi(1, int(GameApp.content.rules.get("simulation_tick_rate", 30))))
	return tick_rate / float(maxi(1, interval))


func _weapon_mastery_bonus(mastery_id: String) -> int:
	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	var level := int(upgrades.get(mastery_id, 0))
	for upgrade in GameApp.content.rules.get("upgrades", []):
		if upgrade is Dictionary and str(upgrade.get("id", "")) == mastery_id:
			return level * int(upgrade.get("effect_per_level", 0))
	return 0


# Mirrors the run_model formulas so the card shows what research actually
# delivers in battle; raw base stats made upgraded research look lost.
func _weapon_effective_stat(definition: Dictionary, field: String, mastery_id: String) -> int:
	return int(definition.get(field, 1)) + _weapon_mastery_bonus(mastery_id)


func _show_honors() -> void:
	var stack := _new_content_stack(GameApp.text("menu.honors"))
	# Editable player name (参考 Status page: name header above the record).
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 12)
	stack.add_child(name_row)
	var name_caption := Label.new()
	name_caption.text = GameApp.text("status.player_name")
	name_caption.add_theme_font_size_override("font_size", 21)
	name_row.add_child(name_caption)
	var name_edit := LineEdit.new()
	name_edit.text = str(GameApp.profile.get("player_name", ""))
	name_edit.placeholder_text = GameApp.text("status.name_hint")
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(260, 44)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_edit)
	var name_save_error := Label.new()
	name_save_error.add_theme_color_override("font_color", Color("ff8d7a"))
	var save_name := func() -> void:
		var result := GameApp.update_profile_field("player_name", name_edit.text.strip_edges())
		if not bool(result.get("ok", false)):
			name_save_error.text = GameApp.text("feedback.save_failed")
		else:
			name_save_error.text = ""
	name_edit.text_submitted.connect(func(_text: String) -> void: save_name.call())
	name_edit.focus_exited.connect(save_name)
	stack.add_child(name_save_error)
	var stats: Dictionary = GameApp.profile.get("stats", {})
	var progress := Label.new()
	progress.text = "%s %d  ·  %s %d  ·  %s %d  ·  %s %d" % [
		GameApp.text("result.kills"), int(stats.get("total_kills", 0)),
		GameApp.text("common.stage"), int(stats.get("stages_completed", 0)),
		GameApp.text("menu.coins"), int(stats.get("total_coins_earned", 0)),
		GameApp.text("result.crystals"), int(GameApp.profile.get("crystals", 0))
	]
	progress.add_theme_font_size_override("font_size", 21)
	stack.add_child(progress)
	# Career playtime accumulated by GameApp into the active save's stats.
	var playtime := Label.new()
	playtime.text = "%s: %s" % [GameApp.text("saves.playtime"), _format_playtime(int(stats.get("playtime_seconds", 0)))]
	playtime.add_theme_font_size_override("font_size", 21)
	playtime.add_theme_color_override("font_color", Color("9bc5e6"))
	stack.add_child(playtime)
	# Battle record line (参考 Status screen: Win / Lose / Win%).
	var won := int(stats.get("battles_won", 0))
	var lost := int(stats.get("battles_lost", 0))
	var battles := won + lost
	var win_rate := (100.0 * float(won) / float(battles)) if battles > 0 else 0.0
	var record := Label.new()
	record.text = "%s %d  ·  %s %d  ·  %s %.1f%%" % [
		GameApp.text("result.wins"), won,
		GameApp.text("result.losses"), lost,
		GameApp.text("result.win_rate"), win_rate
	]
	record.add_theme_font_size_override("font_size", 21)
	record.add_theme_color_override("font_color", Color("9bc5e6"))
	stack.add_child(record)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var honors: Dictionary = GameApp.profile.get("honors", {})
	for definition in GameApp.content.rules.get("honors", []):
		var honor_id := str(definition.get("id", ""))
		var unlocked := bool(honors.get(honor_id, false))
		var threshold := maxi(1, int(definition.get("threshold", 1)))
		var current := _honor_progress(definition, stats)
		var card := PanelContainer.new()
		list.add_child(card)
		var honor_stack := VBoxContainer.new()
		honor_stack.add_theme_constant_override("separation", 6)
		card.add_child(honor_stack)
		var label := Label.new()
		label.text = "%s  ·  %s\n%s" % [
			"✦" if unlocked else "◇",
			GameApp.text(str(definition.get("name_key", honor_id))),
			GameApp.text(str(definition.get("description_key", "")))
		]
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("ffd166") if unlocked else Color("8693a6"))
		honor_stack.add_child(label)
		# Honor popup progress (参考 honor popup: bar + current/threshold).
		var honor_bar := ProgressBar.new()
		honor_bar.custom_minimum_size = Vector2(0, 14)
		honor_bar.max_value = threshold
		honor_bar.value = mini(threshold, current)
		honor_bar.show_percentage = false
		honor_bar.tooltip_text = "%d / %d" % [mini(current, threshold), threshold]
		honor_stack.add_child(honor_bar)
		var reward := Label.new()
		reward.text = "%s: ◆ %d   %s %d" % [
			GameApp.text("honor.reward"),
			int(definition.get("reward_coins", 0)),
			GameApp.text("common.xp"),
			int(definition.get("reward_xp", 0))
		]
		reward.add_theme_font_size_override("font_size", 15)
		reward.add_theme_color_override("font_color", Color("9fb2c8"))
		honor_stack.add_child(reward)
	_add_back_button(stack)


# Same semantics as honor_service._condition_met: counts behind the honor bar.
static func _honor_progress(definition: Dictionary, stats: Dictionary) -> int:
	var condition := str(definition.get("condition_type", ""))
	if condition == "weapons_used_count":
		return stats.get("weapons_used", []).size()
	return int(stats.get(condition, 0))


# Save-management page: one card per portable slot file with a career summary,
# load/switch actions, and the folder location for hand-carrying saves.
func _show_save_data() -> void:
	var stack := _new_content_stack(GameApp.text("menu.saves"))
	var operation_error := Label.new()
	operation_error.add_theme_color_override("font_color", Color("ff8d7a"))
	var path_hint := Label.new()
	path_hint.text = GameApp.text("saves.path_hint") % GameApp.save_directory_display()
	path_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_hint.add_theme_font_size_override("font_size", 16)
	path_hint.add_theme_color_override("font_color", Color("9fb2c8"))
	stack.add_child(path_hint)
	var open_folder := _button(GameApp.text("saves.open_folder"), 46)
	open_folder.pressed.connect(func() -> void:
		if not bool(GameApp.open_save_directory().get("ok", false)):
			operation_error.text = GameApp.text("feedback.save_failed")
	)
	stack.add_child(open_folder)
	stack.add_child(operation_error)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for summary in GameApp.save_slot_summaries():
		var slot_id := int(summary.get("slot_id", 0))
		var card := PanelContainer.new()
		list.add_child(card)
		var card_stack := VBoxContainer.new()
		card_stack.add_theme_constant_override("separation", 6)
		card.add_child(card_stack)
		var is_active := slot_id == int(GameApp.active_save_slot)
		var is_empty := not bool(summary.get("exists", false))
		var heading := "%s %d" % [GameApp.text("saves.slot"), slot_id]
		if is_active:
			heading += "  ·  " + GameApp.text("saves.current")
		elif is_empty:
			heading += "  ·  " + GameApp.text("saves.empty")
		elif bool(summary.get("ok", true)) and not str(summary.get("player_name", "")).is_empty():
			heading += "  ·  " + str(summary.get("player_name", ""))
		var title := Label.new()
		title.text = heading
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", Color("ffd166") if is_active else Color("e9eef5"))
		card_stack.add_child(title)
		if not is_empty:
			if bool(summary.get("ok", true)):
				var stats: Dictionary = summary.get("stats", {})
				var info := Label.new()
				info.text = "%s %d  ·  %s %d  ·  ◆ %d  ·  %s %d  ·  %s %s" % [
					GameApp.text("saves.stages_cleared"), int(stats.get("stages_completed", 0)),
					GameApp.text("result.kills"), int(stats.get("total_kills", 0)),
					int(summary.get("coins", 0)),
					GameApp.text("result.crystals"), int(summary.get("crystals", 0)),
					GameApp.text("saves.playtime"), _format_playtime(int(stats.get("playtime_seconds", 0)))
				]
				info.add_theme_font_size_override("font_size", 18)
				card_stack.add_child(info)
				var saved_label := Label.new()
				saved_label.text = "%s: %s  ·  %s %02d" % [
					GameApp.text("saves.last_saved"), _format_saved_at(str(summary.get("saved_at_utc", ""))),
					GameApp.text("common.stage"), int(summary.get("highest_unlocked_stage", 1))
				]
				saved_label.add_theme_font_size_override("font_size", 15)
				saved_label.add_theme_color_override("font_color", Color("9fb2c8"))
				card_stack.add_child(saved_label)
			else:
				var broken := Label.new()
				broken.text = GameApp.text("saves.broken")
				broken.add_theme_color_override("font_color", Color("ff8d7a"))
				card_stack.add_child(broken)
		var action := _button(
			GameApp.text("saves.in_use") if is_active else (GameApp.text("saves.new_game") if is_empty else GameApp.text("saves.load")),
			56
		)
		action.disabled = is_active or (not is_empty and not bool(summary.get("ok", true)))
		action.pressed.connect(func() -> void:
			var result := GameApp.switch_save_slot(slot_id)
			if bool(result.get("ok", false)):
				_refresh_header()
				_show_save_data()
			else:
				operation_error.text = GameApp.text("feedback.save_failed")
		)
		card_stack.add_child(action)
	_add_back_button(stack)


func _format_playtime(seconds: int) -> String:
	var total_minutes := maxi(0, seconds) / 60
	var hours := total_minutes / 60
	if hours <= 0:
		return GameApp.text("playtime.minutes") % total_minutes
	return GameApp.text("playtime.hours_minutes") % [hours, total_minutes % 60]


func _format_saved_at(saved_at_utc: String) -> String:
	if saved_at_utc.is_empty():
		return "-"
	return saved_at_utc.replace("T", " ")


func _show_settings() -> void:
	var stack := _new_content_stack(GameApp.text("settings.title"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var settings_content := VBoxContainer.new()
	settings_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_content.add_theme_constant_override("separation", 10)
	scroll.add_child(settings_content)
	_add_slider_row(settings_content, "settings.master", "master_volume")
	_add_slider_row(settings_content, "settings.music", "music_volume")
	_add_slider_row(settings_content, "settings.sfx", "sfx_volume")
	var language_row := _setting_row(GameApp.text("settings.language"))
	var language := OptionButton.new()
	language.add_item("简体中文")
	language.add_item("English")
	language.selected = 1 if str(GameApp.settings.get("language", "zh_CN")) == "en_US" else 0
	language.item_selected.connect(func(index: int) -> void:
		if _save_setting("language", "en_US" if index == 1 else "zh_CN"):
			_refresh_after_language_change()
	)
	language_row.add_child(language)
	settings_content.add_child(language_row)
	var resolution_row := _setting_row(GameApp.text("settings.resolution"))
	var resolution := OptionButton.new()
	var resolutions := ["1280x720", "1366x768", "1920x1080", "2560x1440"]
	for value in resolutions:
		resolution.add_item(value)
	resolution.selected = maxi(0, resolutions.find(str(GameApp.settings.get("resolution", "1920x1080"))))
	resolution.item_selected.connect(func(index: int) -> void: _save_setting("resolution", resolutions[index]))
	resolution_row.add_child(resolution)
	settings_content.add_child(resolution_row)
	_add_toggle_row(settings_content, "settings.fullscreen", "fullscreen")
	_add_toggle_row(settings_content, "settings.borderless", "borderless")
	_add_toggle_row(settings_content, "settings.aim_assist", "aim_assist")
	_add_toggle_row(settings_content, "settings.auto_fire", "auto_fire")
	_add_toggle_row(settings_content, "settings.shake", "screen_shake")
	_add_range_slider_row(settings_content, "settings.ui_scale", "ui_scale", 0.85, 1.25, 0.05)
	var quality_row := _setting_row(GameApp.text("settings.quality"))
	var quality := OptionButton.new()
	var qualities := ["low", "medium", "high"]
	for value in qualities:
		quality.add_item(GameApp.text("quality." + value))
	quality.selected = maxi(0, qualities.find(str(GameApp.settings.get("quality", "medium"))))
	quality.item_selected.connect(func(index: int) -> void: _save_setting("quality", qualities[index]))
	quality_row.add_child(quality)
	settings_content.add_child(quality_row)
	var note := Label.new()
	note.text = GameApp.text("settings.applied")
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("9fb2c8"))
	settings_content.add_child(note)
	_settings_note = note
	var export_diagnostics := _button(GameApp.text("settings.export_diagnostics"), 54)
	export_diagnostics.pressed.connect(_export_diagnostics)
	settings_content.add_child(export_diagnostics)
	_add_back_button(stack)


func _show_tutorial() -> void:
	var stack := _new_content_stack(GameApp.text("tutorial.title"))
	var glyphs := Label.new()
	glyphs.text = "⌖     🖱     ① ② ③     ⚡"
	glyphs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyphs.add_theme_font_size_override("font_size", 44)
	glyphs.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(glyphs)
	var body := Label.new()
	body.text = GameApp.text("tutorial.body")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(body)
	var save_error := Label.new()
	save_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	save_error.add_theme_color_override("font_color", Color("ff8d7a"))
	stack.add_child(save_error)
	var training := _button(GameApp.text("menu.start") + " · %s 01" % GameApp.text("common.stage"), 68)
	training.pressed.connect(func() -> void:
		var save_result := GameApp.complete_tutorial()
		if not bool(save_result.get("ok", false)):
			save_error.text = GameApp.text("feedback.save_failed")
			return
		GameApp.start_stage("stage_001", 1001)
	)
	stack.add_child(training)
	_add_back_button(stack)


func _new_content_stack(title_text: String) -> VBoxContainer:
	_clear_content()
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	_content_margin.add_child(stack)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(title)
	stack.add_child(HSeparator.new())
	return stack


func _clear_content() -> void:
	_settings_note = null
	for child in _content_margin.get_children():
		_content_margin.remove_child(child)
		child.queue_free()


func _add_back_button(stack: VBoxContainer) -> void:
	var back := _button("←  " + GameApp.text("menu.back"), 54)
	back.pressed.connect(_show_main_navigation)
	stack.add_child(back)


func _button(label: String, height: float) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = height
	return button


func _setting_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 52
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	return row


func _add_slider_row(stack: VBoxContainer, label_key: String, setting_key: String) -> void:
	_add_range_slider_row(stack, label_key, setting_key, 0.0, 1.0, 0.05)


func _add_range_slider_row(stack: VBoxContainer, label_key: String, setting_key: String, minimum: float, maximum: float, increment: float) -> void:
	var row := _setting_row(GameApp.text(label_key))
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 250
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = float(GameApp.settings.get(setting_key, 0.8))
	slider.value_changed.connect(func(value: float) -> void: _save_setting(setting_key, value))
	row.add_child(slider)
	stack.add_child(row)


func _add_toggle_row(stack: VBoxContainer, label_key: String, setting_key: String) -> void:
	var row := _setting_row(GameApp.text(label_key))
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(GameApp.settings.get(setting_key, true))
	toggle.toggled.connect(func(value: bool) -> void: _save_setting(setting_key, value))
	row.add_child(toggle)
	stack.add_child(row)


func _refresh_header() -> void:
	if _stage_label == null:
		return
	_stage_label.text = "%s %02d" % [GameApp.text("common.stage"), int(GameApp.profile.get("highest_unlocked_stage", 1))]
	_coins_label.text = str(int(GameApp.profile.get("coins", 0)))
	_crystals_label.text = str(int(GameApp.profile.get("crystals", 0)))
	var progress: Dictionary = Progression.level_progress(GameApp.content.rules, int(GameApp.profile.get("xp", 0)))
	_xp_label.text = GameApp.text("status.level_short") % int(progress.get("level", 1))
	_xp_bar.max_value = maxi(1, int(progress.get("needed", 1)))
	_xp_bar.value = int(progress.get("into_level", 0))
	_xp_bar.tooltip_text = "%d / %d %s" % [int(progress.get("into_level", 0)), int(progress.get("needed", 1)), GameApp.text("common.xp")]
	_rebuild_loadout()


# Original-style loadout strip in the top bar: every bow is an icon (click to
# equip; the gold frame marks the equipped one) followed by the three battle
# spell icons, replacing the old weapons list page.
func _rebuild_loadout() -> void:
	if _loadout_row == null:
		return
	for child in _loadout_row.get_children():
		_loadout_row.remove_child(child)
		child.queue_free()
	var current_id := str(GameApp.profile.get("current_weapon_id", "basic_bow"))
	var unlocked: Array = GameApp.profile.get("unlocked_weapons", [])
	for definition in GameApp.content.rules.get("weapons", []):
		var weapon_id := str(definition.get("id", ""))
		var weapon_name := GameApp.text(str(definition.get("name_key", weapon_id)))
		var is_unlocked := unlocked.has(weapon_id)
		var icon := Button.new()
		icon.text = str(WEAPON_GLYPHS.get(weapon_id, "🏹"))
		icon.custom_minimum_size = Vector2(56, 56)
		icon.add_theme_font_size_override("font_size", 27)
		icon.disabled = not is_unlocked
		if is_unlocked:
			icon.tooltip_text = "%s\n%s" % [weapon_name, _weapon_summary(definition)]
			if weapon_id != current_id:
				icon.pressed.connect(func() -> void:
					if bool(GameApp.select_weapon(weapon_id).get("ok", false)):
						_refresh_header()
				)
		else:
			icon.modulate = Color(0.55, 0.6, 0.68, 1)
			icon.tooltip_text = "%s\n🔒 %s %02d" % [weapon_name, GameApp.text("common.stage"), int(definition.get("unlock_stage", 1))]
		if weapon_id == current_id:
			for state in ["normal", "hover", "pressed", "disabled"]:
				icon.add_theme_stylebox_override(state, _loadout_frame(true))
		_loadout_row.add_child(icon)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	_loadout_row.add_child(gap)
	for spell_definition in [["🔥", "skill.fire"], ["❄", "skill.ice"], ["⚡", "skill.lightning"]]:
		var spell := Label.new()
		spell.text = str(spell_definition[0])
		spell.custom_minimum_size = Vector2(56, 56)
		spell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		spell.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		spell.add_theme_font_size_override("font_size", 27)
		spell.add_theme_stylebox_override("normal", _loadout_frame(false))
		spell.tooltip_text = GameApp.text(str(spell_definition[1]))
		_loadout_row.add_child(spell)


func _loadout_frame(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16263c")
	style.border_color = Color("ffd166") if highlighted else Color("33465e")
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(10)
	return style


# Coin/crystal purse pill (参考 top bar assets): glyph + amount in a framed box.
func _make_asset_pill(glyph: String, color: Color, value_label: Label) -> PanelContainer:
	var pill := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16263c")
	style.border_color = Color("33465e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 12.0
	style.content_margin_right = 14.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	pill.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	pill.add_child(row)
	var icon := Label.new()
	icon.text = glyph
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", color)
	row.add_child(icon)
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 21)
	value_label.custom_minimum_size = Vector2(64, 0)
	row.add_child(value_label)
	return pill


func _refresh_after_language_change() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_layout()
	_show_settings()


func _save_setting(key: String, value: Variant) -> bool:
	var result := GameApp.update_setting(key, value)
	if _settings_note != null and is_instance_valid(_settings_note):
		if bool(result.get("ok", false)):
			_settings_note.text = GameApp.text("settings.applied")
			_settings_note.add_theme_color_override("font_color", Color("9fb2c8"))
		else:
			_settings_note.text = GameApp.text("feedback.save_failed")
			_settings_note.add_theme_color_override("font_color", Color("ff8d7a"))
	return bool(result.get("ok", false))


func _export_diagnostics() -> void:
	var result := GameApp.export_diagnostics()
	if _settings_note == null or not is_instance_valid(_settings_note):
		return
	if bool(result.get("ok", false)):
		_settings_note.text = GameApp.text("settings.diagnostics_exported")
		_settings_note.add_theme_color_override("font_color", Color("8ce99a"))
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(str(result.get("path", ""))), true)
	else:
		_settings_note.text = GameApp.text("feedback.save_failed")
		_settings_note.add_theme_color_override("font_color", Color("ff8d7a"))


func _upgrade_display_name(upgrade_id: String) -> String:
	for definition in GameApp.content.rules.get("upgrades", []):
		if str(definition.get("id", "")) == upgrade_id:
			return GameApp.text(str(definition.get("name_key", upgrade_id)))
	return upgrade_id


static func _upgrade_color(upgrade_id: String) -> Color:
	if upgrade_id.contains("fire") or upgrade_id == "strength":
		return Color("ff9b54")
	if upgrade_id.contains("ice") or upgrade_id == "agility":
		return Color("78dce8")
	return Color("d7aefb")
