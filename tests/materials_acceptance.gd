extends SceneTree

const Art = preload("res://src/presentation/art/game_art.gd")
const Creatures = preload("res://src/presentation/art/creature_visuals.gd")
var failures: Array[String] = []
var passes := 0
var app: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	if OS.get_cmdline_user_args().has("--verify-pack"):
		_expect(not ResourceLoader.exists("res://tests/run_all.gd") and not DirAccess.dir_exists_absolute("res://参考"), "pack excludes original reference images and test scripts")
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["upgrades"]["lava_moat"] = 1
	profile["upgrades"]["magic_tower"] = 1
	app.set("profile", profile)
	app.get("settings")["auto_fire"] = false
	for key in Art.FILES:
		var texture := Art.texture(key)
		_expect(texture != null and texture.get_width() > 0, "imported " + key)
		if texture != null and not key in ["menu", "battle", "lava"]:
			_expect(maxi(texture.get_width(), texture.get_height()) <= 1024, "bounded texture " + key)
	_expect(Art.FILES["power_bow"] == "武器图标4" and Art.FILES["hurricane_bow"] == "武器图标2", "weapon mapping follows actual colors")
	_expect(Art.FILES["wall"] == "主城墙new", "runtime and exported pack select the new complete fortress")
	var upper_uv := Rect2(0.05, 0, 0.91, 0.55)
	var upper_vertices: PackedVector2Array = Art.quad(upper_uv).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	_expect(upper_vertices[0].is_equal_approx(upper_uv.position) and upper_vertices[2].is_equal_approx(upper_uv.end), "turret mesh respects atlas region instead of duplicating the entire image")
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames(3)
	await _capture("01-menu")
	menu.call("_show_research_page", "weapons", "unlock_power_bow")
	await _frames(3)
	await _capture("02-weapons")
	menu.free()
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	var sample: Dictionary = game.get("snapshot").duplicate(true)
	var enemies: Array = []
	var index := 0
	for definition in app.get("content").rules["enemies"]:
		var enemy: Dictionary = definition.duplicate(true)
		enemy["enemy_id"] = definition["id"]
		enemy["entity_id"] = index + 1
		enemy["max_hp"] = enemy["hp"]
		enemy["x_milli"] = (680 + (index % 3) * 465) * 1000
		enemy["y_milli"] = (320 + (index / 3) * 235) * 1000
		enemy["attack_cooldown"] = 15
		enemies.append(enemy)
		index += 1
	var spike: Dictionary = enemies[1].duplicate(true)
	spike["entity_id"] = 21
	spike["x_milli"] = 900000
	spike["y_milli"] = 410000
	enemies.append(spike)
	sample["enemies"] = enemies
	sample["projectiles"] = [{"x_milli": 900000, "y_milli": 540000, "vx_milli": 40000, "vy_milli": 0}]
	game.call("_on_snapshot", sample)
	var visuals: RefCounted = game.get("_creatures")
	var original := JSON.stringify(sample)
	visuals.call("advance", 0.1)
	_expect(JSON.stringify(sample) == original, "animation does not mutate authoritative snapshots")
	_expect(visuals.get("actors").size() == 10, "all enemy archetypes plus cosmetic variant")
	game.queue_redraw()
	await _frames(3)
	await _capture("03-bestiary")
	var first: Dictionary = visuals.get("actors")[1]
	var initial_clock := float(first["clock"])
	game.call("_on_events", [{"type": "wall_damage", "entity_id": 1, "amount": 0}])
	_expect(is_zero_approx(float(game.get("_shake_strength"))) and game.get("_hud").feedback_label.text.is_empty(), "fully armored hits animate without false HP-loss feedback")
	first["enemy"]["freeze_ticks"] = 30
	visuals.call("advance", 0.2)
	_expect(is_equal_approx(initial_clock, float(first["clock"])), "freeze stops locomotion")
	first["enemy"]["freeze_ticks"] = 0
	first["enemy"]["stun_ticks"] = 30
	visuals.call("advance", 0.2)
	_expect(is_equal_approx(initial_clock, float(first["clock"])), "stun stops locomotion")
	first["enemy"]["stun_ticks"] = 0
	first["enemy"]["slow_ticks"] = 30
	first["enemy"]["slow_permille"] = 400
	visuals.call("advance", 0.2)
	_expect(is_equal_approx(float(first["clock"]) - initial_clock, 0.08), "slow scales locomotion clock")
	var live_clock := float(first["clock"])
	var battlefield_clock := float(game.get("_elapsed_visual"))
	paused = true
	game.call("_process", 0.2)
	_expect(is_equal_approx(live_clock, float(first["clock"])) and is_equal_approx(battlefield_clock, float(game.get("_elapsed_visual"))), "pause freezes battlefield and actors")
	paused = false
	for enemy in enemies:
		enemy["x_milli"] = enemy.get("attack_x_milli", 350000)
		enemy["y_milli"] = 200000 + int(enemy["entity_id"]) * 68000
		enemy["attack_cooldown"] = 25
	# Keep bosses separately legible in the attack review.
	enemies[6]["y_milli"] = 360000
	enemies[6]["x_milli"] = 850000
	enemies[7]["y_milli"] = 700000
	enemies[7]["x_milli"] = 1000000
	enemies[8]["y_milli"] = 520000
	enemies[8]["x_milli"] = 1460000
	enemies[9]["y_milli"] = 810000
	game.call("_on_snapshot", sample)
	game.call("_on_events", [{"type": "wall_damage", "entity_id": 3, "amount": 10}, {"type": "defense_attack", "defense_id": "magic_tower", "x_milli": 1000000, "y_milli": 700000}])
	_expect(float(visuals.get("actors")[3]["attack"]) > 0.0, "real wall damage triggers attack pose")
	game.call("_process", 0.12)
	game.queue_redraw()
	await _frames(3)
	await _capture("04-attacks")
	visuals.call("event", {"type": "death", "entity_id": 1})
	_expect(visuals.get("retired").size() == 1, "death keeps one fading sprite")
	visuals.call("sync", [])
	_expect(visuals.get("actors").is_empty(), "removed actors are pruned")
	visuals.call("advance", 0.6)
	_expect(visuals.get("retired").is_empty(), "death sprites expire")
	for number in range(80):
		visuals.call("sync", [enemies[0]])
		visuals.call("event", {"type": "death", "entity_id": 1})
	_expect(visuals.get("retired").size() == Creatures.CORPSE_LIMIT, "corpse queue is bounded")
	var walk := Creatures._pose_mesh("flutter", "walk", 4)
	_expect(walk == Creatures._pose_mesh("flutter", "walk", 4), "pose meshes are reused")
	_expect(walk.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != Creatures._pose_mesh("flutter", "walk", 12).surface_get_arrays(0)[Mesh.ARRAY_VERTEX], "wing geometry visibly changes")
	# Render 100 animated creatures / 200 arrows after warming shared poses.
	var crowd: Array = []
	var arrows: Array = []
	for number in range(100):
		var enemy: Dictionary = enemies[number % 6].duplicate(true)
		enemy["entity_id"] = number + 100
		enemy["x_milli"] = (550 + number % 10 * 135) * 1000
		enemy["y_milli"] = (240 + number / 10 * 68) * 1000
		crowd.append(enemy)
	for number in range(200):
		arrows.append({"x_milli": (400 + number % 20 * 74) * 1000, "y_milli": (265 + number / 20 * 63) * 1000, "vx_milli": 40000, "vy_milli": 0})
	sample["enemies"] = crowd
	sample["projectiles"] = arrows
	game.call("_on_snapshot", sample)
	visuals.call("advance", 0.6)
	var visual_begin := Time.get_ticks_usec()
	for frame in range(90):
		game.call("_process", 1.0 / 60.0)
		await process_frame
	var frame_ms := float(Time.get_ticks_usec() - visual_begin) / 90000.0
	print("[MATERIALS] 100 creatures / 200 arrows: mean frame %.2f ms (%s)" % [frame_ms, DisplayServer.get_name()])
	_expect(visuals.get("actors").size() == 100 and visuals.get("retired").is_empty(), "stress population stays bounded")
	await _capture("05-crowd")
	game.free()
	await _check_live_session()
	print("[MATERIALS] %d passed, %d failed" % [passes, failures.size()])
	for failure in failures:
		printerr("[MATERIALS FAIL] " + failure)
	quit(0 if failures.is_empty() else 1)


func _check_live_session() -> void:
	# Exercise the real GameSession event/snapshot path, not a hand-made pose.
	var previous_profile: Dictionary = app.get("profile").duplicate(true)
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["upgrades"]["wall_armor"] = 10
	profile["upgrades"]["strength"] = 8
	app.set("profile", profile)
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	var session: Node = game.get("session")
	session.set_physics_process(false)
	var counts := {"wall_damage": 0, "shot": 0, "death": 0}
	session.connect("events_produced", func(events: Array) -> void:
		for event in events:
			var kind := str(event.get("type", ""))
			if counts.has(kind):
				counts[kind] += 1
	)
	for tick in range(1100):
		var snapshot: Dictionary = session.call("current_snapshot")
		if str(snapshot.get("status", "")) != "running":
			break
		if tick == 670:
			session.call("queue_command", {"type": "fire_started"})
		var enemies: Array = snapshot.get("enemies", [])
		if not enemies.is_empty():
			enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["x_milli"]) < int(b["x_milli"]))
			session.call("queue_command", {"type": "aim", "x_milli": enemies[0]["x_milli"], "y_milli": enemies[0]["y_milli"]})
		session.call("_physics_process", 1.0 / 30.0)
		game.call("_process", 1.0 / 60.0)
		game.call("_process", 1.0 / 60.0)
		if tick == 450:
			var moving_snapshot: Dictionary = session.call("current_snapshot")
			var moving_visuals: RefCounted = game.get("_creatures")
			_expect(not moving_snapshot.get("enemies", []).is_empty(), "live interpolation check has actual moving enemies")
			for enemy in moving_snapshot.get("enemies", []):
				var position: Vector2 = moving_visuals.get("actors")[int(enemy["entity_id"])]["position"]
				var target := Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0
				_expect(position.distance_to(target) < 0.1, "live movement interpolates to authoritative position")
		if tick == 650:
			game.queue_redraw()
			await _capture("06-live-stage")
		if tick % 30 == 0:
			await process_frame
	var snapshot: Dictionary = session.call("current_snapshot")
	_expect(int(counts["wall_damage"]) > 0, "live stage enemies reach the wall and attack")
	_expect(int(counts["shot"]) > 0 and int(counts["death"]) > 0, "live stage arrows produce authoritative deaths")
	var visuals: RefCounted = game.get("_creatures")
	_expect(visuals.get("actors").size() == snapshot.get("enemies", []).size(), "live stage visual population matches the core")
	print("[MATERIALS LIVE] %s tick=%d" % [counts, int(snapshot.get("tick", 0))])
	game.queue_redraw()
	await _frames(3)
	game.free()
	app.set("profile", previous_profile)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)


func _frames(count: int) -> void:
	for index in range(count):
		await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	var path := "res://Builds/materials-review"
	DirAccess.make_dir_recursive_absolute(path)
	var result := root.get_texture().get_image().save_png(path.path_join(label + ".png"))
	_expect(result == OK, "captured " + label)
