extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var menu_scene := load("res://scenes/main_menu.tscn") as PackedScene
	var gameplay_scene := load("res://scenes/gameplay.tscn") as PackedScene
	for viewport_size in [Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440)]:
		await _check_scene(menu_scene, "MainMenu", viewport_size)
		await _check_scene(gameplay_scene, "Gameplay", viewport_size)
	for failure in failures:
		push_error("[LAYOUT FAIL] " + failure)
	print("[LAYOUT] 3 resolutions x 2 scenes checked; failures=%d" % failures.size())
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
	var out_of_bounds: Array[String] = []
	_collect_out_of_bounds(instance, Rect2(Vector2.ZERO, Vector2(1920, 1080)), out_of_bounds)
	if not out_of_bounds.is_empty():
		failures.append("%s at %dx%d: %s" % [scene_name, viewport_size.x, viewport_size.y, out_of_bounds])
	else:
		print("[LAYOUT PASS] %s %dx%d" % [scene_name, viewport_size.x, viewport_size.y])
	root.remove_child(viewport)
	viewport.free()


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
