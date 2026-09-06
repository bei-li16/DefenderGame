extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")
const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

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
	var original_save_service: Variant = app.get("save_service")
	var test_directory := "user://save-slot-acceptance-test"
	var absolute_directory := ProjectSettings.globalize_path(test_directory)
	_delete_test_directory(absolute_directory)
	app.set("save_service", SaveService.new(test_directory))

	# Full bootstrap against an empty save directory: the active slot file must
	# materialize immediately and initialization must succeed.
	app.set("initialized_ok", false)
	app.call("initialize")
	_expect(bool(app.get("initialized_ok")), "initialization succeeds against an empty save directory")
	_expect(FileAccess.file_exists(test_directory + "/slot_1.json"), "the active slot file materializes on first launch")
	_expect(int(app.get("active_save_slot")) == 1, "a fresh install starts on slot 1")

	var updated: Dictionary = app.call("update_profile_field", "coins", 555)
	_expect(bool(updated.get("ok", false)), "a profile mutation persists into the active slot")

	var switch_result: Dictionary = app.call("switch_save_slot", 2)
	_expect(bool(switch_result.get("ok", false)), "switching to an empty slot succeeds")
	_expect(int(app.get("active_save_slot")) == 2, "the switched slot becomes active")
	_expect(int(app.get("profile").get("coins", 0)) == 180, "an empty slot starts a fresh profile")
	_expect(FileAccess.file_exists(test_directory + "/slot_2.json"), "the fresh slot file is written immediately")
	var persisted_settings: Dictionary = app.get("save_service").load_settings({})
	_expect(int(persisted_settings.get("payload", {}).get("active_save_slot", 0)) == 2, "the active slot choice persists in settings")

	app.call("update_profile_field", "coins", 777)
	var switch_back: Dictionary = app.call("switch_save_slot", 1)
	_expect(bool(switch_back.get("ok", false)) and int(app.get("profile").get("coins", 0)) == 555, "switching back restores the slot's own progress")

	var summaries: Array = app.call("save_slot_summaries")
	var coins_by_slot := {}
	for summary in summaries:
		coins_by_slot[int(summary.get("slot_id", 0))] = int(summary.get("coins", -1)) if bool(summary.get("exists", false)) else "empty"
	_expect(int(coins_by_slot.get(1, -2)) == 555 and int(coins_by_slot.get(2, -3)) == 777 and coins_by_slot.get(3, "x") == "empty", "slot summaries report each slot's career snapshot")

	# Playtime buffering: flushed seconds land in the active slot's stats only.
	app.set("_playtime_buffer", 45.0)
	var flush_result: Dictionary = app.call("_flush_playtime")
	var stats: Dictionary = app.get("profile").get("stats", {})
	_expect(bool(flush_result.get("ok", false)) and int(stats.get("playtime_seconds", 0)) >= 45 and int(stats.get("playtime_seconds", 0)) < 60, "buffered playtime flushes into the active save")
	app.call("switch_save_slot", 2)
	var slot_two_stats: Dictionary = app.get("profile").get("stats", {})
	_expect(int(slot_two_stats.get("playtime_seconds", 0)) < 45, "playtime stays inside the slot it accrued in")

	# Failure injection: a failed settings write must leave the old slot active.
	app.set("save_service", FailingSaveService.new())
	var failed_switch: Dictionary = app.call("switch_save_slot", 3)
	_expect(not bool(failed_switch.get("ok", false)), "a failed slot save is rejected")
	_expect(int(app.get("active_save_slot")) == 2 and int(app.get("profile").get("coins", 0)) == 777, "a failed switch leaves the current save untouched")
	app.set("save_service", SaveService.new(test_directory))

	# Menu page builds against the real summaries without script errors.
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	menu.call("_show_save_data")
	await process_frame
	var playtime_key: String = app.call("text", "saves.playtime")
	var found_playtime := false
	for label in menu.find_children("*", "Label", true, false):
		if label is Label and str(label.text).contains(playtime_key):
			found_playtime = true
			break
	_expect(found_playtime, "the save page renders career info including playtime")
	root.remove_child(menu)
	menu.free()

	# Legacy migration through the real bootstrap: profile.json is adopted by
	# slot 1 and re-saved as a slot file.
	var legacy_directory := "user://save-slot-acceptance-legacy"
	var legacy_absolute := ProjectSettings.globalize_path(legacy_directory)
	_delete_test_directory(legacy_absolute)
	var legacy_service := SaveService.new(legacy_directory)
	legacy_service.save_profile({"coins": 66, "xp": 5, "reward_ledger": [], "upgrades": {}}, 1)
	app.set("save_service", legacy_service)
	app.set("initialized_ok", false)
	app.call("initialize")
	_expect(bool(app.get("initialized_ok")) and int(app.get("profile").get("coins", 0)) == 66, "bootstrap adopts the legacy single-save profile")
	_expect(FileAccess.file_exists(legacy_directory + "/slot_1.json"), "the adopted legacy profile persists as slot 1")

	app.set("save_service", original_save_service)
	app.set("profile", original_profile)
	app.set("settings", original_settings)
	app.call("_apply_settings")
	_delete_test_directory(absolute_directory)
	_delete_test_directory(legacy_absolute)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[SLOT FAIL] " + failure)
	print("[SLOT] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[SLOT PASS] " + description)
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
