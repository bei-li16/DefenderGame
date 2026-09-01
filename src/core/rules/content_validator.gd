class_name DefenderContentValidator
extends RefCounted


static func validate(config: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	_require_positive_int(config, "config_version", errors)
	_require_positive_int(config, "simulation_tick_rate", errors)
	if not config.has("ruleset_version") or str(config.get("ruleset_version", "")).is_empty():
		_add_error(errors, "ruleset_version", "missing_value")

	var enemy_ids := _validate_id_list(config.get("enemies", []), "enemies", errors)
	var weapon_ids := _validate_id_list(config.get("weapons", []), "weapons", errors)
	var skill_ids := _validate_id_list(config.get("skills", []), "skills", errors)
	var upgrade_ids := _validate_id_list(config.get("upgrades", []), "upgrades", errors)
	var stage_ids := _validate_id_list(config.get("stages", []), "stages", errors)

	if weapon_ids.is_empty():
		_add_error(errors, "weapons", "empty_collection")
	if skill_ids.size() < 3:
		_add_error(errors, "skills", "requires_three_mvp_skills")
	if stage_ids.size() < 10:
		_add_error(errors, "stages", "requires_ten_mvp_stages")

	for index in range(config.get("enemies", []).size()):
		var enemy: Dictionary = config["enemies"][index]
		for field in ["hp", "speed_milli_per_tick", "attack_damage", "attack_interval_ticks", "collision_radius_milli"]:
			_require_positive_int(enemy, field, errors, "enemies[%d]." % index)
		var resistance := int(enemy.get("status_resistance_permille", 0))
		if resistance < 0 or resistance > 1000:
			_add_error(errors, "enemies[%d].status_resistance_permille" % index, "out_of_range")

	for index in range(config.get("weapons", []).size()):
		var weapon: Dictionary = config["weapons"][index]
		for field in ["damage", "interval_ticks", "min_interval_ticks", "projectile_speed_milli_per_tick"]:
			_require_positive_int(weapon, field, errors, "weapons[%d]." % index)
		for field in ["power_shot_chance_per_10000", "fatal_chance_per_10000"]:
			var value := int(weapon.get(field, -1))
			if value < 0 or value > 10000:
				_add_error(errors, "weapons[%d].%s" % [index, field], "out_of_range")

	for index in range(config.get("skills", []).size()):
		var skill: Dictionary = config["skills"][index]
		for field in ["mana_cost", "cooldown_ticks", "damage", "radius_milli"]:
			_require_non_negative_int(skill, field, errors, "skills[%d]." % index)
		if int(skill.get("cooldown_ticks", 0)) < 1:
			_add_error(errors, "skills[%d].cooldown_ticks" % index, "less_than_one_tick")

	var upgrade_dependencies: Dictionary = {}
	for index in range(config.get("upgrades", []).size()):
		var upgrade: Dictionary = config["upgrades"][index]
		var upgrade_id := str(upgrade.get("id", ""))
		upgrade_dependencies[upgrade_id] = upgrade.get("prerequisites", [])
		for prerequisite in upgrade.get("prerequisites", []):
			if not upgrade_ids.has(str(prerequisite)):
				_add_error(errors, "upgrades[%d].prerequisites" % index, "unknown_reference")
	if _has_dependency_cycle(upgrade_dependencies):
		_add_error(errors, "upgrades", "dependency_cycle")

	for index in range(config.get("stages", []).size()):
		var stage: Dictionary = config["stages"][index]
		var groups: Array = stage.get("groups", [])
		if groups.is_empty():
			_add_error(errors, "stages[%d].groups" % index, "empty_collection")
		for group_index in range(groups.size()):
			var group: Dictionary = groups[group_index]
			if not enemy_ids.has(str(group.get("enemy_id", ""))):
				_add_error(errors, "stages[%d].groups[%d].enemy_id" % [index, group_index], "unknown_reference")
			_require_positive_int(group, "count", errors, "stages[%d].groups[%d]." % [index, group_index])
			_require_positive_int(group, "interval_ticks", errors, "stages[%d].groups[%d]." % [index, group_index])
		var reward: Dictionary = stage.get("clear_reward", {})
		_require_non_negative_int(reward, "coins", errors, "stages[%d].clear_reward." % index)
		_require_non_negative_int(reward, "xp", errors, "stages[%d].clear_reward." % index)
	return errors


static func _validate_id_list(items: Variant, path: String, errors: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	if not items is Array:
		_add_error(errors, path, "expected_array")
		return ids
	for index in range(items.size()):
		if not items[index] is Dictionary:
			_add_error(errors, "%s[%d]" % [path, index], "expected_object")
			continue
		var item_id := str(items[index].get("id", ""))
		if item_id.is_empty():
			_add_error(errors, "%s[%d].id" % [path, index], "missing_value")
		elif ids.has(item_id):
			_add_error(errors, "%s[%d].id" % [path, index], "duplicate_id")
		else:
			ids.append(item_id)
	return ids


static func _has_dependency_cycle(graph: Dictionary) -> bool:
	var visiting: Dictionary = {}
	var visited: Dictionary = {}
	for node in graph.keys():
		if _visit_dependency(str(node), graph, visiting, visited):
			return true
	return false


static func _visit_dependency(node: String, graph: Dictionary, visiting: Dictionary, visited: Dictionary) -> bool:
	if visited.has(node):
		return false
	if visiting.has(node):
		return true
	visiting[node] = true
	for dependency in graph.get(node, []):
		if _visit_dependency(str(dependency), graph, visiting, visited):
			return true
	visiting.erase(node)
	visited[node] = true
	return false


static func _require_positive_int(data: Dictionary, field: String, errors: Array[Dictionary], prefix: String = "") -> void:
	if not data.has(field) or int(data.get(field, 0)) <= 0:
		_add_error(errors, prefix + field, "must_be_positive")


static func _require_non_negative_int(data: Dictionary, field: String, errors: Array[Dictionary], prefix: String = "") -> void:
	if not data.has(field) or int(data.get(field, -1)) < 0:
		_add_error(errors, prefix + field, "must_be_non_negative")


static func _add_error(errors: Array[Dictionary], field_path: String, error_code: String) -> void:
	errors.append({
		"ok": false,
		"field_path": field_path,
		"error_code": error_code,
		"message_key": "config.%s" % error_code
	})

