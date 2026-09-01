extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")
const ContentValidator = preload("res://src/core/rules/content_validator.gd")
const DeterministicRng = preload("res://src/core/rules/deterministic_rng.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const UpgradeService = preload("res://src/application/upgrade_service.gd")
const SaveService = preload("res://src/application/save_service.gd")
const ReplayService = preload("res://src/application/replay_service.gd")

var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("[TEST] Aegis of Ember headless suite")
	var content := ContentService.new()
	var load_result := content.load_builtin()
	_expect(bool(load_result.get("ok", false)), "builtin content validates")
	if bool(load_result.get("ok", false)):
		_test_rng()
		_test_deterministic_run(content.rules)
		_test_mana_rejection(content.rules)
		_test_fatal_blow_snapshot(content.rules)
		_test_defeat_priority(content.rules)
		_test_failure_keeps_kill_reward(content.rules)
		_test_reward_idempotency()
		_test_upgrade_atomicity(content.rules)
		_test_migration()
		_test_save_backup_recovery()
		_test_migration_backup_recovery()
		_test_replay_export()
		_test_bad_config_reports_path(content.rules)
		_test_scene_smoke()
		_test_core_dependency_boundary()
		_test_offline_dependency_boundary()
	print("[TEST] %d passed, %d failed" % [passes, failures.size()])
	for failure in failures:
		push_error("[FAIL] " + failure)
	var app := root.get_node_or_null("GameApp")
	if app != null and app.get("audio") != null:
		app.get("audio").stop_all()
	quit(failures.size())


func _test_rng() -> void:
	var first := DeterministicRng.new(98765)
	var second := DeterministicRng.new(98765)
	var first_values: Array[int] = []
	var second_values: Array[int] = []
	for index in range(100):
		first_values.append(first.next_int())
		second_values.append(second.next_int())
	_expect(first_values == second_values, "fixed seed RNG repeats exactly")


func _test_deterministic_run(source_config: Dictionary) -> void:
	var first := _execute_tiny_victory(source_config, 424242)
	var second := _execute_tiny_victory(source_config, 424242)
	_expect(first["status"] == "victory", "tiny run reaches victory")
	_expect(first["hash"] == second["hash"], "fixed seed and commands produce identical event hash")
	_expect(int(first["result"]["coins"]) > 0, "victory includes kill and clear rewards")


func _execute_tiny_victory(source_config: Dictionary, run_seed: int) -> Dictionary:
	var config := source_config.duplicate(true)
	config["world"]["enemy_y_min_milli"] = 500000
	config["world"]["enemy_y_max_milli"] = 500001
	config["enemies"][0]["hp"] = 1
	config["enemies"][0]["armor"] = 0
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", run_seed, {"upgrades": {}})
	var event_log: Array = []
	for current_tick in range(1, 40):
		var commands: Array = []
		if current_tick == 24:
			commands = [
				{"type": "select_skill", "skill_id": "fire_ball"},
				{"type": "cast_skill", "x_milli": 1880000, "y_milli": 500000}
			]
		event_log.append_array(model.step(commands))
		if model.status != "running":
			break
	return {"status": model.status, "result": model.result(), "hash": EventHasher.hash_events(event_log)}


func _test_mana_rejection(source_config: Dictionary) -> void:
	var model := RunModel.new()
	model.setup(source_config, "stage_001", 99, {"upgrades": {}})
	model.mana = 0
	var events := model.step([
		{"type": "select_skill", "skill_id": "fire_ball"},
		{"type": "cast_skill", "x_milli": 1200000, "y_milli": 500000}
	])
	var rejected := false
	for event in events:
		if event["type"] == "skill_rejected" and event.get("reason", "") == "no_mana":
			rejected = true
	_expect(rejected and model.mana == 0, "insufficient Mana rejects cast without spending")


func _test_fatal_blow_snapshot(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["world"]["enemy_y_min_milli"] = 555000
	config["world"]["enemy_y_max_milli"] = 555001
	config["weapons"][0]["fatal_chance_per_10000"] = 10000
	config["weapons"][0]["power_shot_chance_per_10000"] = 0
	config["enemies"][0]["hp"] = 500
	config["enemies"][0]["armor"] = 0
	config["enemies"][0]["speed_milli_per_tick"] = 1
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 123, {"upgrades": {"strength": 0}})
	var fatal_shot := false
	var fatal_damage := 0
	for current_tick in range(80):
		var commands: Array = []
		if current_tick == 23:
			commands = [
				{"type": "aim", "x_milli": 1880000, "y_milli": 555000},
				{"type": "fire_started"},
				{"type": "fire_stopped"}
			]
		for event in model.step(commands):
			if event["type"] == "shot":
				fatal_shot = bool(event.get("fatal", false))
			if event["type"] == "damage" and event.get("source", "") == "arrow":
				fatal_damage = int(event.get("amount", 0))
		if fatal_damage > 0:
			break
	_expect(fatal_shot and fatal_damage == 68, "forced Fatal Blow snapshots exactly 2x arrow damage")


func _test_defeat_priority(source_config: Dictionary) -> void:
	var model := RunModel.new()
	model.setup(source_config, "stage_001", 7, {"upgrades": {}})
	model.debug_force_wall_damage(model.wall_max_hp)
	var events := model.step([])
	var run_end_count := 0
	for event in events:
		if event["type"] == "run_end":
			run_end_count += 1
	_expect(model.status == "defeat" and run_end_count == 1, "wall at zero resolves one defeat")
	_expect(model.step([]).is_empty(), "finished run cannot settle twice")


func _test_failure_keeps_kill_reward(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["world"]["enemy_y_min_milli"] = 500000
	config["world"]["enemy_y_max_milli"] = 500001
	config["enemies"][0]["hp"] = 1
	config["enemies"][0]["armor"] = 0
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 2, "interval_ticks": 100}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 8181, {"upgrades": {}})
	for current_tick in range(24):
		var commands: Array = []
		if current_tick == 23:
			commands = [
				{"type": "select_skill", "skill_id": "fire_ball"},
				{"type": "cast_skill", "x_milli": 1880000, "y_milli": 500000}
			]
		model.step(commands)
	model.debug_force_wall_damage(model.wall_max_hp)
	model.step([])
	var result := model.result()
	_expect(result["status"] == "defeat" and int(result["kills"]) == 1 and int(result["coins"]) == 7, "failed run keeps kill coins without clear reward")


func _test_reward_idempotency() -> void:
	var service := UpgradeService.new()
	var profile := {"coins": 0, "xp": 0, "reward_ledger": []}
	var reward := {"run_id": "run-one", "reward_version": "v1", "coins": 50, "xp": 10}
	var first := service.apply_run_reward(profile, reward)
	var second := service.apply_run_reward(first["profile"], reward)
	_expect(int(second["profile"]["coins"]) == 50 and bool(second["duplicate"]), "run reward is idempotent")


func _test_upgrade_atomicity(config: Dictionary) -> void:
	var service := UpgradeService.new()
	var poor_profile := {"coins": 0, "upgrades": {"strength": 0}}
	var rejected := service.purchase(poor_profile, config, "strength")
	_expect(not bool(rejected.get("ok", false)) and int(poor_profile["coins"]) == 0 and int(poor_profile["upgrades"]["strength"]) == 0, "failed upgrade purchase does not mutate profile")
	var funded_profile := {"coins": 500, "upgrades": {"strength": 0}}
	var purchased := service.purchase(funded_profile, config, "strength")
	_expect(bool(purchased.get("ok", false)) and int(purchased["profile"]["upgrades"]["strength"]) == 1 and int(funded_profile["upgrades"]["strength"]) == 0, "successful upgrade is atomic on a new profile")


func _test_migration() -> void:
	var old_envelope := {"schema_version": 1, "payload": {"coins": 12, "xp": 3, "upgrades": {}}}
	var migrated := SaveService.migrate_envelope(old_envelope)
	var payload: Dictionary = migrated.get("envelope", {}).get("payload", {})
	_expect(bool(migrated.get("ok", false)) and int(migrated["envelope"]["schema_version"]) == 3, "profile migrates v1 to v3")
	_expect(payload.has("reward_ledger") and payload.has("crystals"), "migration adds required fields")


func _test_save_backup_recovery() -> void:
	var directory := "user://automated-save-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		_delete_test_directory(absolute_directory)
	var service := SaveService.new(directory)
	var first_profile := {"coins": 10, "xp": 1, "reward_ledger": []}
	var second_profile := {"coins": 25, "xp": 2, "reward_ledger": []}
	var first_save := service.save_profile(first_profile, 1)
	var second_save := service.save_profile(second_profile, 1)
	_expect(bool(first_save.get("ok", false)) and bool(second_save.get("ok", false)), "profile saves with verified replacement: %s / %s" % [first_save, second_save])
	var main_path := directory + "/profile.json"
	var corrupt := FileAccess.open(main_path, FileAccess.WRITE)
	if corrupt != null:
		corrupt.store_string("{broken")
		corrupt.flush()
	var recovered := service.load_profile({})
	_expect(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)), "corrupt main profile recovers from backup: %s" % recovered)
	_expect(int(recovered.get("payload", {}).get("coins", 0)) == 10, "backup contains previous valid profile: %s" % recovered)
	_delete_test_directory(absolute_directory)


func _test_migration_backup_recovery() -> void:
	var directory := "user://automated-migration-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		_delete_test_directory(absolute_directory)
	var service := SaveService.new(directory)
	service.save_profile({"coins": 31, "xp": 4, "reward_ledger": []}, 1)
	service.save_profile({"coins": 99, "xp": 8, "reward_ledger": []}, 1)
	var main_path := directory + "/profile.json"
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(main_path))
	envelope["schema_version"] = 99
	var rewritten := FileAccess.open(main_path, FileAccess.WRITE)
	if rewritten != null:
		rewritten.store_string(JSON.stringify(envelope, "  ", true))
		rewritten.flush()
	var recovered := service.load_profile({})
	_expect(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)), "unsupported main schema falls back to valid backup")
	_expect(int(recovered.get("payload", {}).get("coins", 0)) == 31, "migration fallback preserves previous profile")
	_delete_test_directory(absolute_directory)


func _test_replay_export() -> void:
	var directory := "user://automated-replay-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		_delete_test_directory(absolute_directory)
	var service := ReplayService.new(directory)
	var record := {"run_id": "test-run", "stage_id": "stage_001", "seed": 42, "commands": [{"type": "fire_started"}], "event_hash": "abc123"}
	var exported := service.export_record(record, "golden")
	var loaded := service.load_record(str(exported.get("path", "")))
	_expect(bool(exported.get("ok", false)) and bool(loaded.get("ok", false)) and loaded.get("record", {}).get("event_hash", "") == "abc123", "debug replay record exports and reloads")
	_delete_test_directory(absolute_directory)


func _test_bad_config_reports_path(source_config: Dictionary) -> void:
	var broken := source_config.duplicate(true)
	broken["enemies"][1]["id"] = broken["enemies"][0]["id"]
	var errors := ContentValidator.validate(broken)
	var found_path := false
	for error in errors:
		if str(error.get("field_path", "")) == "enemies[1].id" and str(error.get("error_code", "")) == "duplicate_id":
			found_path = true
	_expect(found_path, "bad content reports the exact duplicate field path")


func _test_scene_smoke() -> void:
	var menu_resource := load("res://scenes/main_menu.tscn") as PackedScene
	var gameplay_resource := load("res://scenes/gameplay.tscn") as PackedScene
	_expect(menu_resource != null and gameplay_resource != null, "main menu and gameplay scenes load")
	if menu_resource != null:
		var menu := menu_resource.instantiate()
		root.add_child(menu)
		_expect(menu.get_node_or_null(".") != null, "main menu scene instantiates")
		root.remove_child(menu)
		menu.free()
	if gameplay_resource != null:
		var gameplay := gameplay_resource.instantiate()
		root.add_child(gameplay)
		_expect(gameplay.get("session") != null, "gameplay scene creates application session")
		root.remove_child(gameplay)
		gameplay.free()


func _test_core_dependency_boundary() -> void:
	var violations: Array[String] = []
	var files := _collect_gd_files("res://src/core")
	for path in files:
		var file := FileAccess.open(path, FileAccess.READ)
		var source := file.get_as_text() if file != null else ""
		for forbidden in ["extends Node", "get_tree(", "Input.", "FileAccess", "AudioServer", "Time."]:
			if source.contains(forbidden):
				violations.append(path + " -> " + forbidden)
	_expect(violations.is_empty(), "core has no SceneTree/Input/FileAccess/Audio/Time dependencies: " + str(violations))


func _test_offline_dependency_boundary() -> void:
	var violations: Array[String] = []
	for path in _collect_gd_files("res://src"):
		var file := FileAccess.open(path, FileAccess.READ)
		var source := file.get_as_text() if file != null else ""
		for forbidden in ["HTTPRequest", "HTTPClient", "WebSocketPeer", "StreamPeerTCP", "ENetMultiplayerPeer"]:
			if source.contains(forbidden):
				violations.append(path + " -> " + forbidden)
	_expect(violations.is_empty(), "production scripts contain no network client dependencies: " + str(violations))


func _collect_gd_files(directory_path: String) -> Array[String]:
	var output: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return output
	directory.list_dir_begin()
	var item := directory.get_next()
	while not item.is_empty():
		var full_path := directory_path + "/" + item
		if directory.current_is_dir():
			output.append_array(_collect_gd_files(full_path))
		elif item.ends_with(".gd"):
			output.append(full_path)
		item = directory.get_next()
	directory.list_dir_end()
	return output


func _delete_test_directory(absolute_path: String) -> void:
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


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[PASS] " + description)
	else:
		failures.append(description)
