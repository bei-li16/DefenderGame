extends SceneTree

const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const Orchestrator = preload("res://src/application/run_orchestrator.gd")
const HonorService = preload("res://src/application/honor_service.gd")
const Validator = preload("res://src/core/rules/content_validator.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

var app: Node
var config: Dictionary
var failures: Array[String] = []
var passes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	config = app.get("content").rules
	_check_generation()
	_check_validation()
	_check_spawn_delivery()
	_check_rewards_and_saves()
	await _check_ui()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[ENDLESS FAIL] " + failure)
	print("[ENDLESS] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _profile(number: int) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["highest_unlocked_stage"] = number
	profile["tutorial_complete"] = true
	return profile


func _check_generation() -> void:
	var examples: Array[int] = [1, 10, 20, 29, 30, 31, 39, 40, 50, 60, 100, 1000, 9999, 10000, 1000000, StageCatalog.MAX_STAGE_NUMBER]
	for number in examples:
		var id := StageCatalog.id_for(number)
		var stage := StageCatalog.resolve(config, id)
		_expect(not stage.is_empty() and int(stage["number"]) == number and stage["id"] == id, "resolve stage " + str(number))
		_expect(app.get("content").find_by_id("stages", id) == stage, "content/core share stage " + str(number))
		var model := RunModel.new()
		_expect(bool(model.setup(config, id, 7711, _profile(number)).get("ok", false)) and model.snapshot()["spawn_total"] == stage["enemy_count"] and model.snapshot()["wave_total"] == stage["wave_count"], "stage %d uses actual count and mixed-wave count without double scaling" % number)
		if number > 30:
			_expect(stage["groups"].size() <= 361 and stage["wave_count"] <= 12 and stage["spawn_duration_ticks"] <= 5400, "stage %d has bounded generation work" % number)
			_expect(stage == StageCatalog.resolve(config, id), "stage %d regenerates identically" % number)
			var scales := StageCatalog.enemy_scaling(config, number)
			_expect(int(scales["hp"]) > 1850 and int(scales["damage"]) > 1600 and int(scales["speed"]) <= 1600, "stage %d increases strength within speed limits" % number)
		print("[ENDLESS CURVE] %d enemies=%d waves=%d spawn=%.1fs boss=%s hp_scale=%d" % [number, stage["enemy_count"], stage["wave_count"], float(stage["spawn_duration_ticks"]) / 30.0, str(stage.get("boss_id", stage["boss"])), StageCatalog.enemy_scaling(config, number)["hp"]])
	for invalid in ["", "stage_000", "stage_-01", "stage_1", "stage_0001", "stage_31", "stage_031abc", "stage_3.1", "stage_+31", "stage_9007199254740992", "stage_999999999999999999999"]:
		_expect(StageCatalog.resolve(config, invalid).is_empty(), "reject noncanonical/out-of-range ID: " + invalid)
	var bosses_correct := true
	var plans_correct := true
	var monotonic := true
	var previous := StageCatalog.describe(config, 31)
	for number in range(1, 601):
		var stage := StageCatalog.resolve(config, StageCatalog.id_for(number))
		var boss_count := 0
		var previous_tick := 0
		var waves := {}
		for group in stage["groups"]:
			var enemy: Dictionary = app.get("content").find_by_id("enemies", group["enemy_id"])
			if enemy["tags"].has("boss"):
				boss_count += int(group["count"])
				bosses_correct = bosses_correct and number % 10 == 0 and group["enemy_id"] == config["endless_stages"]["boss_rotation"][(number / 10 - 1) % 3]
			if bool(stage.get("generated", false)):
				plans_correct = plans_correct and group["at_tick"] >= previous_tick and group["at_tick"] <= int(config["world"]["spawn_start_tick"]) + int(stage["spawn_duration_ticks"])
				previous_tick = int(group["at_tick"])
				waves[int(group["wave"])] = true
		bosses_correct = bosses_correct and boss_count == (1 if number % 10 == 0 else 0) and bool(stage["boss"]) == (number % 10 == 0)
		if number > 30:
			plans_correct = plans_correct and waves.size() == stage["wave_count"] and waves.has(1) and waves.has(stage["wave_count"])
			monotonic = monotonic and int(stage["enemy_count"]) - int(stage["boss"]) >= int(previous["enemy_count"]) - int(previous["boss"]) and stage["wave_count"] >= previous["wave_count"] and stage["spawn_duration_ticks"] >= previous["spawn_duration_ticks"]
			previous = stage
	_expect(bosses_correct, "stages 1-600: exactly one rotating boss every 10; none on ordinary stages")
	_expect(plans_correct, "stages 31-600: complete mixed waves and ordered spawns inside each planned window")
	_expect(monotonic, "stages 31-600: normal-enemy count, waves and spawn duration never shrink")
	var early := StageCatalog.composition(config, 31, 1000)
	var late := StageCatalog.composition(config, 10000, 1000)
	_expect(int(late["armored_guard"]) > int(early["armored_guard"]) and int(late["sky_harrier"]) > int(early["sky_harrier"]) and int(late["ranged_hexer"]) > int(early["ranged_hexer"]), "late-stage mix increases armored, flying and ranged shares")
	var orchestrator := Orchestrator.new()
	_expect(bool(orchestrator.prepare(config, "stage_031", 1, _profile(31)).get("ok", false)), "unlocked generated stage passes application preparation")
	_expect(orchestrator.prepare(config, "stage_032", 1, _profile(31)).get("error_code") == "stage_locked", "generated stages still enforce sequential unlocks")
	app.set("profile", _profile(31))
	var current_id: String = app.get("current_stage_id")
	_expect(app.call("start_stage", "stage_032").get("error_code") == "stage_locked" and app.get("current_stage_id") == current_id, "direct start cannot bypass generated-stage locks or mutate run identity")
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	_expect(Validator.validate(fallback).is_empty() and fallback["endless_stages"] == config["endless_stages"] and StageCatalog.resolve(fallback, "stage_1000") == StageCatalog.resolve(config, "stage_1000"), "release fallback produces identical endless stages")


func _check_validation() -> void:
	for mutation in [
		{"boss_interval": 5}, {"boss_rotation": ["melee_basic"]}, {"boss_rotation": ["ember_warlord", "ember_warlord", "storm_matron"]},
		{"authored_stage_count": 29}, {"pressure_stage_span": 0}, {"max_active_enemies": 10000},
		{"normal_pool": [{"enemy_id": "ember_warlord", "base_weight": 1, "weight_per_pressure": 0}]},
		{"enemy_count": {"base": 70, "per_pressure": 42, "limit": 1000000}},
		{"wave_count": {"base": 4, "per_pressure": 2, "limit": 200}},
	]:
		var bad := config.duplicate(true)
		bad["endless_stages"].merge(mutation, true)
		_expect(not Validator.validate(bad).is_empty(), "reject unsafe endless rule " + str(mutation))
	var ordinary_boss := config.duplicate(true)
	ordinary_boss["stages"][4]["boss"] = true
	ordinary_boss["stages"][4]["groups"].append({"enemy_id": "ember_warlord", "count": 1, "interval_ticks": 1})
	_expect(not Validator.validate(ordinary_boss).is_empty(), "validator rejects bosses hidden in ordinary authored stages")
	var missing_boss := config.duplicate(true)
	missing_boss["stages"][9]["groups"].pop_back()
	missing_boss["stages"][9]["boss"] = false
	_expect(not Validator.validate(missing_boss).is_empty(), "validator rejects a boss-free tenth authored stage")


func _check_spawn_delivery() -> void:
	for number in [31, 40, 50, 60, 101, 1000, 1000000]:
		var first := _drain(number, 4242)
		var repeat := _drain(number, 4242)
		_expect(first["result"]["status"] == "victory" and first["result"]["kills"] == first["total"] and first["result"]["wave"] == first["result"]["wave_total"], "stage %d delivers every scheduled enemy/wave before victory" % number)
		_expect(first["warnings"] == (1 if number % 10 == 0 else 0) and first["result"]["bosses_slain"] == first["warnings"], "stage %d produces exactly its scheduled boss warning/death" % number)
		_expect(first["hash"] == repeat["hash"], "generated stage %d replays deterministically" % number)
	var clogged := RunModel.new()
	clogged.setup(config, "stage_1000", 11, _profile(1000))
	clogged.wall_hp = 1000000000000
	for ignored in range(int(clogged.stage["spawn_duration_ticks"]) + 60):
		clogged.step([])
	var frontier := clogged.spawn_cursor
	_expect(clogged.enemies.size() == 96 and frontier < clogged.spawn_queue.size() and clogged.status == "running", "active-enemy budget delays pending spawns without skipping them or declaring victory")
	clogged.enemies[0]["hp"] = 0
	clogged.step([])
	clogged.step([])
	_expect(clogged.enemies.size() == 96 and clogged.spawn_cursor == frontier + 1, "one freed enemy slot releases exactly one delayed spawn")
	clogged.debug_force_wall_damage(clogged.wall_hp)
	clogged.step([])
	var stopped_cursor := clogged.spawn_cursor
	_expect(clogged.status == "defeat" and clogged.step([]).is_empty() and clogged.spawn_cursor == stopped_cursor, "defeat stops the generated schedule")


func _drain(number: int, run_seed: int) -> Dictionary:
	var model := RunModel.new()
	model.setup(config, StageCatalog.id_for(number), run_seed, _profile(number))
	var events: Array[Dictionary] = []
	var warnings := 0
	# Structural delivery check: instant cleanup isolates spawn and settlement
	# contracts. Actual combat difficulty is checked by stage_autoplay.gd.
	while model.status == "running" and model.tick < int(model.stage["spawn_duration_ticks"]) + 100:
		for enemy in model.enemies:
			enemy["hp"] = 0
		var current := model.step([])
		for event in current:
			if event["type"] == "boss_warning":
				warnings += 1
		events.append_array(current)
	return {"result": model.result(), "warnings": warnings, "total": model.spawn_queue.size(), "hash": EventHasher.hash_events(events)}


func _result(number: int, run_id: String) -> Dictionary:
	return {"run_id": run_id, "reward_version": config["ruleset_version"], "stage_id": StageCatalog.id_for(number), "stage_number": number, "status": "victory", "kills": 5, "wall_percent": 90, "tick": 200, "coins": 55, "xp": 10, "wave": 4, "wave_total": 4}


func _check_rewards_and_saves() -> void:
	var legacy := _profile(30)
	legacy["coins"] = 4321
	legacy["crystals"] = 23
	legacy["best_results"]["stage_030"] = {"status": "victory"}
	var recovered: Dictionary = app.call("_normalize_profile", legacy)
	_expect(recovered["highest_unlocked_stage"] == 31 and recovered["coins"] == 4321 and recovered["crystals"] == 23, "old completed stage-30 save unlocks 31 without inventing rewards")
	legacy["best_results"]["stage_030"]["status"] = "defeat"
	_expect(app.call("_normalize_profile", legacy)["highest_unlocked_stage"] == 30, "unbeaten stage-30 save does not skip ahead")
	var deep := _profile(1000001)
	_expect(app.call("_normalize_profile", deep)["highest_unlocked_stage"] == 1000001, "deep progress is not clamped back to the authored prefix")
	_expect(HonorService.first_clear_crystals("stage_031", config) == 9 and HonorService.first_clear_crystals("stage_040", config) == 14 and HonorService.first_clear_crystals("stage_041", config) == 11, "generated ordinary and tenth stages use the actual first-clear reward curve")
	_expect(HonorService.first_clear_crystals("stage_00031", config) == 0, "alternate stage-ID spellings cannot mint another first-clear reward")
	var income_profile := _profile(41)
	income_profile["best_results"] = {"stage_031": {"status": "victory"}, "stage_040": {"status": "victory"}, "stage_041": {"status": "defeat"}}
	_expect(HonorService.expected_crystal_income(income_profile, config) == 23, "income reconciliation includes generated wins and excludes defeats")
	var save_service: Variant = app.get("save_service")
	app.set("profile", _profile(30))
	var before: Dictionary = app.get("profile").duplicate(true)
	app.set("save_service", FailingSaveService.new())
	var failed: Dictionary = app.call("settle_run", _result(30, "endless-failed-save"))
	_expect(not bool(failed.get("ok", false)) and app.get("profile") == before, "failed stage-30 save cannot commit unlocks or rewards")
	app.set("save_service", save_service)
	var settled: Dictionary = app.call("settle_run", _result(30, "endless-clear-30"))
	_expect(bool(settled.get("ok", false)) and app.get("profile")["highest_unlocked_stage"] == 31, "settling stage 30 unlocks 31")
	settled = app.call("settle_run", _result(31, "endless-clear-31"))
	_expect(bool(settled.get("ok", false)) and app.get("profile")["highest_unlocked_stage"] == 32 and int(settled.get("crystals_awarded", 0)) == 9, "generated victory unlocks its successor and awards first-clear crystals")
	before = app.get("profile").duplicate(true)
	app.call("settle_run", _result(31, "endless-clear-31"))
	_expect(app.get("profile") == before, "duplicate generated settlement is idempotent")
	settled = app.call("settle_run", _result(31, "endless-repeat-31"))
	_expect(int(settled.get("crystals_awarded", -1)) == 0, "replaying a cleared generated stage does not repeat crystals")
	var persisted: Dictionary = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(persisted["payload"]["highest_unlocked_stage"] == 32 and persisted["payload"]["best_results"].has("stage_031"), "generated progress and best result survive a real save reload")
	app.set("profile", deep)
	var saved: Dictionary = save_service.save_profile_slot(app.get("active_save_slot"), deep, int(config["config_version"]))
	persisted = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(bool(saved.get("ok", false)) and app.call("_normalize_profile", persisted["payload"])["highest_unlocked_stage"] == 1000001, "million-stage frontier round-trips through disk and normalization")


func _check_ui() -> void:
	app.set("profile", _profile(45))
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		app.set("profile", _profile(45))
		menu.call("_show_stage_select")
		await _frames()
		var grid := menu.find_child("StageGrid", true, false) as GridContainer
		_expect(grid.get_child_count() == 20 and menu.find_child("Stage_041", true, false) == null and menu.find_child("Stage_41", true, false) != null, locale + " picker generates only its 20-stage current page")
		_expect(not (menu.find_child("Stage_45", true, false) as Button).disabled and (menu.find_child("Stage_46", true, false) as Button).disabled, locale + " picker preserves the unlock boundary beyond stage 30")
		_expect((menu.find_child("Stage_50", true, false) as Button).text.contains(app.call("text", "common.boss")) and not (menu.find_child("Stage_49", true, false) as Button).text.contains("⚠"), locale + " only tenth-stage cards show Boss")
		await _capture("stages-41-60-" + locale)
		(menu.find_child("StageScroll", true, false) as ScrollContainer).ensure_control_visible(menu.find_child("Stage_50", true, false))
		await _frames()
		await _capture("boss-50-" + locale)
		(menu.find_child("StagePreviousPage", true, false) as Button).pressed.emit()
		await _frames()
		_expect(menu.find_child("Stage_21", true, false) != null and menu.find_child("Stage_41", true, false) == null, locale + " previous page removes the old buttons")
		var jump := menu.find_child("StageJumpNumber", true, false) as SpinBox
		jump.value = 45
		(menu.find_child("StageJumpButton", true, false) as Button).pressed.emit()
		await _frames()
		_expect(menu.find_child("Stage_45", true, false) != null, locale + " direct page jump finds the chosen unlocked stage")
		app.set("profile", _profile(59))
		menu.call("_show_stage_select")
		await _frames()
		var scroll := menu.find_child("StageScroll", true, false) as ScrollContainer
		_expect(scroll.get_global_rect().encloses((menu.find_child("Stage_59", true, false) as Control).get_global_rect()), locale + " default page scrolls to a frontier near its bottom")
		(menu.find_child("StagePreviousPage", true, false) as Button).pressed.emit()
		await _frames()
		(menu.find_child("StageJumpNumber", true, false) as SpinBox).value = 59
		(menu.find_child("StageJumpButton", true, false) as Button).pressed.emit()
		await _frames()
		scroll = menu.find_child("StageScroll", true, false) as ScrollContainer
		_expect(scroll.get_global_rect().encloses((menu.find_child("Stage_59", true, false) as Control).get_global_rect()), locale + " direct jump brings the actual chosen card into view")
		app.set("profile", _profile(1000001))
		menu.call("_show_stage_select")
		await _frames()
		_expect((menu.find_child("StageGrid", true, false) as GridContainer).get_child_count() == 20 and menu.find_child("Stage_1000001", true, false) != null, locale + " million-stage picker remains bounded")
		await _capture("stages-million-" + locale)
	root.remove_child(menu)
	menu.free()
	app.get("settings")["language"] = "zh_CN"
	app.set("profile", _profile(31))
	app.set("current_stage_id", "stage_030")
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	gameplay.set_physics_process(false)
	gameplay.get("session").set_physics_process(false)
	gameplay.call("_show_result", _result(30, "view-only"), {"ok": true})
	await _frames()
	_expect(gameplay.find_child("NextStageButton", true, false) != null and not (gameplay.find_child("NextStageButton", true, false) as Button).disabled, "stage 30 result offers the enabled next-stage action after saving")
	await _capture("stage-30-next")
	gameplay.get("_result_overlay").free()
	gameplay.set("_result_overlay", null)
	gameplay.call("_show_result", _result(1000000, "view-only-deep"), {"ok": false})
	await _frames()
	_expect((gameplay.find_child("NextStageButton", true, false) as Button).disabled, "unsaved victory cannot continue to an uncommitted next stage")
	root.remove_child(gameplay)
	gameplay.free()
	paused = false


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var directory := "res://Builds/endless-stages-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print("[ENDLESS CAPTURE] " + label)


func _frames() -> void:
	await process_frame
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
		print("[ENDLESS PASS] " + message)
	else:
		failures.append(message)
