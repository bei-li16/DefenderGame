extends Node

const UiTheme = preload("res://src/presentation/ui_theme.gd")

var _message: Label
var _retry: Button


func _ready() -> void:
	GameApp.initialization_finished.connect(_on_initialization_finished)
	call_deferred("_continue_startup")


func _continue_startup() -> void:
	if GameApp.initialized_ok:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	else:
		_build_recovery_ui()


func _build_recovery_ui() -> void:
	for child in get_children():
		child.queue_free()
	var background := ColorRect.new()
	background.color = Color("08111f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := PanelContainer.new()
	panel.theme = UiTheme.create()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-360, -230)
	panel.size = Vector2(720, 460)
	background.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)
	var title := Label.new()
	title.text = _safe_text("recovery.title", "启动恢复 / Startup Recovery")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("ff8d7a"))
	stack.add_child(title)
	_message = Label.new()
	_message.text = _error_summary(GameApp.initialization_error)
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_message)
	_retry = Button.new()
	_retry.text = _safe_text("recovery.retry", "重试 / Retry")
	_retry.custom_minimum_size.y = 58
	_retry.pressed.connect(_retry_initialization)
	stack.add_child(_retry)
	var new_profile := Button.new()
	new_profile.text = _safe_text("recovery.new_profile", "保留诊断副本并开始新档 / Start New Profile")
	new_profile.custom_minimum_size.y = 58
	new_profile.disabled = str(GameApp.initialization_error.get("error_code", "")).contains("content") or str(GameApp.initialization_error.get("error_code", "")) in ["file_missing", "file_open_failed", "json_parse_failed", "json_root_not_object"]
	new_profile.pressed.connect(_start_new_profile)
	stack.add_child(new_profile)
	var exit_button := Button.new()
	exit_button.text = _safe_text("recovery.exit", "退出 / Exit")
	exit_button.custom_minimum_size.y = 54
	exit_button.pressed.connect(func() -> void: get_tree().quit())
	stack.add_child(exit_button)


func _retry_initialization() -> void:
	_retry.disabled = true
	_message.text = _safe_text("recovery.retrying", "正在重试… / Retrying…")
	GameApp.initialize()
	if not GameApp.initialized_ok:
		_retry.disabled = false
		_message.text = _error_summary(GameApp.initialization_error)


func _start_new_profile() -> void:
	var result := GameApp.start_new_profile()
	if not bool(result.get("ok", false)):
		_message.text = _error_summary(result)


func _on_initialization_finished(ok: bool, _error: Dictionary) -> void:
	if ok:
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _error_summary(error: Dictionary) -> String:
	var format := _safe_text("recovery.body", "无法读取有效配置或存档。原文件已保留。\nUnable to load valid content or save data.\n\nCode: %s\nField: %s")
	return format % [error.get("error_code", "unknown"), error.get("field_path", "unknown")]


func _safe_text(key: String, fallback: String) -> String:
	if not GameApp.content.localization.is_empty():
		return GameApp.text(key)
	return fallback
