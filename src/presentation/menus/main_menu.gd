extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const MenuBackdrop = preload("res://src/presentation/menus/menu_backdrop.gd")

var _content_panel: PanelContainer
var _content_margin: MarginContainer
var _coins_label: Label
var _xp_label: Label
var _stage_label: Label
var _settings_note: Label


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

	var top := PanelContainer.new()
	top.custom_minimum_size.y = 78
	vertical.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 28)
	top.add_child(top_row)
	var title := Label.new()
	title.text = GameApp.text("app.title")
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", Color("ffd166"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)
	_stage_label = Label.new()
	_coins_label = Label.new()
	_xp_label = Label.new()
	for label in [_stage_label, _coins_label, _xp_label]:
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 23)
		top_row.add_child(label)
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
		["menu.weapons", Callable(self, "_show_weapons")],
		["menu.honors", Callable(self, "_show_honors")],
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


func _show_research_page(page_id: String) -> void:
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
	var wallet := Label.new()
	wallet.text = "◆  %d %s" % [int(GameApp.profile.get("coins", 0)), GameApp.text("menu.coins")]
	wallet.add_theme_font_size_override("font_size", 26)
	wallet.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(wallet)
	var operation_error := Label.new()
	operation_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	operation_error.add_theme_color_override("font_color", Color("ff8d7a"))
	stack.add_child(operation_error)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	for definition in GameApp.content.rules.get("upgrades", []):
		if not page_id.is_empty() and str(definition.get("page", "")) != page_id:
			continue
		var upgrade_id := str(definition.get("id", ""))
		var level := int(upgrades.get(upgrade_id, 0))
		var max_level := int(definition.get("max_level", 0))
		var price := GameApp.upgrade_service.price_for_level(definition, level)
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
		var card := PanelContainer.new()
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name := Label.new()
		name.text = "%s   %s%d / %d" % [GameApp.text(str(definition.get("name_key", upgrade_id))), GameApp.text("common.level"), level, max_level]
		name.add_theme_font_size_override("font_size", 25)
		name.add_theme_color_override("font_color", _upgrade_color(upgrade_id))
		info.add_child(name)
		var description := Label.new()
		description.text = "%s\n%s  ·  %s: %s" % [
			GameApp.text(str(definition.get("description_key", ""))),
			effect_text,
			GameApp.text("upgrade.prerequisites"),
			prerequisite_text
		]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 17)
		info.add_child(description)
		var purchase := _button(GameApp.text("common.max") if level >= max_level else "◆ %d\n%s" % [price, GameApp.text("common.upgrade")], 66)
		purchase.custom_minimum_size.x = 146
		purchase.disabled = level >= max_level or int(GameApp.profile.get("coins", 0)) < price or not prerequisites_met
		purchase.pressed.connect(func() -> void:
			var purchase_result := GameApp.purchase_upgrade(upgrade_id)
			if not bool(purchase_result.get("ok", false)):
				operation_error.text = GameApp.text("feedback.save_failed")
				return
			_refresh_header()
			_show_upgrades()
		)
		row.add_child(purchase)
	_add_back_button(stack)


func _show_weapons() -> void:
	var stack := _new_content_stack(GameApp.text("menu.weapons"))
	var current_id := str(GameApp.profile.get("current_weapon_id", "basic_bow"))
	var unlocked: Array = GameApp.profile.get("unlocked_weapons", [])
	var note := Label.new()
	note.text = "%s: %s" % [GameApp.text("menu.selected"), GameApp.text(str(GameApp.content.find_by_id("weapons", current_id).get("name_key", current_id)))]
	note.add_theme_font_size_override("font_size", 22)
	note.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for definition in GameApp.content.rules.get("weapons", []):
		var weapon_id := str(definition.get("id", ""))
		var is_unlocked := unlocked.has(weapon_id)
		var card := PanelContainer.new()
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name := Label.new()
		name.text = "%s  ·  %s %d" % [GameApp.text(str(definition.get("name_key", weapon_id))), GameApp.text("common.stage"), int(definition.get("unlock_stage", 1))]
		name.add_theme_font_size_override("font_size", 25)
		name.add_theme_color_override("font_color", Color("8ce99a") if is_unlocked else Color("8693a6"))
		info.add_child(name)
		var description := Label.new()
		description.text = "%s\n%s: %d  ·  %s: %d  ·  %s: %d" % [
			GameApp.text(str(definition.get("description_key", ""))),
			GameApp.text("weapon.damage"), _weapon_effective_damage(definition),
			GameApp.text("weapon.projectiles"), _weapon_effective_stat(definition, "projectile_count", "hurricane_mastery"),
			GameApp.text("weapon.pierce"), _weapon_effective_stat(definition, "pierce", "phantom_mastery")
		]
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(description)
		var equip := _button(GameApp.text("menu.selected") if weapon_id == current_id else (GameApp.text("menu.unlocked") if is_unlocked else GameApp.text("menu.locked")), 66)
		equip.custom_minimum_size.x = 150
		equip.disabled = not is_unlocked or weapon_id == current_id
		equip.pressed.connect(func() -> void:
			var result := GameApp.select_weapon(weapon_id)
			if bool(result.get("ok", false)):
				_show_weapons()
		)
		row.add_child(equip)
	_add_back_button(stack)


func _weapon_effective_damage(definition: Dictionary) -> int:
	return _weapon_effective_stat(definition, "damage", "strength")


# Mirrors the run_model formulas so the card shows what research actually
# delivers in battle; raw base stats made upgraded research look lost.
func _weapon_effective_stat(definition: Dictionary, field: String, mastery_id: String) -> int:
	var base := int(definition.get(field, 1))
	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	var level := int(upgrades.get(mastery_id, 0))
	var effect_per_level := 0
	for upgrade in GameApp.content.rules.get("upgrades", []):
		if upgrade is Dictionary and str(upgrade.get("id", "")) == mastery_id:
			effect_per_level = int(upgrade.get("effect_per_level", 0))
			break
	return base + level * effect_per_level


func _show_honors() -> void:
	var stack := _new_content_stack(GameApp.text("menu.honors"))
	var stats: Dictionary = GameApp.profile.get("stats", {})
	var progress := Label.new()
	progress.text = "%s %d  ·  %s %d  ·  %s %d" % [
		GameApp.text("result.kills"), int(stats.get("total_kills", 0)),
		GameApp.text("common.stage"), int(stats.get("stages_completed", 0)),
		GameApp.text("menu.coins"), int(stats.get("total_coins_earned", 0))
	]
	progress.add_theme_font_size_override("font_size", 21)
	stack.add_child(progress)
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
		var card := PanelContainer.new()
		list.add_child(card)
		var label := Label.new()
		label.text = "%s  ·  %s\n%s\n%s" % [
			"✦" if unlocked else "◇",
			GameApp.text(str(definition.get("name_key", honor_id))),
			GameApp.text(str(definition.get("description_key", ""))),
			GameApp.text("menu.unlocked") if unlocked else GameApp.text("menu.locked")
		]
		label.add_theme_font_size_override("font_size", 19)
		label.add_theme_color_override("font_color", Color("ffd166") if unlocked else Color("8693a6"))
		card.add_child(label)
	_add_back_button(stack)


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
	_stage_label.text = "%s  %02d" % [GameApp.text("common.stage"), int(GameApp.profile.get("highest_unlocked_stage", 1))]
	_coins_label.text = "◆  %d" % int(GameApp.profile.get("coins", 0))
	_xp_label.text = "%s  %d" % [GameApp.text("common.xp"), int(GameApp.profile.get("xp", 0))]


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
