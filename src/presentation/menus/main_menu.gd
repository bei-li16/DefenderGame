extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const MenuBackdrop = preload("res://src/presentation/menus/menu_backdrop.gd")
const ResearchTree = preload("res://src/presentation/menus/research_tree.gd")
const Progression = preload("res://src/core/rules/progression.gd")
const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
const ResearchCatalog = preload("res://src/core/rules/research_catalog.gd")
const ResearchText = preload("res://src/presentation/research_text.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const SkillText = preload("res://src/presentation/skill_text.gd")
const AttackCatalog = preload("res://src/core/rules/attack_catalog.gd")
const AttackText = preload("res://src/presentation/attack_text.gd")
const Art = preload("res://src/presentation/art/game_art.gd")

var _content_panel: PanelContainer
var _identity_panel: PanelContainer
var _content_margin: MarginContainer
var _coins_label: Label
var _crystals_label: Label
var _xp_label: Label
var _xp_bar: ProgressBar
var _stage_label: Label
var _loadout_row: HBoxContainer
var _loadout_error: Label
var _research_detail_refresh: Callable
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
	_research_detail_refresh = Callable()
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
	_loadout_error = Label.new()
	_loadout_error.name = "LoadoutError"
	_loadout_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loadout_error.add_theme_color_override("font_color", Color("ff8d7a"))
	_loadout_error.visible = false
	vertical.add_child(_loadout_error)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 30)
	vertical.add_child(body)

	var identity := PanelContainer.new()
	_identity_panel = identity
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.custom_minimum_size.x = 620
	identity.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.02, 0.04, 0.07, 0.12), Color(0.6, 0.75, 0.9, 0.18)))
	body.add_child(identity)
	var identity_margin := MarginContainer.new()
	identity_margin.add_theme_constant_override("margin_left", 46)
	identity_margin.add_theme_constant_override("margin_right", 46)
	identity_margin.add_theme_constant_override("margin_top", 54)
	identity_margin.add_theme_constant_override("margin_bottom", 48)
	identity.add_child(identity_margin)
	var identity_stack := VBoxContainer.new()
	identity_stack.alignment = BoxContainer.ALIGNMENT_END
	identity_stack.add_theme_constant_override("separation", 18)
	identity_margin.add_child(identity_stack)
	var crest := Label.new()
	crest.text = "◆"
	crest.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crest.add_theme_font_size_override("font_size", 28)
	crest.add_theme_color_override("font_color", Color("e9b44c"))
	identity_stack.add_child(crest)
	var heading := Label.new()
	heading.text = GameApp.text("app.title")
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 64)
	heading.add_theme_color_override("font_color", Color("ffe2a8"))
	heading.add_theme_color_override("font_outline_color", Color("111b28"))
	heading.add_theme_constant_override("outline_size", 8)
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
	_content_panel.add_theme_stylebox_override("panel", UiTheme.panel_box(Color(0.025, 0.045, 0.075, 0.88), Color(0.45, 0.57, 0.7, 0.8)))
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


func _show_stage_select(page_index: int = -1, focus_stage: int = 0) -> void:
	_refresh_header()
	var stack := _new_content_stack(GameApp.text("menu.stage"))
	_identity_panel.visible = false
	var unlocked := clampi(int(GameApp.profile.get("highest_unlocked_stage", 1)), 1, StageCatalog.MAX_STAGE_NUMBER)
	if page_index < 0:
		focus_stage = unlocked
	var preview_end := mini(StageCatalog.MAX_STAGE_NUMBER, unlocked + StageCatalog.PAGE_SIZE)
	var last_page := (preview_end - 1) / StageCatalog.PAGE_SIZE
	var page := clampi((unlocked - 1) / StageCatalog.PAGE_SIZE if page_index < 0 else page_index, 0, last_page)
	var first := page * StageCatalog.PAGE_SIZE + 1
	var last := mini(StageCatalog.MAX_STAGE_NUMBER, first + StageCatalog.PAGE_SIZE - 1)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 14)
	stack.add_child(navigation)
	var previous := _button(GameApp.text("stage.previous_page"), 48)
	previous.name = "StagePreviousPage"
	previous.disabled = page == 0
	previous.pressed.connect(func() -> void: _show_stage_select(page - 1))
	navigation.add_child(previous)
	var range_label := Label.new()
	range_label.name = "StagePageRange"
	range_label.text = GameApp.text("stage.page_range") % [first, last]
	range_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_label.add_theme_font_size_override("font_size", 22)
	navigation.add_child(range_label)
	var following := _button(GameApp.text("stage.next_page"), 48)
	following.name = "StageNextPage"
	following.disabled = page >= last_page
	following.pressed.connect(func() -> void: _show_stage_select(page + 1))
	navigation.add_child(following)
	var jump := SpinBox.new()
	jump.name = "StageJumpNumber"
	jump.min_value = 1
	jump.max_value = unlocked
	jump.value = focus_stage if focus_stage > 0 else unlocked
	jump.step = 1
	jump.custom_minimum_size.x = 180
	jump.tooltip_text = GameApp.text("stage.jump_hint")
	navigation.add_child(jump)
	var jump_button := _button(GameApp.text("stage.jump"), 48)
	jump_button.name = "StageJumpButton"
	jump_button.pressed.connect(func() -> void: _show_stage_select((int(jump.value) - 1) / StageCatalog.PAGE_SIZE, int(jump.value)))
	navigation.add_child(jump_button)
	var note := Label.new()
	note.text = GameApp.text("stage.endless_hint")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 18)
	stack.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.name = "StageScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "StageGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	var best_results: Dictionary = GameApp.profile.get("best_results", {})
	var tick_rate := int(GameApp.content.rules.get("simulation_tick_rate", 30))
	for number in range(first, last + 1):
		var stage := StageCatalog.describe(GameApp.content.rules, number)
		if stage.is_empty():
			continue
		var stage_id := str(stage["id"])
		var label := "%s %02d  ·  %s" % [GameApp.text("common.stage"), number, GameApp.text(str(stage.get("name_key", "")))]
		if bool(stage.get("boss", false)):
			label += "  ⚠ " + GameApp.text("common.boss")
			if not str(stage.get("boss_id", "")).is_empty():
				label += " · " + GameApp.text(str(GameApp.content.find_by_id("enemies", str(stage["boss_id"])).get("name_key", "")))
		label += "\n" + GameApp.text("stage.plan_stats") % [int(stage["enemy_count"]), int(stage["wave_count"]), float(stage["spawn_duration_ticks"]) / tick_rate]
		var best: Dictionary = best_results.get(stage_id, {})
		if not best.is_empty():
			label += "\n★ %d%%  ·  %s %d" % [int(best.get("wall_percent", 0)), GameApp.text("result.kills"), int(best.get("kills", 0))]
		if number > unlocked:
			label += "\n🔒 " + GameApp.text("menu.locked")
		var reward: Dictionary = stage.get("clear_reward", {})
		label += "\n◆ %d   %s %d" % [int(reward.get("coins", 0)), GameApp.text("common.xp"), int(reward.get("xp", 0))]
		var stage_button := _button(label, 132)
		stage_button.name = "Stage_" + str(number)
		stage_button.add_theme_font_size_override("font_size", 21)
		stage_button.clip_text = true
		stage_button.tooltip_text = label
		stage_button.disabled = number > unlocked
		stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_button.pressed.connect(func() -> void: GameApp.start_stage(stage_id))
		grid.add_child(stage_button)
		if number == focus_stage:
			_focus_stage_card(scroll, stage_button)
	_add_back_button(stack)


func _focus_stage_card(scroll: ScrollContainer, card: Control) -> void:
	# Containers need their layout pass before the target's scroll offset exists.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(scroll) and is_instance_valid(card) and scroll.is_inside_tree():
		scroll.ensure_control_visible(card)


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
	# Research graphs use the full canvas, as in the reference screenshots.
	var full_tree := page_id in ["magic", "attack"]
	_identity_panel.visible = not full_tree
	if full_tree:
		stack.add_theme_constant_override("separation", 10)
	var page_tabs := HBoxContainer.new()
	page_tabs.add_theme_constant_override("separation", 8)
	for page in GameApp.content.rules.get("research_pages", []):
		var page_button := _button(GameApp.text(str(page.get("name_key", page.get("id", "")))), 48)
		# Five tabs must share the panel width: clip long labels instead of
		# pushing the minimum width past the canvas (layout gate AT-013).
		page_button.clip_text = true
		page_button.tooltip_text = GameApp.text(str(page.get("name_key", page.get("id", ""))))
		page_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_page := str(page.get("id", ""))
		page_button.disabled = selected_page == page_id
		page_button.pressed.connect(func() -> void: _show_research_page(selected_page))
		page_tabs.add_child(page_button)
	stack.add_child(page_tabs)
	# Asset purses (参考 top bar): coin and crystal pills.
	var wallet_row := HBoxContainer.new()
	wallet_row.visible = not full_tree
	wallet_row.add_theme_constant_override("separation", 14)
	stack.add_child(wallet_row)
	if page_id == "attack":
		var research_note := Label.new()
		research_note.add_theme_font_size_override("font_size", 16)
		research_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		research_note.text = GameApp.text("attack.rules") % str(GameApp.content.rules["ruleset_version"])
		var refund := int(GameApp.profile.get("attack_research_migration", {}).get("refunded_coins", 0))
		if refund > 0:
			research_note.text += "  " + GameApp.text("attack.refunded") % refund
		stack.add_child(research_note)
	var wallet_coins := Label.new()
	wallet_coins.text = str(int(GameApp.profile.get("coins", 0)))
	wallet_row.add_child(_make_asset_pill("◆", Color("ffd166"), wallet_coins))
	var wallet_crystals := Label.new()
	wallet_crystals.text = str(int(GameApp.profile.get("crystals", 0)))
	wallet_row.add_child(_make_asset_pill("✦", Color("8fd3ff"), wallet_crystals))
	var operation_error := Label.new()
	operation_error.visible = false
	operation_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	operation_error.add_theme_color_override("font_color", Color("ff8d7a"))
	stack.add_child(operation_error)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	# Tree layout (classic research pages): prerequisite chains linked by arrows.
	scroll.name = "ResearchScroll"
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
	if page_id == "magic":
		detail_info.add_theme_constant_override("separation", 2)
	detail_row.add_child(detail_info)
	var detail_name := Label.new()
	detail_name.name = "ResearchDetailName"
	detail_name.add_theme_font_size_override("font_size", 26)
	detail_info.add_child(detail_name)
	var detail_body := Label.new()
	detail_body.name = "ResearchDetailBody"
	detail_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_body.add_theme_font_size_override("font_size", 18)
	detail_info.add_child(detail_body)
	# Keep richer single-impact stats readable without hiding the three chains
	# above: compare current/next side by side instead of stacking eight lines.
	var skill_columns := HBoxContainer.new()
	skill_columns.name = "ResearchSkillComparison"
	skill_columns.add_theme_constant_override("separation", 18)
	skill_columns.visible = false
	detail_info.add_child(skill_columns)
	var skill_current := Label.new()
	skill_current.name = "ResearchSkillCurrent"
	var skill_next := Label.new()
	skill_next.name = "ResearchSkillNext"
	for stats in [skill_current, skill_next]:
		stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stats.add_theme_font_size_override("font_size", 17)
		skill_columns.add_child(stats)
	# Bottom-right purchase block (参考 detail panel): price above the button.
	var detail_right := VBoxContainer.new()
	detail_right.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_right.add_theme_constant_override("separation", 4)
	detail_row.add_child(detail_right)
	var growth_label := Label.new()
	growth_label.name = "ResearchGrowthPolicy"
	growth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	growth_label.add_theme_font_size_override("font_size", 14)
	detail_right.add_child(growth_label)
	var detail_price := Label.new()
	detail_price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_price.add_theme_font_size_override("font_size", 22)
	detail_price.add_theme_color_override("font_color", Color("ffd166"))
	detail_right.add_child(detail_price)
	var detail_button := _button("", 64)
	detail_button.name = "ResearchPurchaseButton"
	detail_button.custom_minimum_size = Vector2(180, 64)
	detail_right.add_child(detail_button)
	# Weapons page extra: equip the bow referenced by the selected node.
	var detail_equip := _button(GameApp.text("research.equip"), 64)
	detail_equip.name = "ResearchEquipButton"
	detail_equip.custom_minimum_size = Vector2(150, 64)
	detail_equip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	detail_equip.visible = false
	detail_row.add_child(detail_equip)

	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	var definitions_by_id := {}
	for definition in page_definitions:
		definitions_by_id[str(definition.get("id", ""))] = definition
	# Bows unlocked before the weapons research page existed (stage-based
	# legacy saves) count as their unlock node already purchased.
	if page_id == "weapons":
		upgrades = upgrades.duplicate(true)
		for weapon_id in GameApp.profile.get("unlocked_weapons", []):
			var unlock_key := "unlock_" + str(weapon_id)
			if definitions_by_id.has(unlock_key):
				upgrades[unlock_key] = 1

	var refresh_detail := func() -> void:
		var upgrade_id := tree.selected()
		var definition: Dictionary = definitions_by_id.get(upgrade_id, {})
		if definition.is_empty():
			return
		var level := ResearchCatalog.normalize_level(definition, int(upgrades.get(upgrade_id, 0)))
		var can_upgrade := ResearchCatalog.can_upgrade(definition, level)
		var effect_per_level := int(definition.get("effect_per_level", 0))
		var current_effect := ResearchCatalog.add_scaled(0, effect_per_level, level)
		var effect_text := GameApp.text("upgrade.effect_current") % current_effect
		if can_upgrade:
			effect_text = GameApp.text("upgrade.effect_next") % [current_effect, ResearchCatalog.add_scaled(0, effect_per_level, level + 1)]
		var prerequisite_names: Array[String] = []
		var prerequisites_met := true
		for prerequisite in definition.get("prerequisites", []):
			var prerequisite_id := str(prerequisite)
			var required := int(definition.get("prerequisite_levels", {}).get(prerequisite_id, 1))
			prerequisite_names.append("%s Lv.%d" % [_upgrade_display_name(prerequisite_id), required])
			if int(upgrades.get(prerequisite_id, 0)) < required:
				prerequisites_met = false
		var prerequisite_text := GameApp.text("upgrade.none") if prerequisite_names.is_empty() else ", ".join(prerequisite_names)
		var limit_text := "∞" if ResearchCatalog.is_endless(definition) else str(definition.get("max_level", 0))
		detail_name.text = "%s   %s%s / %s" % [GameApp.text(str(definition.get("name_key", upgrade_id))), GameApp.text("common.level"), ResearchText.compact(level), limit_text]
		detail_name.tooltip_text = "Lv.%d / %s" % [level, limit_text]
		detail_name.add_theme_color_override("font_color", _upgrade_color(upgrade_id))
		detail_body.text = "%s\n%s  ·  %s: %s" % [
			GameApp.text(str(definition.get("description_key", ""))),
			effect_text,
			GameApp.text("upgrade.prerequisites"),
			prerequisite_text
		]
		var price := GameApp.upgrade_service.price_for_level(definition, level)
		var currency := str(definition.get("currency", "coins"))
		var weapon_ref := str(definition.get("weapon_ref", ""))
		var already_unlocked: bool = upgrade_id == "unlock_" + weapon_ref and GameApp.profile.get("unlocked_weapons", []).has(weapon_ref)
		var price_glyph := "✦" if currency == "crystals" else "◆"
		detail_price.text = GameApp.text("common.max") if not can_upgrade else ("✦" if already_unlocked else "%s %s" % [price_glyph, ResearchText.compact(price)])
		detail_price.tooltip_text = "%s %d" % [price_glyph, price]
		detail_price.add_theme_color_override("font_color", Color("8fd3ff") if currency == "crystals" else Color("ffd166"))
		detail_button.text = GameApp.text("research.unlocked") if already_unlocked else (GameApp.text("common.upgrade") if can_upgrade else GameApp.text("common.max"))
		detail_button.disabled = not can_upgrade or already_unlocked or int(GameApp.profile.get(currency, 0)) < price or not prerequisites_met
		# Weapons page: show the referenced bow's stats and offer equipping it.
		if not weapon_ref.is_empty():
			var weapon_definition: Dictionary = GameApp.content.find_by_id("weapons", weapon_ref)
			if not weapon_definition.is_empty():
				detail_body.text += "
%s" % _weapon_summary(weapon_definition)
			var unlocked_weapons: Array = GameApp.profile.get("unlocked_weapons", [])
			var equipped := str(GameApp.profile.get("current_weapon_id", "basic_bow")) == weapon_ref
			detail_equip.visible = unlocked_weapons.has(weapon_ref)
			detail_equip.text = GameApp.text("menu.selected" if equipped else "research.equip")
			detail_equip.disabled = equipped or not unlocked_weapons.has(weapon_ref)
		else:
			detail_equip.visible = false
		if page_id == "attack":
			var equipped_weapon := GameApp.content.find_by_id("weapons", str(GameApp.profile.get("current_weapon_id", "basic_bow")))
			detail_body.text = GameApp.text(str(definition["description_key"])) + "\n"
			detail_body.text += AttackText.detail(GameApp.content.rules, GameApp.profile, equipped_weapon, upgrade_id, GameApp.text)
			detail_body.text += "\n" + GameApp.text("upgrade.prerequisites") + ": " + prerequisite_text
		var skill_ref := str(definition.get("skill_ref", ""))
		skill_columns.visible = not skill_ref.is_empty()
		detail_body.add_theme_font_size_override("font_size", 17 if not skill_ref.is_empty() else 18)
		if not skill_ref.is_empty():
			var current := SkillCatalog.effective(GameApp.content.rules, GameApp.profile, skill_ref)
			var next_profile: Dictionary = GameApp.profile.duplicate(true)
			next_profile["upgrades"][upgrade_id] = level + 1 if can_upgrade else level
			var next := SkillCatalog.effective(GameApp.content.rules, next_profile, skill_ref)
			var rate := int(GameApp.content.rules.get("simulation_tick_rate", 30))
			detail_body.text = GameApp.text(str(definition["description_key"])) + "  ·  " + GameApp.text("upgrade.prerequisites") + ": " + prerequisite_text
			skill_current.text = GameApp.text("skill.current") + SkillText.summary(current, GameApp.text, rate)
			skill_next.visible = can_upgrade
			skill_next.text = GameApp.text("skill.next") + SkillText.summary(next, GameApp.text, rate)
			var available := SkillCatalog.available(GameApp.content.rules, GameApp.profile, skill_ref)
			var equipped := SkillCatalog.loadout(GameApp.content.rules, GameApp.profile).values().has(skill_ref)
			detail_equip.visible = available
			detail_equip.disabled = equipped
			detail_equip.text = GameApp.text("menu.selected" if equipped else "research.equip")

		var specialized := ResearchText.specialized(GameApp.content.rules, GameApp.profile, upgrade_id, GameApp.text)
		if not specialized.is_empty():
			detail_body.text = GameApp.text(str(definition["description_key"])) + "\n" + specialized
			detail_body.text += "\n" + GameApp.text("upgrade.prerequisites") + ": " + prerequisite_text
		if ResearchCatalog.is_endless(definition):
			var growth_note := GameApp.text("research.endless_damage") % int(definition["secondary_max_level"]) if definition.has("skill_ref") else GameApp.text("research.endless_growth")
			detail_name.tooltip_text += "\n" + growth_note
			growth_label.text = GameApp.text("research.endless_short")
			if definition.has("skill_ref"):
				growth_label.text += "\n" + GameApp.text("research.secondary_cap") % int(definition["secondary_max_level"])
		else:
			growth_label.text = ""
			detail_name.tooltip_text += "\n" + GameApp.text("research.finite_growth") % int(definition.get("max_level", 0))

	tree.node_selected.connect(func(_upgrade_id: String) -> void: refresh_detail.call())
	_research_detail_refresh = refresh_detail
	detail_equip.pressed.connect(func() -> void:
		var upgrade_id := tree.selected()
		var definition: Dictionary = definitions_by_id.get(upgrade_id, {})
		var weapon_ref := str(definition.get("weapon_ref", ""))
		if not weapon_ref.is_empty():
			_equip_weapon(weapon_ref)
		var skill_ref := str(definition.get("skill_ref", ""))
		if not skill_ref.is_empty():
			operation_error.text = ""
			operation_error.visible = false
			_equip_skill(skill_ref)
	)
	detail_button.pressed.connect(func() -> void:
		var upgrade_id := tree.selected()
		var purchase_result := GameApp.purchase_upgrade(upgrade_id)
		if not bool(purchase_result.get("ok", false)):
			var error_code := str(purchase_result.get("error_code", ""))
			if error_code == "insufficient_crystals":
				operation_error.text = GameApp.text("feedback.insufficient_crystals")
			elif error_code == "insufficient_coins":
				operation_error.text = GameApp.text("feedback.insufficient_coins")
			else:
				operation_error.text = GameApp.text("feedback.save_failed")
			operation_error.visible = true
			return
		operation_error.visible = false
		_refresh_header()
		_show_research_page(page_id, upgrade_id, scroll.scroll_vertical)
	)
	tree.build(page_definitions, upgrades, {"coins": int(GameApp.profile.get("coins", 0)), "crystals": int(GameApp.profile.get("crystals", 0))}, selected_id)
	refresh_detail.call()
	_add_back_button(stack)
	if saved_scroll > 0:
		# Layout must run once before the scrollbar range exists to clamp into.
		await get_tree().process_frame
		if is_instance_valid(scroll):
			scroll.scroll_vertical = saved_scroll


# One-line effective stats for the loadout icon tooltips.
func _weapon_summary(definition: Dictionary) -> String:
	var stats := AttackCatalog.effective(GameApp.content.rules, GameApp.profile, definition)
	return "%s: %d  ·  %s: %.1f/s  ·  %s: %d  ·  %s: %d" % [
		GameApp.text("weapon.damage"), int(stats["damage"]),
		GameApp.text("weapon.fire_rate"), _weapon_effective_fire_rate(definition),
		GameApp.text("weapon.projectiles"), int(stats["projectile_count"]),
		GameApp.text("weapon.pierce"), int(stats["pierce"])
	]


func _weapon_effective_damage(definition: Dictionary) -> int:
	return int(AttackCatalog.effective(GameApp.content.rules, GameApp.profile, definition)["damage"])


# Shared with battle, including the configured minimum fire interval.
func _weapon_effective_fire_rate(definition: Dictionary) -> float:
	var interval := int(AttackCatalog.effective(GameApp.content.rules, GameApp.profile, definition)["interval_ticks"])
	var tick_rate := float(maxi(1, int(GameApp.content.rules.get("simulation_tick_rate", 30))))
	return tick_rate / float(maxi(1, interval))


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
		var honor_value: Variant = honors.get(honor_id, 0)
		var honor_level: int = (1 if bool(honor_value) else 0) if honor_value is bool else clampi(int(honor_value), 0, 3)
		var current := _honor_progress(definition, stats)
		var milestones: Array = definition.get("milestones", [])
		var maxed := honor_level >= milestones.size()
		var card := PanelContainer.new()
		list.add_child(card)
		var honor_stack := VBoxContainer.new()
		honor_stack.add_theme_constant_override("separation", 6)
		card.add_child(honor_stack)
		# Badge pips light up per achieved level (参考 Status badge row).
		var pips := ""
		for pip in range(milestones.size()):
			pips += "✦" if pip < honor_level else "◇"
		var label := Label.new()
		label.text = "%s  ·  %s %d/%d\n%s" % [
			pips,
			GameApp.text(str(definition.get("name_key", honor_id))),
			honor_level, milestones.size(),
			GameApp.text(str(definition.get("description_key", "")))
		]
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("ffd166") if honor_level > 0 else Color("8693a6"))
		honor_stack.add_child(label)
		# Progress toward the next milestone (full bar at max level).
		var honor_bar := ProgressBar.new()
		honor_bar.custom_minimum_size = Vector2(0, 14)
		if maxed:
			honor_bar.max_value = 1
			honor_bar.value = 1
			honor_bar.tooltip_text = GameApp.text("honor.maxed")
		else:
			var next_milestone := int(milestones[honor_level])
			honor_bar.max_value = next_milestone
			honor_bar.value = mini(next_milestone, current)
			honor_bar.show_percentage = false
			honor_bar.tooltip_text = "%s %d / %d" % [GameApp.text("honor.next_milestone"), mini(current, next_milestone), next_milestone]
		honor_stack.add_child(honor_bar)
		var reward := Label.new()
		var reward_coins: Array = definition.get("reward_coins", [])
		var reward_xp: Array = definition.get("reward_xp", [])
		var reward_level := mini(honor_level, maxi(0, reward_coins.size() - 1))
		reward.text = "%s: ◆ %d   %s %d" % [
			GameApp.text("honor.reward"),
			int(reward_coins[reward_level]) if not reward_coins.is_empty() else 0,
			GameApp.text("common.xp"),
			int(reward_xp[reward_level]) if not reward_xp.is_empty() else 0
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
	_add_admin_section(settings_content)
	_add_back_button(stack)


# Admin console: entering the password unlocks two fields that directly set
# the coin and crystal balances, persisted through the same save-first
# transaction as every other profile write.
func _add_admin_section(settings_content: VBoxContainer) -> void:
	settings_content.add_child(HSeparator.new())
	var admin_title := Label.new()
	admin_title.text = GameApp.text("admin.title")
	admin_title.add_theme_font_size_override("font_size", 22)
	admin_title.add_theme_color_override("font_color", Color("ffd166"))
	settings_content.add_child(admin_title)
	var password_row := _setting_row(GameApp.text("admin.password"))
	var password := LineEdit.new()
	password.name = "AdminPassword"
	password.secret = true
	password.secret_character = "*"
	password.custom_minimum_size.x = 250
	password.placeholder_text = GameApp.text("admin.password_hint")
	password_row.add_child(password)
	settings_content.add_child(password_row)
	var feedback := Label.new()
	feedback.add_theme_font_size_override("font_size", 16)
	settings_content.add_child(feedback)
	var unlock := _button(GameApp.text("admin.unlock"), 54)
	unlock.name = "AdminUnlock"
	settings_content.add_child(unlock)
	var panel := VBoxContainer.new()
	panel.name = "AdminPanel"
	panel.add_theme_constant_override("separation", 10)
	panel.visible = false
	settings_content.add_child(panel)
	var coins_edit := _add_admin_amount_row(panel, "admin.coins", int(GameApp.profile.get("coins", 0)), "AdminCoins")
	var crystals_edit := _add_admin_amount_row(panel, "admin.crystals", int(GameApp.profile.get("crystals", 0)), "AdminCrystals")
	var apply := _button(GameApp.text("admin.apply"), 54)
	apply.name = "AdminApply"
	panel.add_child(apply)
	unlock.pressed.connect(func() -> void:
		if password.text == "root":
			panel.visible = true
			unlock.disabled = true
			password.editable = false
			feedback.text = GameApp.text("admin.unlocked")
			feedback.add_theme_color_override("font_color", Color("8ce99a"))
		else:
			feedback.text = GameApp.text("admin.wrong_password")
			feedback.add_theme_color_override("font_color", Color("ff8d7a"))
	)
	apply.pressed.connect(func() -> void:
		var coins_result := GameApp.update_profile_field("coins", maxi(0, int(coins_edit.value)))
		if not bool(coins_result.get("ok", false)):
			feedback.text = GameApp.text("feedback.save_failed")
			feedback.add_theme_color_override("font_color", Color("ff8d7a"))
			return
		var crystals_result := GameApp.update_profile_field("crystals", maxi(0, int(crystals_edit.value)))
		if not bool(crystals_result.get("ok", false)):
			feedback.text = GameApp.text("feedback.save_failed")
			feedback.add_theme_color_override("font_color", Color("ff8d7a"))
			return
		feedback.text = GameApp.text("admin.applied")
		feedback.add_theme_color_override("font_color", Color("8ce99a"))
		_refresh_header()
	)


func _add_admin_amount_row(panel: VBoxContainer, label_key: String, current: int, node_name: String) -> SpinBox:
	var row := _setting_row(GameApp.text(label_key))
	var edit := SpinBox.new()
	edit.name = node_name
	edit.min_value = 0
	edit.max_value = 999999999
	edit.step = 1
	edit.value = current
	edit.custom_minimum_size.x = 250
	row.add_child(edit)
	panel.add_child(row)
	return edit


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
	_research_detail_refresh = Callable()
	_identity_panel.visible = true
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


# Original-style loadout strip in the top bar: a single slot for the equipped
# bow (click it for the bow dropdown) followed by the three battle spells.
# The dropdown lists every bow: unlocked ones equip on click, locked ones
# route into the weapons research page.
func _rebuild_loadout() -> void:
	if _loadout_row == null:
		return
	for child in _loadout_row.get_children():
		_loadout_row.remove_child(child)
		child.queue_free()
	var current_id := str(GameApp.profile.get("current_weapon_id", "basic_bow"))
	var unlocked: Array = GameApp.profile.get("unlocked_weapons", [])
	var current_definition: Dictionary = GameApp.content.find_by_id("weapons", current_id)
	# MenuButton applies the viewport scale and window offset to its popup.
	# A plain Button + get_global_rect() uses logical canvas coordinates and
	# leaves the dropdown detached from the slot in resized/moved windows.
	var slot := MenuButton.new()
	slot.name = "BowSelector"
	slot.flat = false
	slot.text = GameApp.text("loadout.dropdown_hint")
	slot.icon = Art.texture(current_id)
	slot.expand_icon = true
	slot.add_theme_constant_override("icon_max_width", 48)
	slot.custom_minimum_size = Vector2(120, 56)
	slot.add_theme_font_size_override("font_size", 27)
	slot.clip_text = true
	slot.tooltip_text = "%s
%s" % [GameApp.text(str(current_definition.get("name_key", current_id))), _weapon_summary(current_definition)]
	var bow_menu := slot.get_popup()
	bow_menu.add_theme_stylebox_override("panel", UiTheme.panel_box())
	bow_menu.add_theme_font_size_override("font_size", 24)
	bow_menu.add_theme_color_override("font_disabled_color", Color("ffd166"))
	bow_menu.add_theme_constant_override("v_separation", 12)
	var index_by_item := {}
	var item_index := 0
	for definition in GameApp.content.rules.get("weapons", []):
		var weapon_id := str(definition.get("id", ""))
		var weapon_name := GameApp.text(str(definition.get("name_key", weapon_id)))
		if weapon_id == current_id:
			bow_menu.add_item("✓  " + weapon_name, item_index)
			bow_menu.set_item_disabled(item_index, true)
		elif unlocked.has(weapon_id):
			bow_menu.add_item("      " + weapon_name, item_index)
			index_by_item[item_index] = weapon_id
		else:
			# Locked bows route into the weapons research page; show the price
			# from that page's unlock node (single source of truth).
			var unlock_node: Dictionary = GameApp.content.find_by_id("upgrades", "unlock_" + weapon_id)
			var price := int(unlock_node.get("base_cost", 0))
			if price > 0:
				bow_menu.add_item("🔒  %s  ·  ◆ %d" % [weapon_name, price], item_index)
			else:
				bow_menu.add_item("🔒  %s" % weapon_name, item_index)
			index_by_item[item_index] = "unlock_" + weapon_id
		bow_menu.set_item_tooltip(item_index, weapon_name + "  ·  " + _weapon_summary(definition))
		bow_menu.set_item_icon(item_index, Art.texture(weapon_id))
		bow_menu.set_item_icon_max_width(item_index, 42)
		item_index += 1
	bow_menu.index_pressed.connect(func(item_index: int) -> void:
		bow_menu.hide()
		var target: String = index_by_item.get(item_index, "")
		if target.is_empty():
			return
		if target.begins_with("unlock_"):
			_show_research_page("weapons", target)
		else:
			_equip_weapon(target)
	)
	_loadout_row.add_child(slot)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	_loadout_row.add_child(gap)
	var loadout := SkillCatalog.loadout(GameApp.content.rules, GameApp.profile)
	for spell_definition in [["🔥", "fire"], ["❄", "ice"], ["⚡", "lightning"]]:
		var skill := SkillCatalog.effective(GameApp.content.rules, GameApp.profile, str(loadout.get(spell_definition[1], "")))
		var spell := MenuButton.new()
		spell.name = "SkillSelector_" + str(spell_definition[1])
		spell.flat = false
		spell.text = "%s%s ▾" % [str(spell_definition[0]), ["Ⅰ", "Ⅱ", "Ⅲ"][int(skill.get("tier", 1)) - 1]]
		spell.custom_minimum_size = Vector2(92, 56)
		spell.add_theme_font_size_override("font_size", 23)
		spell.add_theme_stylebox_override("normal", _loadout_frame(false))
		spell.add_theme_stylebox_override("hover", _loadout_frame(true))
		spell.add_theme_stylebox_override("pressed", _loadout_frame(true))
		spell.add_theme_stylebox_override("hover_pressed", _loadout_frame(true))
		spell.tooltip_text = GameApp.text(str(skill.get("name_key", ""))) + "\n" + SkillText.summary(skill, GameApp.text, int(GameApp.content.rules.get("simulation_tick_rate", 30)))
		var popup := spell.get_popup()
		popup.add_theme_stylebox_override("panel", UiTheme.panel_box())
		popup.add_theme_font_size_override("font_size", 24)
		popup.add_theme_color_override("font_disabled_color", Color("d9be78"))
		popup.add_theme_stylebox_override("hover", _loadout_frame(true))
		popup.add_theme_constant_override("v_separation", 12)
		var choices: Array[Dictionary] = []
		for definition in GameApp.content.rules.get("skills", []):
			if str(definition["element"]) != str(spell_definition[1]):
				continue
			var id := str(definition["id"])
			var available := SkillCatalog.available(GameApp.content.rules, GameApp.profile, id)
			var equipped := id == str(skill["id"])
			var index := choices.size()
			choices.append(definition)
			popup.add_item("%s %s %s  ·  ◈ %d" % ["✓" if equipped else ("  " if available else "🔒"), ["Ⅰ", "Ⅱ", "Ⅲ"][int(definition["tier"]) - 1], GameApp.text(str(definition["name_key"])), int(definition["mana_cost"])], index)
			popup.set_item_disabled(index, equipped)
			popup.set_item_tooltip(index, SkillText.summary(SkillCatalog.effective(GameApp.content.rules, GameApp.profile, id), GameApp.text, int(GameApp.content.rules.get("simulation_tick_rate", 30))))
		popup.index_pressed.connect(func(index: int) -> void:
			popup.hide()
			if index < 0 or index >= choices.size():
				return
			var definition := choices[index]
			if SkillCatalog.available(GameApp.content.rules, GameApp.profile, str(definition["id"])):
				_equip_skill(str(definition["id"]))
			else:
				_show_research_page("magic", str(definition["upgrade_id"]))
		)
		_loadout_row.add_child(spell)


# Both entry points persist the same profile field. Refresh the open research
# detail without rebuilding its tree, so selection and scroll stay in place.
func _equip_weapon(weapon_id: String) -> void:
	var result := GameApp.select_weapon(weapon_id)
	var saved := bool(result.get("ok", false))
	_loadout_error.text = "" if saved else GameApp.text("feedback.save_failed")
	_loadout_error.visible = not saved
	if not saved:
		return
	_refresh_header()
	if _research_detail_refresh.is_valid():
		_research_detail_refresh.call()


func _equip_skill(skill_id: String) -> void:
	var saved := bool(GameApp.select_skill(skill_id).get("ok", false))
	_loadout_error.text = "" if saved else GameApp.text("feedback.save_failed")
	_loadout_error.visible = not saved
	if saved:
		_refresh_header()
		if _research_detail_refresh.is_valid():
			_research_detail_refresh.call()


func _loadout_frame(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16263c")
	style.border_color = Color("ffd166") if highlighted else Color("33465e")
	style.set_border_width_all(2 if highlighted else 1)
	style.set_corner_radius_all(10)
	# Identical compact margins in normal/hover/pressed states prevent the
	# tier and dropdown arrow being clipped when MenuButton opens its popup.
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
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
	var upgrade := GameApp.content.find_by_id("upgrades", upgrade_id)
	var skill := GameApp.content.find_by_id("skills", str(upgrade.get("skill_ref", "")))
	match str(skill.get("element", "")):
		"fire": return Color("ff9b54")
		"ice": return Color("78dce8")
		"lightning": return Color("d7aefb")
	if upgrade_id.contains("fire") or upgrade_id == "strength":
		return Color("ff9b54")
	if upgrade_id.contains("ice") or upgrade_id == "agility":
		return Color("78dce8")
	return Color("d7aefb")
