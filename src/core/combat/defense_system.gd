class_name DefenderDefenseSystem
extends RefCounted

# Lava Moat and Magic Tower updates, extracted from RunModel (architecture
# §6.1 DefenseSystem).  Functions receive the RunModel facade as `model`;
# code is behaviour-preserving.

static func update(model, events: Array[Dictionary]) -> void:
	var defenses: Dictionary = model.config.get("defenses", {})
	for defense_id in ["lava_moat", "magic_tower"]:
		var level: int = model._upgrade_level(defense_id)
		if level <= 0:
			continue
		var definition: Dictionary = defenses.get(defense_id, {})
		if definition.is_empty() or int(model.defense_cooldowns.get(defense_id, 0)) > 0:
			continue
		var target_enemies: Array[Dictionary] = []
		var range_milli := int(definition.get("range_milli", 0))
		for enemy in model.enemies:
			if int(enemy.get("hp", 0)) <= 0:
				continue
			var distance_to_castle: int = absi(int(enemy.get("x_milli", 0)) - int(model.config["world"].get("castle_x_milli", 0)))
			if distance_to_castle <= range_milli:
				target_enemies.append(enemy)
		if target_enemies.is_empty():
			continue
		target_enemies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["x_milli"]) == int(b["x_milli"]):
				return int(a["entity_id"]) < int(b["entity_id"])
			return int(a["x_milli"]) < int(b["x_milli"])
		)
		var damage := int(definition.get("damage", 0)) + maxi(0, level - 1) * int(definition.get("damage_per_level", 0))
		if defense_id == "lava_moat":
			for enemy in target_enemies:
				model._apply_enemy_damage(enemy, damage, "lava_moat", events)
				enemy["burn_damage"] = maxi(int(enemy.get("burn_damage", 0)), int(definition.get("burn_damage", 0)))
				enemy["burn_interval_ticks"] = maxi(1, int(definition.get("burn_interval_ticks", 15)))
				enemy["burn_counter"] = enemy["burn_interval_ticks"]
				enemy["burn_ticks"] = maxi(int(enemy.get("burn_ticks", 0)), int(definition.get("burn_duration_ticks", 0)))
		else:
			model._apply_enemy_damage(target_enemies[0], damage, "magic_tower", events)
		model._emit(events, "defense_attack", {"defense_id": defense_id, "level": level, "target_count": target_enemies.size() if defense_id == "lava_moat" else 1, "x_milli": int(target_enemies[0]["x_milli"]), "y_milli": int(target_enemies[0]["y_milli"])})
		model.defense_cooldowns[defense_id] = maxi(1, int(definition.get("interval_ticks", 30)))
