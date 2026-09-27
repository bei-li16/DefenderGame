extends SceneTree
## Serial, isolated --script fixture. Exercises real presentation event routing
## and captures actual Godot frames, not a mockup of the desired appearance.
const Motion = preload("res://src/presentation/art/creature_animation.gd")
const Art = preload("res://src/presentation/art/game_art.gd")
const Creatures = preload("res://src/presentation/art/creature_visuals.gd")
const OUTPUT := "res://Builds/creature-review"
var app: Node
var passes := 0
var failures: Array[String] = []
var viewport: SubViewport
var game: Node2D
var sample: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	app.get("settings")["sfx_volume"] = 0.0
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	app.set("profile", profile)
	_check_assets()
	_check_states()
	await _check_gameplay()
	await _check_live_bosses()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[CREATURE FAIL] " + failure)
	print("[CREATURE ANIMATION] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _enemy(id: String, entity: int = 1) -> Dictionary:
	for definition in app.get("content").rules["enemies"]:
		if str(definition["id"]) == id:
			var enemy: Dictionary = definition.duplicate(true)
			enemy.merge({"enemy_id": id, "entity_id": entity, "max_hp": enemy["hp"], "x_milli": 1080000, "y_milli": 620000, "attack_cooldown": 20, "special_counter": 0}, true)
			return enemy
	return {}


func _check_assets() -> void:
	for art in Motion.SETTINGS:
		var sheet := Art.texture("anim_" + art)
		_expect(sheet != null and sheet.get_width() <= 2048, art + " imported bounded sheet")
		var distinct := {}
		for row in range(4):
			for frame in range(6):
				var cell := Motion.cell(art, row, frame)
				var pixels := cell.get_image()
				distinct[hash(pixels.get_data())] = true
				_expect(pixels.detect_alpha() != Image.ALPHA_NONE, "%s %d/%d real alpha" % [art, row, frame])
				var rect := Motion.rectangle(art, row, frame, Vector2(900, 600))
				var actual_ratio := rect.size.x / rect.size.y
				var original_ratio := cell.region.size.x / cell.region.size.y
				_expect(absf(actual_ratio - original_ratio) < 0.004, art + " uniform pixel scale")
		_expect(distinct.size() == 24, art + " has 24 independently painted frames")


func _check_states() -> void:
	for id in Art.CREATURES:
		var enemy := _enemy(id, 11)
		var visuals := Creatures.new()
		visuals.sync([enemy])
		var actor: Dictionary = visuals.actors[11]
		visuals.advance(0.1)
		var original := JSON.stringify(enemy)
		var clock := float(actor["clock"])
		actor["enemy"]["freeze_ticks"] = 12
		visuals.advance(0.2)
		_expect(is_equal_approx(float(actor["clock"]), clock), id + " freeze holds gait")
		actor["enemy"]["freeze_ticks"] = 0
		actor["enemy"]["slow_ticks"] = 30
		actor["enemy"]["slow_permille"] = 400
		visuals.advance(0.2)
		_expect(is_equal_approx(float(actor["clock"]) - clock, 0.08), id + " slow changes gait tempo")
		_expect(JSON.stringify(enemy) == original, id + " snapshots are not mutated")
		actor["enemy"]["x_milli"] = enemy["attack_x_milli"]
		actor["enemy"]["attack_cooldown"] = 1
		_expect(Motion.pose(actor)["row"] == 1 and Motion.pose(actor)["frame"] == 2, id + " winds up before real damage")
		visuals.event({"type": "wall_damage", "entity_id": 11, "source": "enemy"})
		_expect(Motion.pose(actor)["frame"] == 3, id + " contact frame starts on damage event")
		actor["enemy"]["attack_cooldown"] = 20
		visuals.advance(0.15)
		_expect(Motion.pose(actor)["frame"] >= 4, id + " authored follow-through")
		if enemy.get("tags", []).has("boss"):
			actor["enemy"]["special_counter"] = int(enemy["special_interval_ticks"]) - 3
			_expect(Motion.pose(actor)["state"] == "special_windup", id + " telegraphs signature")
			visuals.event({"type": "boss_special", "entity_id": 11})
			_expect(Motion.pose(actor)["row"] == 2 and Motion.pose(actor)["frame"] == 3, id + " signature release frame")
		visuals.event({"type": "death", "entity_id": 11})
		visuals.event({"type": "death", "entity_id": 11})
		_expect(visuals.retired.size() == 1, id + " duplicate death does not duplicate body")
		visuals.sync([])
		visuals.advance(0.5)
		_expect(not visuals.retired.is_empty() and Motion.pose(visuals.retired[0])["row"] == 3, id + " full collapse survives actor removal")
		visuals.advance(2.0)
		_expect(visuals.retired.is_empty(), id + " corpse expires")


func _check_gameplay() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	game = (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	viewport.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	game.set("_pointer_inside_window", false)
	sample = game.get("snapshot").duplicate(true)
	sample["defenses"] = {"lava_moat_level": 0, "magic_tower_level": 0}
	sample["projectiles"] = []
	var minors: Array = []
	var ids := ["melee_basic", "armored_guard", "fast_raider", "ranged_hexer", "sky_harrier", "ember_shaman"]
	for i in range(ids.size()):
		var enemy := _enemy(ids[i], i * 2 + 11)
		enemy["x_milli"] = (760 + i % 3 * 430) * 1000
		enemy["y_milli"] = (420 + i / 3 * 340) * 1000
		minors.append(enemy)
	for action in ["walk", "windup", "attack", "hurt", "death"]:
		_set_enemies(minors)
		var visuals: RefCounted = game.get("_creatures")
		for actor in visuals.actors.values():
			actor["clock"] = 0.18
			if action == "windup":
				actor["enemy"]["attack_x_milli"] = actor["enemy"]["x_milli"]
				actor["enemy"]["attack_cooldown"] = 2
			if action in ["attack", "hurt", "death"]:
				visuals.event({"type": {"attack": "wall_damage", "hurt": "damage", "death": "death"}[action], "entity_id": actor["enemy"]["entity_id"]})
		if action == "death":
			sample["enemies"] = []
			game.call("_on_snapshot", sample)
		game.call("_process", 0.06 if action != "death" else 0.58)
		await _capture("minions-" + action)
	for id in ["ember_warlord", "frost_titan", "storm_matron"]:
		var enemy := _enemy(id, 55)
		_set_enemies([enemy])
		await _capture(id + "-walk")
		var actor: Dictionary = game.get("_creatures").actors[55]
		actor["enemy"]["special_counter"] = int(enemy["special_interval_ticks"]) - 2
		await _capture(id + "-windup")
		actor["enemy"]["special_counter"] = 0
		game.call("_on_events", [{"type": "boss_special", "entity_id": 55, "special": enemy["special"]}])
		game.call("_process", 0.13)
		_expect(game.get("effects").size() == 1 and game.get("effects")[0]["kind"] == "boss_wave", id + " one signature effect")
		await _capture(id + "-release")
		game.call("_process", 0.34)
		await _capture(id + "-follow-through")
		var before: Dictionary = Motion.pose(actor)
		paused = true
		game.call("_process", 0.3)
		_expect(Motion.pose(actor) == before, id + " pause freezes cast")
		paused = false
		# Basic attacks during a special must not replace the signature pose.
		game.call("_on_events", [{"type": "wall_damage", "entity_id": 55, "amount": 0, "source": "boss_special"}])
		_expect(Motion.pose(actor)["state"] == "special", id + " special damage keeps signature pose")
		game.set("effects", [] as Array[Dictionary])
		game.call("_on_events", [{"type": "death", "entity_id": 55, "boss": true}])
		sample["enemies"] = []
		game.call("_on_snapshot", sample)
		game.call("_process", 0.86)
		await _capture(id + "-death")
		await _clip(id, enemy)
		# The real attack anchor is much closer to the parapet than the isolated
		# cast showcase. Verify the extended weapon and effect there as well.
		var at_wall := enemy.duplicate(true)
		at_wall["x_milli"] = at_wall["attack_x_milli"]
		_set_enemies([at_wall])
		game.call("_on_events", [{"type": "wall_damage", "entity_id": 55, "amount": 0, "source": "enemy"}])
		game.call("_process", 0.04)
		await _capture(id + "-wall-attack")
		_set_enemies([at_wall])
		game.call("_on_events", [{"type": "boss_special", "entity_id": 55, "special": enemy["special"]}])
		game.call("_process", 0.13)
		await _capture(id + "-wall-special")
		viewport.size = Vector2i(1280, 720)
		await _capture(id + "-wall-special-720p")
		viewport.size = Vector2i(1920, 1080)
	game.free()
	viewport.free()


func _set_enemies(enemies: Array) -> void:
	game.set("_creatures", Creatures.new())
	game.set("effects", [] as Array[Dictionary])
	game.set("floating_texts", [] as Array[Dictionary])
	sample["enemies"] = enemies.duplicate(true)
	game.call("_on_snapshot", sample)
	game.get("_creatures").advance(0.18)


func _check_live_bosses() -> void:
	# Arrange one boss at the castle, then use the real fixed-tick model and
	# GameSession signals for every attack, signature and terminal death.
	for id in ["ember_warlord", "frost_titan", "storm_matron"]:
		var live := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		root.add_child(live)
		live.set_process(false)
		live.set_physics_process(false)
		live.set("_pointer_inside_window", false)
		var session: Node = live.get("session")
		session.set_physics_process(false)
		var profile: Dictionary = app.call("_default_profile")
		profile["tutorial_complete"] = true
		profile["upgrades"]["wall_repair"] = 100
		app.set("profile", profile)
		var run_id: String = "creature-live-" + str(id) + "-" + str(Time.get_ticks_usec())
		session.call("start", app.get("content").rules, "stage_001", 913, profile, run_id)
		var model: RefCounted = session.get("_model")
		model.set("spawn_queue", [{"tick": 1, "wave": 1, "enemy_id": id, "y_milli": 600000}] as Array[Dictionary])
		var counts := {"basic": 0, "special": 0, "death": 0, "contact_pose": 0, "cast_pose": 0}
		session.connect("events_produced", func(events: Array) -> void:
			for event in events:
				var kind := str(event.get("type", ""))
				if kind == "death":
					counts["death"] += 1
				var actor: Dictionary = live.get("_creatures").actors.get(int(event.get("entity_id", -1)), {})
				if actor.is_empty():
					continue
				if kind == "wall_damage" and event.get("source", "") == "enemy":
					counts["basic"] += 1
					if Motion.pose(actor)["state"] in ["attack", "special", "special_windup"]:
						counts["contact_pose"] += 1
				if kind == "boss_special":
					counts["special"] += 1
					if Motion.pose(actor)["state"] == "special" and Motion.pose(actor)["frame"] == 3:
						counts["cast_pose"] += 1
		)
		for tick in range(390):
			session.call("_physics_process", 1.0 / 30.0)
			if tick == 0:
				model.get("enemies")[0]["x_milli"] = model.get("enemies")[0]["attack_x_milli"]
			live.call("_process", 1.0 / 30.0)
			if tick % 30 == 0:
				await process_frame
		_expect(counts["basic"] > 10 and counts["special"] >= 2, id + " real model exercises basic and signature cycles")
		_expect(counts["cast_pose"] == counts["special"] and counts["contact_pose"] == counts["basic"], id + " real event/pose timing matches")
		model.get("enemies")[0]["hp"] = 0
		session.call("_physics_process", 1.0 / 30.0)
		_expect(model.get("status") == "victory" and counts["death"] == 1, id + " core terminates before presentation delay")
		_expect(live.get("_result_overlay") == null and live.get("_result_delay") > 1.0, id + " final boss collapse remains visible")
		_expect(not app.get("profile")["reward_ledger"].is_empty(), id + " rewards persisted before collapse delay")
		live.call("_process", 0.7)
		_expect(live.get("_result_overlay") == null and not live.get("_creatures").retired.is_empty(), id + " death remains visible mid-collapse")
		live.call("_process", 0.7)
		_expect(live.get("_result_overlay") != null and live.get("_pending_result").is_empty(), id + " result appears once after collapse")
		print("[CREATURE LIVE] %s %s" % [id, counts])
		live.free()


func _clip(id: String, enemy: Dictionary) -> void:
	if not OS.get_cmdline_user_args().has("--movie") or DisplayServer.get_name().contains("headless"):
		return
	_set_enemies([enemy])
	var original_size := viewport.size
	viewport.size = Vector2i(960, 540)
	var visuals: RefCounted = game.get("_creatures")
	var actor: Dictionary = visuals.actors[55]
	for frame in range(120):
		var t := frame / 20.0
		if t < 1.0:
			actor["enemy"]["x_milli"] = 1100000
		elif t < 2.0:
			actor["enemy"]["special_counter"] = int(enemy["special_interval_ticks"]) - int((2.0 - t) * 30)
		elif frame == 40:
			actor["enemy"]["special_counter"] = 0
			game.call("_on_events", [{"type": "boss_special", "entity_id": 55, "special": enemy["special"]}])
		elif frame == 67:
			game.set("effects", [] as Array[Dictionary])
			game.call("_on_events", [{"type": "death", "entity_id": 55, "boss": true}])
			sample["enemies"] = []
			game.call("_on_snapshot", sample)
		game.call("_process", 1.0 / 20.0)
		await _capture("frames/" + id + "/%04d" % frame)
	viewport.size = original_size


func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name().contains("headless"):
		return
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var path := OUTPUT.path_join(label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := viewport.get_texture().get_image()
	_expect(image.save_png(path) == OK, "capture " + label)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
