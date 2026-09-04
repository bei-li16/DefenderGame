extends Node2D

const GameSession = preload("res://src/application/game_session.gd")
const RunOrchestrator = preload("res://src/application/run_orchestrator.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const SkillButton = preload("res://src/presentation/gameplay/skill_button.gd")

var session: DefenderGameSession
var snapshot: Dictionary = {}
var effects: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []
var _wall_bar: ProgressBar
var _mana_bar: ProgressBar
var _progress_bar: ProgressBar
var _wall_value_label: Label
var _mana_value_label: Label
var _stage_label: Label
var _enemy_label: Label
var _coin_label: Label
var _weapon_label: Label
var _defense_label: Label
var _feedback_label: Label
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _skill_buttons: Dictionary = {}
var _pause_overlay: Control
var _settings_overlay: Control
var _result_overlay: Control
var _tutorial_hint: Control
var _quick_settings_note: Label
var _settled: bool = false
var _shake_strength: float = 0.0
var _feedback_timer: float = 0.0
var _elapsed_visual: float = 0.0
# Fire ownership (FR-022): with settings.auto_fire on, hovering the battlefield
# fires without a button press; fire commands are edge-driven so the core log
# stays replay-clean. With auto_fire off the classic hold-to-fire path applies.
var _auto_firing: bool = false
# Drag-cast state (FR-023): left button held while a skill is selected; the cast
# commits on release, releasing over UI cancels the spell.
var _cast_dragging: bool = false
# Last known battlefield position per entity id. The snapshot is one tick older
# than the event stream, so same-tick spawn hits and just-died enemies would
# otherwise fall back to a screen-center position for their floating texts.
var _last_known_positions: Dictionary = {}


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
	var start_result := session.start(prepared["config"], prepared["stage_id"], prepared["seed"], prepared["profile_snapshot"], GameApp.current_run_id)
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
	# Poll the physical button so a drag release consumed by UI still resolves
	# (FR-023): releasing over a Control cancels the spell instead of casting.
	if _cast_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_cast_drag()
	_update_fire_source()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or _result_overlay != null:
		return
	if event.is_action_pressed("combat_select_fire"):
		_select_skill("fire_ball")
	elif event.is_action_pressed("combat_select_ice"):
		_select_skill("glacial_spike")
	elif event.is_action_pressed("combat_select_lightning"):
		_select_skill("lightning_strike")
	elif event.is_action_pressed("game_pause"):
		if _cast_dragging or not str(snapshot.get("selected_skill", "")).is_empty():
			_cancel_cast_drag()
		else:
			_toggle_pause()
	elif event.is_action_pressed("combat_cancel_cast"):
		_cancel_cast_drag()
	elif event.is_action_pressed("combat_fire") or event.is_action_pressed("combat_cast"):
		if not str(snapshot.get("selected_skill", "")).is_empty():
			# FR-023: with a skill selected the left button begins a drag; the
			# cast commits on release at the pointer, not on press.
			_cast_dragging = true
		elif not _auto_fire_enabled():
			session.queue_command({"type": "fire_started"})
	elif event.is_action_released("combat_fire"):
		if _cast_dragging:
			_finish_cast_drag()
		elif not _auto_fire_enabled():
			session.queue_command({"type": "fire_stopped"})


func _auto_fire_enabled() -> bool:
	return bool(GameApp.settings.get("auto_fire", true))


func _apply_fire_edge(want_fire: bool) -> void:
	if want_fire == _auto_firing or session == null:
		return
	_auto_firing = want_fire
	session.queue_command({"type": "fire_started" if want_fire else "fire_stopped"})


func _hover_blocks_fire() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered == null:
		return false
	# Skill buttons are casting shortcuts, not fire blockers: hovering them
	# must not silence the bow while the pointer travels across the HUD.
	for button in _skill_buttons.values():
		if hovered == button:
			return false
	return true


func _update_fire_source() -> void:
	if not _auto_fire_enabled():
		return
	var want_fire := not _cast_dragging \
		and not get_tree().paused \
		and _result_overlay == null \
		and str(snapshot.get("selected_skill", "")).is_empty() \
		and str(snapshot.get("status", "running")) == "running" \
		and not _hover_blocks_fire()
	_apply_fire_edge(want_fire)


func _finish_cast_drag() -> void:
	_cast_dragging = false
	var selected := str(snapshot.get("selected_skill", ""))
	if selected.is_empty():
		return
	if get_viewport().gui_get_hovered_control() != null:
		session.queue_command({"type": "cancel_skill"})
		return
	var mouse := get_global_mouse_position()
	session.queue_command({"type": "cast_skill", "skill_id": selected, "x_milli": int(mouse.x * 1000.0), "y_milli": int(mouse.y * 1000.0)})


func _cancel_cast_drag() -> void:
	_cast_dragging = false
	session.queue_command({"type": "cancel_skill"})


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
	_stage_label.text = "%s  %02d" % [GameApp.text("common.stage"), int(snapshot.get("stage_number", 0))]
	_enemy_label.text = "%s  %d / %d" % [GameApp.text("hud.wave"), int(snapshot.get("kills", 0)), int(snapshot.get("spawn_total", 0))]
	_progress_bar.max_value = maxi(1, int(snapshot.get("spawn_total", 1)))
	_progress_bar.value = int(snapshot.get("spawned", 0))
	_progress_bar.tooltip_text = "%d / %d" % [int(snapshot.get("spawned", 0)), int(snapshot.get("spawn_total", 0))]
	_coin_label.text = "◆  %d" % int(snapshot.get("coins_earned", 0))
	_weapon_label.text = "%s: %s" % [GameApp.text("hud.weapon"), GameApp.text(str(snapshot.get("weapon_name_key", "weapon.basic_bow")))]
	var defenses: Dictionary = snapshot.get("defenses", {})
	_defense_label.text = "%s  %s %d  ·  %s %d" % [
		GameApp.text("hud.defenses"), GameApp.text("hud.lava_moat"), int(defenses.get("lava_moat_level", 0)),
		GameApp.text("hud.magic_tower"), int(defenses.get("magic_tower_level", 0))
	]
	_update_skill_buttons()
	_update_boss_bar()
	for enemy in snapshot.get("enemies", []):
		_last_known_positions[int(enemy.get("entity_id", 0))] = Vector2(float(enemy.get("x_milli", 0)) / 1000.0, float(enemy.get("y_milli", 0)) / 1000.0)


func _on_events(events_value: Array) -> void:
	var sfx_volume := float(GameApp.settings.get("sfx_volume", 0.85))
	for event_value in events_value:
		var event: Dictionary = event_value
		# Events arrive ordered (spawn < hit < damage < death). Recording spawn
		# positions first keeps same-tick hits on freshly spawned enemies anchored
		# to the real position instead of the unknown-entity fallback.
		if str(event.get("type", "")) == "spawn":
			_last_known_positions[int(event.get("entity_id", 0))] = Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0)
		GameApp.audio.play_event(event, sfx_volume)
		match str(event.get("type", "")):
			"skill_cast":
				var position := Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0)
				_append_effect({"kind": str(event.get("skill_id", "")), "position": position, "age": 0.0, "duration": 0.72})
				_shake_strength = _quality_shake(10.0)
			"hit":
				var hit_position := _entity_position(int(event.get("entity_id", 0)))
				_append_effect({"kind": "hit", "position": hit_position, "age": 0.0, "duration": 0.22})
				if bool(event.get("fatal", false)):
					_add_float(GameApp.text("feedback.fatal"), hit_position, Color("ffd166"), 30)
				if bool(event.get("power", false)):
					_add_float(GameApp.text("feedback.power"), hit_position + Vector2(0, 30), Color("ff9b54"), 24)
			"damage":
				_add_float("-%d" % int(event.get("amount", 0)), _entity_position(int(event.get("entity_id", 0))), _damage_color(str(event.get("source", ""))), 21)
			"death":
				_append_effect({"kind": "death", "position": _entity_position(int(event.get("entity_id", 0))), "age": 0.0, "duration": 0.55})
			"wall_damage":
				_shake_strength = _quality_shake(13.0)
				_feedback("⚠  " + (GameApp.text("feedback.wall_damage") % int(event.get("amount", 0))), Color("ff7b6b"))
			"skill_rejected":
				var key := "feedback.no_mana" if str(event.get("reason", "")) == "no_mana" else "feedback.cooldown"
				_feedback("✕  " + GameApp.text(key), Color("ff9b7b"))
			"boss_warning":
				_feedback("⚠  " + GameApp.text("feedback.boss") + "  ⚠", Color("ff587d"), 3.5)
			"boss_special":
				_shake_strength = _quality_shake(18.0)
				_append_effect({"kind": "boss_wave", "position": Vector2(780, 540), "age": 0.0, "duration": 0.8})
			"defense_attack":
				_feedback(GameApp.text("feedback.defense"), Color("ff9b54"), 0.8)
				_append_effect({"kind": "defense", "position": Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0), "age": 0.0, "duration": 0.35})


func _on_run_finished(result: Dictionary) -> void:
	if _settled:
		return
	_settled = true
	if session != null:
		session.export_debug_replay()
	var settlement := GameApp.settle_run(result)
	_show_result(result, settlement)


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
	var pause := Button.new()
	pause.text = "Ⅱ"
	pause.custom_minimum_size = Vector2(64, 54)
	pause.mouse_filter = Control.MOUSE_FILTER_STOP
	pause.pressed.connect(_toggle_pause)
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
	var sword := _hud_label("⚔", 24, Color("b9d7ea"), 34)
	progress_stack.add_child(sword)
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(240, 22)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress_stack.add_child(_progress_bar)
	var skull := _hud_label("💀", 24, Color("ff8d7a"), 40)
	progress_stack.add_child(skull)
	_coin_label = _hud_label("", 24, Color("ffd166"), 150)
	top_row.add_child(_coin_label)

	# Bottom-left status cluster: red wall HP bar over blue Mana bar with icons,
	# matching the classic layout; weapon/defense readouts sit right of it.
	var status_margin := MarginContainer.new()
	status_margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_margin.position = Vector2(24, -180)
	status_margin.size = Vector2(430, 160)
	status_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(status_margin)
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
	_weapon_label = _hud_label("", 18, Color("b9d7ea"), 430)
	_weapon_label.size.y = 32
	_weapon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_stack.add_child(_weapon_label)
	_defense_label = _hud_label("", 17, Color("f2bd76"), 430)
	_defense_label.size.y = 32
	_defense_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_stack.add_child(_defense_label)

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
	skills.alignment = BoxContainer.ALIGNMENT_END
	skills.add_theme_constant_override("separation", 18)
	skills_margin.add_child(skills)
	for definition in [
		["fire_ball", "🔥"],
		["glacial_spike", "❄"],
		["lightning_strike", "⚡"]
	]:
		var button := SkillButton.new()
		button.skill_id = str(definition[0])
		button.glyph = str(definition[1])
		button.low_mana_text = GameApp.text("feedback.no_mana")
		button.tooltip_text = GameApp.text("skill.fire" if definition[0] == "fire_ball" else ("skill.ice" if definition[0] == "glacial_spike" else "skill.lightning"))
		button.pressed.connect(func() -> void: _select_skill(button.skill_id))
		skills.add_child(button)
		_skill_buttons[button.skill_id] = button


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
		var save_result := GameApp.complete_tutorial()
		if not bool(save_result.get("ok", false)):
			body.text = GameApp.text("tutorial.body") + "\n\n" + GameApp.text("feedback.save_failed")
			return
		get_tree().paused = false
		_tutorial_hint.queue_free()
		_tutorial_hint = null
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
	_cast_dragging = false
	if session != null:
		if _auto_fire_enabled():
			_apply_fire_edge(false)
		else:
			session.queue_command({"type": "fire_stopped"})
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
		_quick_settings_note = null
	if _pause_overlay != null:
		_pause_overlay.queue_free()
		_pause_overlay = null


func _show_quick_settings() -> void:
	if _settings_overlay != null:
		return
	_settings_overlay = _overlay_panel(Vector2(560, 520))
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
		slider.value_changed.connect(func(value: float) -> void: _save_quick_setting(str(setting[1]), value))
		row.add_child(slider)
		stack.add_child(row)
	var shake := CheckButton.new()
	shake.text = GameApp.text("settings.shake")
	shake.button_pressed = bool(GameApp.settings.get("screen_shake", true))
	shake.toggled.connect(func(value: bool) -> void: _save_quick_setting("screen_shake", value))
	stack.add_child(shake)
	var quality_row := HBoxContainer.new()
	var quality_label := Label.new()
	quality_label.text = GameApp.text("settings.quality")
	quality_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_row.add_child(quality_label)
	var quality := OptionButton.new()
	var quality_values := ["low", "medium", "high"]
	for quality_value in quality_values:
		quality.add_item(GameApp.text("quality." + quality_value))
	quality.selected = maxi(0, quality_values.find(str(GameApp.settings.get("quality", "medium"))))
	quality.item_selected.connect(func(index: int) -> void: _save_quick_setting("quality", quality_values[index]))
	quality_row.add_child(quality)
	stack.add_child(quality_row)
	_quick_settings_note = Label.new()
	_quick_settings_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_quick_settings_note.add_theme_color_override("font_color", Color("9fb2c8"))
	stack.add_child(_quick_settings_note)
	var close := _overlay_button(GameApp.text("menu.back"))
	close.pressed.connect(func() -> void:
		_settings_overlay.queue_free()
		_settings_overlay = null
		_quick_settings_note = null
	)
	stack.add_child(close)


func _confirm_return_to_menu() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.title = GameApp.text("hud.main_menu")
	dialog.dialog_text = GameApp.text("dialog.abandon_run")
	dialog.ok_button_text = GameApp.text("hud.main_menu")
	dialog.cancel_button_text = GameApp.text("menu.back")
	dialog.confirmed.connect(func() -> void: GameApp.return_to_menu())
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 220))


func _show_result(result: Dictionary, settlement: Dictionary = {"ok": true}) -> void:
	# The run is over: never show the result panel on top of a paused tree,
	# otherwise PAUSABLE HUD children would stop responding to input.
	get_tree().paused = false
	_result_overlay = _overlay_panel(Vector2(720, 760 if not bool(settlement.get("ok", false)) else 680))
	var stack := _result_overlay.get_meta("stack") as VBoxContainer
	var victory := str(result.get("status", "")) == "victory"
	var title := _overlay_title(GameApp.text("result.victory") if victory else GameApp.text("result.defeat"))
	title.add_theme_color_override("font_color", Color("ffd166") if victory else Color("ff7697"))
	stack.add_child(title)
	var summary := Label.new()
	summary.text = "%s %02d\n\n%s        %d / %d\n%s        %d\n%s        %d%%\n%s     +%d\n%s       +%d" % [
		GameApp.text("common.stage"), int(result.get("stage_number", 0)),
		GameApp.text("result.wave"), int(result.get("wave", 0)), int(result.get("wave_total", 0)),
		GameApp.text("result.kills"), int(result.get("kills", 0)),
		GameApp.text("result.wall"), int(result.get("wall_percent", 0)),
		GameApp.text("result.coins"), int(result.get("coins", 0)),
		GameApp.text("result.xp"), int(result.get("xp", 0))
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.add_theme_font_size_override("font_size", 26)
	stack.add_child(summary)
	if not bool(settlement.get("ok", false)):
		var save_error := Label.new()
		save_error.text = GameApp.text("feedback.save_failed")
		save_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_error.add_theme_color_override("font_color", Color("ff8d7a"))
		stack.add_child(save_error)
		var retry_save := _overlay_button(GameApp.text("result.retry_save"))
		retry_save.pressed.connect(func() -> void: _retry_settlement(result))
		stack.add_child(retry_save)
	var total_stages: int = GameApp.content.rules.get("stages", []).size()
	if victory and int(result.get("stage_number", 0)) < total_stages:
		var unlocked := Label.new()
		unlocked.text = "✦  " + (GameApp.text("result.stage_unlocked") % (int(result.get("stage_number", 0)) + 1)) + "  ✦"
		unlocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unlocked.add_theme_color_override("font_color", Color("8ce99a"))
		stack.add_child(unlocked)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_child(actions)
	var restart := _overlay_button(GameApp.text("hud.restart"))
	restart.custom_minimum_size.x = 200
	restart.pressed.connect(func() -> void: GameApp.start_stage(GameApp.current_stage_id))
	actions.add_child(restart)
	var menu := _overlay_button(GameApp.text("hud.main_menu"))
	menu.custom_minimum_size.x = 200
	menu.pressed.connect(func() -> void: GameApp.return_to_menu())
	actions.add_child(menu)
	if not settlement.get("new_honors", []).is_empty():
		var honor_names: Array[String] = []
		for honor_id in settlement.get("new_honors", []):
			var honor := GameApp.content.find_by_id("honors", str(honor_id))
			if not honor.is_empty():
				honor_names.append(GameApp.text(str(honor.get("name_key", honor_id))))
		var honors_label := Label.new()
		honors_label.text = "✦  %s: %s  ✦" % [GameApp.text("result.honors"), ", ".join(honor_names)]
		honors_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		honors_label.add_theme_color_override("font_color", Color("8ce99a"))
		stack.add_child(honors_label)
	if victory and int(result.get("stage_number", 0)) < total_stages:
		var next := _overlay_button(GameApp.text("result.next"))
		next.custom_minimum_size.x = 200
		next.pressed.connect(func() -> void:
			GameApp.start_stage("stage_%03d" % (int(result.get("stage_number", 0)) + 1))
		)
		actions.add_child(next)
	for button in actions.get_children():
		button.process_mode = Node.PROCESS_MODE_ALWAYS
	restart.call_deferred("grab_focus")


func _retry_settlement(result: Dictionary) -> void:
	var settlement := GameApp.settle_run(result)
	if bool(settlement.get("ok", false)):
		_result_overlay.free()
		_result_overlay = null
		_show_result(result, settlement)


func _save_quick_setting(key: String, value: Variant) -> void:
	var save_result := GameApp.update_setting(key, value)
	if _quick_settings_note == null or not is_instance_valid(_quick_settings_note):
		return
	if bool(save_result.get("ok", false)):
		_quick_settings_note.text = GameApp.text("settings.applied")
		_quick_settings_note.add_theme_color_override("font_color", Color("9fb2c8"))
	else:
		_quick_settings_note.text = GameApp.text("feedback.save_failed")
		_quick_settings_note.add_theme_color_override("font_color", Color("ff8d7a"))


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


func _bar_fill(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	return style


func _select_skill(skill_id: String) -> void:
	if get_tree().paused or session == null:
		return
	_cast_dragging = false
	if not _auto_fire_enabled():
		# Legacy hold-to-fire: selecting a spell re-purposes the left button.
		session.queue_command({"type": "fire_stopped"})
	session.queue_command({"type": "select_skill", "skill_id": skill_id})


func _update_skill_buttons() -> void:
	var selected := str(snapshot.get("selected_skill", ""))
	var cooldowns: Dictionary = snapshot.get("skill_cooldowns", {})
	var mana := int(snapshot.get("mana", 0))
	for skill_id in _skill_buttons.keys():
		var button: Control = _skill_buttons[skill_id]
		var cooldown := int(cooldowns.get(skill_id, 0))
		var definition := _skill_definition(skill_id)
		var max_cooldown := maxi(1, int(definition.get("cooldown_ticks", 1)))
		var mana_cost := int(definition.get("mana_cost", 0))
		button.set_state(float(cooldown) / float(max_cooldown), mana >= mana_cost, selected == skill_id)


func _skill_definition(skill_id: String) -> Dictionary:
	for skill in GameApp.content.rules.get("skills", []):
		if skill is Dictionary and str(skill.get("id", "")) == skill_id:
			return skill
	return {}


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
	var limit := int(_quality_profile()["floating_text_limit"])
	while floating_texts.size() >= limit:
		floating_texts.pop_front()
	floating_texts.append({"text": value, "x": position.x, "y": position.y, "color": color, "font_size": font_size, "age": 0.0})


func _append_effect(effect: Dictionary) -> void:
	var limit := int(_quality_profile()["effect_limit"])
	while effects.size() >= limit:
		effects.pop_front()
	effects.append(effect)


func _quality_shake(base_strength: float) -> float:
	if not bool(GameApp.settings.get("screen_shake", true)):
		return 0.0
	return base_strength * float(_quality_profile()["shake_multiplier"])


func _quality_profile() -> Dictionary:
	match str(GameApp.settings.get("quality", "medium")):
		"low":
			return {
				"background_bands": 6,
				"background_stones": 10,
				"effect_limit": 12,
				"floating_text_limit": 8,
				"effect_detail": 0.45,
				"shake_multiplier": 0.0
			}
		"high":
			return {
				"background_bands": 12,
				"background_stones": 34,
				"effect_limit": 64,
				"floating_text_limit": 32,
				"effect_detail": 1.0,
				"shake_multiplier": 1.0
			}
		_:
			return {
				"background_bands": 9,
				"background_stones": 22,
				"effect_limit": 32,
				"floating_text_limit": 18,
				"effect_detail": 0.7,
				"shake_multiplier": 0.65
			}


func _entity_position(entity_id: int) -> Vector2:
	for enemy in snapshot.get("enemies", []):
		if int(enemy.get("entity_id", -1)) == entity_id:
			return Vector2(float(enemy.get("x_milli", 0)) / 1000.0, float(enemy.get("y_milli", 0)) / 1000.0)
	if _last_known_positions.has(entity_id):
		return _last_known_positions[entity_id]
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
	_draw_cast_drag_indicator()
	draw_set_transform(Vector2.ZERO)


func _draw_background() -> void:
	var quality := _quality_profile()
	var background_bands := int(quality["background_bands"])
	for band in range(background_bands):
		var ratio := float(band) / float(background_bands - 1)
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
	for stone in range(int(quality["background_stones"])):
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
	var detail := float(_quality_profile()["effect_detail"])
	match kind:
		"fire_ball":
			draw_circle(position, 40.0 + progress * 165.0, Color(1.0, 0.25, 0.04, (1.0 - progress) * 0.34))
			var fire_rays := maxi(4, int(round(10.0 * detail)))
			draw_arc(position, 55.0 + progress * 135.0, 0, TAU, maxi(16, int(round(48.0 * detail))), Color(1.0, 0.78, 0.18, 1.0 - progress), 12)
			for ray in range(fire_rays):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / float(fire_rays))
				draw_line(position + direction * 28.0, position + direction * (70.0 + progress * 130.0), Color(1.0, 0.48, 0.08, 1.0 - progress), 8)
		"glacial_spike":
			var ice_rays := maxi(5, int(round(12.0 * detail)))
			for ray in range(ice_rays):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / float(ice_rays))
				var side := direction.rotated(0.32)
				draw_colored_polygon(PackedVector2Array([position + side * 15.0, position + direction * (70.0 + 150.0 * (1.0 - progress)), position - side * 15.0]), Color(0.42, 0.88, 1.0, 0.85 * (1.0 - progress)))
		"lightning_strike":
			var lightning_bolts := maxi(2, int(round(5.0 * detail)))
			var lightning_segments := maxi(5, int(round(8.0 * detail)))
			for bolt in range(lightning_bolts):
				var points := PackedVector2Array()
				for segment in range(lightning_segments):
					var y := position.y - 460.0 + float(segment) * (462.0 / float(lightning_segments - 1))
					var x := position.x + sin(float(segment * 13 + bolt * 7)) * (34.0 + bolt * 5.0)
					points.append(Vector2(x, y))
				draw_polyline(points, Color(0.84, 0.72, 1.0, 1.0 - progress), 7.0 - float(bolt))
		"hit":
			var hit_rays := maxi(3, int(round(6.0 * detail)))
			for ray in range(hit_rays):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / float(hit_rays))
				draw_line(position, position + direction * (18.0 + 34.0 * (1.0 - progress)), Color(1.0, 0.93, 0.55, 1.0 - progress), 4)
		"death":
			draw_arc(position, 24.0 + progress * 70.0, 0, TAU, maxi(10, int(round(24.0 * detail))), Color(1.0, 0.43, 0.22, 1.0 - progress), 8)
		"boss_wave":
			draw_arc(position, 80.0 + progress * 620.0, -1.2, 1.2, maxi(16, int(round(48.0 * detail))), Color(0.9, 0.16, 0.36, 1.0 - progress), 14)


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


func _draw_cast_drag_indicator() -> void:
	if not _cast_dragging:
		return
	var skill_id := str(snapshot.get("selected_skill", ""))
	var skill := GameApp.content.find_by_id("skills", skill_id)
	if skill.is_empty():
		return
	var mouse := get_global_mouse_position()
	var radius := float(skill.get("radius_milli", 0)) / 1000.0
	var valid := _cast_target_valid(skill, mouse)
	var color := Color(0.44, 0.91, 0.63, 0.85) if valid else Color(1.0, 0.48, 0.42, 0.85)
	draw_arc(mouse, maxf(14.0, radius), 0.0, TAU, 48, color, 4.0)
	draw_arc(mouse, maxf(10.0, radius * 0.55), 0.0, TAU, 36, Color(color, 0.4), 2.0)
	draw_circle(mouse, 5.0, color)
	if not valid:
		var cross := 12.0
		draw_line(mouse + Vector2(-cross, -cross), mouse + Vector2(cross, cross), color, 3.0)
		draw_line(mouse + Vector2(cross, -cross), mouse + Vector2(-cross, cross), color, 3.0)


func _cast_target_valid(skill: Dictionary, position: Vector2) -> bool:
	var skill_id := str(skill.get("id", ""))
	var cooldowns: Dictionary = snapshot.get("skill_cooldowns", {})
	if int(cooldowns.get(skill_id, 0)) > 0:
		return false
	if int(snapshot.get("mana", 0)) < int(skill.get("mana_cost", 0)):
		return false
	var world: Dictionary = GameApp.content.rules.get("world", {})
	var x_milli := position.x * 1000.0
	var y_milli := position.y * 1000.0
	return x_milli >= float(world.get("castle_x_milli", 0)) and x_milli <= float(world.get("width_milli", 1920000)) and y_milli >= 0.0 and y_milli <= float(world.get("height_milli", 1080000))


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
