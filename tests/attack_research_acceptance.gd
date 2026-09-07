extends SceneTree

const RunModel = preload("res://src/core/combat/run_model.gd")
const Attack = preload("res://src/core/rules/attack_catalog.gd")
const Projectiles = preload("res://src/core/combat/projectile_system.gd")
const Validator = preload("res://src/core/rules/content_validator.gd")
const UpgradeService = preload("res://src/application/upgrade_service.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const FailingSave = preload("res://tests/support/failing_save_service.gd")

var app: Node
var config: Dictionary
var passes := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	config = app.get("content").rules
	_check_dependencies()
	_check_stats_and_volleys()
	_check_poison_and_knockback()
	_check_xp()
	_check_migration()
	_check_validator()
	await _check_ui()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[ATTACK FAIL] " + failure)
	print("[ATTACK] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _profile(levels: Dictionary = {}, bow: String = "basic_bow") -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["coins"] = 1000000
	profile["tutorial_complete"] = true
	profile["current_weapon_id"] = bow
	profile["unlocked_weapons"] = ["basic_bow", "power_bow", "hurricane_bow", "phantom_bow"]
	profile["upgrades"].merge(levels, true)
	return profile


func _model(profile: Dictionary, rules: Dictionary = config) -> DefenderRunModel:
	var copy := rules.duplicate(true)
	copy["world"]["spawn_start_tick"] = 1
	copy["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(copy, "stage_001", 481, profile)
	model.step([])
	var enemy: Dictionary = model.enemies[0]
	enemy["hp"] = 100000
	enemy["max_hp"] = 100000
	enemy["armor"] = 0
	enemy["speed_milli_per_tick"] = 0
	enemy["x_milli"] = 1000000
	enemy["y_milli"] = 555000
	enemy["knockback_resistance_permille"] = 0
	enemy["status_resistance_permille"] = 0
	return model


func _shot(model: DefenderRunModel) -> Array[Dictionary]:
	return model.step([{"type": "aim", "x_milli": 1500000, "y_milli": 555000}, {"type": "fire_started"}, {"type": "fire_stopped"}])


func _check_dependencies() -> void:
	var service := UpgradeService.new()
	var parents := {"strength": [], "agility": [], "power_shot": ["strength"], "poisoned_arrow": ["strength", "agility"], "fatal_blow": ["agility"], "multiple_arrows": ["power_shot", "fatal_blow"], "senior_hunter": ["multiple_arrows"]}
	for id in Attack.IDS:
		var definition := Attack.find(config, id)
		_expect(definition["prerequisites"] == parents[id], str(id) + " matches reference branch edges")
		var profile := _profile()
		for parent in parents[id]:
			profile["upgrades"][parent] = 3
		for missing in parents[id]:
			var invalid := profile.duplicate(true)
			invalid["upgrades"][missing] = 2
			var before := invalid.duplicate(true)
			var rejected := service.purchase(invalid, config, id)
			_expect(rejected.get("error_code", "") == "missing_prerequisite" and invalid == before, "%s needs %s Lv.3 (every parent required)" % [id, missing])
		var result := service.purchase(profile, config, id)
		_expect(result.get("ok", false) and int(result["profile"]["upgrades"][id]) == 1 and int(result["profile"]["coins"]) == int(profile["coins"]) - int(definition["base_cost"]), str(id) + " purchases atomically at configured price")
		profile["upgrades"][id] = int(definition["max_level"])
		_expect(service.purchase(profile, config, id).get("error_code", "") == "max_level", str(id) + " rejects beyond its cap")
	_expect(service.purchase(_profile(), config, "power_mastery").get("error_code", "") == "unknown_upgrade", "retired mastery cannot be repurchased")
	var poor := _profile()
	poor["coins"] = 0
	_expect(service.purchase(poor, config, "strength").get("error_code", "") == "insufficient_coins", "insufficient balance does not buy research")


func _check_stats_and_volleys() -> void:
	for weapon in config["weapons"]:
		var previous_total := 0
		for level in range(10):
			var profile := _profile({"multiple_arrows": level}, str(weapon["id"]))
			var stats := Attack.effective(config, profile, weapon)
			var total := int(stats["projectile_count"]) * int(stats["damage"])
			_expect(int(stats["projectile_count"]) <= 5 and total > previous_total, "%s multi Lv.%d increases actual rounded volley damage, max five arrows" % [weapon["id"], level])
			previous_total = total
			var model := _model(profile)
			_shot(model)
			var mirrored := model.projectiles.size() == int(stats["projectile_count"])
			for index in range(model.projectiles.size()):
				var arrow: Dictionary = model.projectiles[index]
				var expected := int(stats["damage"]) * (2 if bool(arrow["fatal"]) else 1)
				var speed := Vector2(arrow["vx_milli"], arrow["vy_milli"]).length()
				mirrored = mirrored and arrow["damage"] == expected and absf(speed - float(weapon["projectile_speed_milli_per_tick"])) < 2.0
				mirrored = mirrored and int(arrow["vy_milli"]) == -int(model.projectiles[model.projectiles.size() - 1 - index]["vy_milli"])
			_expect(mirrored, "%s multi Lv.%d matches preview, symmetric spread and fixed speed" % [weapon["id"], level])
		var profile := _profile({"strength": 4, "agility": 6, "fatal_blow": 3, "power_shot": 2, "poisoned_arrow": 2}, str(weapon["id"]))
		var stats := Attack.effective(config, profile, weapon)
		_expect(int(stats["base_damage"]) == int(weapon["damage"]) + 16 and int(stats["interval_ticks"]) >= int(weapon["min_interval_ticks"]), str(weapon["id"]) + " strength and agility apply without changing projectile speed")
		_expect(int(stats["fatal_chance_per_10000"]) == int(weapon["fatal_chance_per_10000"]) + 1500 and int(stats["knockback_milli"]) == int(weapon["knockback_milli"]) + 40000, str(weapon["id"]) + " critical and knockback research combine with innate bow stats")
	var rules := config.duplicate(true)
	Attack.find(rules, "fatal_blow")["effect_per_level"] = 10000
	var critical := _model(_profile({"fatal_blow": 1, "poisoned_arrow": 3}), rules)
	_shot(critical)
	var old_arrow := critical.projectiles[0].duplicate(true)
	_expect(old_arrow["fatal"] and int(old_arrow["damage"]) == 68 and int(old_arrow["poison_damage"]) == 5, "fatal research triggers exactly double physical damage, not double poison")
	critical.attack_stats["damage"] = 999
	critical.attack_stats["poison_damage"] = 999
	_expect(critical.projectiles[0] == old_arrow, "in-flight projectile keeps damage, poison and knockback snapshots")
	var original := _profile({"strength": 1})
	var immutable := _model(original)
	original["upgrades"]["strength"] = 12
	_expect(immutable.attack_stats["base_damage"] == 38, "run stats are independent of later profile edits")
	var a := _model(_profile({"fatal_blow": 9, "multiple_arrows": 9, "poisoned_arrow": 9, "power_shot": 9}))
	var b := _model(_profile({"fatal_blow": 9, "multiple_arrows": 9, "poisoned_arrow": 9, "power_shot": 9}))
	var events_a: Array = []
	var events_b: Array = []
	for tick in range(200):
		events_a.append_array(_shot(a) if tick % 12 == 0 else a.step([]))
		events_b.append_array(_shot(b) if tick % 12 == 0 else b.step([]))
	_expect(EventHasher.hash_events(events_a) == EventHasher.hash_events(events_b) and a.snapshot() == b.snapshot(), "poison, crits, knockback and multi-arrow replays are deterministic")


func _check_poison_and_knockback() -> void:
	var model := _model(_profile({"poisoned_arrow": 9, "power_shot": 3}))
	_shot(model)
	var arrow := model.projectiles[0].duplicate(true)
	arrow["x_milli"] = 1000000
	arrow["y_milli"] = 555000
	arrow["vx_milli"] = 0
	arrow["vy_milli"] = 0
	arrow["power"] = true
	model.projectiles = [arrow]
	var enemy: Dictionary = model.enemies[0]
	enemy["knockback_resistance_permille"] = 500
	var hit_events: Array[Dictionary] = []
	model.call("_update_projectiles", hit_events)
	_expect(int(enemy["x_milli"]) == 1065000 and int(enemy["poison_ticks"]) == 90, "actual hit applies researched knockback with resistance and poison")
	var before_hp := int(enemy["hp"])
	for tick in range(90):
		model.step([])
	_expect(before_hp - int(enemy["hp"]) == int(arrow["poison_damage"]) * 3 and int(enemy["poison_ticks"]) == 0, "poison deals exactly three ticks then expires")
	before_hp = int(enemy["hp"])
	for tick in range(30):
		model.step([])
	_expect(before_hp == int(enemy["hp"]), "expired poison stops damage")
	for tick in range(90):
		Projectiles.apply_poison(model, enemy, arrow, hit_events)
		model.step([])
	_expect(before_hp - int(enemy["hp"]) == int(arrow["poison_damage"]) * 3, "rapid refresh neither stacks nor postpones periodic damage")
	var weaker := arrow.duplicate(true)
	weaker["poison_damage"] = 1
	Projectiles.apply_poison(model, enemy, weaker, hit_events)
	_expect(int(enemy["poison_damage"]) == int(arrow["poison_damage"]), "weaker poison cannot replace an active stronger effect")
	enemy["poison_ticks"] = 0
	Projectiles.apply_poison(model, enemy, weaker, hit_events)
	_expect(int(enemy["poison_damage"]) == 1, "new poison after expiration does not inherit stale damage")
	enemy["poison_ticks"] = 0
	enemy["status_resistance_permille"] = 500
	enemy["resistances"]["poison"] = 500
	Projectiles.apply_poison(model, enemy, arrow, hit_events)
	before_hp = int(enemy["hp"])
	for tick in range(45):
		model.step([])
	_expect(before_hp - int(enemy["hp"]) == int(arrow["poison_damage"]) / 2 and int(enemy["poison_ticks"]) == 0, "boss-style resistance reduces duration and poison damage independently")
	# Poison does not overwrite ice, lightning or fire timers.
	enemy["burn_ticks"] = 60
	enemy["burn_counter"] = 30
	enemy["burn_interval_ticks"] = 30
	enemy["burn_damage"] = 3
	enemy["freeze_ticks"] = 30
	enemy["stun_ticks"] = 30
	Projectiles.apply_poison(model, enemy, arrow, hit_events)
	model.step([])
	_expect(enemy["burn_ticks"] == 59 and enemy["freeze_ticks"] == 29 and enemy["stun_ticks"] == 29 and int(enemy["poison_ticks"]) > 0, "poison coexists with burn, freeze and stun")
	enemy["hp"] = 0
	enemy["poison_ticks"] = 0
	Projectiles.apply_poison(model, enemy, arrow, hit_events)
	_expect(enemy["poison_ticks"] == 0, "dead target cannot receive poison")
	var pierced := _model(_profile({"poisoned_arrow": 2}, "phantom_bow"))
	var second := pierced.enemies[0].duplicate(true)
	second["entity_id"] = 50
	second["x_milli"] = 1100000
	pierced.enemies.append(second)
	_shot(pierced)
	for tick in range(18):
		pierced.step([])
	_expect(int(pierced.enemies[0]["poison_ticks"]) > 0 and int(second["poison_ticks"]) > 0, "Phantom applies poison independently to pierced targets")


func _check_xp() -> void:
	var profile := _profile({"senior_hunter": 9})
	var model := _model(profile)
	model.enemies[0]["reward_xp"] = 100
	model.enemies[0]["hp"] = 0
	model.stage["clear_reward"]["xp"] = 100
	var events := model.step([])
	var event_total := 0
	for event in events:
		if event["type"] == "reward":
			event_total += int(event["xp"])
	_expect(model.result()["xp"] == 290 and event_total == 290, "Senior Hunter boosts kills and clear XP once, reward events match settlement")
	var service := UpgradeService.new()
	var paid := service.apply_run_reward(profile, model.result())
	var duplicate := service.apply_run_reward(paid["profile"], model.result())
	_expect(paid["profile"]["xp"] == 290 and duplicate["profile"]["xp"] == 290, "research XP reward is idempotent")
	var defeated := _model(_profile({"senior_hunter": 9, "xp_bounty": 1}))
	defeated.enemies[0]["reward_xp"] = 100
	defeated.enemies[0]["hp"] = 0
	defeated.wall_hp = 0
	defeated.step([])
	var bounty := Attack.bonus(config, defeated.profile_snapshot, "xp_bounty")
	_expect(defeated.result()["xp"] == (100 + bounty) * 1450 / 1000, "defeat retains enhanced kill XP, never clear XP or clear bounty")
	var honor := config.duplicate(true)
	for definition in honor["honors"]:
		if str(definition["bonus_type"]) == "xp_pct":
			profile["honors"][definition["id"]] = 1
			definition["bonus_per_level"] = 10
	_expect(Attack.reward_xp(honor, profile, 1000) == 1595, "Senior Hunter multiplies the honor XP bonus without intermediate rounding")


func _check_migration() -> void:
	var old := _profile({"strength": 5, "agility": 4, "power_mastery": 2, "hurricane_mastery": 1, "phantom_mastery": 1}, "phantom_bow")
	old["coins"] = 100
	var normalized: Dictionary = app.call("_normalize_profile", old)
	_expect(normalized["coins"] == 1050 and normalized["upgrades"]["strength"] == 5 and normalized["upgrades"]["agility"] == 4, "legacy refund equals historical paid prices (180 + 270 + 240 + 260), roots retained")
	_expect(not normalized["upgrades"].has("power_mastery") and normalized["attack_research_migration"]["retired_levels"]["power_mastery"] == 2 and old["coins"] == 100, "migration archives old levels without mutating its input")
	_expect(app.call("_normalize_profile", normalized) == normalized, "repeat normalization never refunds twice")
	_expect(normalized["current_weapon_id"] == "phantom_bow" and normalized["unlocked_weapons"] == old["unlocked_weapons"] and normalized["equipped_skills"] == old["equipped_skills"], "migration retains bows and three-series spell equipment")
	var save: Variant = app.get("save_service")
	save.save_profile_slot(2, old, 4)
	var current: Dictionary = app.get("profile").duplicate(true)
	app.set("save_service", FailingSave.new(save.base_directory))
	var rejected: Dictionary = app.call("switch_save_slot", 2)
	_expect(not rejected.get("ok", false) and app.get("profile") == current and app.get("active_save_slot") == 1, "failed migration save leaves active profile and slot unchanged")
	app.set("save_service", save)
	app.call("switch_save_slot", 2)
	var persisted: Dictionary = save.load_profile_slot(2, app.call("_default_profile"))
	_expect(persisted["payload"]["coins"] == 1050 and int(persisted["payload"]["attack_research_revision"]) == 1, "real slot load migrates even when defaults were merged, atomically persists marker and refund")
	app.call("switch_save_slot", 1)
	app.call("switch_save_slot", 2)
	_expect(app.get("profile")["coins"] == 1050, "save reload cannot pay the refund twice")
	app.call("switch_save_slot", 1)
	var rich := _profile({"agility": 3})
	app.set("profile", rich)
	app.set("save_service", FailingSave.new(save.base_directory))
	app.call("purchase_upgrade", "fatal_blow")
	_expect(app.get("profile") == rich, "failed research purchase saves neither coin spend nor new effect")
	app.set("save_service", save)


func _check_validator() -> void:
	_expect(Validator.validate(config).is_empty(), "primary attack configuration validates")
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	_expect(Validator.validate(fallback).is_empty(), "fallback configuration validates")
	for id in Attack.IDS:
		_expect(Attack.find(config, id) == Attack.find(fallback, id), str(id) + " is identical in fallback")
	for issue in ["missing_node", "wrong_parent", "duplicate_parent", "missing_page", "bad_threshold", "zero_tick", "oversized_volley", "damage_regression", "bad_chance"]:
		var broken := config.duplicate(true)
		match issue:
			"missing_node": broken["upgrades"].erase(Attack.find(broken, "poisoned_arrow"))
			"wrong_parent": Attack.find(broken, "multiple_arrows")["prerequisites"] = ["poisoned_arrow"]
			"duplicate_parent": Attack.find(broken, "poisoned_arrow")["prerequisites"] = ["strength", "strength"]
			"missing_page": broken["research_pages"].remove_at(0)
			"bad_threshold": Attack.find(broken, "power_shot")["prerequisite_levels"]["strength"] = 999
			"zero_tick": Attack.find(broken, "poisoned_arrow")["interval_ticks"] = 0
			"oversized_volley": Attack.find(broken, "multiple_arrows")["level_effects"][1]["projectile_count"] = 6
			"damage_regression": Attack.find(broken, "multiple_arrows")["level_effects"][1]["damage_permille"] = 1
			"bad_chance": Attack.find(broken, "power_shot")["chance_per_level"] = -1
		_expect(not Validator.validate(broken).is_empty(), "validator rejects " + issue)


func _check_ui() -> void:
	app.set("profile", _profile({"strength": 3, "agility": 3, "power_shot": 3, "fatal_blow": 3, "multiple_arrows": 3}))
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		menu.call("_show_research_page", "attack", "multiple_arrows")
		await _frames()
		var scroll := menu.find_child("ResearchScroll", true, false) as ScrollContainer
		for id in Attack.IDS:
			var button := menu.find_child("Research_" + str(id), true, false) as Button
			_expect(button != null and scroll.get_global_rect().encloses(button.get_global_rect()), locale + " displays " + str(id) + " without scrolling")
			button.pressed.emit()
			await _frames()
			var detail := menu.find_child("ResearchDetailBody", true, false) as Label
			_expect(detail.text.contains(str(app.call("text", "skill.current"))) and detail.text.contains(str(app.call("text", "skill.next"))), str(id) + " shows current and next real attributes")
		menu.call("_show_research_page", "attack", "multiple_arrows")
		await _frames()
		await _capture("attack-" + locale)
		var purchase := menu.find_child("ResearchPurchaseButton", true, false) as Button
		var prior := int(app.get("profile")["upgrades"]["multiple_arrows"])
		purchase.pressed.emit()
		await _frames()
		_expect(int(app.get("profile")["upgrades"]["multiple_arrows"]) == prior + 1, locale + " actual research button persists the selected node")
		var tree := (menu.find_child("ResearchScroll", true, false) as ScrollContainer).get_child(0)
		_expect(tree.call("selected") == "multiple_arrows", "purchase preserves selection")
		var before_text: String = (menu.find_child("ResearchDetailBody", true, false) as Label).text
		menu.call("_equip_weapon", "hurricane_bow" if locale == "zh_CN" else "basic_bow")
		await _frames()
		_expect((menu.find_child("ResearchDetailBody", true, false) as Label).text != before_text, "header equipment change refreshes the open attack preview")
	root.remove_child(menu)
	menu.free()
	app.get("settings")["language"] = "zh_CN"
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	gameplay.set_physics_process(false)
	gameplay.get("session").set_physics_process(false)
	var model := _model(_profile({"poisoned_arrow": 9, "multiple_arrows": 9}))
	_shot(model)
	var events: Array[Dictionary] = []
	Projectiles.apply_poison(model, model.enemies[0], model.projectiles[0], events)
	gameplay.call("_on_snapshot", model.snapshot())
	gameplay.call("_on_events", events)
	await _frames()
	await _capture("poison-volley")
	root.remove_child(gameplay)
	gameplay.free()


func _frames() -> void:
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var directory := "res://Builds/attack-research-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
