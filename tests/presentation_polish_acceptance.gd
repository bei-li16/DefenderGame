extends SceneTree

const RunModel = preload("res://src/core/combat/run_model.gd")
const Audio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const Bank = preload("res://src/infrastructure/audio/sound_bank.gd")
const FailingSave = preload("res://tests/support/failing_save_service.gd")
var app: Node
var passes := 0
var failures: Array[String] = []
const OUTPUT := "res://Builds/polish-review-20260922"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	if OS.get_cmdline_user_args().has("--interactive"):
		_prepare_visual_profile()
		# High wall HP and no passive damage allow time to inspect real inputs.
		app.get("profile")["highest_unlocked_stage"] = 30
		app.get("profile")["upgrades"]["wall_repair"] = 100000
		app.get("profile")["upgrades"]["strength"] = 10
		var preview := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(preview)
		current_scene = preview
		print("[POLISH PLAYTEST] Isolated test profile; close the game to finish.")
		return
	_check_gameplay()
	_check_audio()
	await _check_views()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[POLISH FAIL] " + failure)
	print("[POLISH] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_gameplay() -> void:
	var config: Dictionary = app.get("content").rules
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["honors"]["great_mage"] = 3
	profile["upgrades"]["coin_bounty"] = 10
	var model := RunModel.new()
	model.setup(config, "stage_001", 907, profile, "polish-empty")
	_expect(model.mana == model.max_mana and model.mana > 120, "honor mana is full on entry")
	model.debug_force_wall_damage(model.wall_max_hp)
	model.step([])
	_expect(model.result()["coins"] == 0, "zero-kill defeat cannot farm completion bounty")
	model.setup(config, "stage_001", 907, profile, "polish-kills")
	model.coins_earned = 23
	model.kills = 1
	model.debug_force_wall_damage(model.wall_max_hp)
	model.step([])
	_expect(model.result()["coins"] == 23, "defeat retains actual kill earnings only")
	model.setup(config, "stage_001", 907, profile, "polish-victory")
	model.status = "victory"
	_expect(model.result()["coins"] == int(model.stage["clear_reward"]["coins"]) + 10, "victory still includes researched completion bounty")
	# Real commands -> model result -> transaction -> disk -> idempotent retry.
	profile["stats"]["fire_casts"] = 199
	app.set("profile", profile)
	model.setup(config, "stage_001", 907, profile, "polish-elements")
	for id in ["fire_ball", "glacial_spike", "lightning_strike"]:
		model.step([{"type": "cast_skill", "skill_id": id, "x_milli": 950000, "y_milli": 500000}])
	model.debug_force_wall_damage(model.wall_max_hp)
	model.step([])
	var result := model.result()
	for element in ["fire", "ice", "lightning"]:
		_expect(int(result.get(element + "_casts", 0)) == 1, element + " actual cast reaches Result")
	var original_save: Variant = app.get("save_service")
	var fail := FailingSave.new("user://polish-save-failure")
	app.set("save_service", fail)
	var before := JSON.stringify(app.get("profile"))
	var failed: Dictionary = app.call("settle_run", result)
	_expect(not failed["ok"] and JSON.stringify(app.get("profile")) == before, "failed settlement cannot advance elemental honor")
	app.set("save_service", original_save)
	var settled: Dictionary = app.call("settle_run", result)
	_expect(settled["ok"] and int(app.get("profile")["honors"].get("fire_master", 0)) == 1, "actual fire cast crosses honor threshold")
	var saved: Dictionary = original_save.load_profile_slot(1, {})
	_expect(int(saved.get("payload", {}).get("stats", {}).get("fire_casts", 0)) == 200, "cast count survives save/reload")
	var second: Dictionary = app.call("settle_run", result)
	_expect(second.get("duplicate", false) and int(app.get("profile")["stats"]["fire_casts"]) == 200, "settlement retry never double-counts casts")

func _check_audio() -> void:
	_expect(Audio.gain_db(0.0) == -80, "zero-volume music has a silent gain")
	var mixer := Audio.new()
	_expect(mixer.allow_event("fire", 1000) and not mixer.allow_event("fire", 1030) and mixer.allow_event("fire", 1110), "dense impacts are rate limited")
	_expect(mixer.allow_event("boss", 1030), "boss alert is independent of impact gate")
	mixer.free()
	var total_bytes := 0
	for mood in ["menu", "battle", "boss"]:
		var score := Bank.music(mood)
		var bytes := score.data
		total_bytes += bytes.size()
		var peak := 0
		for i in range(0, bytes.size(), 2):
			peak = maxi(peak, absi(bytes.decode_s16(i)))
		_expect(peak > 1000 and peak < 30000, mood + " score is non-silent and unclipped")
		_expect(absi(bytes.decode_s16(0)) <= 1 and absi(bytes.decode_s16(bytes.size() - 2)) < 100, mood + " loop edges fade to zero")
		_expect(score.loop_end == bytes.size() / 2 and score.get_length() >= 8, mood + " four-bar score has complete loop bounds")
		if OS.get_cmdline_user_args().has("--capture"):
			DirAccess.make_dir_recursive_absolute(OUTPUT)
			score.save_to_wav(OUTPUT + "/" + mood + ".wav")
	_expect(total_bytes < 1500000, "three music scores stay within 1.5 MB PCM budget")
	for kind in ["shot", "hit", "fire", "ice", "lightning", "victory", "defeat"]:
		var clip := Bank.effect(kind)
		_expect(clip.loop_mode == AudioStreamWAV.LOOP_DISABLED and clip.data.decode_s16(0) == 0, kind + " foley has attack ramp and no loop")

func _prepare_visual_profile() -> void:
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["highest_unlocked_stage"] = 30
	profile["coins"] = 25000
	profile["crystals"] = 240
	for skill in app.get("content").rules["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = 3
		if int(skill["tier"]) == 3:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	profile["upgrades"]["mana_capacity"] = 30
	app.set("profile", profile)
	app.get("settings")["auto_fire"] = false

func _check_views() -> void:
	_prepare_visual_profile()
	var mixer: Node = app.get("audio")
	if not DisplayServer.get_name().contains("headless"):
		_expect(mixer.get("_players").size() == 10 and mixer.get("_music_players").size() == 2, "bounded SFX voices and crossfade players exist")
		mixer.play_music("boss", 0)
		mixer.call("_process", 1.0)
		_expect(mixer.get("_music_players")[mixer.get("_active_music")].volume_db == -80, "runtime music slider zero applies silence floor")
		mixer.set_music_volume(0.65)
		mixer.set_ducked(true)
		mixer.call("_process", 1.0)
		_expect(is_equal_approx(mixer.get("_duck"), 0.32), "pause/result duck reaches target")
		mixer.set_ducked(false)
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		app.get("audio").set_ducked(true)
		var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(menu)
		await _frames(3)
		_expect(menu.find_child("ContinueButton", true, false) != null and menu.find_child("StageBriefing", true, false) != null and is_equal_approx(app.get("audio").get("_duck_target"), 1.0), locale + " menu has CTA/briefing and restores full music after battle")
		await _capture(locale + "-menu")
		menu.call("_show_research_page", "magic", "armageddon")
		await _frames(3)
		await _capture(locale + "-research")
		menu.free()
	app.get("settings")["language"] = "zh_CN"
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	current_scene = game
	var session: Node = game.get("session")
	session.set_physics_process(false)
	game.set_physics_process(false)
	await _frames(2)
	var hud: Control = game.get("_hud")
	_expect(hud.find_child("StatusPanel", true, false).mouse_filter == Control.MOUSE_FILTER_IGNORE, "status panel allows battlefield clicks through")
	_expect(not hud.get("_boss_panel").get_global_rect().intersects(hud.feedback_label.get_global_rect()), "boss health and alert text do not overlap")
	game.call("_on_focus_lost")
	_expect(paused and game.get("_pause_overlay") != null, "focus loss pauses a running battle")
	game.call("_resume_game")
	_expect(not paused, "only explicit resume returns to combat")
	game.call("_feedback", "BOSS", Color.WHITE, 3, 3)
	game.call("_feedback", "minor hit", Color.WHITE)
	_expect(hud.feedback_label.text == "BOSS", "minor effects cannot overwrite critical alerts")
	game.set("_feedback_timer", 0)
	hud.feedback_label.text = ""
	var model: RefCounted = session.get("_model")
	# Sample actual spawned enemies and all three real barrage plans.
	for i in range(240):
		model.step([])
	for index in range(model.enemies.size()):
		model.enemies[index]["x_milli"] = 700000 + index * 145000
		model.enemies[index]["y_milli"] = 300000 + index % 3 * 180000
	model.step([{"type": "cast_skill", "skill_id": "armageddon"}, {"type": "cast_skill", "skill_id": "ice_age"}, {"type": "cast_skill", "skill_id": "ragnarok"}])
	for i in range(45):
		var events: Array = model.step([])
		game.call("_on_events", events)
		game.call("_on_snapshot", model.snapshot())
		game.call("_process", 1.0 / 30)
	game.set_process(false)
	await _frames(3)
	await _capture("battle-vfx")
	var boss_model := RunModel.new()
	boss_model.setup(app.get("content").rules, "stage_010", 42, app.get("profile"), "polish-boss")
	boss_model.wall_hp = 10000000
	for i in range(3600):
		boss_model.step([])
		if boss_model.enemies.any(func(enemy: Dictionary) -> bool: return enemy.get("tags", []).has("boss")):
			break
	var boss_snapshot := boss_model.snapshot()
	boss_snapshot["wall_hp"] = int(boss_snapshot["wall_max_hp"] * 0.2)
	_expect(boss_snapshot["enemies"].any(func(enemy: Dictionary) -> bool: return enemy.get("tags", []).has("boss")), "boss visual fixture contains an actually spawned boss")
	# Preserve model-derived boss state, adding only the floor presentation flag.
	boss_snapshot["defenses"]["lava_moat_level"] = 3
	game.call("_on_snapshot", boss_snapshot)
	game.get("effects").clear()
	game.get("floating_texts").clear()
	game.call("_process", 1.0 / 30)
	game.call("_feedback", app.call("text", "hud.wall_critical"), Color("ff7697"), 3.5, 3)
	await _frames(3)
	await _capture("battle-boss-lava")
	game.call("_show_quick_settings")
	await _frames(3)
	await _capture("quick-settings")
	game.call("_resume_game")
	game.call("_show_result", {"status": "defeat", "stage_number": 1, "tick": 2700, "spells_cast": 3, "kills": 14, "wave": 2, "wave_total": 3, "wall_percent": 0, "coins": 120, "xp": 100}, {"ok": true})
	await _frames(3)
	_expect(game.find_child("ResultResearchButton", true, false) != null, "defeat offers direct research route")
	await _capture("result")
	current_scene = null
	game.free()
	app.set("menu_destination", "research")
	var research_menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(research_menu)
	await _frames(2)
	_expect(app.get("menu_destination") == "" and research_menu.find_child("Research_strength", true, false) != null, "research destination is consumed once")
	research_menu.free()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	root.get_texture().get_image().save_png(OUTPUT + "/" + name + ".png")

func _expect(value: bool, description: String) -> void:
	if value:
		passes += 1
	else:
		failures.append(description)
