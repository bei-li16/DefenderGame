class_name DefenderSkillSystem
extends RefCounted

# Spell casting: validation, cost/cooldown bookkeeping and the three elemental
# applications, extracted from RunModel (architecture §6.1 SkillSystem).
# Functions receive the RunModel facade as `model`; code is behaviour-preserving.

static func cast(model, skill_id: String, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	if skill_id.is_empty():
		return
	var skill: Dictionary = model._find_by_id(model.config.get("skills", []), skill_id)
	if skill.is_empty():
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
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
	model.skill_cooldowns[skill_id] = model._effective_skill_cooldown(skill)
	model.spells_cast += 1
	model.selected_skill = ""
	model._emit(events, "skill_cast", {"skill_id": skill_id, "x_milli": target_x, "y_milli": target_y, "mana": model.mana})
	match skill_id:
		"fire_ball":
			model.fire_casts += 1
		"glacial_spike":
			model.ice_casts += 1
		"lightning_strike":
			model.lightning_casts += 1
	match skill_id:
		"fire_ball":
			apply_fire(model, skill, target_x, target_y, events)
		"glacial_spike":
			apply_ice(model, skill, target_x, target_y, events)
		"lightning_strike":
			apply_lightning(model, skill, target_x, target_y, events)


static func apply_fire(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage: int = model._percent_boosted(int(skill.get("damage", 0)) + model._upgrade_level("fire_mastery") * model._upgrade_effect_per_level("fire_mastery"), "fire_damage_pct")
	var radius: int = model._skill_radius(skill)
	for enemy in model.enemies:
		if model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= model._square(radius):
			model._apply_enemy_damage(enemy, damage, "fire", events)
			enemy["burn_damage"] = int(skill.get("burn_damage", 0))
			enemy["burn_interval_ticks"] = maxi(1, int(skill.get("burn_interval_ticks", 15)))
			enemy["burn_counter"] = enemy["burn_interval_ticks"]
			enemy["burn_ticks"] = model._resisted_ticks(enemy, int(skill.get("burn_duration_ticks", 0)))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "burn", "ticks": enemy["burn_ticks"]})


static func apply_ice(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage: int = model._percent_boosted(int(skill.get("damage", 0)) + model._upgrade_level("ice_mastery") * model._upgrade_effect_per_level("ice_mastery"), "ice_damage_pct")
	var radius: int = model._skill_radius(skill)
	for enemy in model.enemies:
		if model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= model._square(radius):
			model._apply_enemy_damage(enemy, damage, "ice", events)
			enemy["slow_permille"] = int(skill.get("slow_permille", 500))
			enemy["slow_ticks"] = model._resisted_ticks(enemy, int(skill.get("slow_duration_ticks", 0)))
			enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), model._resisted_ticks(enemy, int(skill.get("freeze_ticks", 0))))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "frozen", "ticks": enemy["stun_ticks"]})


static func apply_lightning(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var candidates: Array[Dictionary] = []
	var radius_squared: int = model._square(model._skill_radius(skill))
	for enemy in model.enemies:
		var distance: int = model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y)
		if distance <= radius_squared:
			candidates.append({"enemy": enemy, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["distance"]) < int(b["distance"]))
	var count := mini(int(skill.get("max_targets", 1)), candidates.size())
	var damage: int = model._percent_boosted(int(skill.get("damage", 0)) + model._upgrade_level("lightning_mastery") * model._upgrade_effect_per_level("lightning_mastery"), "lightning_damage_pct")
	for index in range(count):
		var enemy: Dictionary = candidates[index]["enemy"]
		model._apply_enemy_damage(enemy, damage, "lightning", events)
		enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), model._resisted_ticks(enemy, int(skill.get("stun_ticks", 0))))
		model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "stunned", "ticks": enemy["stun_ticks"]})
