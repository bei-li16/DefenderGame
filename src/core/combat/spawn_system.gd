class_name DefenderSpawnSystem
extends RefCounted

const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
# Spawn planning and enemy instantiation, extracted from RunModel (architecture
# §6.1 SpawnSystem).  Functions receive the RunModel facade as `model` so the
# tick ordering, RNG streams and event sequencing stay owned by the model while
# the spawn domain logic lives here. Authored stages retain their original
# schedules; generated stages use explicit wave ticks and population backpressure.

static func build_queue(model) -> void:
	var config: Dictionary = model.config
	var world: Dictionary = config.get("world", {})
	var spawn_tick := maxi(1, int(world.get("spawn_start_tick", 24)))
	var group_gap_ticks := maxi(0, int(world.get("spawn_group_gap_ticks", 45)))
	var y_min := int(world.get("enemy_y_min_milli", 220000))
	var y_max := int(world.get("enemy_y_max_milli", 920000))
	var groups: Array = model.stage.get("groups", [])
	var generated := bool(model.stage.get("generated", false))
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var count := int(group["count"]) if generated else StageCatalog.scaled_group_count(config, int(model.stage["number"]), group)
		var interval := maxi(1, int(group.get("interval_ticks", 30)))
		if generated:
			spawn_tick = int(group["at_tick"])
		for index in range(count):
			model.spawn_queue.append({
				"tick": spawn_tick,
				"wave": int(group.get("wave", group_index + 1)),
				"enemy_id": str(group.get("enemy_id", "")),
				"y_milli": model._spawn_rng.range_exclusive(y_min, y_max)
			})
			spawn_tick += interval
		spawn_tick += group_gap_ticks


static func spawn_due(model, events: Array[Dictionary]) -> void:
	var config: Dictionary = model.config
	while model.spawn_cursor < model.spawn_queue.size() and int(model.spawn_queue[model.spawn_cursor]["tick"]) <= model.tick:
		# Back-pressure delays, never drops, scheduled enemies. The victory
		# condition still waits for the complete queue and all live enemies.
		var active_limit := int(model.stage.get("max_active_enemies", 0))
		if active_limit > 0 and model.enemies.size() >= active_limit:
			break
		var order: Dictionary = model.spawn_queue[model.spawn_cursor]
		var template: Dictionary = model._find_by_id(config.get("enemies", []), str(order["enemy_id"]))
		model.spawn_cursor += 1
		model.current_wave = maxi(model.current_wave, int(order.get("wave", 1)))
		if template.is_empty():
			continue
		var stage_number := int(model.stage.get("number", 1))
		var scales := StageCatalog.enemy_scaling(config, stage_number)
		var hp_scale_permille := int(scales["hp"])
		var damage_scale_permille := int(scales["damage"])
		var speed_scale_permille := int(scales["speed"])
		var reward_scale_permille := int(scales["reward"])
		var world: Dictionary = config.get("world", {})
		var enemy := {
			"entity_id": model.next_entity_id,
			"enemy_id": str(template["id"]),
			"name_key": str(template.get("name_key", "")),
			"x_milli": int(world.get("enemy_spawn_x_milli", 1880000)),
			"y_milli": int(order["y_milli"]),
			"hp": maxi(1, int(template["hp"]) * hp_scale_permille / 1000),
			"max_hp": maxi(1, int(template["hp"]) * hp_scale_permille / 1000),
			"speed_milli_per_tick": maxi(1, int(template["speed_milli_per_tick"]) * speed_scale_permille / 1000),
			"attack_damage": maxi(1, int(template["attack_damage"]) * damage_scale_permille / 1000),
			"attack_interval_ticks": int(template["attack_interval_ticks"]),
			"attack_cooldown": 0,
			"attack_x_milli": int(template["attack_x_milli"]),
			"armor": int(template.get("armor", 0)),
			"reward_coins": maxi(1, int(template.get("reward_coins", 0)) * reward_scale_permille / 1000),
			"reward_xp": int(template.get("reward_xp", 0)) * int(scales["xp"]) / 1000,
			"collision_radius_milli": int(template.get("collision_radius_milli", 30000)),
			"tags": template.get("tags", []).duplicate(),
			"status_resistance_permille": int(template.get("status_resistance_permille", 0)),
			"knockback_resistance_permille": int(template.get("knockback_resistance_permille", 0)),
			"resistances": template.get("resistances", {}).duplicate(true),
			"movement_style": str(template.get("movement_style", "ground")),
			"base_y_milli": int(order["y_milli"]),
			"patrol_amplitude_milli": int(template.get("patrol_amplitude_milli", 0)),
			"patrol_period_ticks": maxi(1, int(template.get("patrol_period_ticks", 1))),
			"slow_permille": 1000,
			"slow_ticks": 0,
			"stun_ticks": 0,
			"burn_ticks": 0,
			"burn_interval_ticks": 0,
			"burn_counter": 0,
			"burn_damage": 0,
			"poison_ticks": 0,
			"poison_interval_ticks": 0,
			"poison_counter": 0,
			"poison_damage": 0,
			"special": str(template.get("special", "")),
			"special_interval_ticks": int(template.get("special_interval_ticks", 0)),
			"special_damage": int(template.get("special_damage", 0)) * (damage_scale_permille if bool(model.stage.get("generated", false)) else 1000) / 1000,
			"special_freeze_ticks": int(template.get("special_freeze_ticks", 75)),
			"special_counter": 0
		}
		model.next_entity_id += 1
		model.enemies.append(enemy)
		model._emit(events, "spawn", {"entity_id": enemy["entity_id"], "enemy_id": enemy["enemy_id"], "x_milli": enemy["x_milli"], "y_milli": enemy["y_milli"]})
		if enemy["tags"].has("boss"):
			model._emit(events, "boss_warning", {"entity_id": enemy["entity_id"], "name_key": enemy["name_key"]})
