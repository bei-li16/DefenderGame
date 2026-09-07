class_name DefenderAttackCatalog
extends RefCounted

# Single source for attack research previews and projectile snapshots.
const IDS := ["strength", "agility", "power_shot", "poisoned_arrow", "fatal_blow", "multiple_arrows", "senior_hunter"]
const REVISION := 1
# Historical paid prices, deliberately independent of new balancing tables.
const RETIRED := {
	"power_mastery": {"max_level": 8, "base_cost": 180, "cost_growth_permille": 1500},
	"hurricane_mastery": {"max_level": 4, "base_cost": 240, "cost_growth_permille": 1700},
	"phantom_mastery": {"max_level": 4, "base_cost": 260, "cost_growth_permille": 1700}
}


static func normalize_profile(source: Dictionary) -> Dictionary:
	var updated := source.duplicate(true)
	if int(updated.get("attack_research_revision", 0)) >= REVISION:
		return updated
	var levels: Dictionary = updated.get("upgrades", {}).duplicate(true)
	var retired := {}
	var refund := 0
	for id in RETIRED:
		var original_level := int(levels.get(id, 0))
		if original_level > 0:
			retired[id] = original_level
		var price := int(RETIRED[id]["base_cost"])
		for ignored in range(clampi(original_level, 0, int(RETIRED[id]["max_level"]))):
			refund += price
			price = maxi(price + 1, int(round(float(price) * float(RETIRED[id]["cost_growth_permille"]) / 1000.0)))
		levels.erase(id)
	updated["upgrades"] = levels
	updated["coins"] = int(updated.get("coins", 0)) + refund
	updated["attack_research_revision"] = REVISION
	if not retired.is_empty():
		updated["attack_research_migration"] = {"refunded_coins": refund, "retired_levels": retired}
	return updated


static func find(config: Dictionary, id: String) -> Dictionary:
	for definition in config.get("upgrades", []):
		if str(definition.get("id", "")) == id:
			return definition
	return {}


static func level(config: Dictionary, profile: Dictionary, id: String) -> int:
	return clampi(int(profile.get("upgrades", {}).get(id, 0)), 0, int(find(config, id).get("max_level", 0)))


static func bonus(config: Dictionary, profile: Dictionary, id: String) -> int:
	return level(config, profile, id) * int(find(config, id).get("effect_per_level", 0))


static func honor_bonus(config: Dictionary, profile: Dictionary, kind: String) -> int:
	for honor in config.get("honors", []):
		if str(honor.get("bonus_type", "")) == kind:
			return clampi(int(profile.get("honors", {}).get(str(honor.get("id", "")), 0)), 0, 3) * int(honor.get("bonus_per_level", 0)) * 10
	return 0


static func effective(config: Dictionary, profile: Dictionary, weapon: Dictionary) -> Dictionary:
	var result := weapon.duplicate(true)
	var base_damage := (int(weapon.get("damage", 1)) + bonus(config, profile, "strength")) * (1000 + honor_bonus(config, profile, "weapon_damage_pct")) / 1000
	base_damage = base_damage * (1000 + bonus(config, profile, str(weapon.get("forge_upgrade_id", ""))) * 10) / 1000
	result["base_damage"] = base_damage
	result["interval_ticks"] = maxi(int(weapon.get("min_interval_ticks", 1)), int(weapon.get("interval_ticks", 10)) - bonus(config, profile, "agility"))
	result["fatal_chance_per_10000"] = clampi(int(weapon.get("fatal_chance_per_10000", 0)) + bonus(config, profile, "fatal_blow"), 0, 10000)
	result["fatal_multiplier"] = 2
	result["power_shot_chance_per_10000"] = clampi(int(weapon.get("power_shot_chance_per_10000", 0)) + level(config, profile, "power_shot") * int(find(config, "power_shot").get("chance_per_level", 0)), 0, 10000)
	result["knockback_milli"] = int(weapon.get("knockback_milli", 0)) + bonus(config, profile, "power_shot")
	var multi := find(config, "multiple_arrows")
	var multi_level := level(config, profile, "multiple_arrows")
	var table: Array = multi.get("level_effects", [{"projectile_count": 1, "damage_permille": 1000}])
	var volley: Dictionary = table[mini(multi_level, table.size() - 1)]
	var innate_count := maxi(1, int(weapon.get("projectile_count", 1)))
	var researched_count := int(volley["projectile_count"])
	var count := mini(5, innate_count + researched_count - 1)
	# Preserve each bow's innate volley budget while capping the physical
	# projectiles at five. In particular, research must not weaken Hurricane.
	var ratio := innate_count * researched_count * int(volley["damage_permille"]) / count
	result["projectile_count"] = count
	result["damage_permille"] = ratio
	result["damage"] = maxi(1, base_damage * ratio / 1000)
	result["spread_milli"] = maxi(int(weapon.get("spread_milli", 0)), int(multi.get("spread_milli", 0)) if multi_level > 0 else 0)
	result["pierce"] = maxi(0, int(weapon.get("pierce", 0)))
	var poison := find(config, "poisoned_arrow")
	var poison_ratio := bonus(config, profile, "poisoned_arrow")
	result["poison_damage"] = maxi(1, int(result["damage"]) * poison_ratio / 1000) if poison_ratio > 0 else 0
	result["poison_damage_permille"] = poison_ratio
	result["poison_duration_ticks"] = int(poison.get("duration_ticks", 0)) if poison_ratio > 0 else 0
	result["poison_interval_ticks"] = int(poison.get("interval_ticks", 1))
	result["xp_bonus_permille"] = bonus(config, profile, "senior_hunter")
	return result


static func reward_xp(config: Dictionary, profile: Dictionary, base_value: int) -> int:
	return maxi(0, base_value) * (1000 + honor_bonus(config, profile, "xp_pct")) * (1000 + bonus(config, profile, "senior_hunter")) / 1000000
