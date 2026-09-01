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
	var original_settings: Dictionary = app.get("settings").duplicate(true)
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var original_save_service: Variant = app.get("save_service")
	var test_directory := "user://settings-acceptance-test"
	var absolute_directory := ProjectSettings.globalize_path(test_directory)
	_delete_test_directory(absolute_directory)
	app.set("save_service", SaveService.new(test_directory))
	var test_profile := original_profile.duplicate(true)
	test_profile["tutorial_complete"] = true
	app.set("profile", test_profile)

	app.call("update_setting", "quality", "low")
	var persisted: Dictionary = app.get("save_service").load_settings({})
	_expect(bool(persisted.get("ok", false)) and str(persisted.get("payload", {}).get("quality", "")) == "low", "quality change saves immediately")

	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await process_frame
	await process_frame

	app.call("update_setting", "quality", "low")
	var low: Dictionary = gameplay.call("_quality_profile")
	app.call("update_setting", "quality", "medium")
	var medium: Dictionary = gameplay.call("_quality_profile")
	app.call("update_setting", "quality", "high")
	var high: Dictionary = gameplay.call("_quality_profile")
	_expect(int(low["background_stones"]) < int(medium["background_stones"]) and int(medium["background_stones"]) < int(high["background_stones"]), "low, medium and high apply distinct background detail budgets")
	_expect(int(low["effect_limit"]) < int(medium["effect_limit"]) and int(medium["effect_limit"]) < int(high["effect_limit"]), "quality presets apply distinct transient effect budgets")
	_expect(float(low["effect_detail"]) < float(medium["effect_detail"]) and float(medium["effect_detail"]) < float(high["effect_detail"]), "quality presets apply distinct effect geometry detail")

	app.call("update_setting", "screen_shake", true)
	app.call("update_setting", "quality", "low")
	gameplay.call("_on_events", [{"type": "wall_damage", "amount": 1}])
	_expect(is_zero_approx(float(gameplay.get("_shake_strength"))), "low quality disables screen shake while retaining textual and audio feedback")
	app.call("update_setting", "quality", "high")
	gameplay.call("_on_events", [{"type": "wall_damage", "amount": 1}])
	_expect(float(gameplay.get("_shake_strength")) > 0.0, "high quality applies screen shake immediately")
	app.call("update_setting", "screen_shake", false)
	gameplay.call("_on_events", [{"type": "wall_damage", "amount": 1}])
	_expect(is_zero_approx(float(gameplay.get("_shake_strength"))), "screen shake toggle overrides the quality preset immediately")

	app.call("update_setting", "ui_scale", 1.25)
	_expect(is_equal_approx(root.content_scale_factor, 1.25), "UI scale applies immediately")

	root.remove_child(gameplay)
	gameplay.free()
	app.set("settings", original_settings)
	app.set("profile", original_profile)
	app.set("save_service", original_save_service)
	app.call("_apply_settings")
	_delete_test_directory(absolute_directory)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[SETTINGS FAIL] " + failure)
	print("[SETTINGS] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[SETTINGS PASS] " + description)
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
