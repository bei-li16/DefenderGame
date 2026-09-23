extends SceneTree
## Serial only: standard --script profile isolation; never touches player saves.
const Bank = preload("res://src/infrastructure/audio/sound_bank.gd")
const Audio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const OUTPUT := "res://Builds/audio-review"
var passes := 0
var failures: Array[String] = []
var app: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	_check_assets()
	_expect(Audio.event_kind({"type": "shot", "fatal": true}) == "shot", "critical shot retains mechanical release")
	_expect(Audio.event_kind({"type": "shot", "volley_index": 1}).is_empty(), "extra volley arrows do not release another string")
	_expect(Audio.event_kind({"type": "hit", "fatal": true}) == "hit", "critical contact retains physical target impact")
	_expect(Audio.event_kind({"type": "damage", "source": "arrow"}).is_empty(), "damage does not duplicate contact sound")
	_expect(Audio.event_kind({"type": "skill_cast", "element": "fire"}).is_empty(), "cast does not duplicate launch sound")
	if not DisplayServer.get_name().contains("headless"):
		_check_voices()
		if OS.get_cmdline_user_args().has("--capture"):
			await _capture_battle()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[COMBAT AUDIO FAIL] " + failure)
	print("[COMBAT AUDIO] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_assets() -> void:
	var total := 0
	var hashes := {}
	for kind in Bank.SAMPLED_KINDS:
		var variants := Bank.effect_variants(kind)
		_expect(variants.size() == 3 and Bank.effect(kind) == variants[0], kind + " loads three cached recorded variants")
		for clip in variants:
			_expect(clip != null and clip.format == AudioStreamWAV.FORMAT_16_BITS and clip.mix_rate == 44100 and not clip.stereo, kind + " preserves uncompressed mono 44.1 kHz PCM")
			if clip == null or clip.format != AudioStreamWAV.FORMAT_16_BITS:
				continue
			var bytes := clip.data
			total += bytes.size()
			hashes[hash(bytes)] = true
			var peak := 0
			var energy := 0.0
			var mean := 0.0
			for index in range(0, bytes.size(), 2):
				var value := bytes.decode_s16(index)
				peak = maxi(peak, absi(value))
				energy += float(value) * value
				mean += value
			var count := bytes.size() / 2
			_expect(peak > 6000 and peak < 25000 and sqrt(energy / count) > 100, kind + " has useful dynamics and headroom")
			_expect(absf(mean / count) < 20 and bytes.decode_s16(0) == 0 and bytes.decode_s16(bytes.size() - 2) == 0, kind + " has no DC or boundary clicks")
			_expect(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and clip.get_length() < 1.5, kind + " is a bounded one-shot")
	_expect(total < 1500000 and hashes.size() == 24, "24 distinct clips stay below 1.5 MB decoded PCM")


func _check_voices() -> void:
	var mixer: Node = app.get("audio")
	mixer.stop_all()
	var players: Array = mixer.get("_players")
	mixer.play_event({"type": "shot"}, 0)
	_expect(players.all(func(p: AudioStreamPlayer) -> bool: return p.stream == null), "muted effects allocate no playback")
	mixer.play_event({"type": "shot", "fatal": true}, .85)
	var bow: AudioStreamPlayer = players[9]
	var bow_clip := bow.stream
	mixer.play_event({"type": "hit"}, .85)
	mixer.play_event({"type": "skill_launch", "element": "fire"}, .85)
	for element in ["fire", "ice", "lightning"]:
		mixer.play_event({"type": "skill_pulse", "element": element}, .85)
	mixer.play_event({"type": "boss_warning"}, .85)
	_expect(bow.playing and bow.stream == bow_clip and players[11].playing, "hit, launch, spells and alert preserve the active bow release")
	_expect(players[6].playing and players[0].playing and players[1].playing and players[2].playing and players[14].playing, "all three elements overlap without stealing launch or alert voices")
	_expect(bow.stream == Bank.effect("shot") and bow.pitch_scale > .95, "critical bow remains a natural recording")
	mixer.get("_last_play").erase("shot")
	mixer.play_event({"type": "shot"}, .85)
	_expect(players[10].stream == Bank.effect_variants("shot")[1] and bow.stream == bow_clip, "next release uses a different recording in a free voice")
	_expect(players.size() == Audio.PLAYER_COUNT, "voice pool remains bounded")
	var limited := false
	for index in range(AudioServer.get_bus_effect_count(0)):
		var effect := AudioServer.get_bus_effect(0, index)
		limited = limited or (effect is AudioEffectHardLimiter and effect.ceiling_db <= -1)
	_expect(limited, "master limiter protects overlapping spells and music")
	mixer.stop_all()
	_expect(players.all(func(p: AudioStreamPlayer) -> bool: return not p.playing and p.stream == null), "cleanup stops and releases every combat voice")


func _capture_battle() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	for key in ["mana_capacity", "agility", "fatal_blow"]:
		profile["upgrades"][key] = 30
	profile["upgrades"]["multiple_arrows"] = 3
	for skill in app.get("content").rules["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = 3
		if int(skill["tier"]) == 3:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	app.set("profile", profile)
	app.get("settings")["music_volume"] = 0.0
	app.get("settings")["sfx_volume"] = .85
	app.get("settings")["auto_fire"] = false
	var rules: Dictionary = app.get("content").rules.duplicate(true)
	rules["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 20, "interval_ticks": 1}]
	rules["enemies"][0]["hp"] = 100000000
	rules["enemies"][0]["speed_milli_per_tick"] = 1
	var model := RunModel.new()
	model.setup(rules, "stage_001", 82941, profile, "combat-audio-review")
	for tick in range(90):
		model.step([])
	for i in range(model.enemies.size()):
		model.enemies[i]["x_milli"] = 590000 + (i % 5) * 180000
		model.enemies[i]["y_milli"] = 520000 + (i / 5) * 20000
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	app.get("audio").stop_all()
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 2.0
	var effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0, capture)
	var recording := PackedVector2Array()
	var counts := {}
	for tick in range(300):
		var commands: Array = [{"type": "aim", "x_milli": 700000, "y_milli": 555000}]
		if tick == 0: commands.append({"type": "fire_started"})
		if tick == 40:
			for id in ["armageddon", "ice_age", "ragnarok"]:
				commands.append({"type": "cast_skill", "skill_id": id})
		var events: Array = model.step(commands)
		for event in events:
			var kind := Audio.event_kind(event)
			if not kind.is_empty(): counts[kind] = int(counts.get(kind, 0)) + 1
		game.call("_on_snapshot", model.snapshot())
		game.call("_on_events", events)
		game.call("_process", 1.0 / 30)
		await create_timer(1.0 / 30).timeout
		recording.append_array(capture.get_buffer(capture.get_frames_available()))
	game.free()
	app.get("audio").stop_all()
	AudioServer.remove_bus_effect(0, effect_index)
	var data := PackedByteArray()
	data.resize(recording.size() * 4)
	var peak := 0.0
	var energy := 0.0
	for index in range(recording.size()):
		var frame := recording[index]
		peak = maxf(peak, maxf(absf(frame.x), absf(frame.y)))
		energy += frame.length_squared()
		data.encode_s16(index * 4, clampi(int(frame.x * 32767), -32767, 32767))
		data.encode_s16(index * 4 + 2, clampi(int(frame.y * 32767), -32767, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(AudioServer.get_mix_rate())
	wav.stereo = true
	wav.data = data
	_expect(wav.save_to_wav(OUTPUT + "/battle-mix.wav") == OK, "actual engine mix was recorded")
	_expect(peak > .1 and peak < .92 and energy > 1, "actual full barrage/rapid bow mix is audible and never clips")
	_expect(capture.get_discarded_frames() == 0, "capture has no dropped audio frames")
	for kind in ["shot", "hit", "fire", "ice", "lightning", "fire_launch", "ice_launch", "lightning_launch"]:
		_expect(int(counts.get(kind, 0)) >= 8, kind + " exercised repeatedly through real combat events")
	print("[COMBAT AUDIO MIX] peak=%.2f dB frames=%d counts=%s" % [linear_to_db(peak), recording.size(), JSON.stringify(counts)])


func _expect(condition: bool, description: String) -> void:
	if condition: passes += 1
	else: failures.append(description)
