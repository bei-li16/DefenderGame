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
		_test_honor_chains(content.rules)
		_test_honor_bonuses(content.rules)
		_test_weapon_research(content.rules)
		_test_reward_coin_curve(content.rules)
		_test_crystal_economy(content.rules)
		_test_event_position_anchor_contract(content.rules)
		_test_migration()
		_test_hashless_legacy_load()
		_test_current_schema_default_completion()
		_test_save_backup_recovery()
		_test_save_slots()
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
	var blocked_profile := {"coins": 1000, "crystals": 1000, "upgrades": {"strength": 0, "ice_mastery": 0}}
	var blocked := service.purchase(blocked_profile, prerequisite_config, "ice_mastery")
	blocked_profile["upgrades"]["strength"] = 1
	var allowed := service.purchase(blocked_profile, prerequisite_config, "ice_mastery")
	_expect(not bool(blocked.get("ok", false)) and bool(allowed.get("ok", false)), "upgrade prerequisites block and allow purchase atomically")
	# Magic research costs crystals; coins stay untouched and vice versa.
	var crystal_poor := {"coins": 100000, "crystals": 0, "upgrades": {"mana_capacity": 0}}
	var crystal_rejected := service.purchase(crystal_poor, config, "mana_capacity")
	_expect(not bool(crystal_rejected.get("ok", false)) and str(crystal_rejected.get("error_code", "")) == "insufficient_crystals" and int(crystal_poor["coins"]) == 100000, "magic research rejects coin-only balances as insufficient crystals")
	var crystal_funded := {"coins": 100, "crystals": 5, "upgrades": {"mana_capacity": 0}}
	var crystal_bought := service.purchase(crystal_funded, config, "mana_capacity")
	_expect(bool(crystal_bought.get("ok", false)) and int(crystal_bought["profile"]["crystals"]) == 4 and int(crystal_bought["profile"]["coins"]) == 100 and str(crystal_bought.get("currency", "")) == "crystals", "magic research spends crystals and keeps coins")
	var coin_only := {"coins": 0, "crystals": 1000, "upgrades": {"strength": 0}}
	var coin_rejected := service.purchase(coin_only, config, "strength")
	_expect(not bool(coin_rejected.get("ok", false)) and str(coin_rejected.get("error_code", "")) == "insufficient_coins" and int(coin_only["crystals"]) == 1000, "attack research rejects crystal-only balances as insufficient coins")


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
		"damage": 1, "fatal": false, "power": true, "knockback_milli": int(model.attack_stats["knockback_milli"]), "collision_radius_milli": 1000, "age_ticks": 0
	}]
	var first_events: Array[Dictionary] = []
	model.call("_update_projectiles", first_events)
	var resisted_position := int(model.enemies[0]["x_milli"])
	model.enemies[0]["x_milli"] = int(source_config["world"]["enemy_spawn_x_milli"]) - 1000
	model.enemies[0]["knockback_resistance_permille"] = 0
	model.projectiles = [{
		"entity_id": 3, "x_milli": model.enemies[0]["x_milli"], "y_milli": 500000, "vx_milli": 0, "vy_milli": 0,
		"damage": 1, "fatal": false, "power": true, "knockback_milli": int(model.attack_stats["knockback_milli"]), "collision_radius_milli": 1000, "age_ticks": 0
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
	# Crystals pay on the FIRST clear of a stage, following rules.crystal_rewards:
	# base 3, +1 per five stages of stage number, +4 extra on boss stages.
	var first_clear := {"status": "victory", "stage_id": "stage_001", "stage_number": 1, "kills": 5, "coins": 10, "xp": 20, "wall_percent": 60, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var first_result: Dictionary = honor_service.apply_result({"stats": {}, "honors": {}, "crystals": 3, "best_results": {}}, first_clear, source_config)
	_expect(int(first_result.get("profile", {}).get("crystals", 0)) == 6, "first clear of a stage awards the base three crystals")
	_expect(int(first_result.get("crystals_awarded", 0)) == 3, "settlement reports the first-clear crystals")
	# settle_run records best_results after the honor pass; simulate that so
	# the repeat sees the stage as already cleared.
	var settled_profile: Dictionary = first_result.get("profile", {})
	settled_profile["best_results"] = {"stage_001": {"status": "victory"}}
	var repeat_result: Dictionary = honor_service.apply_result(settled_profile, first_clear, source_config)
	_expect(int(repeat_result.get("crystals_awarded", 0)) == 0, "repeating a cleared stage pays no crystals")
	var boss_clear := {"status": "victory", "stage_id": "stage_010", "stage_number": 10, "kills": 30, "coins": 60, "xp": 90, "wall_percent": 100, "weapon_id": "basic_bow", "bosses_slain": 1, "spells_cast": 0}
	var boss_result: Dictionary = honor_service.apply_result({"stats": {}, "honors": {}, "crystals": 0, "best_results": {}}, boss_clear, source_config)
	_expect(int(boss_result.get("crystals_awarded", 0)) == 8, "first clear of a boss stage awards the curve amount plus the boss bonus")
	var defeat_run := {"status": "defeat", "stage_id": "stage_002", "stage_number": 2, "kills": 4, "coins": 6, "xp": 5, "wall_percent": 0, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var defeat_result: Dictionary = honor_service.apply_result({"stats": {}, "honors": {}, "crystals": 0, "best_results": {}}, defeat_run, source_config)
	_expect(int(defeat_result.get("crystals_awarded", 0)) == 0, "a failed run pays no crystals")
	# A recorded defeat does not consume the stage's first-clear crystals.
	var after_defeat: Dictionary = defeat_result.get("profile", {})
	after_defeat["best_results"] = {"stage_002": {"status": "defeat", "wall_percent": 0}}
	var late_clear := {"status": "victory", "stage_id": "stage_002", "stage_number": 2, "kills": 5, "coins": 10, "xp": 20, "wall_percent": 80, "weapon_id": "basic_bow", "bosses_slain": 0, "spells_cast": 0}
	var late_result: Dictionary = honor_service.apply_result(after_defeat, late_clear, source_config)
	_expect(int(late_result.get("crystals_awarded", 0)) == 3, "a prior defeat record keeps the first-clear crystals")


func _test_honor_chains(source_config: Dictionary) -> void:
	# Chain honors evaluate three milestone levels and pay each level once.
	var honor_service := HonorService.new()
	var killer_profile := {"stats": {"total_kills": 30000}, "honors": {}, "honor_reward_ledger": []}
	var evaluation: Dictionary = honor_service.evaluate(killer_profile, source_config)
	_expect(int(evaluation.get("honors", {}).get("monster_hunter", 0)) == 2, "30k kills reach Monster Hunter Lv.2")
	_expect(evaluation.get("ledger", []).has("monster_hunter:1") and evaluation.get("ledger", []).has("monster_hunter:2"), "chain levels append id:level ledger keys")
	var monster := _find_honor(source_config, "monster_hunter")
	var expected_coins := int(monster.get("reward_coins", [])[0]) + int(monster.get("reward_coins", [])[1])
	_expect(int(evaluation.get("coins", 0)) == expected_coins, "each reached chain level pays its own reward")
	var settled: Dictionary = honor_service.evaluate({"stats": killer_profile.get("stats"), "honors": evaluation.get("honors"), "honor_reward_ledger": evaluation.get("ledger")}, source_config)
	_expect(int(settled.get("coins", 0)) == 0 and settled.get("ledger", []).size() == evaluation.get("ledger", []).size(), "re-evaluating a settled chain pays nothing again")
	# Legacy single-level unlock counts as its level-1 reward being paid.
	var legacy: Dictionary = honor_service.evaluate({"stats": {"total_kills": 30000}, "honors": {"monster_hunter": true}, "honor_reward_ledger": []}, source_config)
	_expect(int(legacy.get("honors", {}).get("monster_hunter", 0)) == 2 and not legacy.get("new_honors", []).has("monster_hunter:1"), "legacy boolean honor marks level 1 as already paid")


func _test_honor_bonuses(source_config: Dictionary) -> void:
	# Defender chain boosts wall HP by 5% per level during setup.
	var base_model := RunModel.new()
	base_model.setup(source_config, "stage_001", 4242, {"current_weapon_id": "basic_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {}, "honors": {}})
	var boosted_model := RunModel.new()
	boosted_model.setup(source_config, "stage_001", 4242, {"current_weapon_id": "basic_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {}, "honors": {"defender": 2}})
	_expect(int(boosted_model.snapshot()["wall_max_hp"]) == int(round(float(int(base_model.snapshot()["wall_max_hp"])) * 1.10)), "Defender honor boosts wall HP by 5% per level")
	# Big Spender pays +1 coin per kill per level via the reward event.
	var kill_coins := -1
	var boosted_kill_coins := -1
	for run_index in range(2):
		var model := RunModel.new()
		var honors := {} if run_index == 0 else {"big_spender": 2}
		model.setup(source_config, "stage_001", 777, {"current_weapon_id": "basic_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {}, "honors": honors})
		var coins_before := 0
		for step_index in range(140):
			var commands: Array = []
			var visible: Array = model.snapshot().get("enemies", [])
			if not visible.is_empty():
				commands.append({"type": "aim", "x_milli": int(visible[0]["x_milli"]), "y_milli": int(visible[0]["y_milli"])})
			commands.append({"type": "fire_started"})
			var events: Array[Dictionary] = model.step(commands)
			for event in events:
				if str(event.get("type", "")) == "reward" and str(event.get("source", "")) == "kill":
					coins_before = int(event.get("coins", 0))
					break
			if coins_before > 0:
				break
		if run_index == 0:
			kill_coins = coins_before
		else:
			boosted_kill_coins = coins_before
	_expect(kill_coins > 0 and boosted_kill_coins == kill_coins + 2, "Big Spender honor adds +1 coin per kill per level")
	# Fire Master boosts fire skill damage by 3% per level (same seed, same target).
	var fire_damage := -1
	var boosted_fire_damage := -1
	for run_index in range(2):
		var model := RunModel.new()
		var honors := {} if run_index == 0 else {"fire_master": 1}
		model.setup(source_config, "stage_001", 999, {"current_weapon_id": "basic_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {"mana_capacity": 5}, "honors": honors})
		var fire_radius := 0
		for skill in source_config.get("skills", []):
			if skill is Dictionary and str(skill.get("id", "")) == "fire_ball":
				fire_radius = int(skill.get("radius_milli", 0))
				break
		var target_x := 0
		var target_y := 0
		for step_index in range(220):
			var enemies: Array = model.snapshot().get("enemies", [])
			if not enemies.is_empty():
				var enemy_x := int(enemies[0]["x_milli"])
				var enemy_y := int(enemies[0]["y_milli"])
				if enemy_x <= int(source_config["world"]["castle_x_milli"]) + 1400000 and enemy_x >= 300000:
					target_x = enemy_x
					target_y = enemy_y
					break
			model.step([{"type": "aim", "x_milli": 1500000, "y_milli": 540000}])
		_expect(target_x > 0, "enemy in fire range for honor spell probe %d" % run_index)
		var damage_events: Array[Dictionary] = model.step([{"type": "select_skill", "skill_id": "fire_ball"}, {"type": "cast_skill", "x_milli": target_x, "y_milli": target_y}])
		for event in damage_events:
			if str(event.get("type", "")) == "damage" and str(event.get("source", "")) == "fire":
				if run_index == 0:
					fire_damage = int(event.get("amount", 0))
				else:
					boosted_fire_damage = int(event.get("amount", 0))
	_expect(fire_damage > 0 and boosted_fire_damage == fire_damage * 1030 / 1000, "Fire Master honor boosts fire damage by 3% per level")


func _test_weapon_research(source_config: Dictionary) -> void:
	# Forge chain: each level of forge_power_bow adds +8% to power_bow damage.
	var bow := _find_by_id_public(source_config, "weapons", "power_bow")
	_expect(not bow.is_empty() and str(bow.get("forge_upgrade_id", "")) == "forge_power_bow", "power_bow references its forge upgrade")
	var base_damage := int(bow.get("damage", 0))
	var baseline := -1
	var forged := -1
	for forge_level in [0, 2]:
		var upgrades := {"forge_power_bow": forge_level, "unlock_power_bow": 1}
		var model := RunModel.new()
		model.setup(source_config, "stage_001", 31337, {"current_weapon_id": "power_bow", "unlocked_weapons": ["basic_bow", "power_bow"], "upgrades": upgrades})
		var seen := 0
		for step_index in range(90):
			var commands: Array = []
			var visible: Array = model.snapshot().get("enemies", [])
			if not visible.is_empty():
				commands.append({"type": "aim", "x_milli": int(visible[0]["x_milli"]), "y_milli": int(visible[0]["y_milli"])})
			commands.append({"type": "fire_started"})
			var events: Array[Dictionary] = model.step(commands)
			for event in events:
				if str(event.get("type", "")) == "shot":
					var projectiles: Array = model.snapshot().get("projectiles", [])
					if not projectiles.is_empty():
						seen = int(projectiles[0].get("damage", 0))
						break
			if seen > 0:
				break
		if forge_level == 0:
			baseline = seen
		else:
			forged = seen
	_expect(baseline > 0 and forged == baseline * 1160 / 1000, "forge level 2 raises power_bow damage by 16% over its base")
	# The unlock node and forge chain are wired into the weapons research page.
	var page_ids: Array[String] = []
	for page in source_config.get("research_pages", []):
		page_ids.append(str(page.get("id", "")))
	_expect(page_ids.has("weapons"), "research pages include the weapons page")
	_expect(_find_by_id_public(source_config, "upgrades", "forge_hurricane_bow").get("prerequisites", []).has("unlock_hurricane_bow"), "forge chains require their unlock node")


func _test_reward_coin_curve(source_config: Dictionary) -> void:
	# Kill rewards follow the configured per-stage curve (55 permille per
	# stage, capped): the same template pays more on deeper stages, so failed
	# runs still scale with kills and cleared stages pay on top.
	var scaling: Dictionary = source_config.get("difficulty_scaling", {})
	var per_stage := int(scaling.get("reward_per_stage_permille", 0))
	_expect(per_stage > 0, "reward curve is configured")
	var observed := {}
	for stage_number in [1, 10, 20]:
		var stage_id := "stage_%03d" % stage_number
		var model := RunModel.new()
		model.setup(source_config, stage_id, 24680, {"current_weapon_id": "basic_bow", "unlocked_weapons": ["basic_bow"], "upgrades": {}, "honors": {}})
		var guard := 0
		while model.enemies.size() < 2 and guard < 300:
			model.step([{"type": "fire_stopped"}])
			guard += 1
		_expect(not model.enemies.is_empty(), "stage %02d spawns enemies for the coin curve probe" % stage_number)
		for enemy in model.enemies:
			var enemy_id := str(enemy.get("enemy_id", ""))
			var base := int(_find_by_id_public(source_config, "enemies", enemy_id).get("reward_coins", 0))
			var expected_scale := mini(1000 + (stage_number - 1) * per_stage, int(scaling.get("max_reward_scale_permille", 1000)))
			var expected := maxi(1, base * expected_scale / 1000)
			_expect(int(enemy.get("reward_coins", -1)) == expected, "%s pays %d coins on stage %02d (curve)" % [enemy_id, expected, stage_number])
			observed[stage_number] = true


func _find_by_id_public(source_config: Dictionary, collection: String, item_id: String) -> Dictionary:
	for value in source_config.get(collection, []):
		if value is Dictionary and str(value.get("id", "")) == item_id:
			return value
	return {}


func _find_honor(source_config: Dictionary, honor_id: String) -> Dictionary:
	for honor in source_config.get("honors", []):
		if honor is Dictionary and str(honor.get("id", "")) == honor_id:
			return honor
	return {}


func _find_upgrade(source_config: Dictionary, upgrade_id: String) -> Dictionary:
	for upgrade in source_config.get("upgrades", []):
		if upgrade is Dictionary and str(upgrade.get("id", "")) == upgrade_id:
			return upgrade
	return {}


func _test_crystal_economy(source_config: Dictionary) -> void:
	# The crystal economy must let a full clear afford every magic level
	# without leaving a large surplus (design: income 177 vs cost 169).
	var total_income := 0
	var stages: Array = source_config.get("stages", [])
	for stage in stages:
		total_income += HonorService.first_clear_crystals(str(stage.get("id", "")), source_config)
	var total_cost := 0
	for upgrade in source_config.get("upgrades", []):
		if not upgrade is Dictionary:
			continue
		if str(upgrade.get("page", "")) == "magic":
			_expect(str(upgrade.get("currency", "")) == "crystals", "magic research node %s costs crystals" % str(upgrade.get("id", "")))
		if str(upgrade.get("currency", "coins")) != "crystals":
			continue
		for level in range(int(upgrade.get("max_level", 0))):
			total_cost += UpgradeService.price_for_level(upgrade, level)
	_expect(total_income == 177, "first-clear crystal income totals 177 across 30 stages (got %d)" % total_income)
	_expect(total_cost == 169, "magic research crystal cost totals 169 (got %d)" % total_cost)
	_expect(total_cost <= total_income, "crystal income covers the full magic tree")
	_expect(total_income - total_cost <= maxi(10, int(ceil(float(total_cost) * 0.25))), "crystal income avoids a large surplus")
	# Legacy saves cleared stages under the old flat payout; reconcile credits
	# the curve difference exactly once so magic research stays affordable.
	var honor_service := HonorService.new()
	var legacy_best := {}
	for stage in stages:
		legacy_best[str(stage.get("id", ""))] = {"status": "victory"}
	var legacy := {"crystals": 63, "best_results": legacy_best, "stats": {"crystals_earned": 63}, "honors": {}, "honor_reward_ledger": []}
	var topped: Dictionary = honor_service.reconcile(legacy, source_config)
	_expect(int(topped.get("crystal_topup", -1)) == 114, "legacy full-clear save receives the 114-crystal curve difference")
	var topped_profile: Dictionary = topped.get("profile", {})
	_expect(int(topped_profile.get("crystals", 0)) == 177 and bool(topped_profile.get("crystal_topup_v1", false)), "top-up credits crystals and marks the profile")
	_expect(int(topped_profile.get("stats", {}).get("crystals_earned", 0)) == 177, "top-up feeds the lifetime crystals stat")
	var second: Dictionary = honor_service.reconcile(topped_profile, source_config)
	_expect(int(second.get("crystal_topup", -1)) == 0 and int(second.get("profile", {}).get("crystals", 0)) == 177, "the crystal top-up pays exactly once")
	var fresh: Dictionary = honor_service.reconcile({"crystals": 0, "best_results": {}, "stats": {}}, source_config)
	_expect(int(fresh.get("crystal_topup", -1)) == 0, "a fresh profile has nothing to top up")


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
	_expect(bool(migrated.get("ok", false)) and int(migrated["envelope"]["schema_version"]) == 6, "profile migrates v1 to v6")
	_expect(payload.has("reward_ledger") and payload.has("crystals"), "migration adds required fields")
	_expect(payload.has("current_weapon_id") and payload.has("unlocked_weapons") and payload.has("stats") and payload.has("honors"), "migration adds Windows 1.0 weapon, stats and honors fields")
	_expect(payload.has("player_name"), "migration adds the player display name field")
	# v5 backfills the Status battle record from completed stages.
	var v4_envelope := {"schema_version": 4, "payload": {"coins": 5, "xp": 1, "stats": {"stages_completed": 7}}}
	var migrated_v4 := SaveService.migrate_envelope(v4_envelope)
	var v5_stats: Dictionary = migrated_v4.get("envelope", {}).get("payload", {}).get("stats", {})
	_expect(int(migrated_v4.get("envelope", {}).get("schema_version", 0)) == 6 and int(v5_stats.get("battles_won", -1)) == 7 and int(v5_stats.get("battles_lost", -1)) == 0, "v4 to v5 backfills battles_won from stages_completed")
	# v5 to v6 converts honor booleans to levels and seeds lifetime counters.
	var v5_envelope := {"schema_version": 5, "payload": {"coins": 1, "honors": {"defender": true, "big_spender": 2}, "stats": {"stages_completed": 3}}}
	var migrated_v5 := SaveService.migrate_envelope(v5_envelope)
	var v6_payload: Dictionary = migrated_v5.get("envelope", {}).get("payload", {})
	_expect(int(migrated_v5.get("envelope", {}).get("schema_version", 0)) == 6 and int(v6_payload.get("honors", {}).get("defender", 0)) == 1 and int(v6_payload.get("honors", {}).get("big_spender", 0)) == 2, "v5 to v6 converts honor booleans to levels")
	_expect(int(v6_payload.get("stats", {}).get("coins_spent", -1)) == 0 and int(v6_payload.get("stats", {}).get("fire_casts", -1)) == 0, "v5 to v6 seeds lifetime honor counters")


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


func _test_save_slots() -> void:
	var directory := "user://automated-slot-test"
	var absolute_directory := ProjectSettings.globalize_path(directory)
	_delete_test_directory(absolute_directory)
	var service := SaveService.new(directory)
	var slot_one := {"coins": 11, "xp": 1, "reward_ledger": [], "stats": {"total_kills": 7, "stages_completed": 2, "playtime_seconds": 5400}}
	var slot_two := {"coins": 22, "xp": 2, "reward_ledger": [], "stats": {"total_kills": 99, "stages_completed": 8, "playtime_seconds": 60}}
	var first_save := service.save_profile_slot(1, slot_one, 1)
	var second_save := service.save_profile_slot(2, slot_two, 1)
	_expect(bool(first_save.get("ok", false)) and bool(second_save.get("ok", false)), "slot saves write independent portable files")
	_expect(FileAccess.file_exists(directory + "/slot_1.json") and FileAccess.file_exists(directory + "/slot_2.json"), "each slot materializes as its own file beside the EXE directory")
	var reloaded_one := service.load_profile_slot(1, {"reward_ledger": []})
	var reloaded_two := service.load_profile_slot(2, {"reward_ledger": []})
	_expect(int(reloaded_one.get("payload", {}).get("coins", 0)) == 11 and int(reloaded_two.get("payload", {}).get("coins", 0)) == 22, "slot payloads stay isolated per slot file")
	var fresh := service.load_profile_slot(3, {"coins": 180, "reward_ledger": []})
	_expect(bool(fresh.get("ok", false)) and str(fresh.get("source", "")) == "default", "an empty slot resolves to the defaults payload")
	var summary_one := service.read_slot_summary(1)
	_expect(bool(summary_one.get("exists", false)) and int(summary_one.get("coins", 0)) == 11 and int(summary_one.get("stats", {}).get("total_kills", 0)) == 7 and int(summary_one.get("stats", {}).get("playtime_seconds", 0)) == 5400, "slot summaries expose career stats for the save page")
	_expect(not bool(service.read_slot_summary(3).get("exists", true)), "empty slot summaries report exists=false")
	# Portability contract: the file is self-contained, so copying it to another
	# machine's save directory must restore the same profile.
	var portable_directory := "user://automated-slot-portable-test"
	var portable_absolute := ProjectSettings.globalize_path(portable_directory)
	_delete_test_directory(portable_absolute)
	DirAccess.make_dir_recursive_absolute(portable_absolute)
	DirAccess.copy_absolute(directory + "/slot_1.json", portable_directory + "/slot_1.json")
	var portable_load := SaveService.new(portable_directory).load_profile_slot(1, {"reward_ledger": []})
	_expect(bool(portable_load.get("ok", false)) and int(portable_load.get("payload", {}).get("coins", 0)) == 11, "a copied slot file loads identically from another save directory")
	# Migration: a pre-slot install's profile.json is adopted by slot 1.
	var legacy_directory := "user://automated-slot-legacy-test"
	var legacy_absolute := ProjectSettings.globalize_path(legacy_directory)
	_delete_test_directory(legacy_absolute)
	var legacy_service := SaveService.new(legacy_directory)
	legacy_service.save_profile({"coins": 66, "xp": 5, "reward_ledger": []}, 1)
	var legacy_load := legacy_service.load_profile_slot(1, {"reward_ledger": []})
	_expect(bool(legacy_load.get("ok", false)) and str(legacy_load.get("source", "")) == "legacy" and int(legacy_load.get("payload", {}).get("coins", 0)) == 66, "slot 1 adopts the legacy single-save profile on first load")
	_delete_test_directory(absolute_directory)
	_delete_test_directory(portable_absolute)
	_delete_test_directory(legacy_absolute)


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
