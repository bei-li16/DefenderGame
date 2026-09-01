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
		_test_run_instance_identity(content.rules)
		_test_mana_rejection(content.rules)
		_test_skill_rejections_and_mana_bounds(content.rules)
		_test_fatal_blow_snapshot(content.rules)
		_test_defeat_priority(content.rules)
		_test_simultaneous_outcome_priority(content.rules)
		_test_failure_keeps_kill_reward(content.rules)
		_test_reward_idempotency()
		_test_reward_event_identity(content.rules)
		_test_upgrade_atomicity(content.rules)
		_test_data_driven_upgrade_effects(content.rules)
		_test_power_shot_resistance_and_boundary(content.rules)
		_test_migration()
		_test_current_schema_default_completion()
		_test_save_backup_recovery()
		_test_migration_backup_recovery()
		_test_replay_export()
		_test_bad_config_reports_path(content.rules)
		_test_missing_translation_reports_path(content.rules, content.localization)
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
	_expect(int(first["result"]["wave"]) == 1 and int(first["result"]["wave_total"]) == 1, "run result records current and total waves")
	_expect(str(first["result"]["reward_source"]) == "run_settlement" and not str(first["result"]["idempotency_key"]).is_empty(), "run result carries reward source and idempotency identity")


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


func _test_run_instance_identity(source_config: Dictionary) -> void:
	var first := RunModel.new()
	var second := RunModel.new()
	first.setup(source_config, "stage_001", 4444, {"upgrades": {}}, "run-instance-a")
	second.setup(source_config, "stage_001", 4444, {"upgrades": {}}, "run-instance-b")
	_expect(first.seed == second.seed and first.run_id != second.run_id and first.result()["idempotency_key"] != second.result()["idempotency_key"], "application-injected run identity keeps same-seed attempts independently rewardable")


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


func _test_skill_rejections_and_mana_bounds(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["player"]["mana_regen_interval_ticks"] = 1
	config["player"]["mana_regen_amount"] = 10
	var model := RunModel.new()
	model.setup(config, "stage_001", 100, {"upgrades": {}})
	var initial_mana := model.mana
	var invalid_events := model.step([
		{"type": "select_skill", "skill_id": "fire_ball"},
		{"type": "cast_skill", "x_milli": 0, "y_milli": 500000}
	])
	var invalid_rejected := false
	for event in invalid_events:
		invalid_rejected = invalid_rejected or (event["type"] == "skill_rejected" and event.get("reason", "") == "invalid_target")
	var mana_after_invalid := model.mana
	var valid_events := model.step([{"type": "cast_skill", "skill_id": "fire_ball", "x_milli": 1200000, "y_milli": 500000}])
	var cast_happened := false
	for event in valid_events:
		cast_happened = cast_happened or event["type"] == "skill_cast"
	var mana_after_cast := model.mana
	var cooldown_events := model.step([{"type": "cast_skill", "skill_id": "fire_ball", "x_milli": 1200000, "y_milli": 500000}])
	var cooldown_rejected := false
	for event in cooldown_events:
		cooldown_rejected = cooldown_rejected or (event["type"] == "skill_rejected" and event.get("reason", "") == "cooldown")
	model.mana = model.max_mana - 1
	model.step([])
	_expect(invalid_rejected and mana_after_invalid == initial_mana and model.max_mana == initial_mana, "invalid spell target is rejected without spending Mana")
	_expect(cast_happened and cooldown_rejected and mana_after_cast < initial_mana, "successful cast spends Mana and an immediate recast is rejected by cooldown")
	_expect(model.mana == model.max_mana, "Mana regeneration clamps at max_mana")


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


func _test_simultaneous_outcome_priority(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["world"]["enemy_y_min_milli"] = 500000
	config["world"]["enemy_y_max_milli"] = 500001
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 31337, {"upgrades": {}})
	for ignored in range(int(config["world"]["spawn_start_tick"])):
		model.step([])
	var enemy: Dictionary = model.enemies[0]
	enemy["x_milli"] = int(enemy["attack_x_milli"])
	enemy["attack_cooldown"] = 0
	enemy["attack_damage"] = model.wall_hp
	enemy["hp"] = 1
	enemy["armor"] = 0
	model.projectiles.append({
		"entity_id": 9001,
		"x_milli": enemy["x_milli"],
		"y_milli": enemy["y_milli"],
		"vx_milli": 0,
		"vy_milli": 0,
		"damage": 1,
		"fatal": false,
		"power": false,
		"collision_radius_milli": 1000,
		"age_ticks": 0
	})
	var events := model.step([])
	var run_end_count := 0
	for event in events:
		if event["type"] == "run_end":
			run_end_count += 1
	_expect(model.status == "defeat" and model.enemies.is_empty() and run_end_count == 1, "simultaneous last kill and wall loss deterministically resolves as defeat")


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
	var missing_identity := service.apply_run_reward(profile, {"coins": 999, "xp": 999})
	_expect(not bool(missing_identity.get("ok", false)) and int(missing_identity["profile"]["coins"]) == 0, "reward without run and ruleset identity is rejected")
	var long_profile := profile.duplicate(true)
	for run_number in range(205):
		long_profile = service.apply_run_reward(long_profile, {"run_id": "history-%d" % run_number, "reward_version": "v1", "coins": 1, "xp": 0})["profile"]
	var replayed_old_reward := service.apply_run_reward(long_profile, {"run_id": "history-0", "reward_version": "v1", "coins": 1000, "xp": 0})
	_expect(bool(replayed_old_reward.get("duplicate", false)) and int(replayed_old_reward["profile"]["coins"]) == 205, "old reward identity remains idempotent after more than 200 runs")


func _test_reward_event_identity(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["world"]["enemy_y_min_milli"] = 500000
	config["world"]["enemy_y_max_milli"] = 500001
	config["enemies"][0]["hp"] = 1
	config["enemies"][0]["armor"] = 0
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 1717, {"upgrades": {}})
	var rewards: Array[Dictionary] = []
	for current_tick in range(40):
		var commands: Array = []
		if current_tick == int(config["world"]["spawn_start_tick"]) - 1:
			commands = [
				{"type": "select_skill", "skill_id": "fire_ball"},
				{"type": "cast_skill", "x_milli": 1880000, "y_milli": 500000}
			]
		for event in model.step(commands):
			if event["type"] == "reward":
				rewards.append(event)
		if model.status != "running":
			break
	var complete := rewards.size() == 2
	for reward in rewards:
		complete = complete and not str(reward.get("source", "")).is_empty()
		complete = complete and not str(reward.get("reward_version", "")).is_empty()
		complete = complete and not str(reward.get("idempotency_key", "")).is_empty()
		complete = complete and reward.has("coins") and reward.has("xp")
	_expect(complete, "kill and clear rewards carry source, amounts, ruleset version and idempotency keys")


func _test_upgrade_atomicity(config: Dictionary) -> void:
	var service := UpgradeService.new()
	var poor_profile := {"coins": 0, "upgrades": {"strength": 0}}
	var rejected := service.purchase(poor_profile, config, "strength")
	_expect(not bool(rejected.get("ok", false)) and int(poor_profile["coins"]) == 0 and int(poor_profile["upgrades"]["strength"]) == 0, "failed upgrade purchase does not mutate profile")
	var funded_profile := {"coins": 500, "upgrades": {"strength": 0}}
	var purchased := service.purchase(funded_profile, config, "strength")
	_expect(bool(purchased.get("ok", false)) and int(purchased["profile"]["upgrades"]["strength"]) == 1 and int(funded_profile["upgrades"]["strength"]) == 0, "successful upgrade is atomic on a new profile")
	var prerequisite_config := config.duplicate(true)
	for definition in prerequisite_config["upgrades"]:
		if definition["id"] == "ice_mastery":
			definition["prerequisites"] = ["strength"]
	var blocked_profile := {"coins": 1000, "upgrades": {"strength": 0, "ice_mastery": 0}}
	var blocked := service.purchase(blocked_profile, prerequisite_config, "ice_mastery")
	blocked_profile["upgrades"]["strength"] = 1
	var allowed := service.purchase(blocked_profile, prerequisite_config, "ice_mastery")
	_expect(not bool(blocked.get("ok", false)) and bool(allowed.get("ok", false)), "upgrade prerequisites block and allow purchase atomically")


func _test_data_driven_upgrade_effects(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["weapons"][0]["fatal_chance_per_10000"] = 0
	config["weapons"][0]["power_shot_chance_per_10000"] = 0
	for definition in config["upgrades"]:
		if definition["id"] == "strength":
			definition["effect_per_level"] = 13
		if definition["id"] == "agility":
			definition["effect_per_level"] = 2
	var model := RunModel.new()
	model.setup(config, "stage_001", 9191, {"upgrades": {"strength": 2, "agility": 3}})
	model.step([{"type": "aim", "x_milli": 1500000, "y_milli": 555000}, {"type": "fire_started"}])
	var projectile: Dictionary = model.projectiles[0]
	_expect(int(projectile["damage"]) == int(config["weapons"][0]["damage"]) + 26 and model.fire_cooldown == 4, "Strength and Agility use configured per-level effects")


func _test_power_shot_resistance_and_boundary(source_config: Dictionary) -> void:
	var model := RunModel.new()
	model.setup(source_config, "stage_001", 5151, {"upgrades": {}})
	var enemy := {
		"entity_id": 1, "enemy_id": "test", "x_milli": 1000000, "y_milli": 500000,
		"hp": 100, "max_hp": 100, "armor": 0, "collision_radius_milli": 30000,
		"attack_x_milli": 350000, "tags": [], "knockback_resistance_permille": 500
	}
	model.enemies = [enemy]
	model.projectiles = [{
		"entity_id": 2, "x_milli": 1000000, "y_milli": 500000, "vx_milli": 0, "vy_milli": 0,
		"damage": 1, "fatal": false, "power": true, "collision_radius_milli": 1000, "age_ticks": 0
	}]
	var first_events: Array[Dictionary] = []
	model.call("_update_projectiles", first_events)
	var resisted_position := int(model.enemies[0]["x_milli"])
	model.enemies[0]["x_milli"] = int(source_config["world"]["enemy_spawn_x_milli"]) - 1000
	model.enemies[0]["knockback_resistance_permille"] = 0
	model.projectiles = [{
		"entity_id": 3, "x_milli": model.enemies[0]["x_milli"], "y_milli": 500000, "vx_milli": 0, "vy_milli": 0,
		"damage": 1, "fatal": false, "power": true, "collision_radius_milli": 1000, "age_ticks": 0
	}]
	var second_events: Array[Dictionary] = []
	model.call("_update_projectiles", second_events)
	var bounded_position := int(model.enemies[0]["x_milli"])
	_expect(resisted_position == 1035000 and bounded_position == int(source_config["world"]["enemy_spawn_x_milli"]), "Power Shot uses configured knockback resistance and world boundary")


func _test_migration() -> void:
	var old_envelope := {"schema_version": 1, "payload": {"coins": 12, "xp": 3, "upgrades": {}}}
	var migrated := SaveService.migrate_envelope(old_envelope)
	var payload: Dictionary = migrated.get("envelope", {}).get("payload", {})
	_expect(bool(migrated.get("ok", false)) and int(migrated["envelope"]["schema_version"]) == 3, "profile migrates v1 to v3")
	_expect(payload.has("reward_ledger") and payload.has("crystals"), "migration adds required fields")


func _test_current_schema_default_completion() -> void:
	var directory := "user://automated-default-completion-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	_delete_test_directory(absolute_directory)
	var service := SaveService.new(directory)
	service.save_profile({"coins": 12}, 1)
	var profile_defaults := {"coins": 0, "install_id": "new-install", "reward_ledger": [], "upgrades": {}, "tutorial_complete": false}
	var loaded_profile := service.load_profile(profile_defaults)
	service.save_settings({"language": "en_US"}, 1)
	var settings_defaults := {"language": "zh_CN", "quality": "medium", "ui_scale": 1.0}
	var loaded_settings := service.load_settings(settings_defaults)
	_expect(bool(loaded_profile.get("needs_save", false)) and str(loaded_profile["payload"]["install_id"]) == "new-install" and loaded_profile["payload"].has("reward_ledger"), "current-schema Profile fills newly required fields from Profile defaults")
	_expect(bool(loaded_settings.get("needs_save", false)) and str(loaded_settings["payload"]["quality"]) == "medium" and not loaded_settings["payload"].has("coins"), "Settings fill only Settings defaults without Profile fields")
	_delete_test_directory(absolute_directory)


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
	corrupt = null
	var recovered := service.load_profile({})
	_expect(bool(recovered.get("ok", false)) and bool(recovered.get("recovered", false)), "corrupt main profile recovers from backup: %s" % recovered)
	_expect(int(recovered.get("payload", {}).get("coins", 0)) == 10, "backup contains previous valid profile: %s" % recovered)
	var repair_save := service.save_profile(recovered.get("payload", {}), 1)
	var repaired := service.load_profile({})
	_expect(bool(repair_save.get("ok", false)) and bool(repaired.get("ok", false)) and str(repaired.get("source", "")) == "main" and not bool(repaired.get("recovered", false)), "saving the recovered payload repairs the main profile and prevents a recovery loop: %s / %s" % [repair_save, repaired])
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


func _test_missing_translation_reports_path(config: Dictionary, source_localization: Dictionary) -> void:
	var broken := source_localization.duplicate(true)
	broken["en_US"].erase("skill.fire")
	var errors := ContentValidator.validate_localization(broken, config)
	var found_path := false
	for error in errors:
		if str(error.get("field_path", "")) == "localization.en_US.skill.fire" and str(error.get("error_code", "")) == "missing_translation":
			found_path = true
	_expect(found_path, "missing translation reports the exact locale and key path")


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
