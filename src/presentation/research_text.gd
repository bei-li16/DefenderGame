extends RefCounted

const Research = preload("res://src/core/rules/research_catalog.gd")
const Attack = preload("res://src/core/rules/attack_catalog.gd")

static func compact(number: int) -> String:
	for unit in [[1000000000000000, "P"], [1000000000000, "T"], [1000000000, "B"], [1000000, "M"], [1000, "K"]]:
		if number >= int(unit[0]) and number >= 10000:
			return "%.1f%s" % [float(number) / int(unit[0]), str(unit[1])]
	return str(number)


static func specialized(config: Dictionary, profile: Dictionary, id: String, translate: Callable) -> String:
	var definition := Research.find(config, id)
	var level := Research.level(config, profile, id)
	var text := ""
	for offset in range(2 if Research.can_upgrade(definition, level) else 1):
		var summary := ""
		if id in ["lava_moat", "magic_tower"]:
			var defense: Dictionary = config["defenses"][id]
			var damage := Research.add_scaled(int(defense["damage"]), int(defense["damage_per_level"]), maxi(0, level + offset - 1)) if level + offset > 0 else 0
			summary = translate.call("research.defense_stats") % [damage, float(defense["interval_ticks"]) / int(config["simulation_tick_rate"]), int(defense["range_milli"]) / 1000]
		elif id.begins_with("forge_"):
			var preview := profile.duplicate(true)
			preview["upgrades"][id] = level + offset
			for weapon in config["weapons"]:
				if weapon["id"] == definition["weapon_ref"]:
					var stats := Attack.effective(config, preview, weapon)
					summary = translate.call("attack.damage") % [stats["base_damage"], stats["damage"]]
		else:
			return ""
		text += ("\n" if offset > 0 else "") + str(translate.call("skill.next" if offset > 0 else "skill.current")) + summary
	return text
