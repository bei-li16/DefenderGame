class_name DefenderContentValidator
extends RefCounted

const AttackCatalog = preload("res://src/core/rules/attack_catalog.gd")
const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
const ResearchCatalog = preload("res://src/core/rules/research_catalog.gd")

const REQUIRED_UI_KEYS: Array[String] = [
	"research.endless_growth", "research.endless_damage", "research.finite_growth", "research.defense_stats", "research.endless_short", "research.secondary_cap",
	"stage.endless", "stage.previous_page", "stage.next_page", "stage.page_range", "stage.jump", "stage.jump_hint", "stage.endless_hint", "stage.plan_stats", "hud.wave_progress", "hud.spawn_window",
	"skill.hit_stats", "skill.point_stats", "skill.area_stats", "skill.screen_stats", "skill.screen_target",
	"attack.damage", "attack.rate", "attack.power", "attack.poison", "attack.fatal", "attack.volley", "attack.xp", "attack.rules", "attack.refunded",
	"skill.stats", "skill.burn_stats", "skill.freeze_stats", "skill.stun_stats", "skill.current", "skill.next", "feedback.skill_locked",
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
	"research.weapons", "research.visit_hint", "research.unlocked", "research.equip", "loadout.dropdown_hint", "upgrade.unlock_power_bow", "upgrade.forge_power_bow",
	"upgrade.unlock_hurricane_bow", "upgrade.forge_hurricane_bow", "upgrade.unlock_phantom_bow", "upgrade.forge_phantom_bow",
	"feedback.no_mana", "feedback.cooldown", "feedback.invalid_target", "feedback.fatal", "feedback.power", "feedback.boss", "feedback.defense", "feedback.wall_damage", "feedback.save_failed",
	"feedback.insufficient_coins", "feedback.insufficient_crystals",
	"tutorial.title", "tutorial.body", "dialog.abandon_run",
	"settings.title", "settings.language", "settings.master", "settings.music", "settings.sfx",
	"settings.fullscreen", "settings.borderless", "settings.resolution", "settings.aim_assist",
	"settings.auto_fire",
	"settings.shake", "settings.quality", "settings.ui_scale", "settings.applied",
		"settings.export_diagnostics", "settings.diagnostics_exported",
		"admin.title", "admin.password", "admin.password_hint", "admin.unlock", "admin.unlocked",
		"admin.wrong_password", "admin.coins", "admin.crystals", "admin.apply", "admin.applied",
	"quality.low", "quality.medium", "quality.high",
	"recovery.title", "recovery.retry", "recovery.new_profile", "recovery.exit", "recovery.retrying", "recovery.body"
]


static func _validate_attack_tree(config: Dictionary, errors: Array[Dictionary]) -> void:
	var parents := {"strength": [], "agility": [], "power_shot": ["strength"], "poisoned_arrow": ["strength", "agility"], "fatal_blow": ["agility"], "multiple_arrows": ["power_shot", "fatal_blow"], "senior_hunter": ["multiple_arrows"]}
	var found: Array = []
	for definition in config.get("upgrades", []):
		if str(definition.get("page", "")) == "attack":
			found.append(str(definition.get("id", "")))
	if found.size() != AttackCatalog.IDS.size():
		_add_error(errors, "upgrades.attack", "requires_seven_attack_nodes")
	for id in AttackCatalog.IDS:
		var definition := AttackCatalog.find(config, id)
		var path: String = "upgrades." + id + "."
		if definition.is_empty() or not found.has(id):
			_add_error(errors, path, "missing_attack_node")
			continue
		var actual: Array = _as_array(definition.get("prerequisites", []))
		if actual.size() != parents[id].size() or not parents[id].all(func(value) -> bool: return actual.has(str(value))):
			_add_error(errors, path + "prerequisites", "invalid_attack_dependencies")
		var thresholds: Variant = definition.get("prerequisite_levels", {})
		if not thresholds is Dictionary:
			_add_error(errors, path + "prerequisite_levels", "expected_object")
		else:
			for parent in actual:
				var required := int(thresholds.get(str(parent), 0))
				if required < 1 or required > int(AttackCatalog.find(config, str(parent)).get("max_level", 0)):
					_add_error(errors, path + "prerequisite_levels." + str(parent), "out_of_range")
	var poison := AttackCatalog.find(config, "poisoned_arrow")
	for field in ["duration_ticks", "interval_ticks"]:
		_require_positive_int(poison, field, errors, "upgrades.poisoned_arrow.")
	if int(poison.get("duration_ticks", 0)) < int(poison.get("interval_ticks", 1)):
		_add_error(errors, "upgrades.poisoned_arrow.duration_ticks", "shorter_than_one_pulse")
	var power := AttackCatalog.find(config, "power_shot")
	_require_non_negative_int(power, "chance_per_level", errors, "upgrades.power_shot.")
	if int(power.get("chance_per_level", 0)) > 10000:
		_add_error(errors, "upgrades.power_shot.chance_per_level", "out_of_range")
	for id in ["fatal_blow", "poisoned_arrow", "senior_hunter"]:
		var definition := AttackCatalog.find(config, id)
		var maximum := int(definition.get("max_level", 0)) * int(definition.get("effect_per_level", 0))
		if maximum > (10000 if id == "fatal_blow" else 1000):
			_add_error(errors, "upgrades." + id + ".effect_per_level", "out_of_range")
	var multi := AttackCatalog.find(config, "multiple_arrows")
	_require_positive_int(multi, "spread_milli", errors, "upgrades.multiple_arrows.")
	var table := _as_array(multi.get("level_effects", []))
	if table.size() != int(multi.get("max_level", 0)) + 1:
		_add_error(errors, "upgrades.multiple_arrows.level_effects", "requires_every_level_including_zero")
	var previous_count := 0
	var previous_total := 0
	for index in range(table.size()):
		var row := _as_dictionary(table[index])
		var count := int(row.get("projectile_count", 0))
		var ratio := int(row.get("damage_permille", 0))
		if count < 1 or count > 5 or count < previous_count or ratio <= 0 or count * ratio <= previous_total:
			_add_error(errors, "upgrades.multiple_arrows.level_effects[%d]" % index, "invalid_volley_progression")
		if index == 0 and (count != 1 or ratio != 1000):
			_add_error(errors, "upgrades.multiple_arrows.level_effects[0]", "must_preserve_base_volley")
		previous_count = count
		previous_total = count * ratio
	var has_attack_page := false
	for page in config.get("research_pages", []):
		if str(page.get("id", "")) == "attack":
			has_attack_page = true
			if page.get("upgrade_ids", []) != found:
				_add_error(errors, "research_pages.attack.upgrade_ids", "must_match_attack_nodes")
	if not has_attack_page:
		_add_error(errors, "research_pages.attack", "missing_attack_page")


# Magic research is the only crystal sink.  The crystal economy must let a
# player who first-clears the authored opening afford every crystal-priced level
# without a large leftover: total income >= total cost, and the surplus stays
# within 25% of the cost.
static func _validate_crystal_economy(config: Dictionary, errors: Array[Dictionary]) -> void:
	var rewards: Dictionary = _as_dictionary(config.get("crystal_rewards", {}))
	for field in ["first_clear_base", "first_clear_step_stages", "first_clear_step_bonus", "boss_bonus", "repeat_clear"]:
		_require_non_negative_int(rewards, field, errors, "crystal_rewards.")
	if int(rewards.get("first_clear_step_stages", 0)) < 1:
		_add_error(errors, "crystal_rewards.first_clear_step_stages", "less_than_one")
	var total_cost := 0
	for upgrade in _as_array(config.get("upgrades", [])):
		var definition := _as_dictionary(upgrade)
		if str(definition.get("currency", "coins")) != "crystals":
			continue
		var price := int(definition.get("base_cost", 0))
		var growth := int(definition.get("cost_growth_permille", 1000))
		for ignored in range(clampi(int(definition.get("max_level", 0)), 0, 100)):
			total_cost += price
			if growth > 1000:
				price = maxi(price + 1, int(round(float(price) * float(growth) / 1000.0)))
	var base := int(rewards.get("first_clear_base", 0))
	var step_stages := maxi(1, int(rewards.get("first_clear_step_stages", 1)))
	var step_bonus := int(rewards.get("first_clear_step_bonus", 0))
	var boss_bonus := int(rewards.get("boss_bonus", 0))
	var total_income := 0
	var stages := _as_array(config.get("stages", []))
	for index in range(stages.size()):
		var stage := _as_dictionary(stages[index])
		var amount := base + (index / step_stages) * step_bonus
		if bool(stage.get("boss", false)):
			amount += boss_bonus
		total_income += amount
	if total_cost > total_income:
		_add_error(errors, "crystal_rewards", "crystal_cost_exceeds_income")
	if total_income - total_cost > maxi(10, int(ceil(float(total_cost) * 0.25))):
		_add_error(errors, "crystal_rewards", "crystal_income_surplus_too_large")


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
	for field in ["hp_per_stage_permille", "damage_per_stage_permille", "speed_per_stage_permille", "count_per_stage_permille", "reward_per_stage_permille"]:
		_require_non_negative_int(scaling, field, errors, "difficulty_scaling.")
	for field in ["max_hp_scale_permille", "max_damage_scale_permille", "max_speed_scale_permille", "max_count_scale_permille", "max_reward_scale_permille"]:
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
	if stage_ids.is_empty():
		_add_error(errors, "stages", "requires_authored_opening")
	var normal_enemy_count := enemy_ids.size() - boss_enemy_ids.size()
	if normal_enemy_count < 6:
		_add_error(errors, "enemies", "requires_six_windows_normal_enemies")
	if boss_enemy_ids.size() < 3:
		_add_error(errors, "enemies", "requires_three_windows_bosses")
	_validate_endless(config, enemy_ids, boss_enemy_ids, errors)

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
		var currency := str(upgrade.get("currency", "coins"))
		if currency != "coins" and currency != "crystals":
			_add_error(errors, "upgrades[%d].currency" % index, "unknown_currency")
		if str(upgrade.get("page", "")) == "magic" and currency != "crystals":
			_add_error(errors, "upgrades[%d].currency" % index, "magic_research_requires_crystals")
		for prerequisite in _as_array(upgrade.get("prerequisites", [])):
			if not upgrade_ids.has(str(prerequisite)):
				_add_error(errors, "upgrades[%d].prerequisites" % index, "unknown_reference")
	if _has_dependency_cycle(upgrade_dependencies):
		_add_error(errors, "upgrades", "dependency_cycle")
	_validate_research(upgrades, errors)
	_validate_skill_chains(skills, upgrades, errors)
	_validate_attack_tree(config, errors)
	_validate_crystal_economy(config, errors)
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
		if str(stage.get("id", "")) != StageCatalog.id_for(stage_number):
			_add_error(errors, "stages[%d].id" % index, "noncanonical_stage_id")
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
		var rotation := _as_array(_as_dictionary(config.get("endless_stages", {})).get("boss_rotation", []))
		var boss_count := 0
		for group in groups:
			if boss_enemy_ids.has(str(group.get("enemy_id", ""))):
				boss_count += int(group.get("count", 0))
				if stage_number % 10 != 0 or (not rotation.is_empty() and str(group.get("enemy_id", "")) != str(rotation[(stage_number / 10 - 1) % rotation.size()])):
					_add_error(errors, "stages[%d].boss" % index, "boss_outside_ten_stage_rotation")
		if boss_count != (1 if stage_number % 10 == 0 else 0):
			_add_error(errors, "stages[%d].boss" % index, "requires_one_boss_every_ten_stages")
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


static func _validate_endless(config: Dictionary, enemy_ids: Array[String], boss_ids: Array[String], errors: Array[Dictionary]) -> void:
	var rules := _as_dictionary(config.get("endless_stages", {}))
	for field in ["authored_stage_count", "boss_interval", "pressure_stage_span", "wave_gap_ticks", "max_active_enemies", "composition_pressure_limit"]:
		_require_positive_int(rules, field, errors, "endless_stages.")
	if int(rules.get("authored_stage_count", 0)) != _as_array(config.get("stages", [])).size():
		_add_error(errors, "endless_stages.authored_stage_count", "must_match_authored_prefix")
	if int(rules.get("boss_interval", 0)) != 10:
		_add_error(errors, "endless_stages.boss_interval", "boss_interval_must_be_ten")
	if int(rules.get("max_active_enemies", 0)) > 128:
		_add_error(errors, "endless_stages.max_active_enemies", "exceeds_runtime_budget")
	var rotation := _as_array(rules.get("boss_rotation", []))
	var seen: Array = []
	for id in rotation:
		if not boss_ids.has(str(id)) or seen.has(id):
			_add_error(errors, "endless_stages.boss_rotation", "invalid_or_duplicate_boss")
		seen.append(id)
	if rotation.size() != boss_ids.size():
		_add_error(errors, "endless_stages.boss_rotation", "must_include_every_boss_once")
	var limits := {"enemy_count": 1000, "wave_count": 32, "spawn_duration_ticks": 18000}
	for field in limits:
		var curve := _as_dictionary(rules.get(field, {}))
		for component in ["base", "per_pressure", "limit"]:
			_require_positive_int(curve, component, errors, "endless_stages." + field + ".")
		if int(curve.get("base", 0)) > int(curve.get("limit", 0)) or int(curve.get("limit", 0)) > int(limits[field]):
			_add_error(errors, "endless_stages." + field, "invalid_curve_budget")
	var count := _as_dictionary(rules.get("enemy_count", {}))
	var waves := _as_dictionary(rules.get("wave_count", {}))
	var duration := _as_dictionary(rules.get("spawn_duration_ticks", {}))
	if int(count.get("base", 0)) < 2 * int(waves.get("limit", 0)) or int(duration.get("base", 0)) <= int(waves.get("limit", 0)) * int(rules.get("wave_gap_ticks", 0)):
		_add_error(errors, "endless_stages.wave_count", "waves_need_enemies_and_positive_spawn_time")
	seen.clear()
	for entry in _as_array(rules.get("normal_pool", [])):
		var row := _as_dictionary(entry)
		var id := str(row.get("enemy_id", ""))
		if not enemy_ids.has(id) or boss_ids.has(id) or seen.has(id):
			_add_error(errors, "endless_stages.normal_pool", "invalid_normal_enemy_reference")
		seen.append(id)
		_require_positive_int(row, "base_weight", errors, "endless_stages.normal_pool.")
		if int(row.get("base_weight", 0)) + int(rules.get("composition_pressure_limit", 0)) * int(row.get("weight_per_pressure", 0)) < 1:
			_add_error(errors, "endless_stages.normal_pool", "non_positive_late_weight")
	if seen.size() != enemy_ids.size() - boss_ids.size():
		_add_error(errors, "endless_stages.normal_pool", "must_include_every_normal_type")
	var scaling := _as_dictionary(rules.get("enemy_scaling", {}))
	for field in ["hp_per_pressure", "hp_per_power", "damage_per_pressure", "damage_per_power", "speed_per_pressure", "max_speed_permille", "reward_per_pressure", "xp_per_pressure"]:
		_require_positive_int(scaling, field, errors, "endless_stages.enemy_scaling.")
	for field in ["hp_power", "damage_power"]:
		var power := float(scaling.get(field, 0.0))
		if not is_finite(power) or power <= 0 or power > 0.75:
			_add_error(errors, "endless_stages.enemy_scaling." + field, "unsafe_growth_exponent")
	if int(scaling.get("hp_per_power", 0)) > 100 or int(scaling.get("damage_per_power", 0)) > 100 or int(scaling.get("max_speed_permille", 0)) > 2000:
		_add_error(errors, "endless_stages.enemy_scaling", "excessive_growth")
	var reward := _as_dictionary(rules.get("clear_reward", {}))
	for field in ["coins_base", "coins_per_pressure", "xp_base", "xp_per_pressure", "boss_coins", "boss_xp"]:
		_require_non_negative_int(reward, field, errors, "endless_stages.clear_reward.")


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


static func _validate_research(upgrades: Array, errors: Array[Dictionary]) -> void:
	for value in upgrades:
		var node := _as_dictionary(value)
		var path := "upgrades." + str(node.get("id", "")) + "."
		var opening := int(node.get("max_level", 0))
		if opening > 100:
			_add_error(errors, path + "max_level", "opening_must_be_bounded")
		if node.has("endless") and not node["endless"] is bool:
			_add_error(errors, path + "endless", "expected_boolean")
		if ResearchCatalog.is_endless(node):
			if not ResearchCatalog.ENDLESS_IDS.has(str(node.get("id", ""))):
				_add_error(errors, path + "endless", "unsafe_unbounded_attribute")
			var curve := _as_dictionary(node.get("endless_cost", {}))
			_require_positive_int(curve, "step", errors, path + "endless_cost.")
			var power := float(curve.get("power", 0.0))
			if not is_finite(power) or power < 1 or power > 2:
				_add_error(errors, path + "endless_cost.power", "invalid_polynomial_growth")
			if node.has("skill_ref"):
				var secondary := int(node.get("secondary_max_level", 0))
				if secondary < opening or secondary > 30:
					_add_error(errors, path + "secondary_max_level", "skill_secondary_stats_need_safe_cap")
		elif node.has("endless_cost") or node.has("secondary_max_level"):
			_add_error(errors, path + "endless", "unexpected_endless_fields")


static func _validate_skill_chains(skills: Array, upgrades: Array, errors: Array[Dictionary]) -> void:
	var nodes := {}
	for value in upgrades:
		var node := _as_dictionary(value)
		nodes[str(node.get("id", ""))] = node
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		var requirements := _as_dictionary(node.get("prerequisite_levels", {}))
		for required_id in requirements:
			if not _as_array(node.get("prerequisites", [])).has(required_id) or not nodes.has(required_id) or int(requirements[required_id]) < 1 or int(requirements[required_id]) > int(nodes.get(required_id, {}).get("max_level", 0)):
				_add_error(errors, "upgrades.%s.prerequisite_levels" % node_id, "invalid_required_level")
	var chains := {"fire": {}, "ice": {}, "lightning": {}}
	for index in range(skills.size()):
		var skill := _as_dictionary(skills[index])
		var path := "skills[%d]." % index
		var element := str(skill.get("element", ""))
		var tier := int(skill.get("tier", 0))
		if not chains.has(element) or tier < 1 or tier > 3:
			_add_error(errors, path + "tier", "invalid_element_or_tier")
			continue
		if chains[element].has(tier):
			_add_error(errors, path + "tier", "duplicate_element_tier")
		chains[element][tier] = skill
		for field in ["impact_count", "fall_ticks", "mana_cost", "radius_milli", "splash_radius_milli", "splash_damage"]:
			_require_positive_int(skill, field, errors, path)
		for field in ["barrage_duration_ticks", "area_radius_milli"]:
			_require_non_negative_int(skill, field, errors, path)
		var expected_mode: String = ["point", "area", "screen"][tier - 1]
		if str(skill.get("target_mode", "")) != expected_mode:
			_add_error(errors, path + "target_mode", "invalid_tier_delivery")
		var count := int(skill.get("impact_count", 0))
		var duration := int(skill.get("barrage_duration_ticks", 0))
		if count > 64 or int(skill.get("fall_ticks", 0)) > 90 or duration > 600:
			_add_error(errors, path + "impact_count", "excessive_barrage")
		if tier == 1 and (count != 1 or duration != 0):
			_add_error(errors, path + "impact_count", "single_impact_required")
		if tier > 1 and (count < 3 or duration <= count):
			_add_error(errors, path + "barrage_duration_ticks", "insufficient_random_launch_window")
		if (tier == 2 and int(skill.get("area_radius_milli", 0)) <= 0) or (tier != 2 and int(skill.get("area_radius_milli", 0)) != 0):
			_add_error(errors, path + "area_radius_milli", "invalid_delivery_radius")
		if int(skill.get("splash_radius_milli", 0)) <= int(skill.get("radius_milli", 0)) or int(skill.get("splash_damage", 0)) > int(skill.get("damage", 0)):
			_add_error(errors, path + "splash_radius_milli", "invalid_splash_falloff")
		var node: Dictionary = nodes.get(str(skill.get("upgrade_id", "")), {})
		if str(node.get("skill_ref", "")) != str(skill.get("id", "")) or str(node.get("page", "")) != "magic":
			_add_error(errors, path + "upgrade_id", "invalid_skill_research_reference")
		var fields: Array = ["burn_damage", "burn_interval_ticks", "burn_duration_ticks"] if element == "fire" else (["freeze_ticks", "slow_duration_ticks", "slow_permille"] if element == "ice" else ["stun_ticks"])
		for field in fields:
			_require_positive_int(skill, str(field), errors, path)
		for field in ["radius_milli_per_level", "splash_radius_milli_per_level", "splash_damage_per_level", "burn_damage_per_level", "burn_duration_ticks_per_level", "freeze_ticks_per_level", "stun_ticks_per_level", "slow_duration_ticks_per_level"]:
			if skill.has(field):
				_require_non_negative_int(skill, field, errors, path)
		for field in ["impact_count_per_level", "barrage_duration_ticks_per_level", "area_radius_milli_per_level", "fall_ticks_per_level"]:
			if skill.has(field):
				_add_error(errors, path + field, "delivery_does_not_scale_with_research")
		if element == "ice" and int(skill.get("slow_permille", 0)) > 1000:
			_add_error(errors, path + "slow_permille", "out_of_range")
		if int(skill.get("slow_permille_per_level", 0)) > 0:
			_add_error(errors, path + "slow_permille_per_level", "research_must_not_weaken_slow")
		var points := maxi(0, int(node.get("secondary_max_level", node.get("max_level", 0))) - (1 if tier > 1 else 0))
		var max_inner := int(skill.get("radius_milli", 0)) + points * int(skill.get("radius_milli_per_level", 0))
		var max_outer := int(skill.get("splash_radius_milli", 0)) + points * int(skill.get("splash_radius_milli_per_level", 0))
		var max_direct := int(skill.get("damage", 0)) + points * int(node.get("effect_per_level", 0))
		var max_splash := int(skill.get("splash_damage", 0)) + points * int(skill.get("splash_damage_per_level", 0))
		if max_outer <= max_inner or max_splash > max_direct:
			_add_error(errors, path + "splash_radius_milli_per_level", "invalid_upgraded_splash_falloff")
		if ResearchCatalog.is_endless(node) and int(skill.get("splash_damage_per_level", 0)) > int(node.get("effect_per_level", 0)):
			_add_error(errors, path + "splash_damage_per_level", "splash_must_not_outgrow_direct_damage")
	for element in chains:
		var chain: Dictionary = chains[element]
		if chain.size() != 3:
			_add_error(errors, "skills." + element, "requires_three_tiers")
		for tier in [2, 3]:
			if not chain.has(tier) or not chain.has(tier - 1):
				continue
			var previous: Dictionary = chain[tier - 1]
			var current: Dictionary = chain[tier]
			for field in ["mana_cost", "damage", "radius_milli"]:
				if int(current.get(field, 0)) <= int(previous.get(field, 0)):
					_add_error(errors, "skills.%s.%s" % [current.get("id", ""), field], "tiers_must_increase")
			var node: Dictionary = nodes.get(str(current.get("upgrade_id", "")), {})
			if not _as_array(node.get("prerequisites", [])).has(str(previous.get("upgrade_id", ""))):
				_add_error(errors, "skills.%s.upgrade_id" % current.get("id", ""), "missing_previous_tier")


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
