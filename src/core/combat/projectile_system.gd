class_name DefenderProjectileSystem
extends RefCounted

# Projectile motion, swept collision and band-based candidate queries,
# extracted from RunModel (architecture §6.1 ProjectileSystem).  Functions
# receive the RunModel facade as `model`; code is behaviour-preserving.

const COLLISION_BAND_HEIGHT_MILLI := 120000


static func update(model, events: Array[Dictionary]) -> void:
	var enemy_bands := build_enemy_bands(model)
	for projectile_index in range(model.projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = model.projectiles[projectile_index]
		var previous_x := int(projectile["x_milli"])
		var previous_y := int(projectile["y_milli"])
		projectile["x_milli"] = previous_x + int(projectile["vx_milli"])
		projectile["y_milli"] = previous_y + int(projectile["vy_milli"])
		projectile["age_ticks"] = int(projectile["age_ticks"]) + 1
		var hit_enemy: Dictionary = {}
		var best_t := 2.0
		var candidate_enemies := candidates(model, enemy_bands, previous_y, int(projectile["y_milli"]), int(projectile["collision_radius_milli"]))
		var hit_entity_ids: Array = projectile.get("hit_entity_ids", [])
		for enemy in candidate_enemies:
			if int(enemy["hp"]) <= 0:
				continue
			if hit_entity_ids.has(int(enemy["entity_id"])):
				continue
			var radius := int(enemy["collision_radius_milli"]) + int(projectile["collision_radius_milli"])
			var hit_t := segment_hit_t(previous_x, previous_y, int(projectile["x_milli"]), int(projectile["y_milli"]), int(enemy["x_milli"]), int(enemy["y_milli"]), radius)
			if hit_t >= 0.0 and hit_t < best_t:
				best_t = hit_t
				hit_enemy = enemy
		if not hit_enemy.is_empty():
			hit_entity_ids.append(int(hit_enemy["entity_id"]))
			projectile["hit_entity_ids"] = hit_entity_ids
			model._emit(events, "hit", {"projectile_id": projectile["entity_id"], "entity_id": hit_enemy["entity_id"], "fatal": projectile["fatal"], "power": projectile["power"]})
			model._apply_enemy_damage(hit_enemy, int(projectile["damage"]), "arrow", events)
			if bool(projectile["power"]):
				var resistance := clampi(int(hit_enemy.get("knockback_resistance_permille", 0)), 0, 1000)
				var knockback := int(model.weapon.get("knockback_milli", 0)) * (1000 - resistance) / 1000
				hit_enemy["x_milli"] = clampi(
					int(hit_enemy["x_milli"]) + knockback,
					int(hit_enemy["attack_x_milli"]),
					int(model.config["world"]["enemy_spawn_x_milli"])
				)
			var remaining_pierce := int(projectile.get("pierce_remaining", 0))
			if remaining_pierce > 0:
				projectile["pierce_remaining"] = remaining_pierce - 1
			else:
				model.projectiles.remove_at(projectile_index)
		elif int(projectile["age_ticks"]) > 90 or int(projectile["x_milli"]) > int(model.config["world"]["width_milli"]) + 100000 or int(projectile["y_milli"]) < -100000 or int(projectile["y_milli"]) > int(model.config["world"]["height_milli"]) + 100000:
			model.projectiles.remove_at(projectile_index)


static func build_enemy_bands(model) -> Dictionary:
	var bands: Dictionary = {}
	for enemy in model.enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var radius := int(enemy["collision_radius_milli"])
		var minimum_band := band_index(int(enemy["y_milli"]) - radius)
		var maximum_band := band_index(int(enemy["y_milli"]) + radius)
		for band in range(minimum_band, maximum_band + 1):
			if not bands.has(band):
				bands[band] = []
			bands[band].append(enemy)
	return bands


static func candidates(model, bands: Dictionary, previous_y: int, current_y: int, radius: int) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Dictionary = {}
	var minimum_band := band_index(mini(previous_y, current_y) - radius)
	var maximum_band := band_index(maxi(previous_y, current_y) + radius)
	for band in range(minimum_band, maximum_band + 1):
		for enemy in bands.get(band, []):
			var entity_id := int(enemy["entity_id"])
			if seen.has(entity_id):
				continue
			seen[entity_id] = true
			found.append(enemy)
	return found


static func band_index(y_milli: int) -> int:
	return int(floor(float(y_milli) / float(COLLISION_BAND_HEIGHT_MILLI)))


static func segment_hit_t(ax: int, ay: int, bx: int, by: int, px: int, py: int, radius: int) -> float:
	var dx := float(bx - ax)
	var dy := float(by - ay)
	var length_squared := dx * dx + dy * dy
	var t := 0.0
	if length_squared > 0.0:
		t = clampf((float(px - ax) * dx + float(py - ay) * dy) / length_squared, 0.0, 1.0)
	var closest_x := float(ax) + dx * t
	var closest_y := float(ay) + dy * t
	var offset_x := float(px) - closest_x
	var offset_y := float(py) - closest_y
	return t if offset_x * offset_x + offset_y * offset_y <= float(radius) * float(radius) else -1.0
