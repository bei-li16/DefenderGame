extends SceneTree

const RunModel = preload("res://src/core/combat/run_model.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const Validator = preload("res://src/core/rules/content_validator.gd")
const EventHasher = preload("res://src/core/replay/event_hasher.gd")
const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

var failures: Array[String] = []
var passes := 0
var app: Node
var config: Dictionary


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	config = app.get("content").rules
	_expect(config["skills"].size() == 9, "exactly nine spells")
	for element in SkillCatalog.ELEMENTS:
		var previous := {}
		var count := 0
		for skill in config["skills"]:
			if str(skill["element"]) != element:
				continue
			count += 1
			if not previous.is_empty():
				_expect(int(skill["mana_cost"]) > int(previous["mana_cost"]) and int(skill["radius_milli"]) > int(previous["radius_milli"]) and int(skill["damage"]) > int(previous["damage"]), "%s tier %d increases Mana, radius and damage" % [element, skill["tier"]])
			previous = skill
		_expect(count == 3, element + " has three tiers")
	for skill in config["skills"]:
		_check_spell(skill)
	_check_rules_and_legacy()
	await _check_research_and_hud()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[SKILL CHAINS FAIL] " + failure)
	print("[SKILL CHAINS] %d passed, %d failed" % [passes, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _profile(skill_id: String = "") -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["coins"] = 1000000
	profile["tutorial_complete"] = true
	if not skill_id.is_empty():
		var skill := SkillCatalog.find(config, skill_id)
		profile["upgrades"][str(skill["upgrade_id"])] = 1 if int(skill["tier"]) > 1 else 0
		profile["equipped_skills"][str(skill["element"])] = skill_id
	return profile


func _model(profile: Dictionary) -> DefenderRunModel:
	var rules := config.duplicate(true)
	rules["world"]["spawn_start_tick"] = 1
	rules["player"]["mana_regen_interval_ticks"] = 100000
	rules["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(rules, "stage_001", 1701, profile)
	model.step([])
	var template := model.enemies[0].duplicate(true)
	model.enemies.clear()
	for index in range(16):
		var enemy := template.duplicate(true)
		enemy["entity_id"] = index + 1
		enemy["hp"] = 100000
		enemy["max_hp"] = 100000
		enemy["armor"] = 0
		enemy["x_milli"] = 1000000 + (index % 4) * 12000
		enemy["y_milli"] = 500000 + int(index / 4) * 12000
		enemy["speed_milli_per_tick"] = 0
		enemy["status_resistance_permille"] = 0
		enemy["attack_cooldown"] = 0
		enemy["special_counter"] = 29
		model.enemies.append(enemy)
	return model


func _cast(skill_id: String) -> Array:
	return [{"type": "cast_skill", "skill_id": skill_id, "x_milli": 1000000, "y_milli": 500000}]


func _check_spell(skill: Dictionary) -> void:
	var id := str(skill["id"])
	var profile := _profile(id)
	var model := _model(profile)
	var before := model.mana
	var events := model.step(_cast(id))
	_expect(model.mana == before - int(skill["mana_cost"]), id + " spends its exact Mana cost once")
	_expect(model.spells_cast == 1 and int(model.get(str(skill["element"]) + "_casts")) == 1, id + " increments its elemental honor counter once")
	var direct_damage := 0
	for event in events:
		if event["type"] == "damage" and event.get("source", "") == skill["element"]:
			direct_damage += 1
	var targets := mini(16, int(skill.get("max_targets", 16)))
	_expect(direct_damage == targets, id + " obeys its target cap")
	var enemy: Dictionary = model.enemies[0]
	if str(skill["element"]) == "fire":
		_expect(int(enemy["burn_ticks"]) > 0 and int(enemy["burn_damage"]) == int(skill["burn_damage"]), id + " applies persistent burn")
	elif str(skill["element"]) == "ice":
		_expect(int(enemy["freeze_ticks"]) == int(skill["freeze_ticks"]) - 1 and int(enemy["slow_ticks"]) > 0, id + " freezes and slows")
	else:
		_expect(int(enemy["stun_ticks"]) == int(skill["stun_ticks"]) - 1 and int(enemy["special_counter"]) == 0 and int(enemy["attack_cooldown"]) > 0, id + " stuns and cancels charged actions")
	var same_mana := model.mana
	var rejected := model.step(_cast(id))
	_expect(model.mana == same_mana and _reason(rejected) == "cooldown", id + " rejects a second cast without spending")
	for ignored in range(int(skill["pulse_count"]) * int(skill["pulse_interval_ticks"]) + 1):
		events.append_array(model.step([]))
	var pulses := 0
	var all_hits := 0
	var total_damage := 0
	for event in events:
		if event["type"] == "skill_pulse":
			pulses += 1
		if event["type"] == "damage" and event.get("source", "") == skill["element"]:
			all_hits += 1
			total_damage += int(event["amount"])
	_expect(pulses == int(skill["pulse_count"]) and all_hits == targets * pulses and model.mana == before - int(skill["mana_cost"]) and model.active_spells.is_empty() and model.spells_cast == 1, id + " finishes all real damage pulses without extra casts or Mana")
	_expect(total_damage == int(skill["damage"]) * targets * pulses, id + " damage matches the research preview for every pulse")
	var outside := _model(profile)
	outside.enemies[0]["x_milli"] = 1000000 + int(skill["radius_milli"]) + 1
	outside.enemies[0]["y_milli"] = 500000
	outside.step(_cast(id))
	_expect(outside.enemies[0]["hp"] == 100000 and outside.enemies[0]["stun_ticks"] == 0 and outside.enemies[0]["burn_ticks"] == 0, id + " never hits outside its effective radius")
	var no_mana := _model(profile)
	no_mana.mana = int(skill["mana_cost"]) - 1
	var low_events := no_mana.step(_cast(id))
	_expect(_reason(low_events) == "no_mana" and no_mana.mana == int(skill["mana_cost"]) - 1 and no_mana.active_spells.is_empty(), id + " cannot create effects with insufficient Mana")
	var invalid := _model(profile)
	var bad_command := _cast(id)
	bad_command[0]["x_milli"] = -1000
	_expect(_reason(invalid.step(bad_command)) == "invalid_target" and invalid.mana == invalid.max_mana, id + " rejects an illegal target atomically")
	var resistant := _model(profile)
	resistant.enemies[0]["status_resistance_permille"] = 500
	resistant.step(_cast(id))
	var field := "burn_ticks" if skill["element"] == "fire" else "stun_ticks"
	var base := int(skill.get("burn_duration_ticks", skill.get("freeze_ticks", skill.get("stun_ticks", 0))))
	_expect(int(resistant.enemies[0][field]) == int(base / 2) - 1, id + " respects status resistance")
	var replay_a := _model(profile)
	var replay_b := _model(profile)
	var log_a: Array = replay_a.step(_cast(id))
	var log_b: Array = replay_b.step(_cast(id))
	for ignored in range(100):
		log_a.append_array(replay_a.step([]))
		log_b.append_array(replay_b.step([]))
	_expect(EventHasher.hash_events(log_a) == EventHasher.hash_events(log_b), id + " has deterministic pulse and target order")


func _check_rules_and_legacy() -> void:
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	var fallback_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalogs/localization_fallback.json"))
	_expect(Validator.validate(fallback).is_empty() and Validator.validate_localization(fallback_text, fallback).is_empty(), "release fallback contains valid nine-skill rules and all translations")
	_expect(fallback["skills"] == config["skills"], "primary and fallback spell balance stays identical")
	var frozen := _model(_profile("ice_age"))
	frozen.enemies[0]["speed_milli_per_tick"] = 10000
	var start_x := int(frozen.enemies[0]["x_milli"])
	frozen.step(_cast("ice_age"))
	for ignored in range(103):
		frozen.step([])
	_expect(int(frozen.enemies[0]["x_milli"]) == start_x, "Ice Age stops actual movement for its full freeze window")
	frozen.step([])
	frozen.step([])
	_expect(int(frozen.enemies[0]["x_milli"]) == start_x - 2500, "after thawing Ice Age leaves the configured 75 percent slow")
	var boss := _model(_profile("ragnarok"))
	boss.enemies[0]["tags"] = ["boss"]
	boss.enemies[0]["special"] = "war_cry"
	boss.enemies[0]["special_interval_ticks"] = 30
	boss.enemies[0]["special_counter"] = 29
	var boss_events := boss.step(_cast("ragnarok"))
	var interrupted := true
	for event in boss_events:
		if event["type"] == "boss_special":
			interrupted = false
	_expect(interrupted and int(boss.enemies[0]["special_counter"]) == 0, "Ragnarok cancels an actual imminent boss special")
	var service: Variant = app.get("upgrade_service")
	for skill in config["skills"]:
		if int(skill["tier"]) <= 1:
			continue
		var node: Dictionary = app.get("content").find_by_id("upgrades", str(skill["upgrade_id"]))
		var previous := str(node["prerequisites"][0])
		var profile := _profile()
		profile["upgrades"][previous] = 2
		_expect(not bool(service.purchase(profile, config, str(node["id"])).get("ok", false)), str(skill["id"]) + " requires previous tier level 3")
		profile["upgrades"][previous] = 3
		_expect(bool(service.purchase(profile, config, str(node["id"])).get("ok", false)), str(skill["id"]) + " can be learned after its prerequisite")
		profile["upgrades"][node["id"]] = int(node["max_level"])
		_expect(str(service.purchase(profile, config, str(node["id"])).get("error_code", "")) == "max_level", str(skill["id"]) + " respects its research level cap")
	var legacy := _profile()
	legacy.erase("equipped_skills")
	legacy["upgrades"]["fire_mastery"] = 8
	legacy["upgrades"]["ice_mastery"] = 5
	var normalized: Dictionary = app.call("_normalize_profile", legacy)
	_expect(normalized["upgrades"]["fire_mastery"] == 8 and normalized["upgrades"]["ice_mastery"] == 5 and normalized["equipped_skills"]["fire"] == "fire_ball", "old saves retain research and receive valid baseline slots")
	legacy["equipped_skills"] = {"fire": "ice_age", "ice": "frost_nova", "lightning": "missing"}
	_expect(SkillCatalog.loadout(config, legacy).values() == ["fire_ball", "glacial_spike", "lightning_strike"], "wrong-element, locked and unknown equipment safely falls back")
	var locked := _model(_profile())
	_expect(_reason(locked.step(_cast("armageddon"))) == "locked" and locked.mana == locked.max_mana, "locked advanced spells cannot bypass research through commands")
	var invalid := config.duplicate(true)
	invalid["skills"][3]["mana_cost"] = 1
	_expect(not Validator.validate(invalid).is_empty(), "validator rejects non-increasing tier Mana")
	invalid = config.duplicate(true)
	invalid["skills"].pop_back()
	_expect(not Validator.validate(invalid).is_empty(), "validator rejects an incomplete elemental chain")
	var ongoing := _model(_profile("armageddon"))
	ongoing.step(_cast("armageddon"))
	ongoing.debug_force_wall_damage(ongoing.wall_hp)
	ongoing.step([])
	_expect(ongoing.status == "defeat" and ongoing.active_spells.is_empty() and ongoing.step([]).is_empty(), "run end cancels all pending impacts")


func _check_research_and_hud() -> void:
	var save_service: Variant = app.get("save_service")
	app.set("profile", _profile())
	var initial: Dictionary = app.get("profile").duplicate(true)
	var missing: Dictionary = app.call("purchase_upgrade", "meteor")
	_expect(not bool(missing.get("ok", false)) and app.get("profile") == initial, "research prevents buying tier II before tier I level 3")
	app.call("purchase_upgrade", "mana_capacity")
	for ignored in range(3):
		app.call("purchase_upgrade", "fire_mastery")
	app.set("save_service", FailingSaveService.new())
	var before: Dictionary = app.get("profile").duplicate(true)
	app.call("purchase_upgrade", "meteor")
	_expect(app.get("profile") == before, "failed unlock saves neither spend coins nor grant/equip a spell")
	app.set("save_service", save_service)
	app.call("purchase_upgrade", "meteor")
	_expect(SkillCatalog.loadout(config, app.get("profile"))["fire"] == "meteor", "learning tier II equips it automatically")
	app.call("select_skill", "fire_ball")
	app.call("purchase_upgrade", "meteor")
	_expect(SkillCatalog.loadout(config, app.get("profile"))["fire"] == "fire_ball", "improving research does not override a cheaper equipped spell")
	app.set("save_service", FailingSaveService.new())
	app.call("select_skill", "meteor")
	_expect(SkillCatalog.loadout(config, app.get("profile"))["fire"] == "fire_ball", "failed equipment persistence retains the previous spell")
	app.set("save_service", save_service)
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	menu.call("_show_research_page", "magic", "meteor")
	await _frames()
	var scroll := menu.find_child("ResearchScroll", true, false) as ScrollContainer
	var nodes_visible := true
	for skill in config["skills"]:
		var node := menu.find_child("Research_" + str(skill["upgrade_id"]), true, false) as Control
		nodes_visible = nodes_visible and node != null and scroll.get_global_rect().encloses(node.get_global_rect())
	_expect(nodes_visible, "all nine primary spell nodes are visible together")
	var button := menu.find_child("ResearchEquipButton", true, false) as Button
	_expect(button != null and button.visible and not button.disabled, "learned research node offers equipment")
	button.pressed.emit()
	await _frames()
	_expect(SkillCatalog.loadout(config, app.get("profile"))["fire"] == "meteor" and button.disabled, "research equipment updates the current spell state")
	var persisted: Dictionary = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(persisted["payload"]["equipped_skills"]["fire"] == "meteor", "selected spell survives save reload")
	await _capture("magic-research")
	root.remove_child(menu)
	menu.free()
	# Verify the real HUD and hotkey path for every tier, including older bows.
	for tier in [1, 2, 3]:
		var profile := _profile()
		for skill in config["skills"]:
			profile["upgrades"][skill["upgrade_id"]] = 3
			if int(skill["tier"]) == tier:
				profile["equipped_skills"][skill["element"]] = skill["id"]
		app.set("profile", profile)
		var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		root.add_child(gameplay)
		gameplay.set_physics_process(false)
		var session: Node = gameplay.get("session")
		session.set_physics_process(false)
		await _frames()
		var hud: Node = gameplay.get("_hud")
		_expect(hud.get("skill_buttons").size() == 3, "tier %d keeps exactly three HUD slots" % tier)
		for element in SkillCatalog.ELEMENTS:
			var id := str(profile["equipped_skills"][element])
			var skill_button: Node = hud.get("skill_buttons")[id]
			_expect(int(skill_button.get("tier")) == tier and int(skill_button.get("mana_cost")) == int(SkillCatalog.find(config, id)["mana_cost"]), id + " HUD shows correct tier and Mana")
			var input := InputEventAction.new()
			input.action = "combat_select_" + element
			input.pressed = true
			gameplay.call("_unhandled_input", input)
			session.call("_physics_process", 1.0 / 30.0)
			_expect(str(session.call("current_snapshot").get("selected_skill", "")) == id, id + " hotkey selects the equipped tier")
			var model := _model(profile)
			# Spread the visual fixture across the battlefield; rule assertions
			# above intentionally use a tightly packed crowd to check target caps.
			for index in range(model.enemies.size()):
				model.enemies[index]["x_milli"] = 760000 + (index % 4) * 160000
				model.enemies[index]["y_milli"] = 300000 + int(index / 4) * 150000
			gameplay.get("effects").clear()
			gameplay.get("floating_texts").clear()
			var events := model.step(_cast(id))
			gameplay.call("_on_snapshot", model.snapshot())
			gameplay.call("_on_events", events)
			await _frames()
			await _capture(id)
		root.remove_child(gameplay)
		gameplay.free()


func _reason(events: Array) -> String:
	for event in events:
		if event.get("type", "") == "skill_rejected":
			return str(event.get("reason", ""))
	return ""


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var directory := "res://Builds/skill-chains-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))
	print("[SKILL CHAINS CAPTURE] " + label)


func _frames() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
		print("[SKILL CHAINS PASS] " + message)
	else:
		failures.append(message)
