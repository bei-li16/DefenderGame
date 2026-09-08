extends Node2D

const GameSession = preload("res://src/application/game_session.gd")
const RunOrchestrator = preload("res://src/application/run_orchestrator.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const Progression = preload("res://src/core/rules/progression.gd")
const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
const GameplayHud = preload("res://src/presentation/gameplay/gameplay_hud.gd")
const Art = preload("res://src/presentation/art/game_art.gd")
const CreatureVisuals = preload("res://src/presentation/art/creature_visuals.gd")
const CastleView = preload("res://src/presentation/art/castle_view.gd")
const CourtyardView = preload("res://src/presentation/art/courtyard_view.gd")
const MagicCursor = preload("res://src/presentation/gameplay/magic_cursor.gd")

var _creatures := CreatureVisuals.new()
var _bow_recoil := 0.0
var _aim_visual_angle := 0.0
var _snapshot_blend := 0.0

var session: DefenderGameSession
var snapshot: Dictionary = {}
var effects: Array[Dictionary] = []
var floating_texts: Array[Dictionary] = []
var _hud: GameplayHud
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
var _owns_hidden_cursor := false
var _pointer_inside_window := true
# Last known battlefield position per entity id. The snapshot is one tick older
# than the event stream, so same-tick spawn hits and just-died enemies would
# otherwise fall back to a screen-center position for their floating texts.
var _last_known_positions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().mouse_entered.connect(func() -> void: _pointer_inside_window = true)
	get_window().mouse_exited.connect(func() -> void:
		_pointer_inside_window = false
		_sync_pointer_cursor()
	)
	get_window().focus_exited.connect(func() -> void:
		_pointer_inside_window = false
		_sync_pointer_cursor()
	)
	get_window().focus_entered.connect(func() -> void: _pointer_inside_window = true)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for key in Art.FILES:
		Art.texture(key)
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
	# Keep menu/input processing alive while battlefield animation is paused.
	if get_tree().paused:
		delta = 0.0
	else:
		_aim_visual_angle = (get_global_mouse_position() - CastleView.BOW_ORIGIN).angle()
	_creatures.advance(delta)
	_snapshot_blend = minf(1.0, _snapshot_blend + delta * float(Engine.physics_ticks_per_second))
	_bow_recoil = maxf(0.0, _bow_recoil - delta * 7.0)
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
		if _feedback_timer <= 0.0 and _hud != null:
			_hud.feedback_label.text = ""
	# Poll the physical button so a drag release consumed by UI still resolves
	# (FR-023): releasing over a Control cancels the spell instead of casting.
	if _cast_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_cast_drag()
	_update_fire_source()
	_sync_pointer_cursor()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if session == null or _result_overlay != null:
		return
	if event.is_action_pressed("combat_select_fire"):
		_select_element("fire")
	elif event.is_action_pressed("combat_select_ice"):
		_select_element("ice")
	elif event.is_action_pressed("combat_select_lightning"):
		_select_element("lightning")
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
	for button in _hud.skill_buttons.values():
		if hovered == button:
			return false
	return true


func _update_fire_source() -> void:
	if not _auto_fire_enabled():
		# Settings can be changed while a run is alive (for example by an
		# embedded/quick settings panel or an external profile update).  Clear
		# the auto-fire edge before returning; otherwise the core keeps receiving
		# no stop command and will continue firing after auto-fire is disabled.
		_apply_fire_edge(false)
		return
	var want_fire := not _cast_dragging \
		and not get_tree().paused \
		and _result_overlay == null \
		and str(snapshot.get("selected_skill", "")).is_empty() \
		and str(snapshot.get("status", "running")) == "running" \
		and _pointer_in_battlefield() \
		and not _hover_blocks_fire()
	_apply_fire_edge(want_fire)


func _pointer_in_battlefield() -> bool:
	# A null hovered Control can also mean that the pointer has left the game
	# window.  Restrict hover-fire to the visible viewport so moving out of the
	# window cannot keep the bow firing at a stale edge coordinate.
	var viewport := get_viewport()
	if viewport == null:
		return false
	return viewport.get_visible_rect().has_point(viewport.get_mouse_position())


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
	_snapshot_blend = 0.0
	_creatures.sync(value.get("enemies", []))
	if _hud == null:
		return
	_hud.update_snapshot(value)
	_last_known_positions.clear()
	for enemy in snapshot.get("enemies", []):
		_last_known_positions[int(enemy.get("entity_id", 0))] = Vector2(float(enemy.get("x_milli", 0)) / 1000.0, float(enemy.get("y_milli", 0)) / 1000.0)


func _on_events(events_value: Array) -> void:
	var sfx_volume := float(GameApp.settings.get("sfx_volume", 0.85))
	for event_value in events_value:
		var event: Dictionary = event_value
		_creatures.event(event)
		# Events arrive ordered (spawn < hit < damage < death). Recording spawn
		# positions first keeps same-tick hits on freshly spawned enemies anchored
		# to the real position instead of the unknown-entity fallback.
		if str(event.get("type", "")) == "spawn":
			_last_known_positions[int(event.get("entity_id", 0))] = Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0)
		GameApp.audio.play_event(event, sfx_volume)
		match str(event.get("type", "")):
			"shot":
				_bow_recoil = 1.0
			"skill_cast":
				if str(event.get("target_mode", "")) == "screen":
					_feedback(GameApp.text("skill.screen_target"), Color("ffd166"), 1.5)
			"skill_pulse":
				var position := Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0)
				_shake_strength = maxf(_shake_strength, _quality_shake(4.0))
				_append_effect({"kind": "spell", "element": event.get("element", ""), "tier": event.get("tier", 1), "radius": float(event.get("radius_milli", 0)) / 1000.0, "splash_radius": float(event.get("splash_radius_milli", 0)) / 1000.0, "hits": event.get("hits", []), "position": position, "age": 0.0, "duration": 0.6})
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
				var attacker := _entity_position(int(event.get("entity_id", 0)))
				_append_effect({"kind": "enemy_attack", "position": attacker, "age": 0.0, "duration": 0.32})
				# Armor can absorb all damage. Keep the monster's attack action,
				# but do not shake the screen or report a misleading HP loss of 0.
				if int(event.get("amount", 0)) > 0:
					_shake_strength = _quality_shake(13.0)
					_feedback("⚠  " + (GameApp.text("feedback.wall_damage") % int(event.get("amount", 0))), Color("ff7b6b"))
			"skill_rejected":
				var reason := str(event.get("reason", ""))
				var key := "feedback.no_mana" if reason == "no_mana" else ("feedback.cooldown" if reason == "cooldown" else "feedback.invalid_target")
				if reason in ["locked", "not_equipped"]:
					key = "feedback.skill_locked"
				_feedback("✕  " + GameApp.text(key), Color("ff9b7b"))
			"boss_warning":
				_feedback("⚠  " + GameApp.text("feedback.boss") + "  ⚠", Color("ff587d"), 3.5)
			"boss_special":
				_shake_strength = _quality_shake(18.0)
				_append_effect({"kind": "boss_wave", "special": event.get("special", ""), "position": _entity_position(int(event.get("entity_id", 0))), "age": 0.0, "duration": 0.8})
			"defense_attack":
				_feedback(GameApp.text("feedback.defense"), Color("ff9b54"), 0.8)
				_append_effect({"kind": "defense", "defense_id": event.get("defense_id", ""), "position": Vector2(float(event.get("x_milli", 0)) / 1000.0, float(event.get("y_milli", 0)) / 1000.0), "age": 0.0, "duration": 0.35})


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
	_hud = GameplayHud.new()
	_hud.pause_requested.connect(_toggle_pause)
	_hud.skill_selected.connect(_select_skill)
	canvas.add_child(_hud)


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
	# Stage Complete level bar (参考 Stage Complete screen: Level N [bar] into/needed).
	var xp_after := int(GameApp.profile.get("xp", 0))
	var xp_gain := int(result.get("xp", 0)) + int(settlement.get("honor_xp", 0))
	var xp_before := xp_after
	if bool(settlement.get("ok", false)) and not bool(settlement.get("duplicate", false)):
		xp_before = maxi(0, xp_after - xp_gain)
	var rules: Dictionary = GameApp.content.rules
	var level_after: Dictionary = Progression.level_progress(rules, xp_after)
	var level_before: Dictionary = Progression.level_progress(rules, xp_before)
	var level_row := HBoxContainer.new()
	level_row.alignment = BoxContainer.ALIGNMENT_CENTER
	level_row.add_theme_constant_override("separation", 12)
	stack.add_child(level_row)
	var level_label := Label.new()
	level_label.text = GameApp.text("status.level_short") % int(level_after.get("level", 1))
	level_label.add_theme_font_size_override("font_size", 24)
	level_row.add_child(level_label)
	var level_bar := ProgressBar.new()
	level_bar.custom_minimum_size = Vector2(280, 18)
	level_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	level_bar.max_value = maxi(1, int(level_after.get("needed", 1)))
	level_bar.value = int(level_after.get("into_level", 0))
	level_bar.show_percentage = false
	level_bar.tooltip_text = "%d / %d" % [int(level_after.get("into_level", 0)), int(level_after.get("needed", 1))]
	level_row.add_child(level_bar)
	var level_value := Label.new()
	level_value.text = "%d / %d" % [int(level_after.get("into_level", 0)), int(level_after.get("needed", 1))]
	level_value.add_theme_font_size_override("font_size", 20)
	level_row.add_child(level_value)
	if int(settlement.get("crystals_awarded", 0)) > 0:
		var crystal_note := Label.new()
		crystal_note.text = "✦  %s +%d  ✦" % [GameApp.text("result.crystals"), int(settlement.get("crystals_awarded", 0))]
		crystal_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		crystal_note.add_theme_color_override("font_color", Color("9bd1ff"))
		stack.add_child(crystal_note)
	if int(level_after.get("level", 1)) > int(level_before.get("level", 1)):
		var level_up := Label.new()
		level_up.text = "✦  %s  %s → %s  ✦" % [
			GameApp.text("result.level_up"),
			GameApp.text("status.level_short") % int(level_before.get("level", 1)),
			GameApp.text("status.level_short") % int(level_after.get("level", 1))
		]
		level_up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		level_up.add_theme_color_override("font_color", Color("8ce99a"))
		stack.add_child(level_up)
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
	var has_next := StageCatalog.has_next(GameApp.content.rules, int(result.get("stage_number", 0)))
	if victory and has_next and bool(settlement.get("ok", false)):
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
		for honor_key in settlement.get("new_honors", []):
			# Chain keys look like "honor_id:level"; show the achieved level.
			var parts := str(honor_key).split(":")
			var honor := GameApp.content.find_by_id("honors", str(parts[0]))
			if not honor.is_empty():
				var honor_name := GameApp.text(str(honor.get("name_key", str(parts[0]))))
				honor_names.append("%s %s" % [honor_name, GameApp.text("status.level_short") % int(parts[1]) if parts.size() > 1 else honor_name])
		var honors_label := Label.new()
		honors_label.text = "✦  %s: %s  ✦" % [GameApp.text("result.honors"), ", ".join(honor_names)]
		honors_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		honors_label.add_theme_color_override("font_color", Color("8ce99a"))
		stack.add_child(honors_label)
	if victory and has_next:
		var next := _overlay_button(GameApp.text("result.next"))
		next.name = "NextStageButton"
		next.custom_minimum_size.x = 200
		next.disabled = not bool(settlement.get("ok", false))
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


func _select_element(element: String) -> void:
	_select_skill(str(snapshot.get("skill_loadout", {}).get(element, "")))


func _select_skill(skill_id: String) -> void:
	if get_tree().paused or session == null:
		return
	_cast_dragging = false
	if not _auto_fire_enabled():
		# Legacy hold-to-fire: selecting a spell re-purposes the left button.
		session.queue_command({"type": "fire_stopped"})
	session.queue_command({"type": "select_skill", "skill_id": skill_id})


func _feedback(value: String, color: Color, duration: float = 1.7) -> void:
	_hud.feedback_label.text = value
	_hud.feedback_label.add_theme_color_override("font_color", color)
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
	_creatures.draw_retired(self)
	var sorted_enemies: Array = snapshot.get("enemies", []).duplicate()
	sorted_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["y_milli"]) < int(b["y_milli"]))
	for enemy in sorted_enemies:
		_draw_enemy(enemy)
	# The complete fortress already contains its own architectural occlusion.
	# Draw it once over contacting attackers, then its independently aimed bow.
	_draw_castle()
	for projectile in snapshot.get("projectiles", []):
		_draw_projectile(projectile)
	_draw_falling_spells()
	for effect in effects:
		_draw_effect(effect)
	for text_data in floating_texts:
		var alpha := clampf(1.0 - float(text_data["age"]) / 1.25, 0.0, 1.0)
		var color: Color = text_data["color"]
		color.a = alpha
		draw_string(ThemeDB.fallback_font, Vector2(float(text_data["x"]), float(text_data["y"])), str(text_data["text"]), HORIZONTAL_ALIGNMENT_CENTER, 180, int(text_data["font_size"]), color)
	draw_set_transform(Vector2.ZERO)
	# Aiming overlays belong to the pointer, never to the screen shake.
	if not _pointer_cursor_kind().is_empty():
		_draw_cast_drag_indicator()
		_draw_crosshair()


func _draw_background() -> void:
	# These are complete alternate plates, not pieces of one tiled background.
	Art.cover(self, CastleView.floor_key(snapshot), Rect2(0, 0, 1920, 1080), Color(0.86, 0.9, 0.98))
	CourtyardView.draw(self)
	draw_rect(Rect2(0, 0, 1920, 145), Color(0.02, 0.04, 0.07, 0.2))


func _draw_castle() -> void:
	var tower_active := int(snapshot.get("defenses", {}).get("magic_tower_level", 0)) > 0
	CastleView.draw_structure(self, tower_active, _elapsed_visual)
	var origin := CastleView.BOW_ORIGIN
	var aim_angle := _aim_visual_angle
	# The new wall supplies the stone mounting platform. Only reuse the wooden
	# pedestal, not the old turret's second circular stone tower below it.
	var base := Art.region("turret", CastleView.PEDESTAL_UV)
	var bow := Art.region("turret", Rect2(0.05, 0.0, 0.91, 0.55))
	Art.draw_sprite(self, base, CastleView.PEDESTAL_POSITION, CastleView.PEDESTAL_SIZE)
	Art.draw_sprite(self, bow, origin - Vector2.RIGHT.rotated(aim_angle) * _bow_recoil * 12.0, CastleView.BOW_SIZE, aim_angle)

func _draw_enemy(enemy: Dictionary) -> void:
	var position: Vector2 = _creatures.actors.get(int(enemy["entity_id"]), {}).get("position", Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0)
	var radius := float(enemy["collision_radius_milli"]) / 1000.0
	_creatures.draw_enemy(self, enemy)
	if int(enemy.get("stun_ticks", 0)) > 0:
		draw_arc(position, radius + 9, 0, TAU, 16, Color("e5d5ff"), 4)
	if int(enemy.get("freeze_ticks", 0)) > 0:
		_draw_ice_prison(position, radius + 14.0, 0.65)
	if int(enemy.get("burn_ticks", 0)) > 0:
		draw_colored_polygon(PackedVector2Array([position + Vector2(-10, -radius), position + Vector2(0, -radius - 28), position + Vector2(12, -radius)]), Color("ff8b3d"))
	if int(enemy.get("poison_ticks", 0)) > 0:
		# Bubbles + a distinct damage colour keep poison readable beside burn/ice.
		for bubble in range(3):
			draw_circle(position + Vector2(radius + 8 + bubble * 6, -12 - bubble * 14), 5 - bubble, Color("91e76d"))
	var bar_width := radius * 2.0
	var art := Art.creature(enemy)
	var texture := Art.texture(str(art["art"]))
	var bar_y := position.y - float(art["width"]) * texture.get_height() / texture.get_width() * 0.5 - 8.0
	var hp_ratio := float(enemy["hp"]) / maxf(1.0, float(enemy["max_hp"]))
	draw_rect(Rect2(position.x - radius - 2, bar_y - 2, bar_width + 4, 10), Color("1b1824"))
	draw_rect(Rect2(position.x - radius, bar_y, bar_width * hp_ratio, 6), Color("78d887"))

func _draw_projectile(projectile: Dictionary) -> void:
	var position := Vector2(float(projectile["x_milli"]) / 1000.0, float(projectile["y_milli"]) / 1000.0)
	var velocity := Vector2(float(projectile["vx_milli"]), float(projectile["vy_milli"])).normalized()
	var color := Color.WHITE if not bool(projectile.get("fatal", false)) else Color(1.4, 1.1, 0.6)
	if int(projectile.get("poison_damage", 0)) > 0:
		draw_line(position - velocity * 58.0, position - velocity * 24.0, Color("91e76d"), 4.0)
	# Art faces left; anchor its tip at the collision point, trail behind it.
	Art.draw_sprite(self, Art.texture("arrow"), position - velocity * 29.0, Vector2(76, 25.3), velocity.angle() + PI, color)

func _draw_effect(effect: Dictionary) -> void:
	var kind := str(effect.get("kind", ""))
	var position: Vector2 = effect.get("position", Vector2.ZERO)
	var progress := clampf(float(effect.get("age", 0.0)) / maxf(0.01, float(effect.get("duration", 1.0))), 0.0, 1.0)
	var detail := float(_quality_profile()["effect_detail"])
	if kind == "spell":
		_draw_spell_effect(effect, progress, detail)
		return
	match kind:
		"enemy_attack":
			var impact := CastleView.impact_position(position.y)
			if position.x > 440.0:
				var orb := position.lerp(impact, minf(1.0, progress * 2.0))
				draw_line(orb + Vector2(25, 0), orb, Color(0.7, 0.35, 1.0, 1.0 - progress), 8.0)
				draw_circle(orb, 9.0, Color(0.85, 0.6, 1.0, 1.0 - progress))
			else:
				draw_arc(impact, 18.0 + progress * 32.0, -1.1, 1.1, 12, Color(1.0, 0.75, 0.4, 1.0 - progress), 5.0)
		"defense":
			if str(effect.get("defense_id", "")) == "magic_tower":
				var origin := CastleView.magic_origin()
				draw_line(origin, position, Color(0.25, 0.6, 1, (1.0 - progress) * 0.5), 12.0)
				draw_line(origin, position, Color(0.75, 0.95, 1, 1.0 - progress), 3.0)
			else:
				draw_circle(position, 22.0 + progress * 20.0, Color(1, 0.4, 0.05, (1.0 - progress) * 0.65))
		"hit":
			var hit_rays := maxi(3, int(round(6.0 * detail)))
			for ray in range(hit_rays):
				var direction := Vector2.RIGHT.rotated(float(ray) * TAU / float(hit_rays))
				draw_line(position, position + direction * (18.0 + 34.0 * (1.0 - progress)), Color(1.0, 0.93, 0.55, 1.0 - progress), 4)
		"death":
			draw_arc(position, 24.0 + progress * 70.0, 0, TAU, maxi(10, int(round(24.0 * detail))), Color(1.0, 0.43, 0.22, 1.0 - progress), 8)
		"boss_wave":
			var special := str(effect.get("special", ""))
			var tint := Color("ff7946")
			if special == "frost_nova":
				tint = Color("91e2ff")
				_draw_ice_prison(Vector2(150, 555), 130.0, (1.0 - progress) * 0.55)
			elif special == "storm_surge":
				tint = Color("d0a0ff")
			draw_arc(position, 80.0 + progress * 400.0, 0, TAU, maxi(16, int(round(48.0 * detail))), Color(tint, 1.0 - progress), 9)


func _draw_falling_spells() -> void:
	# Render only projectiles that the core has launched but not yet resolved.
	# No visual timer can create an impact or move its authoritative target.
	for falling in snapshot.get("falling_spells", []):
		var target := Vector2(float(falling["x_milli"]), float(falling["y_milli"])) / 1000.0
		var duration := maxf(1.0, int(falling["impact_tick"]) - int(falling["launch_tick"]))
		var progress := clampf((float(snapshot.get("tick", 0)) + _snapshot_blend - int(falling["launch_tick"])) / duration, 0, 1)
		var element := str(falling["element"])
		var origin := Vector2(target.x - 155.0, -85.0)
		if element == "lightning":
			origin.x = target.x
		var position := origin.lerp(target, progress * progress)
		var direction := (target - origin).normalized()
		var size := 17.0 + int(falling["tier"]) * 3.0
		var tint := Color("ff7b25") if element == "fire" else (Color("87dfff") if element == "ice" else Color("d6a5ff"))
		# A restrained landing marker communicates the actual falling point.
		draw_arc(target, 10.0 + progress * 15.0, 0, TAU, 24, Color(tint, 0.12 + progress * 0.25), 1.5)
		if element == "fire":
			for tail in range(7, 0, -1):
				draw_circle(position - direction * tail * 13.0, size * (1.0 - tail * 0.1), Color(1, 0.25 + tail * 0.035, 0.02, 0.65 - tail * 0.075))
			draw_circle(position, size, Color("ff6127"))
			draw_circle(position - direction * 3.0, size * 0.7, Color("ffd45a"))
			draw_circle(position + direction * 3.0, size * 0.35, Color("fff2bd"))
		elif element == "ice":
			var side := direction.orthogonal() * size * 0.6
			var tip := position + direction * size * 1.7
			var back := position - direction * size * 1.5
			draw_line(back - direction * 80.0, back, Color(0.5, 0.8, 1, 0.35), 8.0)
			draw_colored_polygon(PackedVector2Array([tip, position + side, back, position - side]), Color("7ecfff"))
			draw_colored_polygon(PackedVector2Array([tip, back, position - side]), Color("e4fbff"))
		else:
			var points := PackedVector2Array()
			for segment in range(10):
				var point := origin.lerp(position, float(segment) / 9.0)
				if segment > 0 and segment < 9:
					point.x += sin(float(segment * 17 + int(falling["launch_tick"]))) * 18.0
				points.append(point)
			draw_polyline(points, Color(0.65, 0.38, 1, 0.4), 9.0, true)
			draw_polyline(points, Color("eee2ff"), 3.0, true)
			draw_circle(position, size * 0.4, Color("ffffff"))


func _draw_spell_effect(effect: Dictionary, progress: float, detail: float) -> void:
	var center: Vector2 = effect.get("position", Vector2.ZERO)
	var radius := float(effect.get("radius", 180.0))
	var splash := float(effect.get("splash_radius", radius))
	var tier := int(effect.get("tier", 1))
	var fade := 1.0 - progress
	var element := str(effect.get("element", ""))
	var tint := Color("ff9a36") if element == "fire" else (Color("8ee7ff") if element == "ice" else Color("d9a4ff"))
	draw_circle(center, splash, Color(tint, fade * 0.045))
	draw_circle(center, radius, Color(tint, fade * 0.13))
	draw_arc(center, lerpf(radius, splash, progress), 0, TAU, 48, Color(tint, fade * 0.5), 2.0 + tier)
	if element == "fire":
		# Exactly one explosion per actual landing event, regardless of tier.
		var blast := radius * (0.45 + progress * 0.6)
		draw_circle(center, blast, Color(1.0, 0.25, 0.025, fade * 0.5))
		draw_circle(center + Vector2(0, -blast * 0.15), blast * 0.56, Color(1.0, 0.76, 0.17, fade * 0.85))
		draw_arc(center, blast, 0, TAU, 24, Color(1.0, 0.87, 0.38, fade), 4)
	elif element == "ice":
		for hit in effect.get("hits", []):
			var position := Vector2(float(hit["x_milli"]) / 1000.0, float(hit["y_milli"]) / 1000.0)
			_draw_ice_prison(position, 28.0 + tier * 12.0, fade * 0.85)
		var rays := maxi(8, int((8 + tier * 6) * detail))
		for index in range(rays):
			var direction := Vector2.RIGHT.rotated(TAU * index / rays)
			var reach := radius * (0.45 + 0.55 * progress)
			draw_line(center + direction * reach * 0.76, center + direction * reach, Color(0.65, 0.95, 1.0, fade), 3.0)
			if tier == 3:
				var snow := center + direction * radius * 0.75 + Vector2(0, progress * 70)
				draw_line(snow, snow + Vector2(-5, 14), Color(0.86, 0.97, 1, fade * 0.8), 2)
	elif element == "lightning":
		# One sky bolt reaches the scheduled point. Short ground arcs show its
		# splash hits, not extra sky strikes at unscheduled enemy positions.
		var points := PackedVector2Array()
		for segment in range(10):
			var jitter := sin(float(segment * 13)) * 26.0 if segment < 9 else 0.0
			points.append(Vector2(center.x + jitter, lerpf(-85.0, center.y, float(segment) / 9.0)))
		draw_polyline(points, Color(0.68, 0.3, 1.0, fade * 0.45), 10 + tier * 2, true)
		draw_polyline(points, Color(0.95, 0.87, 1.0, fade), 2 + tier, true)
		for hit in effect.get("hits", []):
			var target := Vector2(float(hit["x_milli"]), float(hit["y_milli"])) / 1000.0
			var middle := center.lerp(target, 0.5) + Vector2(12, -15)
			draw_polyline(PackedVector2Array([center, middle, target]), Color(tint, fade * 0.7), 2.0, true)
			draw_arc(target, 24.0 + 25.0 * progress, 0, TAU, 24, Color(tint, fade), 4)


func _draw_ice_prison(position: Vector2, radius: float, opacity: float) -> void:
	var points := PackedVector2Array([position + Vector2(-radius, radius * 0.6), position + Vector2(-radius * 0.65, -radius * 0.65), position + Vector2(0, -radius * 1.6), position + Vector2(radius * 0.7, -radius * 0.6), position + Vector2(radius, radius * 0.6)])
	draw_colored_polygon(points, Color(0.46, 0.82, 1.0, opacity))
	draw_polyline(PackedVector2Array([points[0], points[2], points[4], points[0]]), Color(0.85, 0.97, 1.0, opacity), 3, true)
	draw_line(points[2], position + Vector2(0, radius * 0.6), Color(0.9, 1, 1, opacity), 2)


func _pointer_cursor_kind() -> String:
	if not _pointer_inside_window or not _pointer_in_battlefield() or get_tree().paused or _result_overlay != null or str(snapshot.get("status", "")) != "running":
		return ""
	if get_viewport().gui_get_hovered_control() != null:
		return ""
	var selected := str(snapshot.get("selected_skill", ""))
	if selected.is_empty():
		return "crosshair"
	return str(snapshot.get("skill_definitions", {}).get(selected, {}).get("element", ""))


func _sync_pointer_cursor() -> void:
	if not _pointer_cursor_kind().is_empty():
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
			_owns_hidden_cursor = true
	elif _owns_hidden_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_owns_hidden_cursor = false


func _exit_tree() -> void:
	if _owns_hidden_cursor:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _draw_crosshair() -> void:
	var kind := _pointer_cursor_kind()
	if kind.is_empty():
		return
	var mouse := get_global_mouse_position()
	if kind != "crosshair":
		var skill: Dictionary = snapshot.get("skill_definitions", {}).get(str(snapshot.get("selected_skill", "")), {})
		MagicCursor.draw(self, mouse, kind, int(skill.get("tier", 1)), _cast_target_valid(skill, mouse), _elapsed_visual)
		return
	var color := Color("f4ead5")
	var radius := 22.0
	draw_arc(mouse, radius, 0, TAU, 28, color, 3)
	draw_line(mouse + Vector2(-radius - 10, 0), mouse + Vector2(-radius + 8, 0), color, 3)
	draw_line(mouse + Vector2(radius - 8, 0), mouse + Vector2(radius + 10, 0), color, 3)
	draw_line(mouse + Vector2(0, -radius - 10), mouse + Vector2(0, -radius + 8), color, 3)
	draw_line(mouse + Vector2(0, radius - 8), mouse + Vector2(0, radius + 10), color, 3)
	if bool(GameApp.settings.get("aim_assist", true)):
		var target := _nearest_enemy(mouse, 130.0)
		if target != Vector2.INF:
			draw_line(mouse, target, Color(1.0, 0.84, 0.36, 0.28), 2)


func _draw_cast_drag_indicator() -> void:
	if not _cast_dragging:
		return
	var skill_id := str(snapshot.get("selected_skill", ""))
	var skill: Dictionary = snapshot.get("skill_definitions", {}).get(skill_id, {})
	if skill.is_empty():
		return
	var mouse := get_global_mouse_position()
	var valid := _cast_target_valid(skill, mouse)
	var color := Color(0.44, 0.91, 0.63, 0.85) if valid else Color(1.0, 0.48, 0.42, 0.85)
	var mode := str(skill.get("target_mode", "point"))
	if mode == "screen":
		var world: Dictionary = GameApp.content.rules["world"]
		var left := float(world["castle_x_milli"]) / 1000.0
		var rect := Rect2(left, 0, float(world["width_milli"]) / 1000.0 - left, float(world["height_milli"]) / 1000.0)
		draw_rect(rect, Color(color, 0.035))
		draw_rect(rect.grow(-3), color, false, 3)
		draw_string(ThemeDB.fallback_font, Vector2(750, 180), GameApp.text("skill.screen_target"), HORIZONTAL_ALIGNMENT_CENTER, 480, 26, color)
		return
	var radius := float(skill.get("area_radius_milli", 0) if mode == "area" else skill.get("splash_radius_milli", 0)) / 1000.0
	draw_arc(mouse, maxf(14.0, radius), 0.0, TAU, 48, color, 4.0)
	if mode == "point":
		draw_arc(mouse, maxf(10.0, float(skill.get("radius_milli", 0)) / 1000.0), 0.0, TAU, 36, Color(color, 0.4), 2.0)
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
	if str(skill.get("target_mode", "")) == "screen":
		return true
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
		"poison": return Color("91e76d")
		_: return Color("fff0a8")
