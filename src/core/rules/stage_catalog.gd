class_name DefenderStageCatalog
extends RefCounted

const DeterministicRng = preload("res://src/core/rules/deterministic_rng.gd")
# Representation boundary only, not a campaign ending. JSON saves use doubles.
const MAX_STAGE_NUMBER := 9007199254740991
const PAGE_SIZE := 20


static func id_for(number: int) -> String:
	return "stage_%03d" % number


static func number_from_id(stage_id: String) -> int:
	if not stage_id.begins_with("stage_"):
		return 0
	var suffix := stage_id.trim_prefix("stage_")
	if not suffix.is_valid_int() or suffix.length() > 16:
		return 0
	var number := suffix.to_int()
	# Reject aliases such as stage_1 / stage_0001: a stage has one reward key.
	return number if number > 0 and number <= MAX_STAGE_NUMBER and id_for(number) == stage_id else 0


static func exists(config: Dictionary, number: int) -> bool:
	return number > 0 and number <= MAX_STAGE_NUMBER and (not config.get("endless_stages", {}).is_empty() or number <= config.get("stages", []).size())


static func has_next(config: Dictionary, number: int) -> bool:
	return number < MAX_STAGE_NUMBER and exists(config, number + 1)


static func resolve(config: Dictionary, stage_id: String) -> Dictionary:
	var stage := describe(config, number_from_id(stage_id))
	if bool(stage.get("generated", false)):
		stage["groups"] = _build_groups(config, stage)
	return stage


# Lightweight descriptors are also used by the paged menu and crystal ledger.
# Never generate every earlier stage, or cache an unbounded list of plans.
static func describe(config: Dictionary, number: int) -> Dictionary:
	if not exists(config, number):
		return {}
	for value in config.get("stages", []):
		if int(value.get("number", 0)) == number:
			var stage: Dictionary = value.duplicate(true)
			var count := 0
			var elapsed := 0
			var last_interval := 0
			var gap := int(config.get("world", {}).get("spawn_group_gap_ticks", 0))
			for group in stage.get("groups", []):
				var actual := scaled_group_count(config, number, group)
				if config.get("endless_stages", {}).get("boss_rotation", []).has(str(group.get("enemy_id", ""))):
					stage["boss_id"] = str(group["enemy_id"])
				count += actual
				last_interval = int(group.get("interval_ticks", 1))
				elapsed += actual * last_interval + gap
			stage["enemy_count"] = count
			stage["wave_count"] = stage.get("groups", []).size()
			stage["spawn_duration_ticks"] = maxi(0, elapsed - gap - last_interval)
			return stage
	var rules: Dictionary = config.get("endless_stages", {})
	if rules.is_empty() or number <= int(rules["authored_stage_count"]):
		return {}
	var pressure := pressure_at(config, number)
	var boss := number % int(rules["boss_interval"]) == 0
	var rotation: Array = rules["boss_rotation"]
	var reward: Dictionary = rules["clear_reward"]
	return {
		"id": id_for(number), "number": number, "name_key": "stage.endless", "generated": true,
		"boss": boss, "boss_id": str(rotation[(number / int(rules["boss_interval"]) - 1) % rotation.size()]) if boss else "",
		"enemy_count": _curve(rules["enemy_count"], pressure) + (1 if boss else 0),
		"wave_count": _curve(rules["wave_count"], pressure),
		"spawn_duration_ticks": _curve(rules["spawn_duration_ticks"], pressure),
		"max_active_enemies": int(rules["max_active_enemies"]),
		"clear_reward": {
			"coins": int(reward["coins_base"]) + int(pressure * int(reward["coins_per_pressure"])) + (int(reward["boss_coins"]) if boss else 0),
			"xp": int(reward["xp_base"]) + int(pressure * int(reward["xp_per_pressure"])) + (int(reward["boss_xp"]) if boss else 0),
		}
	}


static func pressure_at(config: Dictionary, number: int) -> float:
	var rules: Dictionary = config.get("endless_stages", {})
	var delta := maxi(0, number - int(rules.get("authored_stage_count", 30)))
	return log(1.0 + float(delta) / maxf(1, float(rules.get("pressure_stage_span", 30)))) / log(2.0)


static func _curve(curve: Dictionary, pressure: float) -> int:
	return mini(int(curve["limit"]), int(curve["base"]) + int(pressure * int(curve["per_pressure"])))


static func legacy_scale(config: Dictionary, field: String, number: int) -> int:
	var scaling: Dictionary = config.get("difficulty_scaling", {})
	return mini(1000 + maxi(0, number - 1) * int(scaling.get(field + "_per_stage_permille", 0)), int(scaling.get("max_" + field + "_scale_permille", 1000)))


static func scaled_group_count(config: Dictionary, number: int, group: Dictionary) -> int:
	var boss := false
	for enemy in config.get("enemies", []):
		if str(enemy.get("id", "")) == str(group.get("enemy_id", "")):
			boss = enemy.get("tags", []).has("boss")
			break
	var scale := 1000 if boss else legacy_scale(config, "count", number)
	return maxi(1, (int(group.get("count", 0)) * scale + 999) / 1000)


static func enemy_scaling(config: Dictionary, number: int) -> Dictionary:
	var result := {"xp": 1000}
	var rules: Dictionary = config.get("endless_stages", {})
	var opening := int(rules.get("authored_stage_count", number))
	for field in ["hp", "damage", "speed", "reward"]:
		result[field] = legacy_scale(config, field, mini(number, opening))
	if number <= opening or rules.is_empty():
		return result
	var pressure := pressure_at(config, number)
	var scaling: Dictionary = rules["enemy_scaling"]
	for field in ["hp", "damage"]:
		result[field] += int(pressure * int(scaling[field + "_per_pressure"]) + int(scaling[field + "_per_power"]) * pow(float(number - opening), float(scaling[field + "_power"])))
	result["speed"] = mini(int(scaling["max_speed_permille"]), int(result["speed"]) + int(pressure * int(scaling["speed_per_pressure"])))
	result["reward"] += int(pressure * int(scaling["reward_per_pressure"]))
	result["xp"] += int(pressure * int(scaling["xp_per_pressure"]))
	return result


static func composition(config: Dictionary, number: int, count: int) -> Dictionary:
	var rules: Dictionary = config["endless_stages"]
	var band := mini(int(rules["composition_pressure_limit"]), int(pressure_at(config, number)))
	var weights := {}
	var total := 0
	for entry in rules["normal_pool"]:
		var weight := maxi(1, int(entry["base_weight"]) + band * int(entry["weight_per_pressure"]))
		weights[str(entry["enemy_id"])] = weight
		total += weight
	var quotas := {}
	var remainders: Array[Dictionary] = []
	var allocated := 0
	for id in weights:
		var amount: int = count * int(weights[id]) / total
		quotas[id] = amount
		allocated += amount
		remainders.append({"id": id, "remainder": count * int(weights[id]) % total})
	# Largest-remainder quotas keep the mix on its curve even in small waves.
	remainders.sort_custom(func(a, b) -> bool: return a["remainder"] > b["remainder"] if a["remainder"] != b["remainder"] else a["id"] < b["id"])
	for index in range(count - allocated):
		quotas[remainders[index]["id"]] += 1
	return quotas


static func _build_groups(config: Dictionary, stage: Dictionary) -> Array[Dictionary]:
	var rules: Dictionary = config["endless_stages"]
	var number := int(stage["number"])
	var count := int(stage["enemy_count"]) - (1 if stage["boss"] else 0)
	var quotas := composition(config, number, count)
	var pool: Array[String] = []
	for id in quotas:
		for ignored in range(int(quotas[id])):
			pool.append(id)
	# Same stage always has the same composition/order; run_seed only changes
	# spawn lanes and combat randomness, so restarting cannot reroll difficulty.
	var rng := DeterministicRng.new((number ^ (number >> 31)) ^ 0x57a93b21)
	for index in range(pool.size() - 1, 0, -1):
		var other := rng.range_exclusive(0, index + 1)
		var value := pool[index]
		pool[index] = pool[other]
		pool[other] = value
	var groups: Array[Dictionary] = []
	var waves := int(stage["wave_count"])
	var duration := int(stage["spawn_duration_ticks"])
	var first := int(config["world"]["spawn_start_tick"])
	var cursor := 0
	for wave in range(waves):
		var slots := count / waves + (1 if wave < count % waves else 0)
		var start := first + duration * wave / waves
		var end := first + duration * (wave + 1) / waves
		if wave < waves - 1 or bool(stage["boss"]):
			end -= int(rules["wave_gap_ticks"])
		for index in range(slots):
			groups.append({"enemy_id": pool[cursor], "count": 1, "interval_ticks": 1, "wave": wave + 1, "at_tick": start + (end - start) * index / maxi(1, slots - 1)})
			cursor += 1
	if bool(stage["boss"]):
		groups.append({"enemy_id": stage["boss_id"], "count": 1, "interval_ticks": 1, "wave": waves, "at_tick": first + duration})
	return groups
