class_name DefenderRunModel
extends RefCounted

const DeterministicRng = preload("res://src/core/rules/deterministic_rng.gd")

const STATUS_RUNNING := "running"
const STATUS_VICTORY := "victory"
const STATUS_DEFEAT := "defeat"
const COLLISION_BAND_HEIGHT_MILLI := 120000
const EVENT_ORDER := {
	"spawn": 10,
	"boss_warning": 11,
	"command": 20,
	"shot": 21,
	"skill_cast": 22,
	"skill_rejected": 23,
	"defense_attack": 24,
	"hit": 30,
	"damage": 40,
	"wall_damage": 41,
	"status": 50,
	"boss_special": 51,
	"death": 60,
	"reward": 70,
	"run_end": 80
}

var config: Dictionary = {}
var stage: Dictionary = {}
var profile_snapshot: Dictionary = {}
var weapon: Dictionary = {}
var weapon_id: String = "basic_bow"
var tick: int = 0
var status: String = STATUS_RUNNING
var wall_hp: int = 0
var wall_max_hp: int = 0
var mana: int = 0
var max_mana: int = 0
var coins_earned: int = 0
var xp_earned: int = 0
var kills: int = 0
var spells_cast: int = 0
var current_wave: int = 0
var enemies: Array[Dictionary] = []
var projectiles: Array[Dictionary] = []
var selected_skill: String = ""
var aim_x_milli: int = 1200000
var aim_y_milli: int = 540000
var fire_down: bool = false
var fire_cooldown: int = 0
var skill_cooldowns: Dictionary = {}
var defense_levels: Dictionary = {}
var defense_cooldowns: Dictionary = {}
var spawn_queue: Array[Dictionary] = []
var spawn_cursor: int = 0
var next_entity_id: int = 1
var run_id: String = ""
var seed: int = 1

var _spawn_rng: DefenderDeterministicRng
var _combat_rng: DefenderDeterministicRng
var _event_sequence: int = 0
var _boss_rewarded: bool = false
var bosses_slain: int = 0


func setup(game_config: Dictionary, stage_id: String, run_seed: int, player_profile: Dictionary, run_instance_id: String = "") -> Dictionary:
	config = game_config.duplicate(true)
	stage = _find_by_id(config.get("stages", []), stage_id)
	if stage.is_empty():
		return {"ok": false, "error_code": "unknown_stage", "field_path": "stage_id"}
	profile_snapshot = player_profile.duplicate(true)
	weapon_id = str(profile_snapshot.get("current_weapon_id", "basic_bow"))
	var unlocked_value: Variant = profile_snapshot.get("unlocked_weapons", [])
	var unlocked_weapons: Array = unlocked_value if unlocked_value is Array else []
	# A missing/empty unlock list is a legacy or incomplete profile, not a
	# wildcard entitlement.  Only the baseline bow is implicitly available;
	# every other weapon must be explicitly unlocked before a run can equip it.
	if weapon_id != "basic_bow" and not unlocked_weapons.has(weapon_id):
		weapon_id = "basic_bow"
	weapon = _find_by_id(config.get("weapons", []), weapon_id)
	if weapon.is_empty():
		weapon_id = "basic_bow"
		weapon = _find_by_id(config.get("weapons", []), weapon_id)
	if weapon.is_empty():
		return {"ok": false, "error_code": "missing_weapon", "field_path": "weapons.basic_bow"}
	seed = run_seed if run_seed != 0 else 1
	run_id = run_instance_id if not run_instance_id.is_empty() else "%s-%d-%d" % [stage_id, seed, int(config.get("config_version", 0))]
	_spawn_rng = DeterministicRng.new(seed ^ 0x4f1bbcdc)
	_combat_rng = DeterministicRng.new(seed ^ 0x2c9277b5)
	tick = 0
	status = STATUS_RUNNING
	var player: Dictionary = config.get("player", {})
	max_mana = int(player.get("max_mana", 100))
	max_mana += _upgrade_level("mana_capacity") * _upgrade_effect_per_level("mana_capacity")
	mana = max_mana
	coins_earned = 0
	xp_earned = 0
	kills = 0
	spells_cast = 0
	current_wave = 0
	enemies.clear()
	projectiles.clear()
	selected_skill = ""
	fire_down = false
	fire_cooldown = 0
	skill_cooldowns.clear()
	defense_levels = profile_snapshot.get("upgrades", {}).duplicate(true)
	defense_cooldowns = {"lava_moat": 0, "magic_tower": 0}
	spawn_queue.clear()
	spawn_cursor = 0
	next_entity_id = 1
	_event_sequence = 0
	_boss_rewarded = false
	bosses_slain = 0
	wall_max_hp = int(player.get("wall_hp", 500)) + _upgrade_level("wall_repair") * _upgrade_effect_per_level("wall_repair")
	wall_hp = wall_max_hp
	_build_spawn_queue()
	return {"ok": true, "run_id": run_id}


func step(commands: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status != STATUS_RUNNING:
		return events
	tick += 1
	_event_sequence = 0
	_tick_cooldowns()
	_spawn_due_enemies(events)
	_process_commands(commands, events)
	_regenerate_mana(events)
	_update_enemies(events)
	_update_defenses(events)
	_update_projectiles(events)
	_resolve_deaths(events)
	_resolve_run_end(events)
	_sort_events(events)
	return events


func snapshot() -> Dictionary:
	# Shallow copies are sufficient: entity entries hold only scalars plus the
	# "tags" array, and core never mutates a tags array in place after spawn.
	# Presentation must treat the snapshot as read-only for this contract to hold.
	var enemies_copy: Array[Dictionary] = []
	for enemy in enemies:
		enemies_copy.append(enemy.duplicate(false))
	var projectiles_copy: Array[Dictionary] = []
	for projectile in projectiles:
		projectiles_copy.append(projectile.duplicate(false))
	return {
		"tick": tick,
		"status": status,
		"stage_id": str(stage.get("id", "")),
		"stage_number": int(stage.get("number", 0)),
	"run_id": run_id,
	"weapon_id": weapon_id,
	"weapon_name_key": str(weapon.get("name_key", "weapon.basic_bow")),
		"wall_hp": wall_hp,
		"wall_max_hp": wall_max_hp,
		"mana": mana,
		"max_mana": max_mana,
		"coins_earned": coins_earned,
		"xp_earned": xp_earned,
		"kills": kills,
		"spells_cast": spells_cast,
		"wave": current_wave,
		"wave_total": stage.get("groups", []).size(),
		"spawned": spawn_cursor,
		"spawn_total": spawn_queue.size(),
		"selected_skill": selected_skill,
	"skill_cooldowns": skill_cooldowns.duplicate(true),
	"defenses": {
		"lava_moat_level": _upgrade_level("lava_moat"),
		"magic_tower_level": _upgrade_level("magic_tower")
	},
		"enemies": enemies_copy,
		"projectiles": projectiles_copy
	}


func result() -> Dictionary:
	var clear_reward: Dictionary = stage.get("clear_reward", {}) if status == STATUS_VICTORY else {}
	var reward_version := str(config.get("ruleset_version", "unknown"))
	var clear_coins := int(clear_reward.get("coins", 0)) + _reward_bonus("coin_bounty")
	var clear_xp := int(clear_reward.get("xp", 0)) + _reward_bonus("xp_bounty")
	return {
		"run_id": run_id,
		"weapon_id": weapon_id,
		"reward_version": reward_version,
		"reward_source": "run_settlement",
		"idempotency_key": run_id + ":" + reward_version,
		"stage_id": str(stage.get("id", "")),
		"stage_number": int(stage.get("number", 0)),
		"status": status,
		"tick": tick,
		"kills": kills,
		"spells_cast": spells_cast,
		"wave": current_wave,
		"wave_total": stage.get("groups", []).size(),
		"wall_percent": int(round(float(wall_hp) * 100.0 / maxf(1.0, float(wall_max_hp)))),
		"boss_slain": _boss_rewarded,
		"bosses_slain": bosses_slain,
		"coins": coins_earned + clear_coins,
		"xp": xp_earned + clear_xp
	}


func debug_force_wall_damage(amount: int) -> void:
	wall_hp = maxi(0, wall_hp - maxi(0, amount))


func _build_spawn_queue() -> void:
	var world: Dictionary = config.get("world", {})
	var spawn_tick := maxi(1, int(world.get("spawn_start_tick", 24)))
	var group_gap_ticks := maxi(0, int(world.get("spawn_group_gap_ticks", 45)))
	var y_min := int(world.get("enemy_y_min_milli", 220000))
	var y_max := int(world.get("enemy_y_max_milli", 920000))
	var groups: Array = stage.get("groups", [])
	var stage_offset := maxi(0, int(stage.get("number", 1)) - 1)
	var scaling: Dictionary = config.get("difficulty_scaling", {})
	var count_scale := mini(
		1000 + stage_offset * int(scaling.get("count_per_stage_permille", 0)),
		int(scaling.get("max_count_scale_permille", 1000))
	)
	for group_index in range(groups.size()):
		var group: Dictionary = groups[group_index]
		var group_enemy := _find_by_id(config.get("enemies", []), str(group.get("enemy_id", "")))
		var count_scale_for_group := 1000 if group_enemy.get("tags", []).has("boss") else count_scale
		var count := maxi(1, int(ceil(float(int(group.get("count", 0)) * count_scale_for_group) / 1000.0)))
		var interval := maxi(1, int(group.get("interval_ticks", 30)))
		for index in range(count):
			spawn_queue.append({
				"tick": spawn_tick,
				"wave": group_index + 1,
				"enemy_id": str(group.get("enemy_id", "")),
				"y_milli": _spawn_rng.range_exclusive(y_min, y_max)
			})
			spawn_tick += interval
		spawn_tick += group_gap_ticks


func _spawn_due_enemies(events: Array[Dictionary]) -> void:
	while spawn_cursor < spawn_queue.size() and int(spawn_queue[spawn_cursor]["tick"]) <= tick:
		var order: Dictionary = spawn_queue[spawn_cursor]
		var template := _find_by_id(config.get("enemies", []), str(order["enemy_id"]))
		spawn_cursor += 1
		current_wave = maxi(current_wave, int(order.get("wave", 1)))
		if template.is_empty():
			continue
		var stage_number := int(stage.get("number", 1))
		var stage_offset := maxi(0, stage_number - 1)
		var scaling: Dictionary = config.get("difficulty_scaling", {})
		var hp_scale_permille := mini(
			1000 + stage_offset * int(scaling.get("hp_per_stage_permille", 0)),
			int(scaling.get("max_hp_scale_permille", 1000))
		)
		var damage_scale_permille := mini(
			1000 + stage_offset * int(scaling.get("damage_per_stage_permille", 0)),
			int(scaling.get("max_damage_scale_permille", 1000))
		)
		var speed_scale_permille := mini(
			1000 + (stage_number - 1) * int(scaling.get("speed_per_stage_permille", 0)),
			int(scaling.get("max_speed_scale_permille", 1000))
		)
		var world: Dictionary = config.get("world", {})
		var enemy := {
			"entity_id": next_entity_id,
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
			"reward_coins": int(template.get("reward_coins", 0)),
			"reward_xp": int(template.get("reward_xp", 0)),
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
			"special": str(template.get("special", "")),
			"special_interval_ticks": int(template.get("special_interval_ticks", 0)),
			"special_damage": int(template.get("special_damage", 0)),
			"special_freeze_ticks": int(template.get("special_freeze_ticks", 75)),
			"special_counter": 0
		}
		next_entity_id += 1
		enemies.append(enemy)
		_emit(events, "spawn", {"entity_id": enemy["entity_id"], "enemy_id": enemy["enemy_id"], "x_milli": enemy["x_milli"], "y_milli": enemy["y_milli"]})
		if enemy["tags"].has("boss"):
			_emit(events, "boss_warning", {"entity_id": enemy["entity_id"], "name_key": enemy["name_key"]})


func _process_commands(commands: Array, events: Array[Dictionary]) -> void:
	for command_value in commands:
		if not command_value is Dictionary:
			continue
		var command: Dictionary = command_value
		var command_type := str(command.get("type", ""))
		match command_type:
			"aim":
				aim_x_milli = clampi(int(command.get("x_milli", aim_x_milli)), 0, int(config["world"]["width_milli"]))
				aim_y_milli = clampi(int(command.get("y_milli", aim_y_milli)), 0, int(config["world"]["height_milli"]))
			"fire_started":
				fire_down = true
				_emit(events, "command", {"command": "fire_started"})
				if selected_skill.is_empty() and fire_cooldown <= 0:
					_fire_arrow(events)
			"fire_stopped":
				fire_down = false
				_emit(events, "command", {"command": "fire_stopped"})
			"select_skill":
				var skill_id := str(command.get("skill_id", ""))
				if not _find_by_id(config.get("skills", []), skill_id).is_empty():
					selected_skill = skill_id
					_emit(events, "command", {"command": "select_skill", "skill_id": selected_skill})
			"cancel_skill":
				selected_skill = ""
				_emit(events, "command", {"command": "cancel_skill"})
			"cast_skill":
				var cast_id := str(command.get("skill_id", selected_skill))
				_cast_skill(cast_id, int(command.get("x_milli", aim_x_milli)), int(command.get("y_milli", aim_y_milli)), events)
	if fire_down and selected_skill.is_empty() and fire_cooldown <= 0:
		_fire_arrow(events)


func _fire_arrow(events: Array[Dictionary]) -> void:
	var player: Dictionary = config.get("player", {})
	var origin_x := int(player.get("bow_origin_x_milli", 245000))
	var origin_y := int(player.get("bow_origin_y_milli", 555000))
	var delta_x := aim_x_milli - origin_x
	var speed := int(weapon.get("projectile_speed_milli_per_tick", 56000))
	var strength_level := _upgrade_level("strength")
	var agility_level := _upgrade_level("agility")
	var base_damage := int(weapon.get("damage", 1)) + strength_level * _upgrade_effect_per_level("strength")
	var power_chance := clampi(int(weapon.get("power_shot_chance_per_10000", 0)) + _upgrade_level("power_mastery") * _upgrade_effect_per_level("power_mastery"), 0, 10000)
	var projectile_count := maxi(1, int(weapon.get("projectile_count", 1)) + _upgrade_level("hurricane_mastery") * _upgrade_effect_per_level("hurricane_mastery"))
	var pierce := maxi(0, int(weapon.get("pierce", 0)) + _upgrade_level("phantom_mastery") * _upgrade_effect_per_level("phantom_mastery"))
	var spread := int(weapon.get("spread_milli", 0))
	for projectile_index in range(projectile_count):
		var centered_index := projectile_index - int((projectile_count - 1) / 2)
		var adjusted_target_y := clampi(aim_y_milli + centered_index * spread, 0, int(config["world"]["height_milli"]))
		var adjusted_delta_y := adjusted_target_y - origin_y
		# Euclidean normalization per arrow: max-norm (Chebyshev) would make
		# diagonal and outer volley arrows up to 41% faster than the configured
		# projectile speed.  Normalizing by the true length keeps every arrow at
		# the configured speed regardless of its spread direction.
		var arrow_length := sqrt(float(delta_x) * float(delta_x) + float(adjusted_delta_y) * float(adjusted_delta_y))
		if arrow_length < 1.0:
			arrow_length = 1.0
		var fatal := _combat_rng.chance_per_10000(int(weapon.get("fatal_chance_per_10000", 0)))
		var power := _combat_rng.chance_per_10000(power_chance)
		var damage := base_damage
		if fatal:
			damage *= int(weapon.get("fatal_multiplier", 2))
		var projectile := {
			"entity_id": next_entity_id,
			"x_milli": origin_x,
			"y_milli": origin_y,
			"vx_milli": int(round(delta_x * speed / arrow_length)),
			"vy_milli": int(round(adjusted_delta_y * speed / arrow_length)),
			"damage": damage,
			"fatal": fatal,
			"power": power,
			"pierce_remaining": pierce,
			"hit_entity_ids": [],
			"collision_radius_milli": int(weapon.get("collision_radius_milli", 18000)),
			"age_ticks": 0
		}
		next_entity_id += 1
		projectiles.append(projectile)
		_emit(events, "shot", {"entity_id": projectile["entity_id"], "fatal": fatal, "power": power, "weapon_id": weapon_id, "volley_index": projectile_index, "volley_size": projectile_count})
	var base_interval := int(weapon.get("interval_ticks", 10))
	var minimum_interval := int(weapon.get("min_interval_ticks", 4))
	fire_cooldown = maxi(minimum_interval, base_interval - agility_level * _upgrade_effect_per_level("agility"))


func _cast_skill(skill_id: String, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	if skill_id.is_empty():
		return
	var skill := _find_by_id(config.get("skills", []), skill_id)
	if skill.is_empty():
		_emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
		return
	if int(skill_cooldowns.get(skill_id, 0)) > 0:
		_emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "cooldown"})
		return
	var mana_cost := int(skill.get("mana_cost", 0))
	if mana < mana_cost:
		_emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "no_mana"})
		return
	var world: Dictionary = config.get("world", {})
	if target_x < int(world.get("castle_x_milli", 0)) or target_x > int(world.get("width_milli", 1920000)) or target_y < 0 or target_y > int(world.get("height_milli", 1080000)):
		_emit(events, "skill_rejected", {"skill_id": skill_id, "reason": "invalid_target"})
		return
	mana = clampi(mana - mana_cost, 0, max_mana)
	skill_cooldowns[skill_id] = _effective_skill_cooldown(skill)
	spells_cast += 1
	selected_skill = ""
	_emit(events, "skill_cast", {"skill_id": skill_id, "x_milli": target_x, "y_milli": target_y, "mana": mana})
	match skill_id:
		"fire_ball":
			_apply_fire_skill(skill, target_x, target_y, events)
		"glacial_spike":
			_apply_ice_skill(skill, target_x, target_y, events)
		"lightning_strike":
			_apply_lightning_skill(skill, target_x, target_y, events)


func _apply_fire_skill(skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage := int(skill.get("damage", 0)) + _upgrade_level("fire_mastery") * _upgrade_effect_per_level("fire_mastery")
	var radius := _skill_radius(skill)
	for enemy in enemies:
		if _distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= _square(radius):
			_apply_enemy_damage(enemy, damage, "fire", events)
			enemy["burn_damage"] = int(skill.get("burn_damage", 0))
			enemy["burn_interval_ticks"] = maxi(1, int(skill.get("burn_interval_ticks", 15)))
			enemy["burn_counter"] = enemy["burn_interval_ticks"]
			enemy["burn_ticks"] = _resisted_ticks(enemy, int(skill.get("burn_duration_ticks", 0)))
			_emit(events, "status", {"entity_id": enemy["entity_id"], "status": "burn", "ticks": enemy["burn_ticks"]})


func _apply_ice_skill(skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var damage := int(skill.get("damage", 0)) + _upgrade_level("ice_mastery") * _upgrade_effect_per_level("ice_mastery")
	var radius := _skill_radius(skill)
	for enemy in enemies:
		if _distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y) <= _square(radius):
			_apply_enemy_damage(enemy, damage, "ice", events)
			enemy["slow_permille"] = int(skill.get("slow_permille", 500))
			enemy["slow_ticks"] = _resisted_ticks(enemy, int(skill.get("slow_duration_ticks", 0)))
			enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), _resisted_ticks(enemy, int(skill.get("freeze_ticks", 0))))
			_emit(events, "status", {"entity_id": enemy["entity_id"], "status": "frozen", "ticks": enemy["stun_ticks"]})


func _apply_lightning_skill(skill: Dictionary, target_x: int, target_y: int, events: Array[Dictionary]) -> void:
	var candidates: Array[Dictionary] = []
	var radius_squared := _square(_skill_radius(skill))
	for enemy in enemies:
		var distance := _distance_squared(enemy["x_milli"], enemy["y_milli"], target_x, target_y)
		if distance <= radius_squared:
			candidates.append({"enemy": enemy, "distance": distance})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["distance"]) < int(b["distance"]))
	var count := mini(int(skill.get("max_targets", 1)), candidates.size())
	var damage := int(skill.get("damage", 0)) + _upgrade_level("lightning_mastery") * _upgrade_effect_per_level("lightning_mastery")
	for index in range(count):
		var enemy: Dictionary = candidates[index]["enemy"]
		_apply_enemy_damage(enemy, damage, "lightning", events)
		enemy["stun_ticks"] = maxi(int(enemy["stun_ticks"]), _resisted_ticks(enemy, int(skill.get("stun_ticks", 0))))
		_emit(events, "status", {"entity_id": enemy["entity_id"], "status": "stunned", "ticks": enemy["stun_ticks"]})


func _update_enemies(events: Array[Dictionary]) -> void:
	for enemy in enemies:
		# Once the wall reaches zero, defeat is the terminal outcome for this
		# tick.  Do not let later enemies emit additional attacks or boss specials
		# after the lethal hit; this keeps the wall-damage event stream meaningful
		# and honours the "stop on zero" rule.
		if wall_hp <= 0:
			break
		if int(enemy["hp"]) <= 0:
			continue
		if int(enemy["burn_ticks"]) > 0:
			enemy["burn_ticks"] = int(enemy["burn_ticks"]) - 1
			enemy["burn_counter"] = int(enemy["burn_counter"]) - 1
			if int(enemy["burn_counter"]) <= 0:
				enemy["burn_counter"] = enemy["burn_interval_ticks"]
				_apply_enemy_damage(enemy, int(enemy["burn_damage"]), "burn", events)
		if int(enemy["hp"]) <= 0:
			continue
		if int(enemy["stun_ticks"]) > 0:
			enemy["stun_ticks"] = int(enemy["stun_ticks"]) - 1
			continue
		if int(enemy["slow_ticks"]) > 0:
			enemy["slow_ticks"] = int(enemy["slow_ticks"]) - 1
		else:
			enemy["slow_permille"] = 1000
		if str(enemy.get("movement_style", "ground")) == "flying":
			var amplitude := int(enemy.get("patrol_amplitude_milli", 0))
			var period := maxi(1, int(enemy.get("patrol_period_ticks", 1)))
			enemy["y_milli"] = int(enemy.get("base_y_milli", enemy["y_milli"])) + int(round(sin(float(tick) * TAU / float(period)) * float(amplitude)))
		if int(enemy["x_milli"]) > int(enemy["attack_x_milli"]):
			var movement := int(enemy["speed_milli_per_tick"]) * int(enemy["slow_permille"]) / 1000
			enemy["x_milli"] = maxi(int(enemy["attack_x_milli"]), int(enemy["x_milli"]) - movement)
		else:
			if int(enemy["attack_cooldown"]) > 0:
				enemy["attack_cooldown"] = int(enemy["attack_cooldown"]) - 1
			else:
				enemy["attack_cooldown"] = int(enemy["attack_interval_ticks"])
				_damage_wall(int(enemy["attack_damage"]), "enemy", enemy["entity_id"], events)
				if wall_hp <= 0:
					break
		if enemy["tags"].has("boss") and int(enemy.get("special_interval_ticks", 0)) > 0:
			enemy["special_counter"] = int(enemy["special_counter"]) + 1
			if int(enemy["special_counter"]) >= int(enemy["special_interval_ticks"]):
				enemy["special_counter"] = 0
				var special_damage := maxi(0, int(enemy.get("special_damage", 0)))
				if str(enemy.get("special", "")) == "frost_nova":
					# Frost Nova encases the player's defenses in ice instead of
					# dealing direct wall damage: moat and tower go dark for a
					# configured window, which threatens upgraded defense builds.
					var freeze_ticks := maxi(1, int(enemy.get("special_freeze_ticks", 75)))
					for defense_id in defense_cooldowns.keys():
						defense_cooldowns[defense_id] = maxi(int(defense_cooldowns[defense_id]), freeze_ticks)
				else:
					_damage_wall(special_damage, "boss_special", enemy["entity_id"], events)
				_emit(events, "boss_special", {"entity_id": enemy["entity_id"], "special": enemy["special"], "amount": special_damage, "wall_hp": wall_hp})
				if wall_hp <= 0:
					break


func _update_projectiles(events: Array[Dictionary]) -> void:
	var enemy_bands := _build_enemy_bands()
	for projectile_index in range(projectiles.size() - 1, -1, -1):
		var projectile: Dictionary = projectiles[projectile_index]
		var previous_x := int(projectile["x_milli"])
		var previous_y := int(projectile["y_milli"])
		projectile["x_milli"] = previous_x + int(projectile["vx_milli"])
		projectile["y_milli"] = previous_y + int(projectile["vy_milli"])
		projectile["age_ticks"] = int(projectile["age_ticks"]) + 1
		var hit_enemy: Dictionary = {}
		var best_t := 2.0
		var candidate_enemies := _projectile_candidates(enemy_bands, previous_y, int(projectile["y_milli"]), int(projectile["collision_radius_milli"]))
		var hit_entity_ids: Array = projectile.get("hit_entity_ids", [])
		for enemy in candidate_enemies:
			if int(enemy["hp"]) <= 0:
				continue
			if hit_entity_ids.has(int(enemy["entity_id"])):
				continue
			var radius := int(enemy["collision_radius_milli"]) + int(projectile["collision_radius_milli"])
			var hit_t := _segment_hit_t(previous_x, previous_y, int(projectile["x_milli"]), int(projectile["y_milli"]), int(enemy["x_milli"]), int(enemy["y_milli"]), radius)
			if hit_t >= 0.0 and hit_t < best_t:
				best_t = hit_t
				hit_enemy = enemy
		if not hit_enemy.is_empty():
			hit_entity_ids.append(int(hit_enemy["entity_id"]))
			projectile["hit_entity_ids"] = hit_entity_ids
			_emit(events, "hit", {"projectile_id": projectile["entity_id"], "entity_id": hit_enemy["entity_id"], "fatal": projectile["fatal"], "power": projectile["power"]})
			_apply_enemy_damage(hit_enemy, int(projectile["damage"]), "arrow", events)
			if bool(projectile["power"]):
				var resistance := clampi(int(hit_enemy.get("knockback_resistance_permille", 0)), 0, 1000)
				var knockback := int(weapon.get("knockback_milli", 0)) * (1000 - resistance) / 1000
				hit_enemy["x_milli"] = clampi(
					int(hit_enemy["x_milli"]) + knockback,
					int(hit_enemy["attack_x_milli"]),
					int(config["world"]["enemy_spawn_x_milli"])
				)
			var remaining_pierce := int(projectile.get("pierce_remaining", 0))
			if remaining_pierce > 0:
				projectile["pierce_remaining"] = remaining_pierce - 1
			else:
				projectiles.remove_at(projectile_index)
		elif int(projectile["age_ticks"]) > 90 or int(projectile["x_milli"]) > int(config["world"]["width_milli"]) + 100000 or int(projectile["y_milli"]) < -100000 or int(projectile["y_milli"]) > int(config["world"]["height_milli"]) + 100000:
			projectiles.remove_at(projectile_index)


func _build_enemy_bands() -> Dictionary:
	var bands: Dictionary = {}
	for enemy in enemies:
		if int(enemy["hp"]) <= 0:
			continue
		var radius := int(enemy["collision_radius_milli"])
		var minimum_band := _band_index(int(enemy["y_milli"]) - radius)
		var maximum_band := _band_index(int(enemy["y_milli"]) + radius)
		for band in range(minimum_band, maximum_band + 1):
			if not bands.has(band):
				bands[band] = []
			bands[band].append(enemy)
	return bands


func _projectile_candidates(bands: Dictionary, previous_y: int, current_y: int, radius: int) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var seen: Dictionary = {}
	var minimum_band := _band_index(mini(previous_y, current_y) - radius)
	var maximum_band := _band_index(maxi(previous_y, current_y) + radius)
	for band in range(minimum_band, maximum_band + 1):
		for enemy in bands.get(band, []):
			var entity_id := int(enemy["entity_id"])
			if seen.has(entity_id):
				continue
			seen[entity_id] = true
			candidates.append(enemy)
	return candidates


static func _band_index(y_milli: int) -> int:
	return int(floor(float(y_milli) / float(COLLISION_BAND_HEIGHT_MILLI)))


func _resolve_deaths(events: Array[Dictionary]) -> void:
	for index in range(enemies.size() - 1, -1, -1):
		var enemy: Dictionary = enemies[index]
		if int(enemy["hp"]) > 0:
			continue
		kills += 1
		var coins := int(enemy.get("reward_coins", 0)) + _reward_bonus("coin_bounty")
		var xp := int(enemy.get("reward_xp", 0)) + _reward_bonus("xp_bounty")
		coins_earned += coins
		xp_earned += xp
		_emit(events, "death", {"entity_id": enemy["entity_id"], "enemy_id": enemy["enemy_id"], "boss": enemy["tags"].has("boss")})
		var reward_version := str(config.get("ruleset_version", "unknown"))
		_emit(events, "reward", {
			"source": "kill",
			"entity_id": enemy["entity_id"],
			"coins": coins,
			"xp": xp,
			"reward_version": reward_version,
			"idempotency_key": "%s:%s:kill:%d" % [run_id, reward_version, int(enemy["entity_id"])]
		})
		if enemy["tags"].has("boss"):
			_boss_rewarded = true
			bosses_slain += 1
		enemies.remove_at(index)


func _resolve_run_end(events: Array[Dictionary]) -> void:
	if status != STATUS_RUNNING:
		return
	if wall_hp <= 0:
		status = STATUS_DEFEAT
		fire_down = false
		_emit(events, "run_end", result())
		return
	if spawn_cursor >= spawn_queue.size() and enemies.is_empty():
		status = STATUS_VICTORY
		fire_down = false
		var result_data := result()
		var clear_coins := int(stage["clear_reward"]["coins"]) + _reward_bonus("coin_bounty")
		var clear_xp := int(stage["clear_reward"]["xp"]) + _reward_bonus("xp_bounty")
		_emit(events, "reward", {
			"source": "stage_clear",
			"coins": clear_coins,
			"xp": clear_xp,
			"reward_version": str(config["ruleset_version"]),
			"idempotency_key": result_data["idempotency_key"]
		})
		_emit(events, "run_end", result_data)


func _apply_enemy_damage(enemy: Dictionary, raw_damage: int, source: String, events: Array[Dictionary]) -> void:
	if int(enemy["hp"]) <= 0:
		return
	var resistance_type := "fire" if source in ["fire", "burn", "lava_moat"] else (source if source in ["ice", "lightning"] else "")
	var resistance := int(enemy.get("resistances", {}).get(resistance_type, 0)) if not resistance_type.is_empty() else 0
	resistance = clampi(resistance, 0, 1000)
	var elemental_damage := maxi(1, raw_damage * (1000 - resistance) / 1000)
	var damage := maxi(1, elemental_damage - int(enemy.get("armor", 0)))
	enemy["hp"] = maxi(0, int(enemy["hp"]) - damage)
	_emit(events, "damage", {"entity_id": enemy["entity_id"], "amount": damage, "source": source, "hp": enemy["hp"]})


func _update_defenses(events: Array[Dictionary]) -> void:
	var defenses: Dictionary = config.get("defenses", {})
	for defense_id in ["lava_moat", "magic_tower"]:
		var level := _upgrade_level(defense_id)
		if level <= 0:
			continue
		var definition: Dictionary = defenses.get(defense_id, {})
		if definition.is_empty() or int(defense_cooldowns.get(defense_id, 0)) > 0:
			continue
		var target_enemies: Array[Dictionary] = []
		var range_milli := int(definition.get("range_milli", 0))
		for enemy in enemies:
			if int(enemy.get("hp", 0)) <= 0:
				continue
			var distance_to_castle: int = absi(int(enemy.get("x_milli", 0)) - int(config["world"].get("castle_x_milli", 0)))
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
				_apply_enemy_damage(enemy, damage, "lava_moat", events)
				enemy["burn_damage"] = maxi(int(enemy.get("burn_damage", 0)), int(definition.get("burn_damage", 0)))
				enemy["burn_interval_ticks"] = maxi(1, int(definition.get("burn_interval_ticks", 15)))
				enemy["burn_counter"] = enemy["burn_interval_ticks"]
				enemy["burn_ticks"] = maxi(int(enemy.get("burn_ticks", 0)), int(definition.get("burn_duration_ticks", 0)))
		else:
			_apply_enemy_damage(target_enemies[0], damage, "magic_tower", events)
		_emit(events, "defense_attack", {"defense_id": defense_id, "level": level, "target_count": target_enemies.size() if defense_id == "lava_moat" else 1, "x_milli": int(target_enemies[0]["x_milli"]), "y_milli": int(target_enemies[0]["y_milli"])})
		defense_cooldowns[defense_id] = maxi(1, int(definition.get("interval_ticks", 30)))


func _regenerate_mana(events: Array[Dictionary]) -> void:
	var player: Dictionary = config.get("player", {})
	var interval := maxi(1, int(player.get("mana_regen_interval_ticks", 15)))
	if tick % interval == 0 and mana < max_mana:
		mana = clampi(mana + int(player.get("mana_regen_amount", 1)) + _reward_bonus("mana_regen"), 0, max_mana)
		_emit(events, "status", {"status": "mana_regen", "mana": mana})


func _tick_cooldowns() -> void:
	if fire_cooldown > 0:
		fire_cooldown -= 1
	for skill_id in skill_cooldowns.keys():
		skill_cooldowns[skill_id] = maxi(0, int(skill_cooldowns[skill_id]) - 1)
	for defense_id in defense_cooldowns.keys():
		defense_cooldowns[defense_id] = maxi(0, int(defense_cooldowns[defense_id]) - 1)


func _upgrade_level(upgrade_id: String) -> int:
	var upgrades: Dictionary = profile_snapshot.get("upgrades", {})
	return int(upgrades.get(upgrade_id, 0))


func _upgrade_effect_per_level(upgrade_id: String) -> int:
	var definition := _find_by_id(config.get("upgrades", []), upgrade_id)
	return int(definition.get("effect_per_level", 0))


func _reward_bonus(upgrade_id: String) -> int:
	return _upgrade_level(upgrade_id) * _upgrade_effect_per_level(upgrade_id)


func _skill_radius(skill: Dictionary) -> int:
	var base_radius := int(skill.get("radius_milli", 0))
	var bonus_permille := _upgrade_level("spell_radius") * _upgrade_effect_per_level("spell_radius")
	return maxi(1, base_radius * (1000 + bonus_permille) / 1000)


func _effective_skill_cooldown(skill: Dictionary) -> int:
	return maxi(1, int(skill.get("cooldown_ticks", 1)) - _upgrade_level("cooldown_mastery") * _upgrade_effect_per_level("cooldown_mastery"))


func _damage_wall(raw_damage: int, source: String, entity_id: int, events: Array[Dictionary]) -> void:
	if wall_hp <= 0:
		return
	var armor := _upgrade_level("wall_armor") * _upgrade_effect_per_level("wall_armor")
	var actual_damage := maxi(0, raw_damage - armor)
	wall_hp = maxi(0, wall_hp - actual_damage)
	_emit(events, "wall_damage", {"entity_id": entity_id, "amount": actual_damage, "raw_amount": raw_damage, "source": source, "wall_hp": wall_hp})


func _resisted_ticks(enemy: Dictionary, base_ticks: int) -> int:
	var floor_permille := int(config.get("rules", {}).get("status_resistance_floor_permille", 950))
	var resistance := clampi(int(enemy.get("status_resistance_permille", 0)), 0, floor_permille)
	return maxi(1, base_ticks * (1000 - resistance) / 1000) if base_ticks > 0 else 0


func _emit(events: Array[Dictionary], event_type: String, values: Dictionary) -> void:
	var event := values.duplicate(true)
	event["type"] = event_type
	event["tick"] = tick
	event["sequence"] = _event_sequence
	_event_sequence += 1
	events.append(event)


func _sort_events(events: Array[Dictionary]) -> void:
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_order := int(EVENT_ORDER.get(str(a["type"]), 999))
		var b_order := int(EVENT_ORDER.get(str(b["type"]), 999))
		if a_order == b_order:
			return int(a["sequence"]) < int(b["sequence"])
		return a_order < b_order
	)


static func _find_by_id(items: Array, item_id: String) -> Dictionary:
	for value in items:
		if value is Dictionary and str(value.get("id", "")) == item_id:
			return value.duplicate(true)
	return {}


static func _square(value: int) -> int:
	return value * value


static func _distance_squared(ax: int, ay: int, bx: int, by: int) -> int:
	var dx := ax - bx
	var dy := ay - by
	return dx * dx + dy * dy


static func _segment_hit_t(ax: int, ay: int, bx: int, by: int, px: int, py: int, radius: int) -> float:
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
