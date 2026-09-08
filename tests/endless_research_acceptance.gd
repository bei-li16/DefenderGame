extends SceneTree

const Research = preload("res://src/core/rules/research_catalog.gd")
const Attack = preload("res://src/core/rules/attack_catalog.gd")
const Skills = preload("res://src/core/rules/skill_catalog.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")
const Validator = preload("res://src/core/rules/content_validator.gd")
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
	_check_prices_and_purchase()
	_check_effects()
	_check_deep_combat()
	_check_validation()
	_check_saves()
	await _check_ui()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[ENDLESS RESEARCH FAIL] " + failure)
	print("[ENDLESS RESEARCH] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _profile(level: int = -1) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["coins"] = 1000000000000
	profile["crystals"] = 1000000000000
	profile["highest_unlocked_stage"] = 1000
	profile["tutorial_complete"] = true
	profile["attack_research_revision"] = 1
	profile["current_weapon_id"] = "phantom_bow"
	profile["unlocked_weapons"] = ["basic_bow", "power_bow", "hurricane_bow", "phantom_bow"]
	for definition in config["upgrades"]:
		profile["upgrades"][definition["id"]] = level if level >= 0 and Research.is_endless(definition) else int(definition["max_level"])
	return profile


func _check_prices_and_purchase() -> void:
	var service: Variant = app.get("upgrade_service")
	var endless_count := 0
	for definition in config["upgrades"]:
		var id := str(definition["id"])
		var old_price := int(definition["base_cost"])
		var same_opening := true
		for level in range(int(definition["max_level"])):
			same_opening = same_opening and Research.price_for_level(definition, level) == old_price
			if int(definition["cost_growth_permille"]) > 1000:
				old_price = maxi(old_price + 1, int(round(float(old_price) * int(definition["cost_growth_permille"]) / 1000.0)))
		_expect(same_opening, id + " preserves every original opening price")
		var source := _profile()
		var original := source.duplicate(true)
		var bought: Dictionary = service.purchase(source, config, id)
		if Research.is_endless(definition):
			endless_count += 1
			var price := Research.price_for_level(definition, int(definition["max_level"]))
			var currency := str(definition.get("currency", "coins"))
			_expect(bool(bought.get("ok", false)) and bought["profile"]["upgrades"][id] == int(definition["max_level"]) + 1 and bought["profile"][currency] == source[currency] - price and source == original, id + " purchases beyond its original cap at the quoted currency/price")
			var previous_price := 0
			var prices_safe := true
			for level in [int(definition["max_level"]), int(definition["max_level"]) + 1, 100, 10000, 1000000, Research.MAX_LEVEL - 1]:
				var quoted := Research.price_for_level(definition, level)
				prices_safe = prices_safe and quoted >= previous_price and quoted > 0 and quoted <= Research.MAX_PRICE
				previous_price = quoted
			_expect(prices_safe, id + " has positive nondecreasing bounded-computation prices through numeric limits")
			var poor := source.duplicate(true)
			poor[currency] = price - 1
			_expect(service.purchase(poor, config, id).get("error_code") == "insufficient_" + currency, id + " rejects insufficient funds beyond the old cap")
			for prerequisite in definition.get("prerequisites", []):
				var locked := source.duplicate(true)
				locked["upgrades"][prerequisite] = 0
				_expect(service.purchase(locked, config, id).get("error_code") == "missing_prerequisite", id + " still requires " + str(prerequisite))
		else:
			_expect(bought.get("error_code") == "max_level" and source == original, id + " retains its finite cap")
	_expect(endless_count == 17, "exactly 17 sustainable research nodes are endless")
	var boundary := _profile(Research.MAX_LEVEL)
	_expect(service.purchase(boundary, config, "strength").get("error_code") == "max_level", "numeric representation boundary never overflows a level or mints a free purchase")


func _model(profile: Dictionary) -> DefenderRunModel:
	var model := RunModel.new()
	model.setup(config, "stage_031", 5142, profile)
	return model


func _check_effects() -> void:
	var original := _profile()
	var advanced := original.duplicate(true)
	advanced["upgrades"]["strength"] += 1
	for weapon in config["weapons"]:
		_expect(Attack.effective(config, advanced, weapon)["damage"] > Attack.effective(config, original, weapon)["damage"], str(weapon["id"]) + " benefits from strength beyond Lv.12")
		var forge := str(weapon.get("forge_upgrade_id", ""))
		if not forge.is_empty():
			var forged := original.duplicate(true)
			forged["upgrades"][forge] += 1
			_expect(Attack.effective(config, forged, weapon)["damage"] > Attack.effective(config, original, weapon)["damage"], forge + " continues damage after Lv.5")
	var baseline := _model(original)
	var upgraded := _model(_profile(21))
	_expect(upgraded.wall_max_hp > baseline.wall_max_hp and upgraded.max_mana > baseline.max_mana, "wall HP and Mana capacity grow beyond their opening limits")
	upgraded.step([{"type": "aim", "x_milli": 1500000, "y_milli": 540000}, {"type": "fire_started"}])
	_expect(not upgraded.projectiles.is_empty() and int(upgraded.projectiles[0]["damage"]) >= int(upgraded.attack_stats["damage"]), "higher research reaches actual projectile snapshots")
	for skill in config["skills"]:
		var id := str(skill["id"])
		var opening := Skills.effective(config, original, id)
		var raised := Skills.effective(config, _profile(9), id)
		var capped := Skills.effective(config, _profile(20), id)
		var deep := Skills.effective(config, _profile(1000000), id)
		_expect(raised["damage"] > opening["damage"] and raised["splash_damage"] > opening["splash_damage"], id + " continues direct and splash damage after Lv.8")
		_expect(deep["damage"] > capped["damage"] and deep["splash_damage"] > capped["splash_damage"], id + " continues damage beyond the secondary-stat cap")
		var stable := true
		for field in ["radius_milli", "splash_radius_milli", "burn_duration_ticks", "freeze_ticks", "stun_ticks", "slow_duration_ticks", "slow_permille", "impact_count", "mana_cost", "cooldown_ticks", "area_radius_milli", "barrage_duration_ticks", "fall_ticks"]:
			stable = stable and deep.get(field) == capped.get(field)
		_expect(stable, id + " cannot grow geometry, status time, count, cost or cadence forever")
		if skill["element"] == "fire":
			_expect(deep["burn_damage"] > capped["burn_damage"], id + " keeps increasing burn damage while burn duration caps")
	for id in ["lava_moat", "magic_tower"]:
		var damage_by_level: Array[int] = []
		for level in [5, 6]:
			var profile := _profile(0)
			profile["upgrades"][id] = level
			var model := _model(profile)
			while model.enemies.is_empty():
				model.step([])
			model.enemies[0]["x_milli"] = int(config["world"]["castle_x_milli"]) + 1000
			model.enemies[0]["hp"] = 1000000
			model.enemies[0]["armor"] = 0
			model.enemies[0]["resistances"] = {}
			var events: Array[Dictionary] = []
			model._update_defenses(events)
			damage_by_level.append(1000000 - int(model.enemies[0]["hp"]))
		_expect(damage_by_level[1] > damage_by_level[0] and damage_by_level[0] > 0, str(id) + " actual attacks grow beyond Lv.5")
	var extreme := _profile(Research.MAX_LEVEL)
	var model := _model(extreme)
	_expect(model.attack_stats["damage"] > 0 and model.attack_stats["damage"] <= Research.MAX_EFFECT and model.wall_max_hp > 0 and model.max_mana > 0, "extreme research cannot wrap damage, HP or Mana negative")
	for skill in config["skills"]:
		var stats := Skills.effective(config, extreme, skill["id"])
		_expect(stats["damage"] > 0 and stats["damage"] <= Research.MAX_EFFECT and stats["splash_radius_milli"] > stats["radius_milli"], str(skill["id"]) + " stays numerically safe at representation limits")


func _check_validation() -> void:
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	_expect(Validator.validate(config).is_empty() and Validator.validate(fallback).is_empty() and config["upgrades"] == fallback["upgrades"], "primary and fallback have the same validated research rules")
	for mutation in [{"endless_cost": {}}, {"endless_cost": {"step": 0, "power": 1.15}}, {"endless_cost": {"step": 90, "power": 9}}, {"max_level": 1000000}, {"endless": "yes"}]:
		var invalid := config.duplicate(true)
		Research.find(invalid, "strength").merge(mutation, true)
		_expect(not Validator.validate(invalid).is_empty(), "reject unsafe price/level configuration " + str(mutation))
	for id in ["agility", "multiple_arrows", "fatal_blow", "mana_regen"]:
		var invalid := config.duplicate(true)
		Research.find(invalid, id)["endless"] = true
		_expect(not Validator.validate(invalid).is_empty(), "reject unbounded sensitive stat " + id)
	var invalid := config.duplicate(true)
	Research.find(invalid, "fire_mastery")["secondary_max_level"] = 1000000
	_expect(not Validator.validate(invalid).is_empty(), "unbounded skill range/duration is rejected")


func _check_deep_combat() -> void:
	# Actual arrows and spell impacts, not forced kills, verify that additional
	# research makes a meaningful difference in generated late-stage combat.
	for sample in [[1000, 75], [10000, 200]]:
		var profile := _profile(int(sample[1]))
		profile["equipped_skills"] = {"fire": "armageddon", "ice": "ice_age", "lightning": "ragnarok"}
		var model := RunModel.new()
		model.setup(config, "stage_%03d" % int(sample[0]), 8000 + int(sample[0]), profile)
		var boss_deaths := 0
		for ignored in range(9000):
			var commands: Array = []
			if model.tick == 0:
				commands.append({"type": "fire_started"})
			var target: Dictionary = {}
			for enemy in model.enemies:
				if target.is_empty() or int(enemy["x_milli"]) < int(target["x_milli"]):
					target = enemy
			if not target.is_empty():
				commands.append({"type": "aim", "x_milli": target["x_milli"], "y_milli": target["y_milli"]})
				for id in ["armageddon", "ice_age", "ragnarok"]:
					if model.skill_cooldowns.get(id, 0) == 0 and model.mana >= int(Skills.find(config, id)["mana_cost"]):
						commands.append({"type": "cast_skill", "skill_id": id, "x_milli": target["x_milli"], "y_milli": target["y_milli"]})
						break
			for event in model.step(commands):
				if event["type"] == "death" and bool(event.get("boss", false)):
					boss_deaths += 1
			if model.status != "running":
				break
		_expect(model.status == "victory" and boss_deaths == 1 and model.kills == model.spawn_queue.size(), "real combat stage %d with research Lv.%d: %s, kills=%d, ticks=%d" % [sample[0], sample[1], model.status, model.kills, model.tick])


func _check_saves() -> void:
	var source := _profile(1000000)
	var normalized: Dictionary = app.call("_normalize_profile", source)
	_expect(normalized["upgrades"] == source["upgrades"] and normalized["coins"] == source["coins"] and normalized["crystals"] == source["crystals"], "normalizing a deep save preserves legitimate levels and balances")
	source["upgrades"]["agility"] = 1000
	source["upgrades"]["fire_mastery"] = -2
	normalized = app.call("_normalize_profile", source)
	_expect(normalized["upgrades"]["agility"] == 6 and normalized["upgrades"]["fire_mastery"] == 0, "invalid negative and over-cap finite levels are normalized")
	var legacy := _profile()
	_expect(app.call("_normalize_profile", legacy)["upgrades"] == legacy["upgrades"], "all old legitimate research levels remain intact without refunds or re-buying")
	app.set("profile", _profile(1000000))
	var snapshot_model := _model(app.get("profile"))
	var before: Dictionary = app.get("profile").duplicate(true)
	var save_service: Variant = app.get("save_service")
	app.set("save_service", FailingSave.new())
	_expect(not bool(app.call("purchase_upgrade", "strength").get("ok", false)) and app.get("profile") == before, "failed deep purchase save rolls back levels, coins and career spending")
	app.set("save_service", save_service)
	_expect(bool(app.call("purchase_upgrade", "strength").get("ok", false)) and app.get("profile")["upgrades"]["strength"] == 1000001, "a retry commits exactly one deep level")
	_expect(bool(app.call("purchase_upgrade", "fire_mastery").get("ok", false)) and app.get("profile")["upgrades"]["fire_mastery"] == 1000001, "deep skill research spends crystals through the application transaction")
	var loaded: Dictionary = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(bool(loaded.get("ok", false)) and app.call("_normalize_profile", loaded["payload"])["upgrades"] == app.get("profile")["upgrades"], "deep levels survive an actual disk reload")
	_expect(snapshot_model.profile_snapshot["upgrades"]["strength"] == 1000000 and snapshot_model.attack_stats == Attack.effective(config, before, snapshot_model.weapon), "purchases cannot alter an already-started combat snapshot")


func _check_ui() -> void:
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		app.set("profile", _profile())
		var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
		root.add_child(menu)
		for id in Research.ENDLESS_IDS:
			var node := Research.find(config, id)
			menu.call("_show_research_page", node["page"], id)
			await _frames()
			var purchase := menu.find_child("ResearchPurchaseButton", true, false) as Button
			_expect(not purchase.disabled and (menu.find_child("ResearchDetailName", true, false) as Label).text.contains("∞"), locale + " " + id + " shows an enabled endless upgrade at the old cap")
			var before := int(app.get("profile")["upgrades"][id])
			purchase.pressed.emit()
			await _frames()
			_expect(app.get("profile")["upgrades"][id] == before + 1 and not (menu.find_child("ResearchPurchaseButton", true, false) as Button).disabled, locale + " " + id + " buys and remains selected/upgradeable")
		app.set("profile", _profile(1000000))
		for id in ["strength", "armageddon", "ice_age", "ragnarok", "forge_phantom_bow", "magic_tower"]:
			menu.call("_show_research_page", Research.find(config, id)["page"], id)
			await _frames()
			var name_label := menu.find_child("ResearchDetailName", true, false) as Label
			_expect(name_label.text.contains("∞") and name_label.tooltip_text.contains("1000000"), locale + " " + id + " shows deep levels compactly with exact tooltip")
			var purchase := menu.find_child("ResearchPurchaseButton", true, false) as Button
			_expect(menu.get_global_rect().encloses(purchase.get_global_rect()) and root.get_visible_rect().encloses(purchase.get_global_rect()), locale + " " + id + " keeps deep purchase on-screen: button=%s viewport=%s menu=%s" % [purchase.get_global_rect(), root.get_visible_rect(), menu.get_global_rect()])
			if Research.find(config, id).has("skill_ref"):
				var scroll := menu.find_child("ResearchScroll", true, false) as Control
				var chains_visible := true
				for skill in config["skills"]:
					chains_visible = chains_visible and scroll.get_global_rect().encloses((menu.find_child("Research_" + str(skill["upgrade_id"]), true, false) as Control).get_global_rect())
				_expect(chains_visible, locale + " " + id + " keeps all three skill chains visible at deep levels")
			await _capture(locale + "-" + id)
		menu.call("_show_research_page", "attack", "fatal_blow")
		await _frames()
		_expect((menu.find_child("ResearchPurchaseButton", true, false) as Button).disabled and not (menu.find_child("ResearchDetailName", true, false) as Label).text.contains("∞"), locale + " capped probability research stays maxed")
		root.remove_child(menu)
		menu.free()


func _frames() -> void:
	await process_frame
	await process_frame


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var path := "res://Builds/endless-research-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	root.get_texture().get_image().save_png(path.path_join(label + ".png"))


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
		print("[ENDLESS RESEARCH PASS] " + message)
	else:
		failures.append(message)
