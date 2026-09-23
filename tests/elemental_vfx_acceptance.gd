extends SceneTree
## Run serially: uses the standard isolated --script profile, never savedata/.
const Art = preload("res://src/presentation/art/game_art.gd")
const Vfx = preload("res://src/presentation/art/spell_visuals.gd")
const Bank = preload("res://src/infrastructure/audio/sound_bank.gd")
const Audio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const OUTPUT := "res://Builds/elemental-vfx-review"
var app: Node
var passes := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	_check_atlases()
	_check_audio()
	_check_audio_players()
	for tier in [1, 2, 3]:
		for element in Vfx.ELEMENTS:
			await _check_delivery(element, tier)
	await _check_mix()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[ELEMENTAL VFX FAIL] " + failure)
	print("[ELEMENTAL VFX] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_atlases() -> void:
	for element in Vfx.ELEMENTS:
		var texture := Art.texture("vfx_" + element)
		_expect(texture != null and texture.get_size() == Vector2(1024, 1024), element + " has imported bounded atlas")
		var fingerprints := {}
		for index in range(4):
			var part := Vfx.cell(element, index)
			var image := part.get_image()
			_expect(image != null and image.get_width() > 500, element + " cell%d is available" % index)
			if image == null:
				continue
			fingerprints[hash(image.get_data())] = true
			var transparent := 0
			var translucent := 0
			var visible := 0
			for y in range(0, image.get_height(), 8):
				for x in range(0, image.get_width(), 8):
					var alpha := image.get_pixel(x, y).a
					if alpha < 0.02: transparent += 1
					elif alpha < 0.95: translucent += 1
					if alpha > 0.25: visible += 1
			_expect(transparent > 100 and translucent > 100 and visible > 100, element + " cell%d has empty background, feathered edges and visible artwork" % index)
		_expect(fingerprints.size() == 4, element + " four distinct sprites, not four copies of the sheet")


func _check_audio() -> void:
	var mixer := Audio.new()
	var total := 0
	var fingerprints := {}
	for kind in Bank.ELEMENT_KINDS:
		var clip := Bank.effect(kind)
		var bytes := clip.data
		total += bytes.size()
		fingerprints[hash(bytes)] = true
		var peak := 0
		var energy := 0.0
		for index in range(0, bytes.size(), 2):
			var sample := bytes.decode_s16(index)
			peak = maxi(peak, absi(sample))
			energy += float(sample) * sample
		_expect(peak > 1000 and peak < 25000 and sqrt(energy / (bytes.size() / 2)) > 80, kind + " is audible and has PCM headroom")
		_expect(bytes.decode_s16(0) == 0 and absi(bytes.decode_s16(bytes.size() - 2)) < 20 and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED, kind + " has click-safe boundaries and no loop")
		_expect(mixer.allow_event(kind, 1000) and not mixer.allow_event(kind, 1030), kind + " dense repeat gate")
		if OS.get_cmdline_user_args().has("--capture"):
			DirAccess.make_dir_recursive_absolute(OUTPUT)
			clip.save_to_wav(OUTPUT + "/" + kind + ".wav")
	_expect(total < 500000 and fingerprints.size() == 6, "six distinct recorded elemental clips within 500 KB")
	for element in Vfx.ELEMENTS:
		_expect(Audio.event_kind({"type": "skill_launch", "element": element}) == element + "_launch", element + " wind-up sound follows launch")
		_expect(Audio.event_kind({"type": "skill_pulse", "element": element}) == element, element + " contact sound follows impact")
	_expect(Audio.event_kind({"type": "skill_cast", "element": "fire"}).is_empty(), "cast does not duplicate the first launch sound")
	mixer.free()


func _profile(tier: int) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["upgrades"]["mana_capacity"] = 30
	for skill in app.get("content").rules["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = 3
		if int(skill["tier"]) == tier:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	return profile


func _check_audio_players() -> void:
	if DisplayServer.get_name().contains("headless"):
		return
	var mixer: Node = app.get("audio")
	mixer.stop_all()
	var players: Array = mixer.get("_players")
	mixer.play_event({"type": "skill_pulse", "element": "fire", "x_milli": 600000}, 0)
	_expect(players.all(func(player: AudioStreamPlayer) -> bool: return player.stream == null), "zero SFX volume creates no voice")
	mixer.play_event({"type": "skill_pulse", "element": "fire", "x_milli": 600000}, 0.8)
	mixer.play_event({"type": "skill_launch", "element": "ice", "x_milli": 900000}, 0.8)
	mixer.play_event({"type": "shot"}, 0.8)
	mixer.play_event({"type": "boss_warning"}, 0.8)
	_expect(players.size() == Audio.PLAYER_COUNT and players[0].stream == mixer.get("_sounds")["fire"] and players[6].stream == mixer.get("_sounds")["ice_launch"] and players[9].stream == mixer.get("_sounds")["shot"] and players[14].stream == mixer.get("_sounds")["boss"], "launch/impact/weapon/alert voice groups are isolated")
	_expect(players[0].pitch_scale >= 0.975 and players[0].pitch_scale <= 1.025 and players[6].pitch_scale >= 0.975 and players[6].pitch_scale <= 1.025, "recorded elemental pitch variation stays subtle")
	mixer.stop_all()


func _fixture(profile: Dictionary, count: int = 16) -> RefCounted:
	var rules: Dictionary = app.get("content").rules.duplicate(true)
	rules["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": count, "interval_ticks": 1}]
	rules["enemies"][0]["hp"] = 100000000
	rules["enemies"][0]["speed_milli_per_tick"] = 1
	var model := RunModel.new()
	model.setup(rules, "stage_001", 2847, profile, "elemental-review")
	for ignored in range(count + 60):
		model.step([])
	for index in range(model.enemies.size()):
		model.enemies[index]["x_milli"] = 800000 + (index % 4) * 210000
		model.enemies[index]["y_milli"] = 330000 + (index / 4) * 150000
	model.enemies[0]["x_milli"] = 1100000
	model.enemies[0]["y_milli"] = 600000
	return model


func _game(profile: Dictionary) -> Node:
	app.set("profile", profile)
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	return game


func _check_delivery(element: String, tier: int) -> void:
	var profile := _profile(tier)
	# Both whole floor plates are checked; the test-only floor selection does
	# not turn on passive moat damage in the combat fixture.
	if tier == 3: profile["upgrades"]["lava_moat"] = 1
	var model := _fixture(_profile(tier))
	var reference := _fixture(_profile(tier))
	var game := _game(profile)
	var id := str(profile["equipped_skills"][element])
	var commands := [{"type": "cast_skill", "skill_id": id, "x_milli": 1100000, "y_milli": 600000}]
	var launched := 0
	var landed := 0
	var saw_flight := false
	var saw_impact := false
	var same := true
	var peak_effects := 0
	for tick in range(150):
		var events: Array = model.step(commands if tick == 0 else [])
		var expected: Array = reference.step(commands if tick == 0 else [])
		same = same and events == expected
		for event in events:
			if event["type"] == "skill_launch": launched += 1
			if event["type"] == "skill_pulse": landed += 1
		game.call("_process", 1.0 / 30)
		var snapshot: Dictionary = model.snapshot()
		if tier == 3: snapshot["defenses"]["lava_moat_level"] = 1
		var before := JSON.stringify(snapshot)
		game.call("_on_snapshot", snapshot)
		game.call("_on_events", events)
		saw_flight = saw_flight or not snapshot["falling_spells"].is_empty()
		saw_impact = saw_impact or game.get("effects").any(func(effect: Dictionary) -> bool: return effect["kind"] == "spell")
		peak_effects = maxi(peak_effects, game.get("effects").size())
		if tick in [14, 22, 52]:
			await _capture("%s-tier%d-t%03d" % [element, tier, tick])
		same = same and JSON.stringify(snapshot) == before
	_expect(same, id + " rendering and audio never mutate snapshot or deterministic event stream")
	_expect(saw_flight and saw_impact and launched == landed and launched > 0, id + " real launch and impact lifecycle")
	_expect(game.get("effects").is_empty() and model.active_spells.is_empty() and peak_effects <= 64, id + " bounded effects expire after final landing")
	game.free()


func _check_mix() -> void:
	var profile := _profile(3)
	var game := _game(profile)
	var model := _fixture(profile, 100)
	for i in range(model.enemies.size()):
		model.enemies[i]["x_milli"] = 560000 + (i % 10) * 132000
		model.enemies[i]["y_milli"] = 220000 + (i / 10) * 72 * 1000
	var commands := []
	for id in ["armageddon", "ice_age", "ragnarok"]:
		commands.append({"type": "cast_skill", "skill_id": id})
	for tick in range(60):
		var events: Array = model.step(commands if tick == 0 else [])
		game.call("_process", 1.0 / 30)
		game.call("_on_snapshot", model.snapshot())
		game.call("_on_events", events)
	var ages := JSON.stringify(game.get("effects"))
	paused = true
	game.call("_process", 0.5)
	_expect(JSON.stringify(game.get("effects")) == ages, "pause freezes every elemental effect age")
	paused = false
	for quality in ["low", "medium", "high"]:
		app.get("settings")["quality"] = quality
		# Rebuild under each budget, not merely change detail on an existing
		# high-quality queue. All tiers still resolve the same core events.
		game.get("effects").clear()
		var quality_model := _fixture(profile, 100)
		for i in range(quality_model.enemies.size()):
			quality_model.enemies[i]["x_milli"] = 560000 + (i % 10) * 132000
			quality_model.enemies[i]["y_milli"] = 220000 + (i / 10) * 72000
		for tick in range(60):
			var events: Array = quality_model.step(commands if tick == 0 else [])
			game.call("_process", 1.0 / 30)
			game.call("_on_snapshot", quality_model.snapshot())
			game.call("_on_events", events)
		_expect(game.get("effects").size() <= int(game.call("_quality_profile")["effect_limit"]), quality + " actual mixed queue respects the quality budget")
		await _capture("mixed-100-enemies-" + quality)
	if not DisplayServer.get_name().contains("headless"):
		var start := Time.get_ticks_usec()
		for frame in range(45):
			game.call("_process", 0.0)
			await process_frame
			await RenderingServer.frame_post_draw
		var ms := float(Time.get_ticks_usec() - start) / 45000.0
		print("[ELEMENTAL RENDER] 100 enemies + three showers average frame interval %.2f ms (includes frame pacing)" % ms)
		_expect(ms < 100, "graphical mixed elemental workload renders within smoke-test budget")
	game.free()


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_texture().get_image().save_png(OUTPUT + "/" + label + ".png")


func _expect(condition: bool, label: String) -> void:
	if condition: passes += 1
	else: failures.append(label)
