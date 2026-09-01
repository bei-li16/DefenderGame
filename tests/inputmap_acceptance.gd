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
	var test_profile := original_profile.duplicate(true)
	test_profile["tutorial_complete"] = true
	app.set("profile", test_profile)
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await process_frame
	await process_frame
	var session: Node = gameplay.get("session")

	gameplay.call("_unhandled_input", _action("combat_fire", true))
	_expect(_last_command(session) == "fire_started", "combat_fire action starts continuous fire")
	gameplay.call("_unhandled_input", _action("combat_fire", false))
	_expect(_last_command(session) == "fire_stopped", "combat_fire release stops continuous fire")
	gameplay.call("_unhandled_input", _action("combat_select_ice", true))
	_expect(_last_command(session) == "select_skill", "combat_select_ice action selects the configured skill")

	var selected_snapshot: Dictionary = gameplay.get("snapshot").duplicate(true)
	selected_snapshot["selected_skill"] = "fire_ball"
	gameplay.set("snapshot", selected_snapshot)
	gameplay.call("_unhandled_input", _action("combat_cast", true))
	_expect(_last_command(session) == "cast_skill", "combat_cast action queues a targeted spell")
	gameplay.call("_unhandled_input", _action("combat_cancel_cast", true))
	_expect(_last_command(session) == "cancel_skill", "combat_cancel_cast action cancels targeting")

	selected_snapshot["selected_skill"] = ""
	gameplay.set("snapshot", selected_snapshot)
	gameplay.call("_unhandled_input", _action("game_pause", true))
	_expect(paused and gameplay.get("_pause_overlay") != null and _last_command(session) == "fire_stopped", "game_pause action stops firing, opens the pause overlay and pauses the tree")
	gameplay.call("_resume_game")

	paused = false
	root.remove_child(gameplay)
	gameplay.free()
	app.set("profile", original_profile)
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
