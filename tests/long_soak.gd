extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")

const SOAK_TICKS := 108000
const CHECKPOINT_TICKS := 9000
const MEBIBYTE := 1024.0 * 1024.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := ContentService.new()
	var loaded := content.load_builtin()
	if not bool(loaded.get("ok", false)):
		push_error("Content failed to load")
		quit(1)
		return
	var config := content.rules.duplicate(true)
	config["player"]["wall_hp"] = 1000000000
	config["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 100, "interval_ticks": 1}]
	config["enemies"][0]["speed_milli_per_tick"] = 1
	config["enemies"][0]["attack_damage"] = 1
	var model := RunModel.new()
	model.setup(config, "stage_001", 606060, {"upgrades": {}})
	for warmup_tick in range(130):
		model.step([])
	for projectile_index in range(200):
		model.projectiles.append({
			"entity_id": 20000 + projectile_index,
			"x_milli": 500000 + projectile_index,
			"y_milli": 100000,
			"vx_milli": 0,
			"vy_milli": 0,
			"damage": 1,
			"fatal": false,
			"power": false,
			"collision_radius_milli": 1000,
			"age_ticks": -200000
		})
	var initial_memory := OS.get_static_memory_usage()
	var initial_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory_samples: Array[int] = [initial_memory]
	var tick_samples: Array[int] = []
	var total_start := Time.get_ticks_usec()
	for simulation_tick in range(SOAK_TICKS):
		var tick_start := Time.get_ticks_usec()
		model.step([])
		tick_samples.append(Time.get_ticks_usec() - tick_start)
		if (simulation_tick + 1) % CHECKPOINT_TICKS == 0:
			var memory_now := OS.get_static_memory_usage()
			memory_samples.append(memory_now)
			print("[SOAK] logical_minute=%d memory=%.2fMiB enemies=%d projectiles=%d" % [
				(simulation_tick + 1) / 1800,
				float(memory_now) / MEBIBYTE,
				model.enemies.size(),
				model.projectiles.size()
			])
	var total_usec := Time.get_ticks_usec() - total_start
	tick_samples.sort()
	var p95_usec := tick_samples[int(floor(float(tick_samples.size() - 1) * 0.95))]
	var final_memory := OS.get_static_memory_usage()
	var peak_memory := OS.get_static_memory_peak_usage()
	var final_nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var memory_growth := final_memory - initial_memory
	var entity_counts_stable := model.enemies.size() == 100 and model.projectiles.size() == 200
	var node_count_stable := final_nodes <= initial_nodes + 2
	var memory_stable := memory_growth <= 64 * 1024 * 1024
	var memory_under_budget := peak_memory < 750 * 1024 * 1024
	var tick_budget_met := p95_usec < 10000
	print("[SOAK RESULT] logical=60min wall=%.2fs p95=%.3fms initial=%.2fMiB final=%.2fMiB growth=%.2fMiB peak=%.2fMiB nodes=%d->%d samples=%s" % [
		float(total_usec) / 1000000.0,
		float(p95_usec) / 1000.0,
		float(initial_memory) / MEBIBYTE,
		float(final_memory) / MEBIBYTE,
		float(memory_growth) / MEBIBYTE,
		float(peak_memory) / MEBIBYTE,
		initial_nodes,
		final_nodes,
		memory_samples
	])
	var failed := false
	if not entity_counts_stable:
		push_error("Entity counts drifted during soak")
		failed = true
	if not node_count_stable:
		push_error("Node count grew during soak")
		failed = true
	if not memory_stable:
		push_error("Static memory grew by more than 64 MiB")
		failed = true
	if not memory_under_budget:
		push_error("Peak static memory exceeded 750 MiB")
		failed = true
	if not tick_budget_met:
		push_error("Simulation p95 exceeded 10 ms")
		failed = true
	quit(1 if failed else 0)
