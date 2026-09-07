extends RefCounted


static func summary(skill: Dictionary, translate: Callable, tick_rate: int) -> String:
	var text := str(translate.call("skill.stats")) % [int(skill.get("tier", 1)), int(skill.get("mana_cost", 0)), float(skill.get("cooldown_ticks", 1)) / tick_rate, int(skill.get("damage", 0)), int(skill.get("pulse_count", 1)), int(skill.get("radius_milli", 0)) / 1000]
	match str(skill.get("element", "")):
		"fire": text += " · " + str(translate.call("skill.burn_stats")) % [int(skill.get("burn_damage", 0)), float(skill.get("burn_interval_ticks", 1)) / tick_rate, float(skill.get("burn_duration_ticks", 0)) / tick_rate]
		"ice": text += " · " + str(translate.call("skill.freeze_stats")) % [float(skill.get("freeze_ticks", 0)) / tick_rate, 100 - int(skill.get("slow_permille", 1000)) / 10]
		"lightning": text += " · " + str(translate.call("skill.stun_stats")) % [int(skill.get("max_targets", 0)), float(skill.get("stun_ticks", 0)) / tick_rate]
	return text
