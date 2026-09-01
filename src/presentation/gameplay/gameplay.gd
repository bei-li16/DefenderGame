extends Node2D

const GameSession = preload("res://src/application/game_session.gd")
const RunOrchestrator = preload("res://src/application/run_orchestrator.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")

var session: DefenderGameSession
var snapshot: Dictionary = {}
var effects: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []
var _wall_bar: ProgressBar
var _mana_bar: ProgressBar
var _wall_value_label: Label
var _mana_value_label: Label
var _stage_label: Label
var _enemy_label: Label
var _coin_label: Label
var _feedback_label: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _skill_buttons: Dictionary = {}
var _pause_overlay: Control
var _settings_overlay: Control
var _result_overlay: Control
var _tutorial_hint: Control
var _settled: bool = false
var _shake_strength: float = 0.0
var _feedback_timer: float = 0.0
var _elapsed_visual: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameApp.audio.play_music("battle", float(GameApp.settings.get("music_volume", 0.65)))
	_build_hud()
	session = GameSession.new()
	session.name = "GameSession"
	session.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(session)
	session.events_produced.connect(_on_events)
	session.snapshot_changed.connect(_on_snapshot)
	session.run_finished.connect(_on_run_finished)
	var orchestrator := RunOrchestrator.new()
	var prepared := orchestrator.prepare(GameApp.content.rules, GameApp.current_stage_id, GameApp.current_seed, GameApp.profile)
	if not bool(prepared.get("ok", false)):
		GameApp.return_to_menu()
		return
	var start_result := session.start(prepared["config"], prepared["stage_id"], prepared["seed"], prepared["profile_snapshot"])
	if not bool(start_result.get("ok", false)):
		GameApp.return_to_menu()
		return
	if int(snapshot.get("stage_number", 1)) == 1 and not bool(GameApp.profile.get("tutorial_complete", false)):
		_show_tutorial_hint()
	queue_redraw()


func _physics_process(_delta: float) -> void:
	if session == null or get_tree().paused or str(snapshot.get("status", "running")) != "running":
		return
	var mouse := get_global_mouse_position()
	session.queue_command({"type": "aim", "x_milli": int(mouse.x * 1000.0), "y_milli": int(mouse.y * 1000.0)})


func _process(delta: float) -> void:
	_elapsed_visual += delta
	for index in range(effects.size() - 1, -1, -1):
		effects[index]["age"] = float(effects[index].get("age", 0.0)) + delta
		if float(effects[index]["age"]) >= float(effects[index].get("duration", 0.5)):
			effects.remove_at(index)
	for index in range(floating_texts.size() - 1, -1, -1):
		floating_texts[index]["age"] = float(floating_texts[index].get("age", 0.0)) + delta
		floating_texts[index]["y"] = float(floating_texts[index]["y"]) - delta * 45.0
		if float(floating_texts[index]["age"]) >= 1.25:
			floating_texts.remove_at(index)
	_shake_strength = maxf(0.0, _shake_strength - delta * 32.0)
	if _feedback_timer > 0.0:
		_feedback_timer -= delta
		if _feedback_timer <= 0.0 and _feedback_label != null:
			_feedback_label.text = ""
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or _result_overlay != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_select_skill("fire_ball")
			KEY_2:
				_select_skill("glacial_spike")
			KEY_3:
				_select_skill("lightning_strike")
			KEY_ESCAPE:
				if not str(snapshot.get("selected_skill", "")).is_empty():
					session.queue_command({"type": "cancel_skill"})
				else:
					_toggle_pause()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			session.queue_command({"type": "cancel_skill"})
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var selected := str(snapshot.get("selected_skill", ""))
				if selected.is_empty():
					session.queue_command({"type": "fire_started"})
				else:
					var mouse := get_global_mouse_position()
					session.queue_command({"type": "cast_skill", "skill_id": selected, "x_milli": int(mouse.x * 1000.0), "y_milli": int(mouse.y * 1000.0)})
			else:
				session.queue_command({"type": "fire_stopped"})


func _on_snapshot(value: Dictionary) -> void:
	snapshot = value
	if _wall_bar == null:
		return
	_wall_bar.max_value = maxi(1, int(snapshot.get("wall_max_hp", 1)))
	_wall_bar.value = int(snapshot.get("wall_hp", 0))
	_wall_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.wall"), int(snapshot.get("wall_hp", 0)), int(snapshot.get("wall_max_hp", 0))]
	_wall_value_label.text = "%s  %d / %d" % [GameApp.text("hud.wall"), int(snapshot.get("wall_hp", 0)), int(snapshot.get("wall_max_hp", 0))]
	_mana_bar.max_value = maxi(1, int(snapshot.get("max_mana", 1)))
	_mana_bar.value = int(snapshot.get("mana", 0))
	_mana_bar.tooltip_text = "%s %d / %d" % [GameApp.text("hud.mana"), int(snapshot.get("mana", 0)), int(snapshot.get("max_mana", 0))]
	_mana_value_label.text = "%s  %d / %d" % [GameApp.text("hud.mana"), int(snapshot.get("mana", 0)), int(snapshot.get("max_mana", 0))]
	_stage_label.text = "STAGE  %02d" % int(snapshot.get("stage_number", 0))
	_enemy_label.text = "%s  %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("kills", 0)), int(snapshot.get("spawn_total", 0))]
	_coin_label.text = "◆  %d" % int(snapshot.get("coins_earned", 0))
	_update_skill_buttons()
	_update_boss_bar()


func _on_events(events_value: Array) -> void:
	var sfx_volume := float(GameApp.settings.get("sfx_volume", 0.85))
	for event_value in events_value:
		var event: Dictionary = event_value
		GameApp.audio.play_event(event, sfx_volume)
		match str(event.get("type", "")):
			"skill_cast":
				var position := Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0)
				effects.append({"kind": str(event.get("skill_id", "")), "position": position, "age": 0.0, "duration": 0.72})
				if bool(GameApp.settings.get("screen_shake", true)):
					_shake_strength = 10.0
			"hit":
				var hit_position := _entity_position(int(event.get("entity_id", 0)))
				effects.append({"kind": "hit", "position": hit_position, "age": 0.0, "duration": 0.22})
				if bool(event.get("fatal", false)):
					_add_float(GameApp.text("feedback.fatal"), hit_position, Color("ffd166"), 30)
				if bool(event.get("power", false)):
					_add_float(GameApp.text("feedback.power"), hit_position + Vector2(0, 30), Color("ff9b54"), 24)
			"damage":
				_add_float("-%d" % int(event.get("amount", 0)), _entity_position(int(event.get("entity_id", 0))), _damage_color(str(event.get("source", ""))), 21)
			"death":
				effects.append({"kind": "death", "position": _entity_position(int(event.get("entity_id", 0))), "age": 0.0, "duration": 0.55})
			"wall_damage":
				_shake_strength = 13.0 if bool(GameApp.settings.get("screen_shake", true)) else 0.0
				_feedback("⚠  -%d WALL" % int(event.get("amount", 0)), Color("ff7b6b"))
			"skill_rejected":
				var key := "feedback.no_mana" if str(event.get("reason", "")) == "no_mana" else "feedback.cooldown"
				_feedback("✕  " + GameApp.text(key), Color("ff9b7b"))
			"boss_warning":
				_feedback("⚠  " + GameApp.text("feedback.boss") + "  ⚠", Color("ff587d"), 3.5)
			"boss_special":
				_shake_strength = 18.0 if bool(GameApp.settings.get("screen_shake", true)) else 0.0
				effects.append({"kind": "boss_wave", "position": Vector2(780, 540), "age": 0.0, "duration": 0.8})


func _on_run_finished(result: Dictionary) -> void:
	if _settled:
		return
	_settled = true
	GameApp.settle_run(result)
	_show_result(result)


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Hud"
	add_child(canvas)
	var root := Control.new()
	root.theme = UiTheme.create()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(root)

	var top_margin := MarginContainer.new()
	top_margin.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_margin.add_theme_constant_override("margin_left", 24)
	top_margin.add_theme_constant_override("margin_right", 24)
	top_margin.add_theme_constant_override("margin_top", 18)
	root.add_child(top_margin)
	var top_panel := PanelContainer.new()
	top_panel.custom_minimum_size.y = 82
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_margin.add_child(top_panel)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 22)
	top_panel.add_child(top_row)
	_stage_label = _hud_label("STAGE", 28, Color("ffd166"), 170)
	top_row.add_child(_stage_label)
	var wall_stack := VBoxContainer.new()
	wall_stack.custom_minimum_size.x = 420
	top_row.add_child(wall_stack)
	_wall_value_label = Label.new()
	_wall_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wall_value_label.add_theme_font_size_override("font_size", 16)
	wall_stack.add_child(_wall_value_label)
	_wall_bar = ProgressBar.new()
	_wall_bar.custom_minimum_size = Vector2(420, 24)
	_wall_bar.show_percentage = false
	wall_stack.add_child(_wall_bar)
	var mana_stack := VBoxContainer.new()
	mana_stack.custom_minimum_size.x = 300
	top_row.add_child(mana_stack)
	_mana_value_label = Label.new()
	_mana_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_value_label.add_theme_font_size_override("font_size", 16)
	mana_stack.add_child(_mana_value_label)
	_mana_bar = ProgressBar.new()
	_mana_bar.custom_minimum_size = Vector2(300, 24)
	_mana_bar.show_percentage = false
	mana_stack.add_child(_mana_bar)
	_enemy_label = _hud_label("", 21, Color.WHITE, 250)
	top_row.add_child(_enemy_label)
	_coin_label = _hud_label("", 24, Color("ffd166"), 150)
	top_row.add_child(_coin_label)
	var pause := Button.new()
	pause.text = "Ⅱ"
	pause.custom_minimum_size = Vector2(64, 54)
	pause.mouse_filter = Control.MOUSE_FILTER_STOP
	pause.pressed.connect(_toggle_pause)
	top_row.add_child(pause)

	_feedback_label = Label.new()
	_feedback_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_feedback_label.position = Vector2(-300, 120)
	_feedback_label.size = Vector2(600, 60)
	_feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_feedback_label.add_theme_font_size_override("font_size", 34)
	_feedback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feedback_label)

	_boss_panel = PanelContainer.new()
	_boss_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_panel.position = Vector2(-320, 118)
	_boss_panel.size = Vector2(640, 80)
	_boss_panel.visible = false
	root.add_child(_boss_panel)
	var boss_stack := VBoxContainer.new()
	_boss_panel.add_child(boss_stack)
	_boss_name = Label.new()
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_color_override("font_color", Color("ff7697"))
	boss_stack.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.show_percentage = false
	boss_stack.add_child(_boss_bar)

	var skills_margin := MarginContainer.new()
	skills_margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	skills_margin.position = Vector2(-640, -160)
	skills_margin.size = Vector2(610, 130)
	root.add_child(skills_margin)
	var skills := HBoxContainer.new()
	skills.add_theme_constant_override("separation", 18)
	skills_margin.add_child(skills)
	for definition in [
		["fire_ball", "①  🔥\n" + GameApp.text("skill.fire")],
		["glacial_spike", "②  ❄\n" + GameApp.text("skill.ice")],
		["lightning_strike", "③  ⚡\n" + GameApp.text("skill.lightning")]
	]:
		var button := Button.new()
		button.text = definition[1]
		button.custom_minimum_size = Vector2(185, 112)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.pressed.connect(func() -> void: _select_skill(str(definition[0])))
		skills.add_child(button)
		_skill_buttons[str(definition[0])] = button


func _show_tutorial_hint() -> void:
	var canvas := get_node("Hud") as CanvasLayer
	_tutorial_hint = PanelContainer.new()
	_tutorial_hint.theme = UiTheme.create()
	_tutorial_hint.set_anchors_preset(Control.PRESET_CENTER)
	_tutorial_hint.position = Vector2(-360, -110)
	_tutorial_hint.size = Vector2(720, 220)
	_tutorial_hint.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(_tutorial_hint)
	var stack := VBoxContainer.new()
	_tutorial_hint.add_child(stack)
	var title := Label.new()
	title.text = GameApp.text("tutorial.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color("ffd166"))
	stack.add_child(title)
	var body := Label.new()
	body.text = GameApp.text("tutorial.body")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(body)
	var close := Button.new()
	close.text = GameApp.text("hud.resume")
	close.pressed.connect(func() -> void:
		get_tree().paused = false
		_tutorial_hint.queue_free()
		_tutorial_hint = null
		GameApp.profile["tutorial_complete"] = true
		GameApp.save_service.save_profile(GameApp.profile, int(GameApp.content.rules["config_version"]))
	)
	stack.add_child(close)
	get_tree().paused = true


func _toggle_pause() -> void:
	if _result_overlay != null:
		return
	if get_tree().paused:
		_resume_game()
	else:
		_show_pause()


func _show_pause() -> void:
	if _pause_overlay != null:
		return
	_pause_overlay = _overlay_panel(Vector2(520, 560))
	var stack := _pause_overlay.get_meta("stack") as VBoxContainer
	var title := _overlay_title(GameApp.text("hud.pause"))
	stack.add_child(title)
	var resume := _overlay_button(GameApp.text("hud.resume"))
	resume.pressed.connect(_resume_game)
	stack.add_child(resume)
	var restart := _overlay_button(GameApp.text("hud.restart"))
	restart.pressed.connect(func() -> void:
		get_tree().paused = false
		GameApp.start_stage(GameApp.current_stage_id, GameApp.current_seed)
	)
	stack.add_child(restart)
	var settings_button := _overlay_button(GameApp.text("menu.settings"))
	settings_button.pressed.connect(_show_quick_settings)
	stack.add_child(settings_button)
	var menu := _overlay_button(GameApp.text("hud.main_menu"))
	menu.pressed.connect(_confirm_return_to_menu)
	stack.add_child(menu)
	get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	if _settings_overlay != null:
		_settings_overlay.queue_free()
		_settings_overlay = null
	if _pause_overlay != null:
		_pause_overlay.queue_free()
		_pause_overlay = null


func _show_quick_settings() -> void:
	if _settings_overlay != null:
		return
	_settings_overlay = _overlay_panel(Vector2(560, 430))
	var stack := _settings_overlay.get_meta("stack") as VBoxContainer
	stack.add_child(_overlay_title(GameApp.text("settings.title")))
	for setting in [["settings.master", "master_volume"], ["settings.sfx", "sfx_volume"]]:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = GameApp.text(setting[0])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var slider := HSlider.new()
		slider.custom_minimum_size.x = 240
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = float(GameApp.settings.get(setting[1], 0.8))
		slider.value_changed.connect(func(value: float) -> void: GameApp.update_setting(str(setting[1]), value))
		row.add_child(slider)
		stack.add_child(row)
	var shake := CheckButton.new()
	shake.text = GameApp.text("settings.shake")
	shake.button_pressed = bool(GameApp.settings.get("screen_shake", true))
	shake.toggled.connect(func(value: bool) -> void: GameApp.update_setting("screen_shake", value))
	stack.add_child(shake)
	var close := _overlay_button(GameApp.text("menu.back"))
	close.pressed.connect(func() -> void:
		_settings_overlay.queue_free()
		_settings_overlay = null
	)
	stack.add_child(close)


func _confirm_return_to_menu() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = GameApp.text("hud.main_menu")
	dialog.dialog_text = "本局进度将丢失，确定返回？" if str(GameApp.settings.get("language", "zh_CN")) == "zh_CN" else "This run will be abandoned. Return to menu?"
	dialog.ok_button_text = GameApp.text("hud.main_menu")
	dialog.cancel_button_text = GameApp.text("menu.back")
	dialog.confirmed.connect(func() -> void: GameApp.return_to_menu())
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 220))


func _show_result(result: Dictionary) -> void:
	_result_overlay = _overlay_panel(Vector2(720, 650))
	var stack := _result_overlay.get_meta("stack") as VBoxContainer
	var victory := str(result.get("status", "")) == "victory"
	var title := _overlay_title(GameApp.text("result.victory") if victory else GameApp.text("result.defeat"))
	title.add_theme_color_override("font_color", Color("ffd166") if victory else Color("ff7697"))
	stack.add_child(title)
	var summary := Label.new()
	summary.text = "STAGE %02d\n\n%s        %d\n%s        %d%%\n%s     +%d\n%s       +%d" % [
		int(result.get("stage_number", 0)),
		GameApp.text("result.kills"), int(result.get("kills", 0)),
		GameApp.text("result.wall"), int(result.get("wall_percent", 0)),
		GameApp.text("result.coins"), int(result.get("coins", 0)),
		GameApp.text("result.xp"), int(result.get("xp", 0))
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 26)
	stack.add_child(summary)
	if victory and int(result.get("stage_number", 0)) < 10:
		var unlocked := Label.new()
		unlocked.text = "✦  STAGE %02d UNLOCKED  ✦" % (int(result.get("stage_number", 0)) + 1)
		unlocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlocked.add_theme_color_override("font_color", Color("8ce99a"))
		stack.add_child(unlocked)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(actions)
	var retry := _overlay_button(GameApp.text("hud.restart"))
	retry.custom_minimum_size.x = 260
	retry.pressed.connect(func() -> void: GameApp.start_stage(GameApp.current_stage_id))
	actions.add_child(retry)
	var next := _overlay_button(GameApp.text("result.next"))
	next.custom_minimum_size.x = 260
	next.pressed.connect(func() -> void: GameApp.return_to_menu())
	actions.add_child(next)


func _overlay_panel(panel_size: Vector2) -> Control:
	var canvas := get_node("Hud") as CanvasLayer
	var overlay := ColorRect.new()
	overlay.color = Color(0.01, 0.02, 0.04, 0.76)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	canvas.add_child(overlay)
	var panel := PanelContainer.new()
	panel.theme = UiTheme.create()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 28)
	panel.add_child(margin)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 18)
	margin.add_child(stack)
	overlay.set_meta("stack", stack)
	return overlay


func _overlay_title(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 42)
	label.add_theme_color_override("font_color", Color("ffd166"))
	return label


func _overlay_button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size = Vector2(390, 62)
	return button


func _hud_label(value: String, font_size: int, color: Color, width: float) -> Label:
	var label := Label.new()
	label.text = value
	label.custom_minimum_size.x = width
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _select_skill(skill_id: String) -> void:
	if get_tree().paused or session == null:
		return
	session.queue_command({"type": "fire_stopped"})
	session.queue_command({"type": "select_skill", "skill_id": skill_id})


func _update_skill_buttons() -> void:
	var selected := str(snapshot.get("selected_skill", ""))
	var cooldowns: Dictionary = snapshot.get("skill_cooldowns", {})
	for skill_id in _skill_buttons.keys():
		var button: Button = _skill_buttons[skill_id]
		var cooldown := int(cooldowns.get(skill_id, 0))
		button.modulate = Color.WHITE if selected == skill_id else Color(0.78, 0.82, 0.9, 1.0)
		button.disabled = cooldown > 0
		if cooldown > 0:
			button.tooltip_text = "%.1fs" % (float(cooldown) / 30.0)
		else:
			button.tooltip_text = GameApp.text("skill.fire" if skill_id == "fire_ball" else ("skill.ice" if skill_id == "glacial_spike" else "skill.lightning"))


func _update_boss_bar() -> void:
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


func _feedback(value: String, color: Color, duration: float = 1.7) -> void:
	_feedback_label.text = value
	_feedback_label.add_theme_color_override("font_color", color)
	_feedback_timer = duration


func _add_float(value: String, position: Vector2, color: Color, font_size: int) -> void:
	floating_texts.append({"text": value, "x": position.x, "y": position.y, "color": color, "font_size": font_size, "age": 0.0})


func _entity_position(entity_id: int) -> Vector2:
	for enemy in snapshot.get("enemies", []):
		if int(enemy.get("entity_id", -1)) == entity_id:
			return Vector2(float(enemy.get("x_milli", 0)) / 1000.0, float(enemy.get("y_milli", 0)) / 1000.0)
	return Vector2(980, 520)


func _draw() -> void:
	var offset := Vector2.ZERO
	if _shake_strength > 0.0:
		offset = Vector2(sin(_elapsed_visual * 71.0), cos(_elapsed_visual * 83.0)) * _shake_strength
	draw_set_transform(offset)
	_draw_background()
	_draw_castle()
	for enemy in snapshot.get("enemies", []):
		_draw_enemy(enemy)
	for projectile in snapshot.get("projectiles", []):
		_draw_projectile(projectile)
	for effect in effects:
		_draw_effect(effect)
	for text_data in floating_texts:
		var alpha := clampf(1.0 - float(text_data["age"]) / 1.25, 0.0, 1.0)
		var color: Color = text_data["color"]
		color.a = alpha
		draw_string(ThemeDB.fallback_font, Vector2(float(text_data["x"]), float(text_data["y"])), str(text_data["text"]), HORIZONTAL_ALIGNMENT_CENTER, 180, int(text_data["font_size"]), color)
	_draw_crosshair()
	draw_set_transform(Vector2.ZERO)


func _draw_background() -> void:
	for band in range(12):
		var ratio := float(band) / 11.0
		draw_rect(Rect2(0, ratio * 720.0, 1920, 68), Color("173452").lerp(Color("31516a"), ratio))
	draw_circle(Vector2(1530, 220), 92, Color(1.0, 0.83, 0.52, 0.14))
	var far_mountains := PackedVector2Array([Vector2(0, 560), Vector2(260, 320), Vector2(480, 560), Vector2(760, 280), Vector2(1020, 560), Vector2(1330, 340), Vector2(1600, 560), Vector2(1920, 300), Vector2(1920, 760), Vector2(0, 760)])
	draw_colored_polygon(far_mountains, Color("1a2b3a"))
	var near_mountains := PackedVector2Array([Vector2(0, 650), Vector2(330, 450), Vector2(630, 650), Vector2(950, 420), Vector2(1260, 660), Vector2(1590, 455), Vector2(1920, 640), Vector2(1920, 820), Vector2(0, 820)])
	draw_colored_polygon(near_mountains, Color("233342"))
	draw_rect(Rect2(0, 660, 1920, 420), Color("49392d"))
	for row in range(7):
		var y := 700.0 + float(row) * 58.0
		draw_line(Vector2(0, y), Vector2(1920, y + 24), Color(0.66, 0.53, 0.38, 0.12), 2)
	for stone in range(34):
		var x := 390.0 + fmod(float(stone * 137), 1500.0)
		var y := 710.0 + fmod(float(stone * 83), 330.0)
		draw_circle(Vector2(x, y), 4.0 + float(stone % 5), Color(0.72, 0.58, 0.42, 0.18))


func _draw_castle() -> void:
	draw_rect(Rect2(0, 170, 255, 720), Color("44576b"))
	for row in range(9):
		for column in range(4):
			var rect := Rect2(column * 65.0 - float(row % 2) * 20.0, 205.0 + row * 70.0, 58, 58)
			draw_rect(rect, Color("536a7f"), true)
			draw_rect(rect, Color("263a4d"), false, 2)
	draw_rect(Rect2(245, 205, 75, 655), Color("71849a"))
	for y in range(245, 840, 90):
		draw_rect(Rect2(265, y, 24, 38), Color("91c9e8"))
	for tower_y in [180.0, 765.0]:
		draw_circle(Vector2(170, tower_y), 82, Color("596f85"))
		draw_circle(Vector2(170, tower_y), 60, Color("263a50"))
		draw_circle(Vector2(170, tower_y), 28, Color("81d4fa"))
	var origin := Vector2(245, 555)
	var mouse := get_global_mouse_position()
	var direction := (mouse - origin).normalized()
	draw_line(origin, origin + direction * 132.0, Color("f0c36a"), 13)
	draw_arc(origin, 68, -1.15, 1.15, 22, Color("d8a44c"), 8)
	draw_circle(origin, 24, Color("243447"))


func _draw_enemy(enemy: Dictionary) -> void:
	var position := Vector2(float(enemy["x_milli"]) / 1000.0, float(enemy["y_milli"]) / 1000.0)
	var radius := float(enemy["collision_radius_milli"]) / 1000.0
	var enemy_id := str(enemy.get("enemy_id", ""))
	match enemy_id:
		"fast_raider":
			draw_colored_polygon(PackedVector2Array([position + Vector2(-radius, 10), position + Vector2(-radius * 0.35, -radius * 0.75), position + Vector2(radius, -5), position + Vector2(radius * 0.25, radius * 0.65)]), Color("f0a35e"))
			draw_line(position + Vector2(-radius * 0.6, 18), position + Vector2(-radius, radius), Color("3d2630"), 7)
			draw_line(position + Vector2(radius * 0.5, 16), position + Vector2(radius, radius), Color("3d2630"), 7)
		"ranged_hexer":
			draw_colored_polygon(PackedVector2Array([position + Vector2(0, -radius), position + Vector2(radius * 0.82, radius), position + Vector2(-radius * 0.82, radius)]), Color("9d6bd1"))
			draw_circle(position + Vector2(0, -radius * 0.35), radius * 0.36, Color("26304f"))
			draw_line(position + Vector2(radius * 0.65, -radius * 0.4), position + Vector2(radius * 1.18, radius * 0.8), Color("f0d890"), 6)
		"ember_warlord":
			draw_circle(position, radius, Color("a82e52"))
			draw_colored_polygon(PackedVector2Array([position + Vector2(-radius * 0.8, -radius * 0.5), position + Vector2(-radius * 0.45, -radius * 1.2), position + Vector2(-radius * 0.15, -radius * 0.55)]), Color("f07c45"))
			draw_colored_polygon(PackedVector2Array([position + Vector2(radius * 0.8, -radius * 0.5), position + Vector2(radius * 0.45, -radius * 1.2), position + Vector2(radius * 0.15, -radius * 0.55)]), Color("f07c45"))
			draw_circle(position, radius * 0.48, Color("391c32"))
		_:
			draw_circle(position, radius, Color("d9534f"))
			draw_colored_polygon(PackedVector2Array([position + Vector2(-radius * 0.8, -radius * 0.5), position + Vector2(-radius * 0.25, -radius * 1.0), position + Vector2(-radius * 0.1, -radius * 0.45)]), Color("efb261"))
			draw_colored_polygon(PackedVector2Array([position + Vector2(radius * 0.8, -radius * 0.5), position + Vector2(radius * 0.25, -radius * 1.0), position + Vector2(radius * 0.1, -radius * 0.45)]), Color("efb261"))
	if int(enemy.get("stun_ticks", 0)) > 0:
		draw_arc(position, radius + 9, 0, TAU, 16, Color("e5d5ff"), 4)
	if int(enemy.get("burn_ticks", 0)) > 0:
		draw_colored_polygon(PackedVector2Array([position + Vector2(-10, -radius), position + Vector2(0, -radius - 28), position + Vector2(12, -radius)]), Color("ff8b3d"))
	var bar_width := radius * 2.0
	var hp_ratio := float(enemy["hp"]) / maxf(1.0, float(enemy["max_hp"]))
	draw_rect(Rect2(position.x - radius, position.y - radius - 18, bar_width, 8), Color("301824"))
	draw_rect(Rect2(position.x - radius, position.y - radius - 18, bar_width * hp_ratio, 8), Color("78d887"))


func _draw_projectile(projectile: Dictionary) -> void:
	var position := Vector2(float(projectile["x_milli"]) / 1000.0, float(projectile["y_milli"]) / 1000.0)
	var velocity := Vector2(float(projectile["vx_milli"]), float(projectile["vy_milli"])).normalized()
	var color := Color("fff0a8") if not bool(projectile.get("fatal", false)) else Color("ffcb47")
	draw_line(position - velocity * 30.0, position + velocity * 8.0, color, 5.0)
	draw_colored_polygon(PackedVector2Array([position + velocity * 15.0, position - velocity.rotated(0.7) * 8.0, position - velocity.rotated(-0.7) * 8.0]), color)


func _draw_effect(effect: Dictionary) -> void:
	var kind := str(effect.get("kind", ""))
	var position: Vector2 = effect.get("position", Vector2.ZERO)
	var progress := clampf(float(effect.get("age", 0.0)) / maxf(0.01, float(effect.get("duration", 1.0))), 0.0, 1.0)
	match kind:
		"fire_ball":
			draw_circle(position, 40.0 + progress * 165.0, Color(1.0, 0.25, 0.04, (1.0 - progress) * 0.34))
			draw_arc(position, 55.0 + progress * 135.0, 0, TAU, 48, Color(1.0, 0.78, 0.18, 1.0 - progress), 12)
			for ray in range(10):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / 10.0)
				draw_line(position + direction * 28.0, position + direction * (70.0 + progress * 130.0), Color(1.0, 0.48, 0.08, 1.0 - progress), 8)
		"glacial_spike":
			for ray in range(12):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / 12.0)
				var side := direction.rotated(0.32)
				draw_colored_polygon(PackedVector2Array([position + side * 15.0, position + direction * (70.0 + 150.0 * (1.0 - progress)), position - side * 15.0]), Color(0.42, 0.88, 1.0, 0.85 * (1.0 - progress)))
		"lightning_strike":
			for bolt in range(5):
				var points := PackedVector2Array()
				for segment in range(8):
					var y := position.y - 460.0 + float(segment) * 66.0
					var x := position.x + sin(float(segment * 13 + bolt * 7)) * (34.0 + bolt * 5.0)
					points.append(Vector2(x, y))
				draw_polyline(points, Color(0.84, 0.72, 1.0, 1.0 - progress), 7.0 - float(bolt))
		"hit":
			for ray in range(6):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / 6.0)
				draw_line(position, position + direction * (18.0 + 34.0 * (1.0 - progress)), Color(1.0, 0.93, 0.55, 1.0 - progress), 4)
		"death":
			draw_arc(position, 24.0 + progress * 70.0, 0, TAU, 24, Color(1.0, 0.43, 0.22, 1.0 - progress), 8)
		"boss_wave":
			draw_arc(position, 80.0 + progress * 620.0, -1.2, 1.2, 48, Color(0.9, 0.16, 0.36, 1.0 - progress), 14)


func _draw_crosshair() -> void:
	var mouse := get_global_mouse_position()
	var selected := str(snapshot.get("selected_skill", ""))
	var color := Color("f4ead5")
	var radius := 22.0
	if selected == "fire_ball":
		color = Color("ff7b3d")
		radius = 48.0
	elif selected == "glacial_spike":
		color = Color("69d6ff")
		radius = 52.0
	elif selected == "lightning_strike":
		color = Color("d9b8ff")
		radius = 58.0
	draw_arc(mouse, radius, 0, TAU, 28, color, 3)
	draw_line(mouse + Vector2(-radius - 10, 0), mouse + Vector2(-radius + 8, 0), color, 3)
	draw_line(mouse + Vector2(radius - 8, 0), mouse + Vector2(radius + 10, 0), color, 3)
	draw_line(mouse + Vector2(0, -radius - 10), mouse + Vector2(0, -radius + 8), color, 3)
	draw_line(mouse + Vector2(0, radius - 8), mouse + Vector2(0, radius + 10), color, 3)
	if bool(GameApp.settings.get("aim_assist", true)) and selected.is_empty():
		var target := _nearest_enemy(mouse, 130.0)
		if target != Vector2.INF:
			draw_line(mouse, target, Color(1.0, 0.84, 0.36, 0.28), 2)


func _nearest_enemy(position: Vector2, maximum_distance: float) -> Vector2:
	var best := Vector2.INF
	var best_distance := maximum_distance
	for enemy in snapshot.get("enemies", []):
		var enemy_position := Vector2(float(enemy["x_milli"]) / 1000.0, float(enemy["y_milli"]) / 1000.0)
		var distance := position.distance_to(enemy_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy_position
	return best


static func _damage_color(source: String) -> Color:
	match source:
		"fire", "burn": return Color("ff8a4c")
		"ice": return Color("6edcff")
		"lightning": return Color("d7b2ff")
		_: return Color("fff0a8")
