extends SceneTree

var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := root.get_node_or_null("GameApp")
	if app == null:
		push_error("GameApp autoload is unavailable")
		quit(1)
		return
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var original_settings: Dictionary = app.get("settings").duplicate(true)
	var test_profile := original_profile.duplicate(true)
	test_profile["tutorial_complete"] = true
	app.set("profile", test_profile)
	var legacy_settings := original_settings.duplicate(true)
	legacy_settings["auto_fire"] = false
	app.set("settings", legacy_settings)
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await process_frame
	await process_frame
	var session: Node = gameplay.get("session")

	gameplay.call("_unhandled_input", _action("combat_fire", true))
	_expect(_last_command(session) == "fire_started", "combat_fire action starts continuous fire when auto-fire is off")
	gameplay.call("_unhandled_input", _action("combat_fire", false))
	_expect(_last_command(session) == "fire_stopped", "combat_fire release stops continuous fire when auto-fire is off")

	var auto_settings := legacy_settings.duplicate(true)
	auto_settings["auto_fire"] = true
	app.set("settings", auto_settings)
	gameplay.call("_update_fire_source")
	_expect(_last_command(session) == "fire_started", "hover auto-fire starts firing over the battlefield without any button press")

	var selected_snapshot: Dictionary = gameplay.get("snapshot").duplicate(true)
	selected_snapshot["selected_skill"] = "fire_ball"
	gameplay.set("snapshot", selected_snapshot)
	gameplay.call("_update_fire_source")
	_expect(_last_command(session) == "fire_stopped", "selecting a spell pauses hover auto-fire")

	gameplay.call("_unhandled_input", _action("combat_fire", true))
	_expect(bool(gameplay.get("_cast_dragging")) and _last_command(session) == "fire_stopped", "left press with a selected spell begins the drag without casting")
	gameplay.call("_unhandled_input", _action("combat_fire", false))
	_expect(not bool(gameplay.get("_cast_dragging")) and _last_command(session) == "cast_skill", "releasing the drag casts at the pointer")

	gameplay.set("snapshot", selected_snapshot)
	gameplay.call("_unhandled_input", _action("combat_fire", true))
	gameplay.call("_unhandled_input", _action("combat_cancel_cast", true))
	var cancelled_command := _last_command(session)
	gameplay.call("_unhandled_input", _action("combat_fire", false))
	_expect(cancelled_command == "cancel_skill" and _last_command(session) == "cancel_skill", "cancel during drag aborts and the release does not cast")

	gameplay.call("_unhandled_input", _action("combat_select_ice", true))
	_expect(_last_command(session) == "select_skill", "combat_select_ice action selects the configured skill")

	selected_snapshot["selected_skill"] = ""
	gameplay.set("snapshot", selected_snapshot)
	gameplay.call("_update_fire_source")
	gameplay.call("_unhandled_input", _action("game_pause", true))
	_expect(paused and gameplay.get("_pause_overlay") != null and _last_command(session) == "fire_stopped", "game_pause action stops firing, opens the pause overlay and pauses the tree")
	gameplay.call("_resume_game")

	paused = false
	root.remove_child(gameplay)
	gameplay.free()
	app.set("profile", original_profile)
	app.set("settings", original_settings)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[INPUTMAP FAIL] " + failure)
	print("[INPUTMAP] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _action(action_name: StringName, pressed_value: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action_name
	event.pressed = pressed_value
	event.strength = 1.0 if pressed_value else 0.0
	return event


func _last_command(session: Node) -> String:
	var commands: Array = session.get("_pending_commands")
	return str(commands[-1].get("type", "")) if not commands.is_empty() else ""


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[INPUTMAP PASS] " + description)
	else:
		failures.append(description)
