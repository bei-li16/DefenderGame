extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")

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
	if DisplayServer.get_name().contains("headless"):
		push_error("Window mode acceptance requires a real display server")
		quit(2)
		return
	var original_settings: Dictionary = app.get("settings").duplicate(true)
	var original_save_service: Variant = app.get("save_service")
	var test_directory := "user://window-mode-acceptance-test"
	var absolute_directory := ProjectSettings.globalize_path(test_directory)
	_delete_test_directory(absolute_directory)
	app.set("save_service", SaveService.new(test_directory))

	app.call("update_setting", "resolution", "1366x768")
	app.call("update_setting", "fullscreen", false)
	app.call("update_setting", "borderless", false)
	await create_timer(0.25).timeout
	_expect(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "windowed mode applies")
	_expect(not DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "windowed mode has a normal frame")

	app.call("update_setting", "borderless", true)
	await create_timer(0.25).timeout
	_expect(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "borderless setting remains a windowed mode")
	_expect(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS), "borderless window flag applies")

	app.call("update_setting", "borderless", false)
	app.call("update_setting", "fullscreen", true)
	await create_timer(0.35).timeout
	_expect(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen mode applies")

	app.call("update_setting", "fullscreen", false)
	app.call("update_setting", "resolution", "1920x1080")
	await create_timer(0.25).timeout
	var gameplay_resource := load("res://scenes/gameplay.tscn") as PackedScene
	var gameplay := gameplay_resource.instantiate()
	root.add_child(gameplay)
	await process_frame
	Input.warp_mouse(Vector2(960, 540))
	await process_frame
	var mapped_mouse: Vector2 = gameplay.get_global_mouse_position()
	_expect(mapped_mouse.distance_to(Vector2(960, 540)) <= 2.0, "viewport mouse position maps back to the same logical battlefield coordinate")
	_expect(root.content_scale_size == Vector2i(1920, 1080), "window modes preserve the 1920x1080 logical canvas")
	root.remove_child(gameplay)
	gameplay.free()

	app.set("settings", original_settings)
	app.call("_apply_settings")
	app.set("save_service", original_save_service)
	_delete_test_directory(absolute_directory)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[WINDOW FAIL] " + failure)
	print("[WINDOW] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[WINDOW PASS] " + description)
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
