class_name DefenderAttackText
extends RefCounted

const AttackCatalog = preload("res://src/core/rules/attack_catalog.gd")


static func summary(id: String, stats: Dictionary, translate: Callable, tick_rate: int) -> String:
	match id:
		"strength":
			return translate.call("attack.damage") % [int(stats["base_damage"]), int(stats["damage"])]
		"agility":
			return translate.call("attack.rate") % [float(tick_rate) / int(stats["interval_ticks"]), int(stats["interval_ticks"]), int(stats["min_interval_ticks"])]
		"power_shot":
			return translate.call("attack.power") % [float(stats["power_shot_chance_per_10000"]) / 100.0, float(stats["knockback_milli"]) / 1000.0]
		"poisoned_arrow":
			return translate.call("attack.poison") % [int(stats["poison_damage"]), float(stats["poison_interval_ticks"]) / tick_rate, float(stats["poison_duration_ticks"]) / tick_rate, float(stats["poison_damage_permille"]) / 10.0]
		"fatal_blow":
			return translate.call("attack.fatal") % [float(stats["fatal_chance_per_10000"]) / 100.0, int(stats["damage"]) * 2]
		"multiple_arrows":
			return translate.call("attack.volley") % [int(stats["projectile_count"]), int(stats["damage"]), float(stats["damage_permille"]) / 10.0, int(stats["projectile_count"]) * int(stats["damage"])]
		"senior_hunter":
			return translate.call("attack.xp") % (float(stats["xp_bonus_permille"]) / 10.0)
	return ""


static func detail(config: Dictionary, profile: Dictionary, weapon: Dictionary, id: String, translate: Callable) -> String:
	var definition := AttackCatalog.find(config, id)
	var current := AttackCatalog.effective(config, profile, weapon)
	var rate := int(config.get("simulation_tick_rate", 30))
	var text := str(translate.call("skill.current")) + summary(id, current, translate, rate)
	if AttackCatalog.level(config, profile, id) < int(definition.get("max_level", 0)):
		var next_profile := profile.duplicate(true)
		next_profile["upgrades"][id] = AttackCatalog.level(config, profile, id) + 1
		text += "\n" + str(translate.call("skill.next")) + summary(id, AttackCatalog.effective(config, next_profile, weapon), translate, rate)
	return text
