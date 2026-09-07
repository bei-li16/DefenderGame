extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")
const RunModel = preload("res://src/core/combat/run_model.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var content := ContentService.new()
	var loaded := content.load_builtin()
	if not bool(loaded.get("ok", false)):
		push_error("Content failed to load")
		quit(1)
		return
	var profile := {
		"current_weapon_id": "phantom_bow",
		"unlocked_weapons": ["basic_bow", "power_bow", "hurricane_bow", "phantom_bow"],
		"upgrades": {
			"strength": 12, "agility": 6, "power_shot": 9, "poisoned_arrow": 9, "fatal_blow": 9, "multiple_arrows": 9, "senior_hunter": 9,
			"fire_mastery": 8, "ice_mastery": 8, "lightning_mastery": 8, "mana_capacity": 8, "mana_regen": 6, "spell_radius": 5, "cooldown_mastery": 6,
			"wall_armor": 10, "wall_repair": 8, "lava_moat": 5, "magic_tower": 5, "coin_bounty": 10, "xp_bounty": 10
		}
	}
	var novice_profile := {"upgrades": {"strength": 0, "agility": 0, "fire_mastery": 0, "ice_mastery": 0, "lightning_mastery": 0}}
	var novice_outcome := _autoplay_stage(content.rules, "stage_001", 1, novice_profile)
	print("[STAGE] novice stage_001 status=%s ticks=%d wall=%d%%" % [novice_outcome["status"], novice_outcome["tick"], novice_outcome["wall_percent"]])
	if novice_outcome["status"] != "victory":
		failures.append("new profile could not complete stage_001")
	for stage in content.rules.get("stages", []):
		var outcome := _autoplay_stage(content.rules, str(stage["id"]), int(stage["number"]), profile)
		print("[STAGE] %s status=%s ticks=%d kills=%d wall=%d%% coins=%d xp=%d boss_deaths=%d" % [
			stage["id"], outcome["status"], outcome["tick"], outcome["kills"], outcome["wall_percent"], outcome["coins"], outcome["xp"], outcome["boss_deaths"]
		])
		if outcome["status"] != "victory":
			failures.append("%s did not reach victory" % stage["id"])
		if bool(stage.get("boss", false)) and int(outcome["boss_deaths"]) != 1:
			failures.append("%s expected exactly one boss death" % stage["id"])
	for failure in failures:
		push_error("[FAIL] " + failure)
	print("[STAGE] 30-stage autoplay complete; failures=%d" % failures.size())
	quit(failures.size())


func _autoplay_stage(config: Dictionary, stage_id: String, stage_number: int, profile: Dictionary) -> Dictionary:
	var model := RunModel.new()
	model.setup(config, stage_id, 7000 + stage_number, profile)
	var boss_deaths := 0
	for simulation_tick in range(18000):
		var commands: Array = []
		if simulation_tick == 0:
			commands.append({"type": "fire_started"})
		var current := model.snapshot()
		var target := _priority_target(current.get("enemies", []))
		if not target.is_empty():
			commands.append({"type": "aim", "x_milli": target["x_milli"], "y_milli": target["y_milli"]})
			var cooldowns: Dictionary = current.get("skill_cooldowns", {})
			var mana := int(current.get("mana", 0))
			var skill_id := ""
			if int(cooldowns.get("lightning_strike", 0)) <= 0 and mana >= 40 and target.get("tags", []).has("boss"):
				skill_id = "lightning_strike"
			elif int(cooldowns.get("fire_ball", 0)) <= 0 and mana >= 30 and current.get("enemies", []).size() >= 2:
				skill_id = "fire_ball"
			elif int(cooldowns.get("glacial_spike", 0)) <= 0 and mana >= 25:
				skill_id = "glacial_spike"
			if not skill_id.is_empty():
				commands.append({"type": "select_skill", "skill_id": skill_id})
				commands.append({"type": "cast_skill", "skill_id": skill_id, "x_milli": target["x_milli"], "y_milli": target["y_milli"]})
		var events := model.step(commands)
		for event in events:
			if event.get("type", "") == "death" and bool(event.get("boss", false)):
				boss_deaths += 1
		if model.status != "running":
			break
	var result := model.result()
	result["boss_deaths"] = boss_deaths
	return result


func _priority_target(enemies: Array) -> Dictionary:
	var target: Dictionary = {}
	var minimum_x := 999999999
	for enemy in enemies:
		if int(enemy.get("hp", 0)) > 0 and int(enemy.get("x_milli", minimum_x)) < minimum_x:
			minimum_x = int(enemy["x_milli"])
			target = enemy
	return target
