class_name DefenderContentValidator
extends RefCounted

const REQUIRED_UI_KEYS: Array[String] = [
	"app.title", "app.subtitle", "controls.hint", "common.stage", "common.xp",
	"common.level", "common.boss", "common.max", "common.upgrade", "common.seconds_short",
	"upgrade.effect_next", "upgrade.effect_current", "upgrade.prerequisites", "upgrade.none",
	"menu.continue", "menu.stage", "menu.upgrades", "menu.weapons", "menu.honors", "menu.settings", "menu.tutorial",
	"menu.quit", "menu.back", "menu.start", "menu.locked", "menu.unlocked", "menu.selected", "menu.coins", "menu.xp",
		"hud.wall", "hud.mana", "hud.wave", "hud.weapon", "hud.defenses", "hud.lava_moat", "hud.magic_tower", "hud.pause", "hud.resume", "hud.restart", "hud.main_menu",
		"weapon.damage", "weapon.projectiles", "weapon.pierce", "weapon.fire_rate",
	"result.victory", "result.defeat", "result.kills", "result.wave", "result.coins", "result.xp", "result.wall", "result.next", "result.retry_save", "result.honors", "result.weapon", "result.stage_unlocked",
	"result.wins", "result.losses", "result.win_rate", "result.level_up", "status.level_short", "honor.reward",
	"result.crystals", "status.player_name", "status.name_hint",
	"feedback.no_mana", "feedback.cooldown", "feedback.invalid_target", "feedback.fatal", "feedback.power", "feedback.boss", "feedback.defense", "feedback.wall_damage", "feedback.save_failed",
	"tutorial.title", "tutorial.body", "dialog.abandon_run",
	"settings.title", "settings.language", "settings.master", "settings.music", "settings.sfx",
	"settings.fullscreen", "settings.borderless", "settings.resolution", "settings.aim_assist",
	"settings.auto_fire",
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
	var world: Dictionary = _as_dictionary(config.get("world", {}))
	for field in ["width_milli", "height_milli", "castle_x_milli", "enemy_spawn_x_milli", "enemy_y_min_milli", "enemy_y_max_milli", "spawn_start_tick"]:
		_require_positive_int(world, field, errors, "world.")
	_require_non_negative_int(world, "spawn_group_gap_ticks", errors, "world.")
	if int(world.get("castle_x_milli", 0)) >= int(world.get("enemy_spawn_x_milli", 0)):
		_add_error(errors, "world.enemy_spawn_x_milli", "must_be_right_of_castle")
	if int(world.get("enemy_y_min_milli", 0)) >= int(world.get("enemy_y_max_milli", 0)) or int(world.get("enemy_y_max_milli", 0)) > int(world.get("height_milli", 0)):
		_add_error(errors, "world.enemy_y_max_milli", "invalid_spawn_range")
	var scaling: Dictionary = _as_dictionary(config.get("difficulty_scaling", {}))
	for field in ["hp_per_stage_permille", "damage_per_stage_permille", "speed_per_stage_permille", "count_per_stage_permille"]:
		_require_non_negative_int(scaling, field, errors, "difficulty_scaling.")
	for field in ["max_hp_scale_permille", "max_damage_scale_permille", "max_speed_scale_permille", "max_count_scale_permille"]:
		_require_positive_int(scaling, field, errors, "difficulty_scaling.")
	for field in ["max_hp_scale_permille", "max_damage_scale_permille", "max_speed_scale_permille", "max_count_scale_permille"]:
		if int(scaling.get(field, 0)) < 1000:
			_add_error(errors, "difficulty_scaling.%s" % field, "less_than_base_scale")

	var player: Dictionary = _as_dictionary(config.get("player", {}))
	_require_positive_int(player, "level_base_xp", errors, "player.")
	var rules: Dictionary = _as_dictionary(config.get("rules", {}))
	if rules.has("status_resistance_floor_permille"):
		var resistance_floor := int(rules.get("status_resistance_floor_permille", -1))
		if resistance_floor < 0 or resistance_floor > 1000:
			_add_error(errors, "rules.status_resistance_floor_permille", "out_of_range")

	var enemies: Array = _as_array(config.get("enemies", []))
	var weapons: Array = _as_array(config.get("weapons", []))
	var skills: Array = _as_array(config.get("skills", []))
	var upgrades: Array = _as_array(config.get("upgrades", []))
	var stages: Array = _as_array(config.get("stages", []))
	var enemy_ids := _validate_id_list(enemies, "enemies", errors)
	var weapon_ids := _validate_id_list(weapons, "weapons", errors)
	var skill_ids := _validate_id_list(skills, "skills", errors)
	var upgrade_ids := _validate_id_list(upgrades, "upgrades", errors)
	var stage_ids := _validate_id_list(stages, "stages", errors)
	var boss_enemy_ids: Array[String] = []
	for enemy in enemies:
		if enemy is Dictionary and _as_array(enemy.get("tags", [])).has("boss"):
			boss_enemy_ids.append(str(enemy.get("id", "")))

	if weapon_ids.is_empty():
		_add_error(errors, "weapons", "empty_collection")
	if skill_ids.size() < 3:
		_add_error(errors, "skills", "requires_three_mvp_skills")
	if stage_ids.size() < 30:
		_add_error(errors, "stages", "requires_thirty_windows_stages")
	var normal_enemy_count := enemy_ids.size() - boss_enemy_ids.size()
	if normal_enemy_count < 6:
		_add_error(errors, "enemies", "requires_six_windows_normal_enemies")
	if boss_enemy_ids.size() < 3:
		_add_error(errors, "enemies", "requires_three_windows_bosses")

	for index in range(enemies.size()):
		var enemy: Dictionary = _as_dictionary(enemies[index])
		for field in ["hp", "speed_milli_per_tick", "attack_damage", "attack_interval_ticks", "collision_radius_milli"]:
			_require_positive_int(enemy, field, errors, "enemies[%d]." % index)
		var resistance := int(enemy.get("status_resistance_permille", 0))
		if resistance < 0 or resistance > 1000:
			_add_error(errors, "enemies[%d].status_resistance_permille" % index, "out_of_range")
		var elemental_resistances: Variant = enemy.get("resistances", {})
		if not elemental_resistances is Dictionary:
			_add_error(errors, "enemies[%d].resistances" % index, "expected_object")
		else:
			for resistance_type in elemental_resistances.keys():
				var elemental_value := int(elemental_resistances[resistance_type])
				if elemental_value < 0 or elemental_value > 1000:
					_add_error(errors, "enemies[%d].resistances.%s" % [index, str(resistance_type)], "out_of_range")
		if not enemy.has("knockback_resistance_permille"):
			_add_error(errors, "enemies[%d].knockback_resistance_permille" % index, "missing_value")
		var knockback_resistance := int(enemy.get("knockback_resistance_permille", -1))
		if knockback_resistance < 0 or knockback_resistance > 1000:
			_add_error(errors, "enemies[%d].knockback_resistance_permille" % index, "out_of_range")
		if _as_array(enemy.get("tags", [])).has("boss"):
			_require_positive_int(enemy, "special_interval_ticks", errors, "enemies[%d]." % index)
			_require_non_negative_int(enemy, "special_damage", errors, "enemies[%d]." % index)
			if str(enemy.get("special", "")) == "frost_nova":
				_require_positive_int(enemy, "special_freeze_ticks", errors, "enemies[%d]." % index)
		if str(enemy.get("movement_style", "ground")) not in ["ground", "flying"]:
			_add_error(errors, "enemies[%d].movement_style" % index, "unknown_movement_style")
		if str(enemy.get("movement_style", "ground")) == "flying":
			_require_non_negative_int(enemy, "patrol_amplitude_milli", errors, "enemies[%d]." % index)
			_require_positive_int(enemy, "patrol_period_ticks", errors, "enemies[%d]." % index)

	for index in range(weapons.size()):
		var weapon: Dictionary = _as_dictionary(weapons[index])
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
		_require_positive_int(weapon, "unlock_stage", errors, "weapons[%d]." % index)
		_require_positive_int(weapon, "projectile_count", errors, "weapons[%d]." % index)
		_require_non_negative_int(weapon, "spread_milli", errors, "weapons[%d]." % index)
		if int(weapon.get("fatal_multiplier", 0)) != 2:
			_add_error(errors, "weapons[%d].fatal_multiplier" % index, "fatal_multiplier_must_be_two")
		if str(weapon.get("name_key", "")).is_empty() or str(weapon.get("description_key", "")).is_empty():
			_add_error(errors, "weapons[%d]" % index, "missing_display_keys")

	for index in range(skills.size()):
		var skill: Dictionary = _as_dictionary(skills[index])
		for field in ["mana_cost", "cooldown_ticks", "damage", "radius_milli"]:
			_require_non_negative_int(skill, field, errors, "skills[%d]." % index)
		if int(skill.get("cooldown_ticks", 0)) < 1:
			_add_error(errors, "skills[%d].cooldown_ticks" % index, "less_than_one_tick")
		if str(skill.get("name_key", "")).is_empty() or str(skill.get("description_key", "")).is_empty():
			_add_error(errors, "skills[%d]" % index, "missing_display_keys")

	var upgrade_dependencies: Dictionary = {}
	for index in range(upgrades.size()):
		var upgrade: Dictionary = _as_dictionary(upgrades[index])
		var upgrade_id := str(upgrade.get("id", ""))
		upgrade_dependencies[upgrade_id] = _as_array(upgrade.get("prerequisites", []))
		for field in ["max_level", "base_cost", "cost_growth_permille", "effect_per_level"]:
			_require_positive_int(upgrade, field, errors, "upgrades[%d]." % index)
		if str(upgrade.get("name_key", "")).is_empty() or str(upgrade.get("description_key", "")).is_empty():
			_add_error(errors, "upgrades[%d]" % index, "missing_display_keys")
		for prerequisite in _as_array(upgrade.get("prerequisites", [])):
			if not upgrade_ids.has(str(prerequisite)):
				_add_error(errors, "upgrades[%d].prerequisites" % index, "unknown_reference")
	if _has_dependency_cycle(upgrade_dependencies):
		_add_error(errors, "upgrades", "dependency_cycle")
	var upgrade_id_set: Array[String] = upgrade_ids.duplicate()
	var research_pages_value: Variant = config.get("research_pages", [])
	var research_pages: Array = research_pages_value if research_pages_value is Array else []
	_validate_id_list(research_pages, "research_pages", errors)
	for page_index in range(research_pages.size()):
		var page: Dictionary = _as_dictionary(research_pages[page_index])
		if str(page.get("id", "")).is_empty():
			_add_error(errors, "research_pages[%d].id" % page_index, "missing_value")
		if str(page.get("name_key", "")).is_empty() or str(page.get("description_key", "")).is_empty():
			_add_error(errors, "research_pages[%d]" % page_index, "missing_display_keys")
		for page_upgrade_id in _as_array(page.get("upgrade_ids", [])):
			if not upgrade_id_set.has(str(page_upgrade_id)):
				_add_error(errors, "research_pages[%d].upgrade_ids" % page_index, "unknown_reference")
	if research_pages.size() < 4:
		_add_error(errors, "research_pages", "requires_four_research_pages")
	var defenses: Dictionary = _as_dictionary(config.get("defenses", {}))
	for defense_id in ["lava_moat", "magic_tower"]:
		var defense: Dictionary = _as_dictionary(defenses.get(defense_id, {}))
		if defense.is_empty():
			_add_error(errors, "defenses.%s" % defense_id, "missing_value")
		else:
			for field in ["damage", "damage_per_level", "interval_ticks", "range_milli"]:
				_require_positive_int(defense, field, errors, "defenses.%s." % defense_id)
	var honors: Array = _as_array(config.get("honors", []))
	if honors.size() < 8:
		_add_error(errors, "honors", "requires_honors")
	var bonus_types := ["coin_per_kill", "wall_hp_pct", "weapon_damage_pct", "xp_pct", "max_mana_pct", "fire_damage_pct", "ice_damage_pct", "lightning_damage_pct"]
	var honor_ids: Array[String] = []
	for honor_index in range(honors.size()):
		var honor: Dictionary = _as_dictionary(honors[honor_index])
		var honor_id := str(honor.get("id", ""))
		honor_ids.append(honor_id)
		if honor_id.is_empty() or str(honor.get("name_key", "")).is_empty() or str(honor.get("description_key", "")).is_empty():
			_add_error(errors, "honors[%d]" % honor_index, "missing_display_keys")
		var milestones: Array = _as_array(honor.get("milestones", []))
		if milestones.size() != 3:
			_add_error(errors, "honors[%d].milestones" % honor_index, "requires_three_milestones")
		else:
			for milestone_index in range(milestones.size()):
				var milestone := int(milestones[milestone_index])
				if milestone <= 0:
					_add_error(errors, "honors[%d].milestones[%d]" % [honor_index, milestone_index], "out_of_range")
				elif milestone_index > 0 and milestone <= int(milestones[milestone_index - 1]):
					_add_error(errors, "honors[%d].milestones[%d]" % [honor_index, milestone_index], "milestones_must_ascending")
		for reward_field in ["reward_coins", "reward_xp"]:
			var rewards: Array = _as_array(honor.get(reward_field, []))
			if rewards.size() != 3:
				_add_error(errors, "honors[%d].%s" % [honor_index, reward_field], "requires_three_rewards")
			else:
				for reward_index in range(rewards.size()):
					if int(rewards[reward_index]) < 0:
						_add_error(errors, "honors[%d].%s[%d]" % [honor_index, reward_field, reward_index], "out_of_range")
		var bonus_type := str(honor.get("bonus_type", ""))
		if not bonus_types.has(bonus_type):
			_add_error(errors, "honors[%d].bonus_type" % honor_index, "unknown_reference")
		if int(honor.get("bonus_per_level", 0)) <= 0:
			_add_error(errors, "honors[%d].bonus_per_level" % honor_index, "out_of_range")


	var stage_numbers: Array[int] = []
	for index in range(stages.size()):
		var stage: Dictionary = _as_dictionary(stages[index])
		_require_positive_int(stage, "number", errors, "stages[%d]." % index)
		var stage_number := int(stage.get("number", 0))
		if stage_numbers.has(stage_number):
			_add_error(errors, "stages[%d].number" % index, "duplicate_stage_number")
		else:
			stage_numbers.append(stage_number)
		var groups: Array = _as_array(stage.get("groups", []))
		if groups.is_empty():
			_add_error(errors, "stages[%d].groups" % index, "empty_collection")
		for group_index in range(groups.size()):
			var group: Dictionary = _as_dictionary(groups[group_index])
			if not enemy_ids.has(str(group.get("enemy_id", ""))):
				_add_error(errors, "stages[%d].groups[%d].enemy_id" % [index, group_index], "unknown_reference")
			_require_positive_int(group, "count", errors, "stages[%d].groups[%d]." % [index, group_index])
			_require_positive_int(group, "interval_ticks", errors, "stages[%d].groups[%d]." % [index, group_index])
		var contains_boss := false
		for group in groups:
			contains_boss = contains_boss or boss_enemy_ids.has(str(group.get("enemy_id", "")))
		if bool(stage.get("boss", false)) != contains_boss:
			_add_error(errors, "stages[%d].boss" % index, "boss_flag_mismatch")
		var reward: Dictionary = _as_dictionary(stage.get("clear_reward", {}))
		_require_non_negative_int(reward, "coins", errors, "stages[%d].clear_reward." % index)
		_require_non_negative_int(reward, "xp", errors, "stages[%d].clear_reward." % index)
		if str(stage.get("name_key", "")).is_empty():
			_add_error(errors, "stages[%d].name_key" % index, "missing_value")
	# Stages are presented and unlocked as a linear campaign.  Reject gaps or a
	# sequence that starts above one; otherwise a valid-looking profile could
	# point at a stage ID that can never be reached through the menu.
	var sorted_stage_numbers: Array[int] = stage_numbers.duplicate()
	sorted_stage_numbers.sort()
	for number_index in range(sorted_stage_numbers.size()):
		if sorted_stage_numbers[number_index] != number_index + 1:
			_add_error(errors, "stages[%d].number" % number_index, "stage_numbers_not_contiguous")
			break
	return errors


static func validate_localization(localization: Dictionary, config: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	var required_keys: Array[String] = REQUIRED_UI_KEYS.duplicate()
	for collection_name in ["weapons", "skills", "enemies", "upgrades", "stages"]:
		for item_value in _as_array(config.get(collection_name, [])):
			var item: Dictionary = _as_dictionary(item_value)
			for field in ["name_key", "description_key"]:
				var key := str(item.get(field, ""))
				if not key.is_empty() and not required_keys.has(key):
					required_keys.append(key)
	for collection_name in ["honors"]:
		for item_value in _as_array(config.get(collection_name, [])):
			var item: Dictionary = _as_dictionary(item_value)
			for field in ["name_key", "description_key"]:
				var key := str(item.get(field, ""))
				if not key.is_empty() and not required_keys.has(key):
					required_keys.append(key)
	var localization_defenses: Dictionary = _as_dictionary(config.get("defenses", {}))
	for defense_id in localization_defenses.keys():
		var defense: Dictionary = _as_dictionary(localization_defenses[defense_id])
		for field in ["name_key", "description_key"]:
			var key := str(defense.get(field, ""))
			if not key.is_empty() and not required_keys.has(key):
				required_keys.append(key)
	for page_value in _as_array(config.get("research_pages", [])):
		var page: Dictionary = _as_dictionary(page_value)
		for field in ["name_key", "description_key"]:
			var key := str(page.get(field, ""))
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


static func _as_array(value: Variant) -> Array:
	return value if value is Array else []


static func _as_dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


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
