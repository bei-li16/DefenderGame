class_name DefenderContentValidator
extends RefCounted

const REQUIRED_UI_KEYS: Array[String] = [
	"app.title", "app.subtitle", "controls.hint", "common.stage", "common.xp",
	"common.level", "common.boss", "common.max", "common.upgrade", "common.seconds_short",
	"upgrade.effect_next", "upgrade.effect_current", "upgrade.prerequisites", "upgrade.none",
	"menu.continue", "menu.stage", "menu.upgrades", "menu.settings", "menu.tutorial",
	"menu.quit", "menu.back", "menu.start", "menu.locked", "menu.coins", "menu.xp",
	"hud.wall", "hud.mana", "hud.wave", "hud.pause", "hud.resume", "hud.restart", "hud.main_menu",
	"result.victory", "result.defeat", "result.kills", "result.wave", "result.coins", "result.xp", "result.wall", "result.next", "result.retry_save", "result.stage_unlocked",
	"feedback.no_mana", "feedback.cooldown", "feedback.fatal", "feedback.power", "feedback.boss", "feedback.wall_damage", "feedback.save_failed",
	"tutorial.title", "tutorial.body", "dialog.abandon_run",
	"settings.title", "settings.language", "settings.master", "settings.music", "settings.sfx",
	"settings.fullscreen", "settings.borderless", "settings.resolution", "settings.aim_assist",
	"settings.shake", "settings.quality", "settings.ui_scale", "settings.applied",
	"settings.export_diagnostics", "settings.diagnostics_exported",
	"quality.low", "quality.medium", "quality.high",
	"recovery.title", "recovery.retry", "recovery.new_profile", "recovery.exit", "recovery.retrying", "recovery.body"
]


static func validate(config: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	_require_positive_int(config, "config_version", errors)
	_require_positive_int(config, "simulation_tick_rate", errors)
	if not config.has("ruleset_version") or str(config.get("ruleset_version", "")).is_empty():
		_add_error(errors, "ruleset_version", "missing_value")
	if not config.has("source") or str(config.get("source", "")).is_empty():
		_add_error(errors, "source", "missing_value")
	var world: Dictionary = config.get("world", {})
	for field in ["width_milli", "height_milli", "castle_x_milli", "enemy_spawn_x_milli", "enemy_y_min_milli", "enemy_y_max_milli", "spawn_start_tick"]:
		_require_positive_int(world, field, errors, "world.")
	_require_non_negative_int(world, "spawn_group_gap_ticks", errors, "world.")
	if int(world.get("castle_x_milli", 0)) >= int(world.get("enemy_spawn_x_milli", 0)):
		_add_error(errors, "world.enemy_spawn_x_milli", "must_be_right_of_castle")
	if int(world.get("enemy_y_min_milli", 0)) >= int(world.get("enemy_y_max_milli", 0)) or int(world.get("enemy_y_max_milli", 0)) > int(world.get("height_milli", 0)):
		_add_error(errors, "world.enemy_y_max_milli", "invalid_spawn_range")
	var scaling: Dictionary = config.get("difficulty_scaling", {})
	for field in ["hp_per_stage_permille", "damage_per_stage_permille"]:
		_require_non_negative_int(scaling, field, errors, "difficulty_scaling.")
	for field in ["max_hp_scale_permille", "max_damage_scale_permille"]:
		_require_positive_int(scaling, field, errors, "difficulty_scaling.")
	if int(scaling.get("max_hp_scale_permille", 0)) < 1000:
		_add_error(errors, "difficulty_scaling.max_hp_scale_permille", "less_than_base_scale")
	if int(scaling.get("max_damage_scale_permille", 0)) < 1000:
		_add_error(errors, "difficulty_scaling.max_damage_scale_permille", "less_than_base_scale")

	var rules: Dictionary = config.get("rules", {})
	if rules.has("status_resistance_floor_permille"):
		var resistance_floor := int(rules.get("status_resistance_floor_permille", -1))
		if resistance_floor < 0 or resistance_floor > 1000:
			_add_error(errors, "rules.status_resistance_floor_permille", "out_of_range")

	var enemy_ids := _validate_id_list(config.get("enemies", []), "enemies", errors)
	var weapon_ids := _validate_id_list(config.get("weapons", []), "weapons", errors)
	var skill_ids := _validate_id_list(config.get("skills", []), "skills", errors)
	var upgrade_ids := _validate_id_list(config.get("upgrades", []), "upgrades", errors)
	var stage_ids := _validate_id_list(config.get("stages", []), "stages", errors)
	var boss_enemy_ids: Array[String] = []
	for enemy in config.get("enemies", []):
		if enemy is Dictionary and enemy.get("tags", []).has("boss"):
			boss_enemy_ids.append(str(enemy.get("id", "")))

	if weapon_ids.is_empty():
		_add_error(errors, "weapons", "empty_collection")
	if skill_ids.size() < 3:
		_add_error(errors, "skills", "requires_three_mvp_skills")
	if stage_ids.size() < 10:
		_add_error(errors, "stages", "requires_ten_mvp_stages")
	if boss_enemy_ids.size() != 1:
		_add_error(errors, "enemies", "requires_one_mvp_boss")

	for index in range(config.get("enemies", []).size()):
		var enemy: Dictionary = config["enemies"][index]
		for field in ["hp", "speed_milli_per_tick", "attack_damage", "attack_interval_ticks", "collision_radius_milli"]:
			_require_positive_int(enemy, field, errors, "enemies[%d]." % index)
		var resistance := int(enemy.get("status_resistance_permille", 0))
		if resistance < 0 or resistance > 1000:
			_add_error(errors, "enemies[%d].status_resistance_permille" % index, "out_of_range")
		if not enemy.has("knockback_resistance_permille"):
			_add_error(errors, "enemies[%d].knockback_resistance_permille" % index, "missing_value")
		var knockback_resistance := int(enemy.get("knockback_resistance_permille", -1))
		if knockback_resistance < 0 or knockback_resistance > 1000:
			_add_error(errors, "enemies[%d].knockback_resistance_permille" % index, "out_of_range")
		if enemy.get("tags", []).has("boss"):
			_require_positive_int(enemy, "special_interval_ticks", errors, "enemies[%d]." % index)
			_require_non_negative_int(enemy, "special_damage", errors, "enemies[%d]." % index)

	for index in range(config.get("weapons", []).size()):
		var weapon: Dictionary = config["weapons"][index]
		for field in ["damage", "interval_ticks", "min_interval_ticks", "projectile_speed_milli_per_tick"]:
			_require_positive_int(weapon, field, errors, "weapons[%d]." % index)
		if int(weapon.get("min_interval_ticks", 0)) > int(weapon.get("interval_ticks", 0)):
			_add_error(errors, "weapons[%d].min_interval_ticks" % index, "greater_than_base_interval")
		for field in ["power_shot_chance_per_10000", "fatal_chance_per_10000"]:
			var value := int(weapon.get(field, -1))
			if value < 0 or value > 10000:
				_add_error(errors, "weapons[%d].%s" % [index, field], "out_of_range")
		for field in ["knockback_milli", "pierce"]:
			_require_non_negative_int(weapon, field, errors, "weapons[%d]." % index)

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
		for field in ["max_level", "base_cost", "cost_growth_permille", "effect_per_level"]:
			_require_positive_int(upgrade, field, errors, "upgrades[%d]." % index)
		for prerequisite in upgrade.get("prerequisites", []):
			if not upgrade_ids.has(str(prerequisite)):
				_add_error(errors, "upgrades[%d].prerequisites" % index, "unknown_reference")
	if _has_dependency_cycle(upgrade_dependencies):
		_add_error(errors, "upgrades", "dependency_cycle")

	var stage_numbers: Array[int] = []
	for index in range(config.get("stages", []).size()):
		var stage: Dictionary = config["stages"][index]
		_require_positive_int(stage, "number", errors, "stages[%d]." % index)
		var stage_number := int(stage.get("number", 0))
		if stage_numbers.has(stage_number):
			_add_error(errors, "stages[%d].number" % index, "duplicate_stage_number")
		else:
			stage_numbers.append(stage_number)
		var groups: Array = stage.get("groups", [])
		if groups.is_empty():
			_add_error(errors, "stages[%d].groups" % index, "empty_collection")
		for group_index in range(groups.size()):
			var group: Dictionary = groups[group_index]
			if not enemy_ids.has(str(group.get("enemy_id", ""))):
				_add_error(errors, "stages[%d].groups[%d].enemy_id" % [index, group_index], "unknown_reference")
			_require_positive_int(group, "count", errors, "stages[%d].groups[%d]." % [index, group_index])
			_require_positive_int(group, "interval_ticks", errors, "stages[%d].groups[%d]." % [index, group_index])
		var contains_boss := false
		for group in groups:
			contains_boss = contains_boss or boss_enemy_ids.has(str(group.get("enemy_id", "")))
		if bool(stage.get("boss", false)) != contains_boss:
			_add_error(errors, "stages[%d].boss" % index, "boss_flag_mismatch")
		var reward: Dictionary = stage.get("clear_reward", {})
		_require_non_negative_int(reward, "coins", errors, "stages[%d].clear_reward." % index)
		_require_non_negative_int(reward, "xp", errors, "stages[%d].clear_reward." % index)
	return errors


static func validate_localization(localization: Dictionary, config: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var required_keys: Array[String] = REQUIRED_UI_KEYS.duplicate()
	for collection_name in ["weapons", "skills", "enemies", "upgrades", "stages"]:
		for item in config.get(collection_name, []):
			for field in ["name_key", "description_key"]:
				var key := str(item.get(field, ""))
				if not key.is_empty() and not required_keys.has(key):
					required_keys.append(key)
	for locale in ["zh_CN", "en_US"]:
		if not localization.has(locale) or not localization[locale] is Dictionary:
			_add_error(errors, "localization.%s" % locale, "missing_locale")
			continue
		var catalog: Dictionary = localization[locale]
		for key in required_keys:
			if not catalog.has(key) or str(catalog.get(key, "")).is_empty():
				_add_error(errors, "localization.%s.%s" % [locale, key], "missing_translation")
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
