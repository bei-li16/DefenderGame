extends Control

const UiTheme = preload("res://src/presentation/ui_theme.gd")
const MenuBackdrop = preload("res://src/presentation/menus/menu_backdrop.gd")

var _content_panel: PanelContainer
var _content_margin: MarginContainer
var _coins_label: Label
var _xp_label: Label
var _stage_label: Label


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
	subtitle.text = "HOLD THE LAST WALL" if str(GameApp.settings.get("language", "zh_CN")) == "en_US" else "守住最后一道城墙"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 24)
	subtitle.add_theme_color_override("font_color", Color("9bc5e6"))
	identity_stack.add_child(subtitle)
	var rule := HSeparator.new()
	rule.custom_minimum_size.y = 16
	identity_stack.add_child(rule)
	var hint := Label.new()
	hint.text = "Mouse  •  1 / 2 / 3  •  Esc"
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
	var continue_button := _button(GameApp.text("menu.continue") + "  ·  Stage %02d" % current_stage, 76)
	continue_button.pressed.connect(func() -> void: GameApp.start_stage("stage_%03d" % current_stage))
	stack.add_child(continue_button)
	for entry in [
		["menu.stage", Callable(self, "_show_stage_select")],
		["menu.upgrades", Callable(self, "_show_upgrades")],
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
		var label := "Stage %02d" % number
		if bool(stage.get("boss", false)):
			label += "  ⚠ BOSS"
		var best: Dictionary = best_results.get(stage_id, {})
		if not best.is_empty():
			label += "\n★ %d%%  ·  %d K" % [int(best.get("wall_percent", 0)), int(best.get("kills", 0))]
		elif number > unlocked:
			label += "\n🔒 " + GameApp.text("menu.locked")
		else:
			var reward: Dictionary = stage.get("clear_reward", {})
			label += "\n◆ %d   XP %d" % [int(reward.get("coins", 0)), int(reward.get("xp", 0))]
		var stage_button := _button(label, 96)
		stage_button.disabled = number > unlocked
		stage_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stage_button.pressed.connect(func() -> void: GameApp.start_stage(stage_id))
		grid.add_child(stage_button)
	_add_back_button(stack)


func _show_upgrades() -> void:
	var stack := _new_content_stack(GameApp.text("menu.upgrades"))
	var wallet := Label.new()
	wallet.text = "◆  %d %s" % [int(GameApp.profile.get("coins", 0)), GameApp.text("menu.coins")]
	wallet.add_theme_font_size_override("font_size", 26)
	wallet.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(wallet)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	var upgrades: Dictionary = GameApp.profile.get("upgrades", {})
	for definition in GameApp.content.rules.get("upgrades", []):
		var upgrade_id := str(definition.get("id", ""))
		var level := int(upgrades.get(upgrade_id, 0))
		var max_level := int(definition.get("max_level", 0))
		var price := GameApp.upgrade_service.price_for_level(definition, level)
		var card := PanelContainer.new()
		list.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		card.add_child(row)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var name := Label.new()
		name.text = "%s   Lv.%d / %d" % [GameApp.text(str(definition.get("name_key", upgrade_id))), level, max_level]
		name.add_theme_font_size_override("font_size", 25)
		name.add_theme_color_override("font_color", _upgrade_color(upgrade_id))
		info.add_child(name)
		var description := Label.new()
		description.text = GameApp.text(str(definition.get("description_key", "")))
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.add_theme_font_size_override("font_size", 17)
		info.add_child(description)
		var purchase := _button("MAX" if level >= max_level else "◆ %d\nUPGRADE" % price, 66)
		purchase.custom_minimum_size.x = 146
		purchase.disabled = level >= max_level or int(GameApp.profile.get("coins", 0)) < price
		purchase.pressed.connect(func() -> void:
			GameApp.purchase_upgrade(upgrade_id)
			_refresh_header()
			_show_upgrades()
		)
		row.add_child(purchase)
	_add_back_button(stack)


func _show_settings() -> void:
	var stack := _new_content_stack(GameApp.text("settings.title"))
	_add_slider_row(stack, "settings.master", "master_volume")
	_add_slider_row(stack, "settings.music", "music_volume")
	_add_slider_row(stack, "settings.sfx", "sfx_volume")
	var language_row := _setting_row(GameApp.text("settings.language"))
	var language := OptionButton.new()
	language.add_item("简体中文")
	language.add_item("English")
	language.selected = 1 if str(GameApp.settings.get("language", "zh_CN")) == "en_US" else 0
	language.item_selected.connect(func(index: int) -> void:
		GameApp.update_setting("language", "en_US" if index == 1 else "zh_CN")
		_refresh_after_language_change()
	)
	language_row.add_child(language)
	stack.add_child(language_row)
	var resolution_row := _setting_row("Resolution" if str(GameApp.settings.get("language", "zh_CN")) == "en_US" else "分辨率")
	var resolution := OptionButton.new()
	var resolutions := ["1280x720", "1366x768", "1920x1080", "2560x1440"]
	for value in resolutions:
		resolution.add_item(value)
	resolution.selected = maxi(0, resolutions.find(str(GameApp.settings.get("resolution", "1920x1080"))))
	resolution.item_selected.connect(func(index: int) -> void: GameApp.update_setting("resolution", resolutions[index]))
	resolution_row.add_child(resolution)
	stack.add_child(resolution_row)
	_add_toggle_row(stack, "settings.fullscreen", "fullscreen")
	_add_toggle_row(stack, "settings.borderless", "borderless")
	_add_toggle_row(stack, "settings.aim_assist", "aim_assist")
	_add_toggle_row(stack, "settings.shake", "screen_shake")
	_add_range_slider_row(stack, "settings.ui_scale", "ui_scale", 0.85, 1.25, 0.05)
	var quality_row := _setting_row(GameApp.text("settings.quality"))
	var quality := OptionButton.new()
	var qualities := ["low", "medium", "high"]
	for value in qualities:
		quality.add_item(value.capitalize())
	quality.selected = maxi(0, qualities.find(str(GameApp.settings.get("quality", "medium"))))
	quality.item_selected.connect(func(index: int) -> void: GameApp.update_setting("quality", qualities[index]))
	quality_row.add_child(quality)
	stack.add_child(quality_row)
	var note := Label.new()
	note.text = "设置立即生效并保存。" if str(GameApp.settings.get("language", "zh_CN")) == "zh_CN" else "Changes apply and save immediately."
	note.add_theme_font_size_override("font_size", 16)
	note.add_theme_color_override("font_color", Color("9fb2c8"))
	stack.add_child(note)
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
	var training := _button(GameApp.text("menu.start") + " · Stage 01", 68)
	training.pressed.connect(func() -> void:
		GameApp.profile["tutorial_complete"] = true
		GameApp.save_service.save_profile(GameApp.profile, int(GameApp.content.rules["config_version"]))
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
	slider.value_changed.connect(func(value: float) -> void: GameApp.update_setting(setting_key, value))
	row.add_child(slider)
	stack.add_child(row)


func _add_toggle_row(stack: VBoxContainer, label_key: String, setting_key: String) -> void:
	var row := _setting_row(GameApp.text(label_key))
	var toggle := CheckButton.new()
	toggle.button_pressed = bool(GameApp.settings.get(setting_key, true))
	toggle.toggled.connect(func(value: bool) -> void: GameApp.update_setting(setting_key, value))
	row.add_child(toggle)
	stack.add_child(row)


func _refresh_header() -> void:
	if _stage_label == null:
		return
	_stage_label.text = "STAGE  %02d" % int(GameApp.profile.get("highest_unlocked_stage", 1))
	_coins_label.text = "◆  %d" % int(GameApp.profile.get("coins", 0))
	_xp_label.text = "XP  %d" % int(GameApp.profile.get("xp", 0))


func _refresh_after_language_change() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_layout()
	_show_settings()


static func _upgrade_color(upgrade_id: String) -> Color:
	if upgrade_id.contains("fire") or upgrade_id == "strength":
		return Color("ff9b54")
	if upgrade_id.contains("ice") or upgrade_id == "agility":
		return Color("78dce8")
	return Color("d7aefb")
