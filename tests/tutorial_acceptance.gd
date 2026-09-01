extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")

var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started_msec := Time.get_ticks_msec()
	var app := root.get_node_or_null("GameApp")
	if app == null:
		push_error("GameApp autoload is unavailable")
		quit(1)
		return
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var original_save_service: Variant = app.get("save_service")
	var original_stage: String = str(app.get("current_stage_id"))
	var original_seed: int = int(app.get("current_seed"))
	var test_directory := "user://tutorial-acceptance-test"
	var absolute_directory := ProjectSettings.globalize_path(test_directory)
	_delete_test_directory(absolute_directory)
	app.set("save_service", SaveService.new(test_directory))
	var test_profile := original_profile.duplicate(true)
	test_profile["tutorial_complete"] = false
	test_profile["highest_unlocked_stage"] = 1
	app.set("profile", test_profile)
	app.set("current_stage_id", "stage_001")
	app.set("current_seed", 1001)

	var gameplay_resource := load("res://scenes/gameplay.tscn") as PackedScene
	var gameplay := gameplay_resource.instantiate()
	root.add_child(gameplay)
	await process_frame
	await process_frame
	_expect(paused, "first-run tutorial pauses simulation while instructions are visible")
	var tutorial_panel: Control = gameplay.get("_tutorial_hint")
	_expect(tutorial_panel != null and tutorial_panel.is_visible_in_tree(), "tutorial panel is visible for a new profile")
	var continue_button := _find_button(tutorial_panel, str(app.call("text", "hud.resume")))
	_expect(continue_button != null, "tutorial exposes a clear continue action")
	if continue_button != null:
		continue_button.pressed.emit()
	await process_frame
	_expect(not paused, "closing tutorial resumes the fixed-tick session")

	var session: Node = gameplay.get("session")
	session.call("queue_command", {"type": "aim", "x_milli": 1500000, "y_milli": 520000})
	session.call("queue_command", {"type": "fire_started"})
	for ignored in range(12):
		await physics_frame
	var firing_snapshot: Dictionary = session.call("current_snapshot")
	_expect(firing_snapshot.get("projectiles", []).size() >= 2, "holding fire creates repeated arrows at the configured interval")
	session.call("queue_command", {"type": "fire_stopped"})
	await physics_frame
	var projectile_count_after_stop: int = int(session.call("current_snapshot").get("projectiles", []).size())
	for ignored in range(4):
		await physics_frame
	var projectile_count_later: int = int(session.call("current_snapshot").get("projectiles", []).size())
	_expect(projectile_count_later <= projectile_count_after_stop, "releasing fire stops creation of new arrows")

	session.call("queue_command", {"type": "select_skill", "skill_id": "fire_ball"})
	session.call("queue_command", {"type": "cast_skill", "skill_id": "fire_ball", "x_milli": 1200000, "y_milli": 520000})
	await physics_frame
	var cast_snapshot: Dictionary = session.call("current_snapshot")
	_expect(int(cast_snapshot.get("mana", 120)) < 120, "tutorial flow selects and casts a spell with Mana consumption")
	var elapsed_msec := Time.get_ticks_msec() - started_msec
	_expect(elapsed_msec < 60000, "aim, continuous fire and spell cast complete within 60 seconds (%d ms)" % elapsed_msec)

	paused = false
	root.remove_child(gameplay)
	gameplay.free()
	app.set("profile", original_profile)
	app.set("save_service", original_save_service)
	app.set("current_stage_id", original_stage)
	app.set("current_seed", original_seed)
	_delete_test_directory(absolute_directory)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[TUTORIAL FAIL] " + failure)
	print("[TUTORIAL] %d passed, %d failed, elapsed=%d ms" % [passes, failures.size(), elapsed_msec])
	quit(failures.size())


func _find_button(node: Node, expected_text: String) -> Button:
	if node is Button and (node as Button).text == expected_text:
		return node as Button
	for child in node.get_children():
		var result := _find_button(child, expected_text)
		if result != null:
			return result
	return null


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[TUTORIAL PASS] " + description)
	else:
		failures.append(description)


func _delete_test_directory(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var item := directory.get_next()
	while not item.is_empty():
		var item_path := absolute_path.path_join(item)
		if directory.current_is_dir():
			_delete_test_directory(item_path)
		else:
			DirAccess.remove_absolute(item_path)
		item = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
