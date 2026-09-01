extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")


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
	model.setup(config, "stage_001", 123456, {"upgrades": {}})
	for warmup_tick in range(130):
		model.step([])
	for projectile_index in range(200):
		model.projectiles.append({
			"entity_id": 10000 + projectile_index,
			"x_milli": 500000 + projectile_index,
			"y_milli": 100000,
			"vx_milli": 0,
			"vy_milli": 0,
			"damage": 1,
			"fatal": false,
			"power": false,
			"collision_radius_milli": 1000,
			"age_ticks": -20000
		})
	var samples: Array[int] = []
	var total_start := Time.get_ticks_usec()
	for simulation_tick in range(9000):
		var tick_start := Time.get_ticks_usec()
		model.step([])
		samples.append(Time.get_ticks_usec() - tick_start)
	var total_usec := Time.get_ticks_usec() - total_start
	samples.sort()
	var p95_usec := samples[int(floor(float(samples.size() - 1) * 0.95))]
	var average_usec := float(total_usec) / float(samples.size())
	print("[PERF] 5 simulated minutes; enemies=%d projectiles=%d average=%.3fms p95=%.3fms total=%.2fs" % [model.enemies.size(), model.projectiles.size(), average_usec / 1000.0, float(p95_usec) / 1000.0, float(total_usec) / 1000000.0])
	if p95_usec >= 10000:
		push_error("Performance gate failed: p95 must be below 10ms")
		quit(1)
		return
	quit(0)
