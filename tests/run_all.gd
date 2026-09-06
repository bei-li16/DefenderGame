extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")
const ContentValidator = preload("res://src/core/rules/content_validator.gd")
const DeterministicRng = preload("res://src/core/rules/deterministic_rng.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const GameSession = preload("res://src/application/game_session.gd")
const UpgradeService = preload("res://src/application/upgrade_service.gd")
const SaveService = preload("res://src/application/save_service.gd")
const ReplayService = preload("res://src/application/replay_service.gd")
const HonorService = preload("res://src/application/honor_service.gd")
const Progression = preload("res://src/core/rules/progression.gd")

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
		_test_wall_zero_stops_same_tick_damage(content.rules)
		_test_simultaneous_outcome_priority(content.rules)
		_test_failure_keeps_kill_reward(content.rules)
		_test_reward_idempotency()
		_test_reward_ledger_cap()
		_test_reward_event_identity(content.rules)
		_test_boss_slain_diagnostic(content.rules)
		_test_upgrade_atomicity(content.rules)
		_test_data_driven_upgrade_effects(content.rules)
		_test_status_resistance_floor_from_config(content.rules)
		_test_aim_command_coalescing(content.rules)
		_test_power_shot_resistance_and_boundary(content.rules)
		_test_weapon_variants(content.rules)
		_test_hurricane_velocity_consistency(content.rules)
		_test_defenses(content.rules)
		_test_frost_nova_freezes_defenses(content.rules)
		_test_extended_upgrade_effects(content.rules)
		_test_weapon_switch_keeps_upgrades(content.rules)
		_test_progression_and_battle_record(content.rules)
		_test_event_position_anchor_contract(content.rules)
		_test_migration()
		_test_hashless_legacy_load()
		_test_current_schema_default_completion()
		_test_save_backup_recovery()
		_test_corrupt_copy_uniqueness()
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


func _test_reward_ledger_cap() -> void:
	var service := UpgradeService.new()
	var profile := {"coins": 0, "xp": 0, "reward_ledger": [], "reward_ledger_pruned": 0}
	for run_number in range(520):
		profile = service.apply_run_reward(profile, {"run_id": "cap-%d" % run_number, "reward_version": "v1", "coins": 1, "xp": 0})["profile"]
	var ledger: Array = profile["reward_ledger"]
	_expect(ledger.size() == 520 and int(profile["reward_ledger_pruned"]) == 0, "reward ledger is permanent: every settled key is retained")
	var replayed_recent := service.apply_run_reward(profile, {"run_id": "cap-519", "reward_version": "v1", "coins": 1, "xp": 0})
	_expect(bool(replayed_recent.get("duplicate", false)) and int(replayed_recent["profile"]["coins"]) == 520, "recent reward identity remains idempotent")
	var replayed_oldest := service.apply_run_reward(profile, {"run_id": "cap-0", "reward_version": "v1", "coins": 1, "xp": 0})
	_expect(bool(replayed_oldest.get("duplicate", false)) and int(replayed_oldest["profile"]["coins"]) == 520, "oldest reward identity remains idempotent permanently")


func _test_boss_slain_diagnostic(source_config: Dictionary) -> void:
	var plain := _execute_tiny_victory(source_config, 424242)
	_expect(not bool(plain["result"].get("boss_slain", true)), "boss-free victory reports boss_slain false")
	var config := source_config.duplicate(true)
	config["stages"][0]["groups"] = [{"enemy_id": "ember_warlord", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 606, {"upgrades": {}})
	var guard := 0
	while model.enemies.is_empty() and guard < 60:
		model.step([])
		guard += 1
	if model.enemies.is_empty():
		_expect(false, "boss spawned for the boss_slain diagnostic check")
		return
	var boss: Dictionary = model.enemies[0]
	model.projectiles.append({
		"entity_id": 9001, "x_milli": int(boss["x_milli"]), "y_milli": int(boss["y_milli"]),
		"vx_milli": 0, "vy_milli": 0, "damage": 99999, "fatal": false, "power": false,
		"collision_radius_milli": 1000, "age_ticks": 0
	})
	model.step([])
	_expect(model.status == "victory" and bool(model.result().get("boss_slain", false)), "boss kill is reported in the run result and settles victory once")
	_expect(model.step([]).is_empty(), "finished boss run cannot settle twice")


func _test_status_resistance_floor_from_config(source_config: Dictionary) -> void:
	var capped_config := source_config.duplicate(true)
	capped_config["skills"][0]["burn_duration_ticks"] = 1000
	var capped_ticks := _burn_ticks_after_fire(capped_config, 999)
	var open_config := source_config.duplicate(true)
	open_config["skills"][0]["burn_duration_ticks"] = 1000
	open_config["rules"] = {"status_resistance_floor_permille": 0}
	var open_ticks := _burn_ticks_after_fire(open_config, 999)
	_expect(capped_ticks == 50 and open_ticks == 1000, "status resistance floor comes from configuration")


func _burn_ticks_after_fire(config: Dictionary, resistance: int) -> int:
	var model := RunModel.new()
	model.setup(config, "stage_001", 5150, {"upgrades": {}})
	var guard := 0
	while model.enemies.is_empty() and guard < 60:
		model.step([])
		guard += 1
	if model.enemies.is_empty():
		return -1
	model.enemies[0]["status_resistance_permille"] = resistance
	var ticks := -1
	for event in model.step([
		{"type": "select_skill", "skill_id": "fire_ball"},
		{"type": "cast_skill", "x_milli": int(model.enemies[0]["x_milli"]), "y_milli": int(model.enemies[0]["y_milli"])}
	]):
		if event["type"] == "status" and event.get("status", "") == "burn":
			ticks = int(event.get("ticks", -1))
	return ticks


func _test_aim_command_coalescing(source_config: Dictionary) -> void:
	var session := GameSession.new()
	var start_result := session.start(source_config, "stage_001", 2718, {"upgrades": {}})
	_expect(bool(start_result.get("ok", false)), "application session starts for the aim coalescing check")
	session.queue_command({"type": "aim", "x_milli": 1000000, "y_milli": 400000})
	session.queue_command({"type": "aim", "x_milli": 1500000, "y_milli": 500000})
	var pending: Array = session.get("_pending_commands")
	_expect(pending.size() == 1 and session.get("_command_log").size() == 1 and int(pending[0]["x_milli"]) == 1500000, "same-window aim commands coalesce to the latest target")
	session.queue_command({"type": "fire_started"})
	_expect(session.get("_pending_commands").size() == 2 and str(session.get("_pending_commands")[0]["type"]) == "aim" and str(session.get("_pending_commands")[1]["type"]) == "fire_started", "non-aim commands keep their order after a coalesced aim")
	session.free()


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


func _test_weapon_variants(source_config: Dictionary) -> void:
	var hurricane_model := RunModel.new()
	hurricane_model.setup(source_config, "stage_001", 7001, {"current_weapon_id": "hurricane_bow", "unlocked_weapons": ["basic_bow", "hurricane_bow"], "upgrades": {}})
	_expect(hurricane_model.weapon_id == "hurricane_bow", "selected unlocked weapon equips for the run")
	var volley_events := hurricane_model.step([
		{"type": "aim", "x_milli": 1500000, "y_milli": 540000},
		{"type": "fire_started"},
		{"type": "fire_stopped"}
	])
	var volley_shots := 0
	for event in volley_events:
		if str(event.get("type", "")) == "shot":
			volley_shots += 1
	_expect(volley_shots == 3 and hurricane_model.projectiles.size() == 3, "hurricane bow fires a three-arrow volley per shot")

	var locked_model := RunModel.new()
	locked_model.setup(source_config, "stage_001", 7002, {"current_weapon_id": "phantom_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {}})
	_expect(locked_model.weapon_id == "basic_bow", "locked weapon selection falls back to the basic bow")

	var pierce_model := RunModel.new()
	pierce_model.setup(source_config, "stage_001", 7003, {"current_weapon_id": "phantom_bow", "unlocked_weapons": ["basic_bow", "phantom_bow"], "upgrades": {}})
	var spawn_guard := 0
	while pierce_model.enemies.is_empty() and spawn_guard < 60:
		pierce_model.step([])
		spawn_guard += 1
	var stack_template: Dictionary = pierce_model.enemies[0].duplicate(true)
	pierce_model.enemies.clear()
	for stack_index in range(3):
		var copy: Dictionary = stack_template.duplicate(true)
		copy["entity_id"] = 9000 + stack_index
		copy["x_milli"] = 1500000
		copy["y_milli"] = 555000
		copy["hp"] = 10
		copy["max_hp"] = 10
		copy["speed_milli_per_tick"] = 0
		copy["attack_x_milli"] = 1500000
		copy["attack_damage"] = 0
		pierce_model.enemies.append(copy)
	var pierce_events: Array = []
	pierce_events.append_array(pierce_model.step([
		{"type": "aim", "x_milli": 1500000, "y_milli": 555000},
		{"type": "fire_started"},
		{"type": "fire_stopped"}
	]))
	for flight_tick in range(40):
		if pierce_model.status != "running" or pierce_model.projectiles.is_empty():
			break
		pierce_events.append_array(pierce_model.step([]))
	var pierce_deaths := 0
	for event in pierce_events:
		if str(event.get("type", "")) == "death":
			pierce_deaths += 1
	_expect(pierce_deaths == 3, "phantom bow pierces through stacked enemies instead of stopping at the first")


func _test_hurricane_velocity_consistency(source_config: Dictionary) -> void:
	var expected_speed := 0
	for candidate in source_config.get("weapons", []):
		if candidate is Dictionary and str(candidate.get("id", "")) == "hurricane_bow":
			expected_speed = int(candidate.get("projectile_speed_milli_per_tick", 0))
			break
	if expected_speed <= 0:
		_expect(false, "hurricane bow config exposes a positive projectile speed")
		return
	var model := RunModel.new()
	model.setup(source_config, "stage_001", 7004, {"current_weapon_id": "hurricane_bow", "unlocked_weapons": ["basic_bow", "hurricane_bow"], "upgrades": {}})
	# Use a steep aim vector so each spread arrow has a different normalizing
	# divisor.  A centre-vector divisor reused for all arrows would make the
	# outer arrows visibly faster/slower than the configured projectile speed.
	model.step([
		{"type": "aim", "x_milli": 300000, "y_milli": 200000},
		{"type": "fire_started"},
		{"type": "fire_stopped"}
	])
	var consistent := model.projectiles.size() == 3
	var distinct_directions := true
	var vertical_components: Array[int] = []
	for projectile in model.projectiles:
		var vx := float(projectile.get("vx_milli", 0))
		var vy := float(projectile.get("vy_milli", 0))
		var magnitude := sqrt(vx * vx + vy * vy)
		# Integer component quantization can introduce a sub-unit error.
		if absf(magnitude - float(expected_speed)) > 2.0:
			consistent = false
		var vertical := int(projectile.get("vy_milli", 0))
		if vertical_components.has(vertical):
			distinct_directions = false
		vertical_components.append(vertical)
	_expect(consistent and distinct_directions, "hurricane volley keeps every arrow at configured speed across distinct spread directions")


func _test_wall_zero_stops_same_tick_damage(source_config: Dictionary) -> void:
	var model := RunModel.new()
	model.setup(source_config, "stage_001", 7005, {"upgrades": {}})
	var spawn_guard := 0
	while model.enemies.is_empty() and spawn_guard < 60:
		model.step([])
		spawn_guard += 1
	if model.enemies.is_empty():
		_expect(false, "wall-zero regression can obtain an enemy fixture")
		return
	var template: Dictionary = model.enemies[0].duplicate(true)
	model.enemies.clear()
	model.projectiles.clear()
	model.spawn_queue.clear()
	model.spawn_cursor = 0
	for index in range(2):
		var enemy: Dictionary = template.duplicate(true)
		enemy["entity_id"] = 9000 + index
		enemy["hp"] = 100
		enemy["max_hp"] = 100
		enemy["x_milli"] = int(enemy.get("attack_x_milli", 350000))
		enemy["speed_milli_per_tick"] = 0
		enemy["attack_damage"] = 5
		enemy["attack_interval_ticks"] = 1
		enemy["attack_cooldown"] = 0
		enemy["tags"] = []
		enemy["special_interval_ticks"] = 0
		model.enemies.append(enemy)
	model.wall_max_hp = 5
	model.wall_hp = 5
	var events := model.step([])
	var wall_damage_events := 0
	var total_damage := 0
	for event in events:
		if str(event.get("type", "")) == "wall_damage":
			wall_damage_events += 1
			total_damage += int(event.get("amount", 0))
	_expect(model.status == "defeat" and wall_damage_events == 1 and total_damage == 5, "wall reaching zero stops additional same-tick enemy attacks")


func _test_defenses(source_config: Dictionary) -> void:
	var idle_model := RunModel.new()
	idle_model.setup(source_config, "stage_001", 7100, {"upgrades": {}})
	var idle_guard := 0
	while idle_model.enemies.is_empty() and idle_guard < 60:
		idle_model.step([])
		idle_guard += 1
	idle_model.enemies[0]["x_milli"] = 400000
	idle_model.enemies[0]["speed_milli_per_tick"] = 0
	idle_model.enemies[0]["attack_x_milli"] = 400000
	var idle_events: Array[Dictionary] = []
	idle_model.call("_update_defenses", idle_events)
	var idle_attacks := 0
	for event in idle_events:
		if str(event.get("type", "")) == "defense_attack":
			idle_attacks += 1
	_expect(idle_attacks == 0, "defenses stay inactive without research levels")

	var defense_model := RunModel.new()
	defense_model.setup(source_config, "stage_001", 7101, {"upgrades": {"lava_moat": 1, "magic_tower": 1}})
	var defense_guard := 0
	while defense_model.enemies.is_empty() and defense_guard < 60:
		defense_model.step([])
		defense_guard += 1
	defense_model.enemies[0]["x_milli"] = 400000
	defense_model.enemies[0]["y_milli"] = 555000
	defense_model.enemies[0]["speed_milli_per_tick"] = 0
	defense_model.enemies[0]["attack_x_milli"] = 400000
	defense_model.enemies[0]["hp"] = 1000
	defense_model.enemies[0]["max_hp"] = 1000
	var hp_before := int(defense_model.enemies[0]["hp"])
	var defense_events: Array[Dictionary] = []
	defense_model.call("_update_defenses", defense_events)
	var moat_fired := false
	var tower_fired := false
	for event in defense_events:
		if str(event.get("type", "")) == "defense_attack":
			if str(event.get("defense_id", "")) == "lava_moat":
				moat_fired = true
			if str(event.get("defense_id", "")) == "magic_tower":
				tower_fired = true
	_expect(moat_fired and tower_fired, "researched lava moat and magic tower both strike an enemy in range")
	_expect(int(defense_model.enemies[0]["hp"]) < hp_before and int(defense_model.enemies[0].get("burn_ticks", 0)) > 0, "lava moat damages and ignites the target")
	var second_events: Array[Dictionary] = []
	defense_model.call("_update_defenses", second_events)
	var second_attacks := 0
	for event in second_events:
		if str(event.get("type", "")) == "defense_attack":
			second_attacks += 1
	_expect(second_attacks == 0, "defense cooldown blocks an immediate second strike")


func _test_frost_nova_freezes_defenses(source_config: Dictionary) -> void:
	var config := source_config.duplicate(true)
	config["stages"][0]["groups"] = [{"enemy_id": "frost_titan", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(config, "stage_001", 7200, {"upgrades": {"lava_moat": 1}})
	var nova_seen := false
	var nova_guard := 0
	while nova_guard < 400 and model.status == "running" and not nova_seen:
		for event in model.step([]):
			if str(event.get("type", "")) == "boss_special" and str(event.get("special", "")) == "frost_nova":
				nova_seen = true
		nova_guard += 1
	_expect(nova_seen, "frost titan casts frost nova during the run")
	_expect(int(model.get("defense_cooldowns")["lava_moat"]) >= 90, "frost nova freezes the player's defenses instead of helping its allies")


func _test_extended_upgrade_effects(source_config: Dictionary) -> void:
	var mana_model := RunModel.new()
	mana_model.setup(source_config, "stage_001", 7300, {"upgrades": {"mana_capacity": 8}})
	var mana_base := RunModel.new()
	mana_base.setup(source_config, "stage_001", 7301, {"upgrades": {}})
	_expect(mana_model.max_mana == mana_base.max_mana + 8 * 10, "mana capacity research raises max Mana")

	var armor_model := RunModel.new()
	armor_model.setup(source_config, "stage_001", 7302, {"upgrades": {"wall_armor": 10}})
	var armor_guard := 0
	while armor_model.enemies.is_empty() and armor_guard < 60:
		armor_model.step([])
		armor_guard += 1
	armor_model.enemies[0]["x_milli"] = int(armor_model.enemies[0]["attack_x_milli"])
	armor_model.enemies[0]["speed_milli_per_tick"] = 0
	armor_model.enemies[0]["attack_damage"] = 10
	armor_model.enemies[0]["attack_cooldown"] = 0
	var armor_events := armor_model.step([])
	var armor_amount := -1
	for event in armor_events:
		if str(event.get("type", "")) == "wall_damage":
			armor_amount = int(event.get("amount", -1))
	_expect(armor_amount == 0 and armor_model.wall_hp == armor_model.wall_max_hp, "wall armor research absorbs the full incoming hit")

	var bounty_model := RunModel.new()
	bounty_model.setup(source_config, "stage_001", 7303, {"upgrades": {"coin_bounty": 10}})
	var bounty_guard := 0
	while bounty_model.enemies.is_empty() and bounty_guard < 60:
		bounty_model.step([])
		bounty_guard += 1
	var bounty_enemy: Dictionary = bounty_model.enemies[0]
	bounty_enemy["hp"] = 1
	bounty_enemy["speed_milli_per_tick"] = 0
	bounty_enemy["attack_x_milli"] = int(bounty_enemy["x_milli"])
	bounty_model.projectiles.append({
		"entity_id": 9500, "x_milli": int(bounty_enemy["x_milli"]), "y_milli": int(bounty_enemy["y_milli"]),
		"vx_milli": 0, "vy_milli": 0, "damage": 5, "fatal": false, "power": false,
		"collision_radius_milli": 1000, "age_ticks": 0
	})
	bounty_model.step([])
	var expected_coins := int(bounty_enemy.get("reward_coins", 0)) + 10
	_expect(bounty_model.coins_earned == expected_coins, "coin bounty research adds to every kill reward")

	var cooldown_model := RunModel.new()
	cooldown_model.setup(source_config, "stage_001", 7304, {"upgrades": {"cooldown_mastery": 6}})
	cooldown_model.step([
		{"type": "select_skill", "skill_id": "fire_ball"},
		{"type": "cast_skill", "x_milli": 1200000, "y_milli": 540000}
	])
	var base_cooldown := int(_find_skill(source_config, "fire_ball")["cooldown_ticks"])
	_expect(int(cooldown_model.skill_cooldowns.get("fire_ball", -1)) == base_cooldown - 18, "cooldown mastery shortens skill cooldown")

	var radius_config := source_config.duplicate(true)
	var radius_model := RunModel.new()
	radius_model.setup(radius_config, "stage_001", 7305, {"upgrades": {"spell_radius": 5}})
	var radius_guard := 0
	while radius_model.enemies.is_empty() and radius_guard < 60:
		radius_model.step([])
		radius_guard += 1
	var radius_enemy: Dictionary = radius_model.enemies[0]
	radius_enemy["hp"] = 1000
	radius_enemy["max_hp"] = 1000
	radius_enemy["speed_milli_per_tick"] = 0
	radius_enemy["attack_x_milli"] = int(radius_enemy["x_milli"])
	var offset_target_y := clampi(int(radius_enemy["y_milli"]) - 200000, 0, int(radius_config["world"]["height_milli"]))
	var radius_events := radius_model.step([
		{"type": "select_skill", "skill_id": "fire_ball"},
		{"type": "cast_skill", "x_milli": int(radius_enemy["x_milli"]), "y_milli": offset_target_y}
	])
	var fire_hit := false
	for event in radius_events:
		if str(event.get("type", "")) == "damage" and str(event.get("source", "")) == "fire" and int(event.get("entity_id", 0)) == int(radius_enemy["entity_id"]):
			fire_hit = true
	_expect(fire_hit, "spell radius research extends the fire skill beyond its base radius")


func _test_weapon_switch_keeps_upgrades(source_config: Dictionary) -> void:
	# Regression: research bonuses must survive switching the equipped weapon;
	# the model reads upgrades from the profile snapshot regardless of weapon.
	var all_weapons: Array = []
	for weapon in source_config.get("weapons", []):
		all_weapons.append(str(weapon.get("id", "")))
	var strength_level := 5
	for weapon_id in all_weapons:
		var profile := {"current_weapon_id": weapon_id, "unlocked_weapons": all_weapons, "upgrades": {"strength": strength_level}}
		var model := RunModel.new()
		var setup: Dictionary = model.setup(source_config, "stage_001", 9100, profile)
		_expect(bool(setup.get("ok", false)) and model.weapon_id == weapon_id, "run starts with %s equipped" % weapon_id)
		var base := RunModel.new()
		base.setup(source_config, "stage_001", 9101, {"current_weapon_id": weapon_id, "unlocked_weapons": all_weapons, "upgrades": {}})
		var upgraded_damage := -1
		var base_damage := -1
		for step_index in range(30):
			model.step([{"type": "aim", "x_milli": 1500000, "y_milli": 540000}, {"type": "fire_started"}])
			base.step([{"type": "aim", "x_milli": 1500000, "y_milli": 540000}, {"type": "fire_started"}])
			var shots: Array = model.snapshot().get("projectiles", [])
			var base_shots: Array = base.snapshot().get("projectiles", [])
			if not shots.is_empty() and not base_shots.is_empty():
				upgraded_damage = int(shots[0].get("damage", -1))
				base_damage = int(base_shots[0].get("damage", -1))
				break
		var bonus := strength_level * int(_find_upgrade(source_config, "strength").get("effect_per_level", 0))
		_expect(upgraded_damage == base_damage + bonus, "strength research still applies after switching to %s" % weapon_id)


func _test_progression_and_battle_record(source_config: Dictionary) -> void:
	# Level curve behind the Status header / Stage Complete panel: level N
	# costs 100 * N xp, so xp 150 sits at level 2 with 50/200 on the bar.
	var first_level: Dictionary = Progression.level_progress(source_config, 0)
	_expect(int(first_level.get("level", 0)) == 1, "zero xp stays at level 1")
	_expect(int(first_level.get("into_level", -1)) == 0 and int(first_level.get("needed", 0)) == 100, "level 1 bar starts 0/100")
	var mid_level: Dictionary = Progression.level_progress(source_config, 150)
	_expect(int(mid_level.get("level", 0)) == 2, "150 xp reaches level 2")
	_expect(int(mid_level.get("into_level", 0)) == 50 and int(mid_level.get("needed", 0)) == 200, "level 2 bar shows 50/200")
	var capped: Dictionary = Progression.level_progress(source_config, 10000000)
	_expect(int(capped.get("level", 0)) == int(Progression.MAX_LEVEL), "xp beyond the curve caps at max level")
	# The curve is data-driven (FR-080): a config base of 50 halves every step.
	var tuned_rules: Dictionary = source_config.duplicate(true)
	tuned_rules["player"] = {"level_base_xp": 50}
	var tuned: Dictionary = Progression.level_progress(tuned_rules, 60)
	_expect(int(tuned.get("level", 0)) == 2 and int(tuned.get("into_level", 0)) == 10, "level curve follows player.level_base_xp from config")
	# Status-page battle record: settled runs count wins and losses separately.
	var honor_service := HonorService.new()
	var base_profile := {"stats": {}, "honors": {}}
	var victory := {"status": "victory", "kills": 5, "coins": 10, "xp": 20, "stage_number": 1, "wall_percent": 100, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var after_win: Dictionary = honor_service.apply_result(base_profile, victory, source_config).get("profile", {})
	_expect(int(after_win.get("stats", {}).get("battles_won", 0)) == 1, "victory counts battles_won")
	_expect(int(after_win.get("stats", {}).get("battles_lost", 0)) == 0, "victory does not count battles_lost")
	var defeat := {"status": "defeat", "kills": 2, "coins": 4, "xp": 6, "stage_number": 1, "wall_percent": 0, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var after_loss: Dictionary = honor_service.apply_result(after_win, defeat, source_config).get("profile", {})
	var loss_stats: Dictionary = after_loss.get("stats", {})
	_expect(int(loss_stats.get("battles_won", 0)) == 1 and int(loss_stats.get("battles_lost", 0)) == 1, "defeat counts battles_lost separately")
	# Perfect victories earn one crystal (参考 Stage Complete bonus column).
	var perfect := {"status": "victory", "kills": 5, "coins": 10, "xp": 20, "stage_number": 2, "wall_percent": 100, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var perfect_result: Dictionary = honor_service.apply_result({"stats": {}, "honors": {}, "crystals": 3}, perfect, source_config)
	_expect(int(perfect_result.get("profile", {}).get("crystals", 0)) == 4, "perfect victory awards one crystal")
	_expect(int(perfect_result.get("crystals_awarded", 0)) == 1, "settlement reports the awarded crystals")
	var imperfect := {"status": "victory", "kills": 5, "coins": 10, "xp": 20, "stage_number": 2, "wall_percent": 87, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var imperfect_result: Dictionary = honor_service.apply_result({"stats": {}, "honors": {}, "crystals": 3}, imperfect, source_config)
	_expect(int(imperfect_result.get("crystals_awarded", 0)) == 0, "damaged-wall victory awards no crystal")


func _find_upgrade(source_config: Dictionary, upgrade_id: String) -> Dictionary:
	for upgrade in source_config.get("upgrades", []):
		if upgrade is Dictionary and str(upgrade.get("id", "")) == upgrade_id:
			return upgrade
	return {}


func _test_event_position_anchor_contract(source_config: Dictionary) -> void:
	# Presentation anchors floating texts by entity id using the previous
	# snapshot plus same-tick spawn events (event order: spawn < hit < damage
	# < death). The core must keep every position-bearing event resolvable
	# through that pair, including arrows hitting enemies on their spawn tick.
	var profile := {"current_weapon_id": "phantom_bow", "unlocked_weapons": ["basic_bow", "phantom_bow"], "upgrades": {"strength": 10, "agility": 6, "power_mastery": 5, "phantom_mastery": 4, "fire_mastery": 7}}
	for stage_id in ["stage_010", "stage_030"]:
		var model := RunModel.new()
		model.setup(source_config, stage_id, 777, profile)
		var known := {}
		for enemy in model.snapshot().get("enemies", []):
			known[int(enemy["entity_id"])] = true
		var misses := 0
		var position_events := 0
		for anchor_tick in range(1, 4000):
			var events := model.step([{"type": "aim", "x_milli": 1400000, "y_milli": 540000}, {"type": "fire_started"}])
			for event in events:
				var event_type := str(event.get("type", ""))
				if event_type == "spawn":
					known[int(event.get("entity_id", 0))] = true
				elif event_type == "hit" or event_type == "damage" or event_type == "death":
					position_events += 1
					if not known.has(int(event.get("entity_id", 0))):
						misses += 1
			for enemy in model.snapshot().get("enemies", []):
				known[int(enemy["entity_id"])] = true
			if model.status != "running":
				break
		_expect(position_events > 0 and misses == 0, "hit/damage/death events stay position-resolvable on %s" % stage_id)


func _find_skill(config: Dictionary, skill_id: String) -> Dictionary:
	for skill in config.get("skills", []):
		if skill is Dictionary and str(skill.get("id", "")) == skill_id:
			return skill
	return {}


func _test_migration() -> void:
	var old_envelope := {"schema_version": 1, "payload": {"coins": 12, "xp": 3, "upgrades": {}}}
	var migrated := SaveService.migrate_envelope(old_envelope)
	var payload: Dictionary = migrated.get("envelope", {}).get("payload", {})
	_expect(bool(migrated.get("ok", false)) and int(migrated["envelope"]["schema_version"]) == 5, "profile migrates v1 to v5")
	_expect(payload.has("reward_ledger") and payload.has("crystals"), "migration adds required fields")
	_expect(payload.has("current_weapon_id") and payload.has("unlocked_weapons") and payload.has("stats") and payload.has("honors"), "migration adds Windows 1.0 weapon, stats and honors fields")
	_expect(payload.has("player_name"), "migration adds the player display name field")
	# v5 backfills the Status battle record from completed stages.
	var v4_envelope := {"schema_version": 4, "payload": {"coins": 5, "xp": 1, "stats": {"stages_completed": 7}}}
	var migrated_v4 := SaveService.migrate_envelope(v4_envelope)
	var v5_stats: Dictionary = migrated_v4.get("envelope", {}).get("payload", {}).get("stats", {})
	_expect(int(migrated_v4.get("envelope", {}).get("schema_version", 0)) == 5 and int(v5_stats.get("battles_won", -1)) == 7 and int(v5_stats.get("battles_lost", -1)) == 0, "v4 to v5 backfills battles_won from stages_completed")


func _test_hashless_legacy_load() -> void:
	var directory := "user://automated-hashless-legacy-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	_delete_test_directory(absolute_directory)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var path := directory + "/profile.json"
	var envelope := {
		"schema_version": 1,
		"app_version": "0.1.0-mvp",
		"config_version": 1,
		"payload": {"coins": 12, "xp": 3, "upgrades": {}}
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(envelope, "  ", true))
		file.flush()
	file = null
	var service := SaveService.new(directory)
	var loaded := service.load_profile({"coins": 0, "xp": 0, "upgrades": {}})
	var loaded_payload: Variant = loaded.get("payload", {})
	var payload_ok := loaded_payload is Dictionary and int(loaded_payload.get("coins", 0)) == 12 and int(loaded_payload.get("xp", 0)) == 3
	_expect(file == null and bool(loaded.get("ok", false)) and bool(loaded.get("migrated", false)) and payload_ok, "hashless v1 profile loads and migrates to the current schema")
	_delete_test_directory(absolute_directory)


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


func _test_corrupt_copy_uniqueness() -> void:
	var directory := "user://automated-corrupt-copy-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	_delete_test_directory(absolute_directory)
	DirAccess.make_dir_recursive_absolute(absolute_directory)
	var path := directory + "/profile.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("{broken")
		file.flush()
	file = null
	var service := SaveService.new(directory)
	service.call("_preserve_corrupt", path)
	service.call("_preserve_corrupt", path)
	var corrupt_names: Array[String] = []
	var directory_access := DirAccess.open(absolute_directory)
	if directory_access != null:
		directory_access.list_dir_begin()
		var item := directory_access.get_next()
		while not item.is_empty():
			if not directory_access.current_is_dir() and item.contains(".corrupt-"):
				corrupt_names.append(item)
			item = directory_access.get_next()
		directory_access.list_dir_end()
	var unique_names := {}
	for name in corrupt_names:
		unique_names[name] = true
	_expect(corrupt_names.size() >= 2 and unique_names.size() == corrupt_names.size(), "consecutive corrupt-save copies retain unique diagnostic names")
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
		gameplay.set("snapshot", {"enemies": []})
		gameplay.get("_last_known_positions")[42] = Vector2(300, 200)
		_expect(gameplay.call("_entity_position", 42) == Vector2(300, 200), "entity position resolves from the last-known-position map for same-tick spawn hits")
		_expect(gameplay.call("_entity_position", 99) == Vector2(980, 520), "entity position falls back only for never-seen entities")
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
