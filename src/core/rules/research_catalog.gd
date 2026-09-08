class_name DefenderResearchCatalog
extends RefCounted

# No designed level cap for endless nodes. The first bound is the exact JSON
# integer range; the second keeps combat multiplications inside signed int64.
const MAX_LEVEL := 9007199254740991
const MAX_EFFECT := 1000000000000
const MAX_PRICE := 9000000000000000
const ENDLESS_IDS := ["strength", "mana_capacity", "fire_mastery", "meteor", "armageddon", "ice_mastery", "frost_nova", "ice_age", "lightning_mastery", "thunder_storm", "ragnarok", "wall_repair", "lava_moat", "magic_tower", "forge_power_bow", "forge_hurricane_bow", "forge_phantom_bow"]


static func find(config: Dictionary, id: String) -> Dictionary:
	for definition in config.get("upgrades", []):
		if str(definition.get("id", "")) == id:
			return definition
	return {}


static func is_endless(definition: Dictionary) -> bool:
	var value: Variant = definition.get("endless", false)
	return value is bool and value


static func level_limit(definition: Dictionary) -> int:
	return MAX_LEVEL if is_endless(definition) else int(definition.get("max_level", 0))


static func normalize_level(definition: Dictionary, value: int) -> int:
	return clampi(value, 0, level_limit(definition))


static func level(config: Dictionary, profile: Dictionary, id: String) -> int:
	return normalize_level(find(config, id), int(profile.get("upgrades", {}).get(id, 0)))


static func can_upgrade(definition: Dictionary, current_level: int) -> bool:
	return not definition.is_empty() and current_level < level_limit(definition)


static func add_scaled(base: int, per_level: int, count: int) -> int:
	base = clampi(base, 0, MAX_EFFECT)
	count = maxi(0, count)
	if per_level <= 0:
		return base
	if count > (MAX_EFFECT - base) / per_level:
		return MAX_EFFECT
	return base + per_level * count


static func multiply_ratio(value: int, multiplier: int, divisor: int = 1000) -> int:
	# Callers use positive ratios with divisors at most 1,000,000, so this
	# preflight and the accepted product both stay below 10^18.
	value = maxi(0, value)
	multiplier = maxi(0, multiplier)
	if multiplier == 0:
		return 0
	if value > MAX_EFFECT * divisor / multiplier:
		return MAX_EFFECT
	return value * multiplier / divisor


static func bonus(config: Dictionary, profile: Dictionary, id: String) -> int:
	return add_scaled(0, int(find(config, id).get("effect_per_level", 0)), level(config, profile, id))


static func price_for_level(definition: Dictionary, current_level: int) -> int:
	current_level = normalize_level(definition, current_level)
	var opening := int(definition.get("max_level", 0))
	var old_level := mini(current_level, maxi(0, opening - 1)) if is_endless(definition) else current_level
	var price := int(definition.get("base_cost", 0))
	var growth := int(definition.get("cost_growth_permille", 1000))
	# Only the bounded authored opening uses the old rounded exponential.
	# Deep research never loops from zero to the player's current level.
	if growth > 1000:
		for ignored in range(mini(old_level, 100)):
			price = mini(MAX_PRICE, maxi(price + 1, int(minf(MAX_PRICE, round(float(price) * growth / 1000.0)))))
	if is_endless(definition) and current_level >= opening:
		var curve: Dictionary = definition.get("endless_cost", {})
		var extra := pow(float(current_level - opening + 1), float(curve.get("power", 1.15))) * int(curve.get("step", 1))
		return int(minf(MAX_PRICE, float(price) + ceil(extra)))
	return price
