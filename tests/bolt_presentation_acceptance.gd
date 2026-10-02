extends SceneTree
## Serial fixture: real firing cadence, projectile ownership and pixel equality
## through the actual gameplay renderer. --capture saves review frames.
const RunModel = preload("res://src/core/combat/run_model.gd")
const Attack = preload("res://src/core/rules/attack_catalog.gd")
const Bolt = preload("res://src/presentation/art/bolt_visuals.gd")
const OUTPUT := "res://Builds/bolt-review"
const EXPECTED := {"basic_bow": [8, 2], "power_bow": [9, 3], "hurricane_bow": [9, 3], "phantom_bow": [7, 2]}
var app: Node
var config: Dictionary
var passes := 0
var failures: Array[String] = []
var viewport: SubViewport
var game: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	config = app.get("content").rules
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	app.get("settings")["sfx_volume"] = 0.0
	_check_cadence()
	await _check_rendering()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[BOLT FAIL] " + failure)
	print("[BOLT] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _profile(weapon: String, agility: int) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["current_weapon_id"] = weapon
	profile["unlocked_weapons"] = EXPECTED.keys()
	profile["tutorial_complete"] = true
	profile["upgrades"].merge({"agility": agility, "multiple_arrows": 9, "fatal_blow": 1, "poisoned_arrow": 3}, true)
	return profile


func _model(weapon: String, agility: int, rules: Dictionary = config) -> DefenderRunModel:
	var copy := rules.duplicate(true)
	copy["world"]["spawn_start_tick"] = 1
	copy["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(copy, "stage_001", 8301, _profile(weapon, agility))
	model.step([])
	model.enemies[0].merge({"x_milli": 1840000, "y_milli": 950000, "hp": 100000000, "max_hp": 100000000, "speed_milli_per_tick": 0}, true)
	return model


func _check_cadence() -> void:
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	for rules in [config, fallback]:
		_expect(int(rules["config_version"]) == 13, "primary/fallback cadence revision is 13")
		for weapon in rules["weapons"]:
			var id := str(weapon["id"])
			var previous := 999
			for agility in range(7):
				var stats := Attack.effective(rules, _profile(id, agility), weapon)
				var interval := int(stats["interval_ticks"])
				_expect(interval <= previous and interval >= int(EXPECTED[id][1]), id + " legal agility monotonic and bounded")
				previous = interval
			for agility in [0, 6]:
				var model := _model(id, agility, rules)
				var interval := int(EXPECTED[id][0 if agility == 0 else 1])
				_expect(int(model.attack_stats["interval_ticks"]) == interval, id + " actual configured interval")
				var shot_ticks: Array[int] = []
				var shot_count := 0
				for step in range(300):
					var commands: Array = [{"type": "aim", "x_milli": 1840000, "y_milli": 555000}, {"type": "fire_started"}] if step == 0 else []
					for event in model.step(commands):
						if str(event["type"]) == "shot":
							shot_count += 1
							if int(event["volley_index"]) == 0:
								shot_ticks.append(model.tick)
				var correct := shot_ticks.size() == int(ceil(300.0 / interval))
				for index in range(1, shot_ticks.size()):
					correct = correct and shot_ticks[index] - shot_ticks[index - 1] == interval
				_expect(correct and shot_count == shot_ticks.size() * 5, id + " 10s real event cadence and five-arrow volleys")
				var saved := model.snapshot().duplicate(true)
				var owns := not model.projectiles.is_empty()
				var spacing: Array[int] = []
				for projectile in model.projectiles:
					owns = owns and projectile.get("weapon_id", "") == id and Bolt.weapon_key(projectile, "unrelated") == id
					if int(projectile["vy_milli"]) == 0:
						spacing.append(int(projectile["x_milli"]))
				_expect(owns, id + " every in-flight arrow retains its launch weapon")
				spacing.sort()
				var expected_gap := interval * int(weapon["projectile_speed_milli_per_tick"])
				var gaps_match := spacing.size() > 1
				for index in range(1, spacing.size()):
					gaps_match = gaps_match and spacing[index] - spacing[index - 1] == expected_gap
				_expect(gaps_match, id + " actual arrow spacing equals fixed flight speed times cadence")
				_expect(saved == model.snapshot(), "presentation lookup preserves all combat data")
				if rules == config:
					print("[BOLT RATE] %s agility=%d volleys/s=%.4f gap_px=%.1f shots_10s=%d" % [id, agility, 30.0 / interval, float(expected_gap) / 1000.0, shot_ticks.size()])
	_expect(Bolt.weapon_key({}, "phantom_bow") == "phantom_bow" and Bolt.weapon_key({"weapon_id": "invalid"}) == "basic_bow", "legacy fixture fallback and unknown ID are deterministic")


func _check_rendering() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	app.set("profile", _profile("basic_bow", 6))
	game = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	viewport.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	game.set("_pointer_inside_window", false)
	var signatures: Array[int] = []
	for id in EXPECTED:
		var sprite := Bolt.sprite(id)
		_expect(sprite != null and sprite == Bolt.sprite(id) and sprite.region.size.y > 0, id + " shared region exists")
		var model := _model(id, 6)
		for step in range(65):
			model.step([{"type": "aim", "x_milli": 1840000, "y_milli": 555000}, {"type": "fire_started"}] if step == 0 else [])
		var snapshot := model.snapshot()
		snapshot["enemies"] = []
		snapshot["defenses"] = {"lava_moat_level": 5, "magic_tower_level": 5}
		game.call("_on_snapshot", snapshot)
		await _capture(id + "-full-rate-1080p")
		viewport.size = Vector2i(1280, 720)
		await _capture(id + "-full-rate-720p")
		viewport.size = Vector2i(1920, 1080)
		# Compare pixels from the actual gameplay path at an identical location.
		# Crit, knockback and poison may change combat, but never the bolt sprite.
		var arrow := {"entity_id": 9999, "weapon_id": id, "x_milli": 1400000, "y_milli": 555000, "vx_milli": 62000, "vy_milli": 0, "fatal": false, "power": false, "poison_damage": 0}
		snapshot["projectiles"] = []
		game.call("_on_snapshot", snapshot)
		var empty := await _pixels()
		snapshot["projectiles"] = [arrow]
		game.call("_on_snapshot", snapshot)
		var plain := await _pixels()
		if plain != null:
			_expect(plain.get_data() != empty.get_data(), id + " arrow renders visible pixels")
			signatures.append(hash(plain.get_data()))
		for flags in [{"fatal": true}, {"poison_damage": 12}, {"fatal": true, "power": true, "poison_damage": 12}]:
			arrow["fatal"] = false
			arrow["power"] = false
			arrow["poison_damage"] = 0
			arrow.merge(flags, true)
			game.call("_on_snapshot", snapshot)
			var flagged := await _pixels()
			if flagged != null:
				_expect(flagged.get_data() == plain.get_data(), id + " flags do not change any projectile pixels: " + str(flags))
	if not signatures.is_empty():
		var unique := {}
		for signature in signatures:
			unique[signature] = true
		_expect(unique.size() == 4, "four weapons produce four distinct physical bolt designs")
	game.free()
	viewport.free()


func _pixels() -> Image:
	if DisplayServer.get_name().contains("headless"):
		return null
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image().get_region(Rect2i(1280, 520, 160, 70))


func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name().contains("headless"):
		return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_expect(viewport.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png")) == OK, "capture " + label)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
