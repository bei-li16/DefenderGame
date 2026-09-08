extends SceneTree

const RunModel = preload("res://src/core/combat/run_model.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const SkillSystem = preload("res://src/core/combat/skill_system.gd")
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
	if OS.get_cmdline_user_args().has("--english"):
		app.get("settings")["language"] = "en_US"
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
	_check_edge_and_moving_targets()
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
	profile["crystals"] = 100000
	profile["tutorial_complete"] = true
	if not skill_id.is_empty():
		var skill := SkillCatalog.find(config, skill_id)
		profile["upgrades"][str(skill["upgrade_id"])] = 1 if int(skill["tier"]) > 1 else 0
		profile["equipped_skills"][str(skill["element"])] = skill_id
	return profile


func _model(profile: Dictionary, run_seed: int = 1701) -> DefenderRunModel:
	var rules := config.duplicate(true)
	rules["world"]["spawn_start_tick"] = 1
	rules["player"]["mana_regen_interval_ticks"] = 100000
	rules["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 1, "interval_ticks": 1}]
	var model := RunModel.new()
	model.setup(rules, "stage_001", run_seed, profile)
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
	_expect(model.mana == before - int(skill["mana_cost"]) and model.spells_cast == 1 and int(model.get(str(skill["element"]) + "_casts")) == 1, id + " pays Mana and counts one cast only")
	_expect(_count(events, "skill_pulse") == 0 and _count(events, "damage") == 0 and model.enemies[0]["burn_ticks"] == 0 and model.enemies[0]["stun_ticks"] == 0, id + " never damages or controls before landing")
	_expect(_count(events, "skill_launch") == 1 and model.snapshot()["falling_spells"].size() == 1, id + " launches a real visible falling spell immediately")
	var plan: Array = model.active_spells[0]["impacts"].duplicate(true)
	_expect(plan.size() == int(skill["impact_count"]), id + " schedules exactly the configured count")
	var isolated: Dictionary = model.snapshot()
	isolated["falling_spells"][0]["x_milli"] = -99999
	_expect(model.active_spells[0]["impacts"][0]["x_milli"] != -99999, id + " presentation cannot mutate scheduled landings")
	var positions_valid := true
	var times: Array[int] = []
	for impact in plan:
		var px := int(impact["x_milli"])
		var py := int(impact["y_milli"])
		positions_valid = positions_valid and px >= int(config["world"]["castle_x_milli"]) and px <= int(config["world"]["width_milli"]) and py >= 0 and py <= int(config["world"]["height_milli"])
		if skill["target_mode"] == "point":
			positions_valid = positions_valid and px == 1000000 and py == 500000
		elif skill["target_mode"] == "area":
			positions_valid = positions_valid and Vector2(px - 1000000, py - 500000).length() <= int(skill["area_radius_milli"])
		times.append(int(impact["launch_tick"]))
	_expect(positions_valid, id + " uses the correct point, clipped disk or full-battlefield footprint")
	if times.size() > 1:
		var unique := true
		var gaps := {}
		for index in range(1, times.size()):
			unique = unique and times[index] > times[index - 1]
			gaps[times[index] - times[index - 1]] = true
		_expect(unique and gaps.size() > 1 and times[-1] - times[0] < int(skill["barrage_duration_ticks"]), id + " rains at distinct irregular times inside the configured window")
	var predicted_damage := 0
	for impact in plan:
		for enemy in model.enemies:
			predicted_damage += _expected_damage(skill, Vector2(int(enemy["x_milli"]) - int(impact["x_milli"]), int(enemy["y_milli"]) - int(impact["y_milli"])).length())
	var rejection := model.step(_cast(id))
	_expect(_reason(rejection) == "cooldown" and model.mana == before - int(skill["mana_cost"]), id + " rejects repeat payment during the shared cooldown")
	events.append_array(rejection)
	var last_tick := int(plan[-1]["impact_tick"])
	while model.tick <= last_tick:
		events.append_array(model.step([]))
	var total_damage := 0
	for event in events:
		if event["type"] == "damage" and event.get("source", "") == skill["element"]:
			total_damage += int(event["amount"])
	_expect(_count(events, "skill_launch") == int(skill["impact_count"]) and _count(events, "skill_pulse") == int(skill["impact_count"]) and model.active_spells.is_empty(), id + " resolves every launched impact once and prunes its queue")
	_expect(total_damage == predicted_damage and model.mana == before - int(skill["mana_cost"]), id + " each random landing independently resolves exact direct/splash damage")
	_check_impact_math(skill)
	var no_mana := _model(profile)
	no_mana.mana = int(skill["mana_cost"]) - 1
	var rng_before := no_mana._spell_rng.state()
	_expect(_reason(no_mana.step(_cast(id))) == "no_mana" and no_mana.active_spells.is_empty() and no_mana._spell_rng.state() == rng_before, id + " insufficient Mana creates no schedule or random draws")
	var invalid := _model(profile)
	var bad := _cast(id)
	bad[0]["x_milli"] = -1000
	var bad_events := invalid.step(bad)
	_expect((_count(bad_events, "skill_cast") == 1 if skill["tier"] == 3 else _reason(bad_events) == "invalid_target"), id + " target validation follows its delivery tier")
	var high := profile.duplicate(true)
	high["upgrades"][skill["upgrade_id"]] = int(high["upgrades"].get(skill["upgrade_id"], 0)) + 2
	var upgraded := SkillCatalog.effective(config, high, id)
	_expect(int(upgraded["damage"]) > int(skill["damage"]) and int(upgraded["splash_damage"]) > int(skill["splash_damage"]) and int(upgraded["radius_milli"]) > int(skill["radius_milli"]) and int(upgraded["splash_radius_milli"]) > int(skill["splash_radius_milli"]), id + " research improves all single-impact damage/radius parameters")
	_expect(upgraded["impact_count"] == skill["impact_count"] and upgraded["barrage_duration_ticks"] == skill["barrage_duration_ticks"] and upgraded["area_radius_milli"] == skill["area_radius_milli"] and upgraded["mana_cost"] == skill["mana_cost"], id + " upgrades leave count, duration, footprint and Mana fixed")
	var status_field := "burn_duration_ticks" if skill["element"] == "fire" else ("freeze_ticks" if skill["element"] == "ice" else "stun_ticks")
	_expect(int(upgraded[status_field]) > int(skill[status_field]), id + " research extends the elemental status")
	if skill["element"] == "fire":
		_expect(int(upgraded["burn_damage"]) > int(skill["burn_damage"]), id + " research also increases burn damage")
	var replay_a := _model(profile)
	var replay_b := _model(profile)
	var log_a: Array = replay_a.step(_cast(id))
	var second_cast := _cast(id)
	if skill["tier"] == 3:
		second_cast[0]["x_milli"] = 99999999
		second_cast[0]["y_milli"] = -99999999
	var log_b: Array = replay_b.step(second_cast)
	for ignored in range(int(skill["barrage_duration_ticks"]) + int(skill["fall_ticks"]) + 1):
		log_a.append_array(replay_a.step([]))
		log_b.append_array(replay_b.step([]))
	_expect(EventHasher.hash_events(log_a) == EventHasher.hash_events(log_b), id + " replay is deterministic (screen tier ignores aim completely)")
	if int(skill["tier"]) > 1:
		var other_seed := _model(profile, 7099)
		other_seed.step(_cast(id))
		_expect(other_seed.active_spells[0]["impacts"] != plan, id + " another seed creates another rainfall pattern")


func _expected_damage(skill: Dictionary, distance: float) -> int:
	if distance <= int(skill["radius_milli"]):
		return int(skill["damage"])
	if distance >= int(skill["splash_radius_milli"]):
		return 0
	return int(float(skill["splash_damage"]) * (int(skill["splash_radius_milli"]) - distance) / (int(skill["splash_radius_milli"]) - int(skill["radius_milli"])))


func _check_impact_math(skill: Dictionary) -> void:
	var id := str(skill["id"])
	var model := _model(_profile(id))
	var inner := int(skill["radius_milli"])
	var outer := int(skill["splash_radius_milli"])
	var distances := [0, inner, inner + 1, (inner + outer) / 2, outer - 1, outer, outer + 1]
	for index in range(model.enemies.size()):
		model.enemies[index]["x_milli"] = 1000000 + (distances[index] if index < distances.size() else outer + 1000)
		model.enemies[index]["y_milli"] = 500000
	var events: Array[Dictionary] = []
	SkillSystem.apply_pulse(model, skill, 1000000, 500000, events)
	var exact := true
	for index in range(distances.size()):
		var expected := _expected_damage(skill, float(distances[index]))
		var enemy: Dictionary = model.enemies[index]
		exact = exact and int(enemy["hp"]) == 100000 - expected
		if expected == 0:
			exact = exact and enemy["burn_ticks"] == 0 and enemy["stun_ticks"] == 0
	_expect(exact, id + " core edge/full damage, fading splash and outside no-hit are exact")
	var first: Dictionary = model.enemies[0]
	var status_field := "burn_ticks" if skill["element"] == "fire" else "stun_ticks"
	var duration_field := "burn_duration_ticks" if skill["element"] == "fire" else ("freeze_ticks" if skill["element"] == "ice" else "stun_ticks")
	_expect(int(first[status_field]) == int(skill[duration_field]), id + " applies the configured single-impact status")
	var resistant := _model(_profile(id))
	resistant.enemies[0]["status_resistance_permille"] = 500
	SkillSystem.apply_pulse(resistant, skill, 1000000, 500000, [])
	_expect(int(resistant.enemies[0][status_field]) == int(skill[duration_field]) / 2, id + " status resistance still applies")
	if skill["element"] == "fire":
		var before := int(first["hp"])
		for ignored in range(int(skill["burn_duration_ticks"])):
			model.step([])
		var expected_burn := int(skill["burn_damage"]) * (int(skill["burn_duration_ticks"]) / int(skill["burn_interval_ticks"]))
		_expect(before - int(first["hp"]) == expected_burn and first["burn_ticks"] == 0, id + " burns at later intervals for the configured lifetime")
	elif skill["element"] == "ice":
		first["speed_milli_per_tick"] = 10000
		var x := int(first["x_milli"])
		for ignored in range(int(skill["freeze_ticks"])):
			model.step([])
		_expect(first["x_milli"] == x, id + " frozen target cannot move")
		model.step([])
		_expect(first["x_milli"] == x - 10000 * int(skill["slow_permille"]) / 1000, id + " thawing transitions into the configured slow")
	else:
		_expect(first["special_counter"] == 0 and int(first["attack_cooldown"]) >= int(skill["stun_ticks"]), id + " interrupt resets charges and delays attacks")


func _check_edge_and_moving_targets() -> void:
	for skill in config["skills"]:
		var id := str(skill["id"])
		if int(skill["tier"]) == 1:
			var moving := _model(_profile(id))
			moving.enemies[1]["x_milli"] = 1800000
			moving.step(_cast(id))
			# Leave/enter the blast during flight, without changing its target.
			moving.enemies[0]["x_milli"] = 1800000
			moving.enemies[1]["x_milli"] = 1000000
			for ignored in range(int(skill["fall_ticks"])):
				moving.step([])
			_expect(moving.enemies[0]["hp"] == 100000 and moving.enemies[1]["hp"] < 100000, id + " hits positions at landing rather than positions at cast time")
		elif int(skill["tier"]) == 2:
			var valid := true
			var world: Dictionary = config["world"]
			for corner in [Vector2i(int(world["castle_x_milli"]), 0), Vector2i(int(world["width_milli"]), int(world["height_milli"]))]:
				for run_seed in range(1, 17):
					var edge := _model(_profile(id), run_seed)
					edge.step([{"type": "cast_skill", "skill_id": id, "x_milli": corner.x, "y_milli": corner.y}])
					for impact in edge.active_spells[0]["impacts"]:
						var p := Vector2i(impact["x_milli"], impact["y_milli"])
						valid = valid and Vector2(p - corner).length() <= int(skill["area_radius_milli"]) and p.x >= int(world["castle_x_milli"]) and p.x <= int(world["width_milli"]) and p.y >= 0 and p.y <= int(world["height_milli"])
			_expect(valid, id + " corner targeting keeps every random landing inside the disk and world")
		var normal := _model(_profile(id))
		var noisy := _model(_profile(id))
		for ignored in range(57):
			noisy._combat_rng.range_exclusive(0, 1000)
			noisy._spawn_rng.range_exclusive(0, 1000)
		normal.step(_cast(id))
		noisy.step(_cast(id))
		_expect(normal.active_spells == noisy.active_spells, id + " barrage RNG is independent of bow and spawn randomness")
	var fire := SkillCatalog.find(config, "fire_ball").duplicate(true)
	var burn := _model(_profile("fire_ball"))
	SkillSystem.apply_pulse(burn, fire, 1000000, 500000, [])
	for ignored in range(4):
		burn.step([])
	var counter := int(burn.enemies[0]["burn_counter"])
	var stronger := fire.duplicate(true)
	stronger["burn_damage"] = int(fire["burn_damage"]) + 7
	SkillSystem.apply_pulse(burn, stronger, 1000000, 500000, [])
	SkillSystem.apply_pulse(burn, fire, 1000000, 500000, [])
	var enemy: Dictionary = burn.enemies[0]
	_expect(enemy["burn_damage"] == stronger["burn_damage"] and enemy["burn_counter"] == counter and enemy["burn_ticks"] == fire["burn_duration_ticks"], "repeat burns refresh duration, preserve the strongest damage and do not postpone ticks")
	var hp := int(enemy["hp"])
	for ignored in range(counter):
		burn.step([])
	_expect(hp - int(enemy["hp"]) == int(stronger["burn_damage"]), "overlapping burns remain one DoT rather than unlimited stacks")


func _count(events: Array, kind: String) -> int:
	var count := 0
	for event in events:
		if str(event.get("type", "")) == kind:
			count += 1
	return count


func _check_rules_and_legacy() -> void:
	var fallback: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/config/game_rules_fallback.json"))
	var fallback_text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/catalogs/localization_fallback.json"))
	_expect(Validator.validate(fallback).is_empty() and Validator.validate_localization(fallback_text, fallback).is_empty(), "release fallback contains valid nine-skill rules and all translations")
	_expect(fallback["skills"] == config["skills"], "primary and fallback spell balance stays identical")
	var boss := _model(_profile("ragnarok"))
	boss.enemies[0]["tags"] = ["boss"]
	boss.enemies[0]["special"] = "war_cry"
	boss.enemies[0]["special_interval_ticks"] = 30
	boss.enemies[0]["special_counter"] = 29
	var boss_events: Array[Dictionary] = []
	SkillSystem.apply_pulse(boss, SkillCatalog.find(config, "ragnarok"), 1000000, 500000, boss_events)
	boss_events.append_array(boss.step([]))
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
		_expect(bool(service.purchase(profile, config, str(node["id"])).get("ok", false)), str(skill["id"]) + " continues research beyond the old cap")
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
	for mutation in [
		{"tier": 1, "target_mode": "screen"},
		{"tier": 2, "barrage_duration_ticks": 2},
		{"tier": 2, "impact_count": 100},
		{"tier": 2, "area_radius_milli": 0},
		{"tier": 1, "splash_radius_milli": 1},
		{"tier": 1, "splash_damage_per_level": 10000},
		{"tier": 1, "radius_milli_per_level": 1000000},
		{"tier": 2, "impact_count_per_level": 1},
		{"tier": 2, "area_radius_milli_per_level": 1000},
	]:
		invalid = config.duplicate(true)
		for candidate in invalid["skills"]:
			if int(candidate["tier"]) == int(mutation["tier"]):
				candidate.merge(mutation, true)
				break
		_expect(not Validator.validate(invalid).is_empty(), "validator rejects malformed delivery or upgraded splash: " + str(mutation))
	var ongoing := _model(_profile("armageddon"))
	ongoing.step(_cast("armageddon"))
	ongoing.debug_force_wall_damage(ongoing.wall_hp)
	ongoing.step([])
	_expect(ongoing.status == "defeat" and ongoing.active_spells.is_empty() and ongoing.step([]).is_empty(), "run end cancels all pending impacts")


func _check_research_and_hud() -> void:
	var save_service: Variant = app.get("save_service")
	app.get("settings")["auto_fire"] = false
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
		gameplay.set_process(false)
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
			# Spread the visual fixture across the battlefield so individual
			# trajectories and the separate, real landing events are readable.
			for index in range(model.enemies.size()):
				model.enemies[index]["x_milli"] = 760000 + (index % 4) * 160000
				model.enemies[index]["y_milli"] = 300000 + int(index / 4) * 150000
			gameplay.get("effects").clear()
			gameplay.get("floating_texts").clear()
			var events := model.step(_cast(id))
			gameplay.call("_on_snapshot", model.snapshot())
			gameplay.call("_on_events", events)
			var spell := SkillCatalog.effective(config, profile, id)
			var fall := int(spell["fall_ticks"])
			var cast_tick := model.tick
			# Advancing only presentation must not manufacture damage or a blast.
			gameplay.call("_process", 1.0)
			_expect(gameplay.get("effects").is_empty() and model.tick == cast_tick, id + " visual time cannot resolve an impact")
			var blend: float = gameplay.get("_snapshot_blend")
			paused = true
			gameplay.call("_process", 0.5)
			_expect(gameplay.get("_snapshot_blend") == blend, id + " falling animation stops while paused")
			paused = false
			while model.tick < cast_tick + int(fall * 0.75):
				_visual_step(gameplay, model)
			await _frames()
			await _capture(id + "-fall")
			var review_tick := cast_tick + fall + 4
			if tier > 1:
				# Random gaps may legitimately contain no impacts. Capture shortly
				# after a real later landing, not a hard-coded empty moment.
				for impact in model.active_spells[0]["impacts"]:
					review_tick = int(impact["impact_tick"]) + 4
					if int(impact["impact_tick"]) >= cast_tick + 60:
						break
			while model.tick < review_tick:
				_visual_step(gameplay, model)
			_expect(not gameplay.get("effects").is_empty(), id + " landing events drive visible elemental effects")
			await _frames()
			await _capture(id)
		root.remove_child(gameplay)
		gameplay.free()


func _visual_step(gameplay: Node, model: DefenderRunModel) -> void:
	gameplay.call("_process", 1.0 / 30.0)
	var events := model.step([])
	gameplay.call("_on_snapshot", model.snapshot())
	gameplay.call("_on_events", events)
	gameplay.queue_redraw()


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
	if str(app.get("settings").get("language", "")) == "en_US":
		label += "-en"
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
