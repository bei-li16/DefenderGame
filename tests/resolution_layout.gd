extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	var gameplay_scene := load("res://scenes/gameplay.tscn") as PackedScene
	var app := root.get_node("GameApp")
	var original_settings: Dictionary = app.get("settings").duplicate(true)
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var layout_profile := original_profile.duplicate(true)
	layout_profile["tutorial_complete"] = true
	layout_profile["highest_unlocked_stage"] = 10
	app.set("profile", layout_profile)
	for locale in ["zh_CN", "en_US"]:
		var localized_settings := original_settings.duplicate(true)
		localized_settings["language"] = locale
		app.set("settings", localized_settings)
		for viewport_size in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
			await _check_scene(menu_scene, "MainMenu-%s" % locale, viewport_size)
			await _check_scene(gameplay_scene, "Gameplay-%s" % locale, viewport_size)
	app.set("settings", original_settings)
	app.set("profile", original_profile)
	for failure in failures:
		push_error("[LAYOUT FAIL] " + failure)
	print("[LAYOUT] 2 locales x 3 resolutions x menu/gameplay states checked; failures=%d" % failures.size())
	quit(failures.size())


func _check_scene(scene: PackedScene, scene_name: String, viewport_size: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	var instance := scene.instantiate()
	viewport.add_child(instance)
	await process_frame
	await process_frame
	_check_current_view(instance, scene_name + "-initial", viewport_size)
	if scene_name.begins_with("MainMenu"):
		for view in [
			["_show_stage_select", "stage-select"],
			["_show_upgrades", "upgrades"],
			["_show_research_page", "magic-research", "magic"],
			["_show_settings", "settings"],
			["_show_tutorial", "tutorial"]
		]:
			if view.size() == 3:
				instance.call(view[0], view[2])
			else:
				instance.call(view[0])
			await process_frame
			_check_current_view(instance, scene_name + "-" + view[1], viewport_size)
			if view[1] == "magic-research":
				for skill in root.get_node("GameApp").get("content").rules.get("skills", []):
					var research_button := instance.find_child("Research_" + str(skill["upgrade_id"]), true, false) as Button
					if research_button != null:
						research_button.pressed.emit()
						await process_frame
						_check_current_view(instance, scene_name + "-magic-" + str(skill["id"]), viewport_size)
			if view[1] == "upgrades":
				for definition in root.get_node("GameApp").get("content").rules.get("upgrades", []):
					if str(definition.get("page", "")) == "attack":
						var research_button := instance.find_child("Research_" + str(definition["id"]), true, false) as Button
						if research_button != null:
							research_button.pressed.emit()
							await process_frame
							_check_current_view(instance, scene_name + "-attack-" + str(definition["id"]), viewport_size)
	else:
		instance.call("_show_pause")
		await process_frame
		_check_current_view(instance, scene_name + "-pause", viewport_size)
		instance.call("_show_quick_settings")
		await process_frame
		_check_current_view(instance, scene_name + "-quick-settings", viewport_size)
		instance.call("_resume_game")
		instance.call("_show_result", {
			"status": "victory", "stage_number": 9, "wave": 3, "wave_total": 3,
			"kills": 59, "wall_percent": 87, "coins": 928, "xp": 273
		})
		await process_frame
		_check_current_view(instance, scene_name + "-result", viewport_size)
		_check_result_actions(instance, scene_name + "-victory-result", true)
		var victory_overlay := instance.get("_result_overlay") as Control
		victory_overlay.free()
		instance.set("_result_overlay", null)
		instance.call("_show_result", {
			"status": "defeat", "stage_number": 8, "wave": 2, "wave_total": 2,
			"kills": 4, "wall_percent": 0, "coins": 32, "xp": 8
		}, {"ok": true})
		await process_frame
		_check_current_view(instance, scene_name + "-defeat-result", viewport_size)
		_check_result_actions(instance, scene_name + "-defeat-result", false)
	paused = false
	root.remove_child(viewport)
	viewport.free()


func _check_current_view(instance: Node, view_name: String, viewport_size: Vector2i) -> void:
	var out_of_bounds: Array[String] = []
	_collect_out_of_bounds(instance, Rect2(Vector2.ZERO, Vector2(1920, 1080)), out_of_bounds)
	if not out_of_bounds.is_empty():
		failures.append("%s at %dx%d: %s" % [view_name, viewport_size.x, viewport_size.y, out_of_bounds])
	else:
		print("[LAYOUT PASS] %s %dx%d" % [view_name, viewport_size.x, viewport_size.y])


func _check_result_actions(instance: Node, view_name: String, victory: bool) -> void:
	var app := instance.get_tree().root.get_node("GameApp")
	var overlay := instance.get("_result_overlay") as Control
	var stack := overlay.get_meta("stack") as VBoxContainer
	var actions := stack.get_child(stack.get_child_count() - 1) as HBoxContainer
	var expected_count := 3 if victory else 2
	_expect(actions.get_child_count() == expected_count, "%s exposes %d result actions" % [view_name, expected_count])
	if actions.get_child_count() < 2:
		return
	var restart := actions.get_child(0) as Button
	var menu := actions.get_child(1) as Button
	_expect(restart.text == app.call("text", "hud.restart"), "%s exposes restart action" % view_name)
	_expect(menu.text == app.call("text", "hud.main_menu"), "%s exposes main-menu action" % view_name)
	for child in actions.get_children():
		var button := child as Button
		_expect(button != null and button.process_mode == Node.PROCESS_MODE_ALWAYS, "%s keeps result buttons input-active" % view_name)
	_expect(not paused, "%s leaves the scene unpaused" % view_name)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)


func _collect_out_of_bounds(node: Node, bounds: Rect2, output: Array[String], inside_scroll: bool = false) -> void:
	var now_inside_scroll := inside_scroll or node is ScrollContainer
	if node is Control and node.is_visible_in_tree() and not now_inside_scroll:
		var control := node as Control
		var rect := control.get_global_rect()
		if rect.size.x > 1.0 and rect.size.y > 1.0:
			var tolerance := 2.0
			if rect.position.x < -tolerance or rect.position.y < -tolerance or rect.end.x > bounds.end.x + tolerance or rect.end.y > bounds.end.y + tolerance:
				output.append("%s rect=%s" % [control.get_path(), rect])
	for child in node.get_children():
		_collect_out_of_bounds(child, bounds, output, now_inside_scroll)
