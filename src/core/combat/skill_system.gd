class_name DefenderSkillSystem
extends RefCounted

const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")

# Nine data-driven spells: slot validation, one-time payment, deterministic
# multi-impact effects and elemental status rules. No rendering/timers here.

static func cast(model, skill_id: String, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	if skill_id.is_empty():
		return
	var skill := SkillCatalog.effective(model.config, model.profile_snapshot, skill_id)
	if skill.is_empty():
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
		return
	var element := str(skill.get("element", ""))
	if not SkillCatalog.available(model.config, model.profile_snapshot, skill_id):
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "locked"})
		return
	if str(model.skill_loadout.get(element, "")) != skill_id:
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "not_equipped"})
		return
	if int(model.skill_cooldowns.get(skill_id, 0)) > 0:
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "cooldown"})
		return
	var mana_cost := int(skill.get("mana_cost", 0))
	if model.mana < mana_cost:
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "no_mana"})
		return
	var world: Dictionary = model.config.get("world", {})
	if target_x < int(world.get("castle_x_milli", 0)) or target_x > int(world.get("width_milli", 1920000)) or target_y < 0 or target_y > int(world.get("height_milli", 1080000)):
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
		return
	model.mana = clampi(model.mana - mana_cost, 0, model.max_mana)
	for sibling in model.config.get("skills", []):
		if str(sibling.get("element", "")) == element:
			model.skill_cooldowns[str(sibling["id"])] = int(skill["cooldown_ticks"])
	model.spells_cast += 1
	model.selected_skill = ""
	model._emit(events, "skill_cast", {"skill_id": skill_id, "element": element, "tier": skill["tier"], "x_milli": target_x, "y_milli": target_y, "mana": model.mana, "mana_cost": mana_cost})
	match element:
		"fire":
			model.fire_casts += 1
		"ice":
			model.ice_casts += 1
		"lightning":
			model.lightning_casts += 1
	apply_pulse(model, skill, target_x, target_y, events)
	if int(skill.get("pulse_count", 1)) > 1:
		model.active_spells.append({"skill": skill, "x_milli": target_x, "y_milli": target_y, "remaining": int(skill["pulse_count"]) - 1, "next_tick": model.tick + int(skill["pulse_interval_ticks"])})


# Persistent spell state advances only with simulation ticks, never render time.
static func update(model, events: Array[Dictionary]) -> void:
	if model.wall_hp <= 0:
		return
	for index in range(model.active_spells.size() - 1, -1, -1):
		var ongoing: Dictionary = model.active_spells[index]
		if model.tick < int(ongoing["next_tick"]):
			continue
		apply_pulse(model, ongoing["skill"], ongoing["x_milli"], ongoing["y_milli"], events)
		ongoing["remaining"] = int(ongoing["remaining"]) - 1
		ongoing["next_tick"] = model.tick + int(ongoing["skill"]["pulse_interval_ticks"])
		if int(ongoing["remaining"]) <= 0:
			model.active_spells.remove_at(index)


static func apply_pulse(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var start := events.size()
	match str(skill["element"]):
		"fire":
			apply_fire(model, skill, target_x, target_y, events)
		"ice":
			apply_ice(model, skill, target_x, target_y, events)
		"lightning":
			apply_lightning(model, skill, target_x, target_y, events)
	var positions := {}
	for enemy in model.enemies:
		positions[enemy["entity_id"]] = {"x_milli": enemy["x_milli"], "y_milli": enemy["y_milli"]}
	var hits: Array[Dictionary] = []
	for index in range(start, events.size()):
		var event: Dictionary = events[index]
		if str(event["type"]) == "damage" and positions.has(event.get("entity_id", -1)):
			hits.append(positions[event["entity_id"]])
	model._emit(events, "skill_pulse", {"skill_id": skill["id"], "element": skill["element"], "tier": skill["tier"], "radius_milli": skill["radius_milli"], "x_milli": target_x, "y_milli": target_y, "hits": hits})


static func apply_fire(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage := int(skill["damage"])
	var radius := int(skill["radius_milli"])
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0:
			continue
		if model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= model._square(radius):
			model._apply_enemy_damage(enemy, damage, "fire", events)
			var already_burning := int(enemy.get("burn_ticks", 0)) > 0
			enemy["burn_damage"] = maxi(int(enemy.get("burn_damage", 0)), int(skill.get("burn_damage", 0))) if already_burning else int(skill.get("burn_damage", 0))
			enemy["burn_interval_ticks"] = maxi(1, int(skill.get("burn_interval_ticks", 15)))
			if int(enemy.get("burn_ticks", 0)) <= 0:
				enemy["burn_counter"] = enemy["burn_interval_ticks"]
			enemy["burn_ticks"] = maxi(int(enemy.get("burn_ticks", 0)), model._resisted_ticks(enemy, int(skill.get("burn_duration_ticks", 0))))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "burn", "ticks": enemy["burn_ticks"]})


static func apply_ice(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage := int(skill["damage"])
	var radius := int(skill["radius_milli"])
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0:
			continue
		if model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= model._square(radius):
			model._apply_enemy_damage(enemy, damage, "ice", events)
			enemy["slow_permille"] = mini(int(enemy.get("slow_permille", 1000)), int(skill.get("slow_permille", 500)))
			enemy["slow_ticks"] = maxi(int(enemy.get("slow_ticks", 0)), model._resisted_ticks(enemy, int(skill.get("slow_duration_ticks", 0))))
			enemy["freeze_ticks"] = maxi(int(enemy.get("freeze_ticks", 0)), model._resisted_ticks(enemy, int(skill.get("freeze_ticks", 0))))
			enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), model._resisted_ticks(enemy, int(skill.get("freeze_ticks", 0))))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "frozen", "ticks": enemy["stun_ticks"]})


static func apply_lightning(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var candidates: Array[Dictionary] = []
	var radius_squared: int = model._square(int(skill["radius_milli"]))
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var distance: int = model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y)
		if distance <= radius_squared:
			candidates.append({"enemy": enemy, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["distance"]) == int(b["distance"]):
			return int(a["enemy"]["entity_id"]) < int(b["enemy"]["entity_id"])
		return int(a["distance"]) < int(b["distance"])
	)
	var count := mini(int(skill.get("max_targets", 1)), candidates.size())
	var damage := int(skill["damage"])
	for index in range(count):
		var enemy: Dictionary = candidates[index]["enemy"]
		model._apply_enemy_damage(enemy, damage, "lightning", events)
		enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), model._resisted_ticks(enemy, int(skill.get("stun_ticks", 0))))
		enemy["attack_cooldown"] = maxi(int(enemy.get("attack_cooldown", 0)), int(enemy["stun_ticks"]))
		enemy["special_counter"] = 0
		model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "stunned", "ticks": enemy["stun_ticks"]})
