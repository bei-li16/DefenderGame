class_name DefenderSkillSystem
extends RefCounted

const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")

# One impact mechanic per element; tiers change only delivery. All launch times,
# landing positions and hit decisions belong to the seeded fixed-tick simulation.
static func cast(model, skill_id: String, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	if skill_id.is_empty():
		return
	var skill := SkillCatalog.effective(model.config, model.profile_snapshot, skill_id)
	if skill.is_empty():
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
		return
	var element := str(skill["element"])
	var reason := ""
	if not SkillCatalog.available(model.config, model.profile_snapshot, skill_id):
		reason = "locked"
	elif str(model.skill_loadout.get(element, "")) != skill_id:
		reason = "not_equipped"
	elif int(model.skill_cooldowns.get(skill_id, 0)) > 0:
		reason = "cooldown"
	elif model.mana < int(skill["mana_cost"]):
		reason = "no_mana"
	var world: Dictionary = model.config["world"]
	var screen := str(skill["target_mode"]) == "screen"
	if reason.is_empty() and not screen and (target_x < int(world["castle_x_milli"]) or target_x > int(world["width_milli"]) or target_y < 0 or target_y > int(world["height_milli"])):
		reason = "invalid_target"
	if not reason.is_empty():
		model._emit(events, "skill_rejected", {"skill_id": skill_id, "reason": reason})
		return
	# Tier III ignores even out-of-world pointer coordinates. Canonicalizing the
	# anchor makes its entire event stream independent of the clicked location.
	if screen:
		target_x = (int(world["castle_x_milli"]) + int(world["width_milli"])) / 2
		target_y = int(world["height_milli"]) / 2
	model.mana = clampi(model.mana - int(skill["mana_cost"]), 0, model.max_mana)
	for sibling in model.config["skills"]:
		if str(sibling["element"]) == element:
			model.skill_cooldowns[str(sibling["id"])] = int(skill["cooldown_ticks"])
	model.spells_cast += 1
	model.selected_skill = ""
	match element:
		"fire": model.fire_casts += 1
		"ice": model.ice_casts += 1
		"lightning": model.lightning_casts += 1
	model._emit(events, "skill_cast", {
		"skill_id": skill_id, "element": element, "tier": skill["tier"],
		"x_milli": target_x, "y_milli": target_y, "mana": model.mana,
		"mana_cost": skill["mana_cost"], "target_mode": skill["target_mode"],
		"area_radius_milli": skill["area_radius_milli"],
		"impact_count": skill["impact_count"], "barrage_duration_ticks": skill["barrage_duration_ticks"],
	})
	var impacts: Array[Dictionary] = []
	var offsets := launch_offsets(model._spell_rng, int(skill["impact_count"]), int(skill["barrage_duration_ticks"]))
	for offset in offsets:
		var point := landing_point(model, skill, target_x, target_y)
		impacts.append({"x_milli": point.x, "y_milli": point.y, "launch_tick": model.tick + offset, "impact_tick": model.tick + offset + int(skill["fall_ticks"])})
	model.active_spells.append({"skill": skill, "impacts": impacts, "launch_cursor": 0, "impact_cursor": 0})


static func launch_offsets(rng, count: int, duration: int) -> Array[int]:
	if count == 1:
		return [0]
	# Sample ticks WITHOUT replacement. Immediate first launch gives feedback;
	# subsequent gaps are random (not evenly spaced, and never simultaneous).
	var pool: Array[int] = []
	for offset in range(1, duration):
		pool.append(offset)
	var result: Array[int] = [0]
	for index in range(count - 1):
		var chosen: int = rng.range_exclusive(index, pool.size())
		var value := pool[chosen]
		pool[chosen] = pool[index]
		pool[index] = value
		result.append(value)
	result.sort()
	# Also reject the rare arithmetic progression, rather than displaying an
	# apparently periodic barrage for an unlucky seed.
	var regular := true
	var gap := result[1] - result[0]
	for index in range(2, result.size()):
		regular = regular and result[index] - result[index - 1] == gap
	if regular:
		for candidate in range(1, duration):
			if not result.has(candidate):
				result[1] = candidate
				result.sort()
				break
	return result


static func landing_point(model, skill: Dictionary, x: int, y: int) -> Vector2i:
	var mode := str(skill["target_mode"])
	if mode == "point":
		return Vector2i(x, y)
	var world: Dictionary = model.config["world"]
	var left := int(world["castle_x_milli"])
	var right := int(world["width_milli"])
	var bottom := int(world["height_milli"])
	if mode == "screen":
		# Independent uniform ground coordinates, including the center. No
		# exclusion zone, spacing/coverage quota, or radius-dependent re-rolls.
		return Vector2i(model._spell_rng.range_exclusive(left, right + 1), model._spell_rng.range_exclusive(0, bottom + 1))
	var radius := int(skill["area_radius_milli"])
	# Rejection-sample the disk intersected with the battlefield, instead of
	# clamping off-screen points into conspicuous lines along screen edges.
	for attempt in range(128):
		var px: int = model._spell_rng.range_exclusive(maxi(left, x - radius), mini(right, x + radius) + 1)
		var py: int = model._spell_rng.range_exclusive(maxi(0, y - radius), mini(bottom, y + radius) + 1)
		if model._distance_squared(px, py, x, y) <= model._square(radius):
			return Vector2i(px, py)
	return Vector2i(x, y)


static func update(model, events: Array[Dictionary]) -> void:
	if model.wall_hp <= 0:
		return
	for index in range(model.active_spells.size() - 1, -1, -1):
		var ongoing: Dictionary = model.active_spells[index]
		var skill: Dictionary = ongoing["skill"]
		var impacts: Array = ongoing["impacts"]
		while int(ongoing["launch_cursor"]) < impacts.size():
			var launch: Dictionary = impacts[int(ongoing["launch_cursor"])]
			if model.tick < int(launch["launch_tick"]):
				break
			var data := launch.duplicate()
			data.merge({"skill_id": skill["id"], "element": skill["element"], "tier": skill["tier"], "fall_ticks": skill["fall_ticks"]})
			model._emit(events, "skill_launch", data)
			ongoing["launch_cursor"] = int(ongoing["launch_cursor"]) + 1
		while int(ongoing["impact_cursor"]) < impacts.size():
			var impact: Dictionary = impacts[int(ongoing["impact_cursor"])]
			if model.tick < int(impact["impact_tick"]):
				break
			apply_pulse(model, skill, int(impact["x_milli"]), int(impact["y_milli"]), events)
			ongoing["impact_cursor"] = int(ongoing["impact_cursor"]) + 1
		if int(ongoing["impact_cursor"]) >= impacts.size():
			model.active_spells.remove_at(index)


static func falling_snapshot(model) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for ongoing in model.active_spells:
		var skill: Dictionary = ongoing["skill"]
		for index in range(int(ongoing["impact_cursor"]), int(ongoing["launch_cursor"])):
			var item: Dictionary = ongoing["impacts"][index].duplicate()
			item.merge({"skill_id": skill["id"], "element": skill["element"], "tier": skill["tier"], "radius_milli": skill["radius_milli"], "splash_radius_milli": skill["splash_radius_milli"]})
			result.append(item)
	return result


static func damage_at_distance(skill: Dictionary, distance: float) -> int:
	var direct := int(skill["radius_milli"])
	var outer := int(skill["splash_radius_milli"])
	if distance <= direct:
		return int(skill["damage"])
	if distance >= outer:
		return 0
	return maxi(0, int(float(skill["splash_damage"]) * (outer - distance) / maxf(1.0, outer - direct)))


static func apply_pulse(model, skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var hits: Array[Dictionary] = []
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var distance := sqrt(float(model._distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y)))
		var damage := damage_at_distance(skill, distance)
		if damage <= 0:
			continue
		var zone := "direct" if distance <= int(skill["radius_milli"]) else "splash"
		model._apply_enemy_damage(enemy, damage, str(skill["element"]), events)
		events[-1]["skill_id"] = skill["id"]
		events[-1]["hit_zone"] = zone
		hits.append({"entity_id": enemy["entity_id"], "x_milli": enemy["x_milli"], "y_milli": enemy["y_milli"], "hit_zone": zone})
		if int(enemy["hp"]) > 0:
			_apply_status(model, enemy, skill, events)
	model._emit(events, "skill_pulse", {
		"skill_id": skill["id"], "element": skill["element"], "tier": skill["tier"],
		"radius_milli": skill["radius_milli"], "splash_radius_milli": skill["splash_radius_milli"],
		"x_milli": target_x, "y_milli": target_y, "hits": hits,
	})


static func _apply_status(model, enemy: Dictionary, skill: Dictionary, events: Array[Dictionary]) -> void:
	match str(skill["element"]):
		"fire":
			var burning := int(enemy.get("burn_ticks", 0)) > 0
			enemy["burn_damage"] = maxi(int(enemy.get("burn_damage", 0)), int(skill["burn_damage"])) if burning else int(skill["burn_damage"])
			enemy["burn_interval_ticks"] = int(skill["burn_interval_ticks"])
			if not burning:
				enemy["burn_counter"] = enemy["burn_interval_ticks"]
			# Refresh duration and keep the strongest burn; repeated impacts do
			# not create unlimited stacked DoTs or postpone the next burn tick.
			enemy["burn_ticks"] = maxi(int(enemy.get("burn_ticks", 0)), model._resisted_ticks(enemy, int(skill["burn_duration_ticks"])))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "burn", "ticks": enemy["burn_ticks"]})
		"ice":
			enemy["slow_permille"] = mini(int(enemy.get("slow_permille", 1000)), int(skill["slow_permille"]))
			enemy["slow_ticks"] = maxi(int(enemy.get("slow_ticks", 0)), model._resisted_ticks(enemy, int(skill["slow_duration_ticks"])))
			enemy["freeze_ticks"] = maxi(int(enemy.get("freeze_ticks", 0)), model._resisted_ticks(enemy, int(skill["freeze_ticks"])))
			enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), int(enemy["freeze_ticks"]))
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "frozen", "ticks": enemy["freeze_ticks"]})
		"lightning":
			enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), model._resisted_ticks(enemy, int(skill["stun_ticks"])))
			enemy["attack_cooldown"] = maxi(int(enemy.get("attack_cooldown", 0)), int(enemy["stun_ticks"]))
			enemy["special_counter"] = 0
			model._emit(events, "status", {"entity_id": enemy["entity_id"], "status": "stunned", "ticks": enemy["stun_ticks"]})
