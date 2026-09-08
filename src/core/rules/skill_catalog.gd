class_name DefenderSkillCatalog
extends RefCounted

const ResearchCatalog = preload("res://src/core/rules/research_catalog.gd")

# One rule source for research previews, loadouts, HUD and combat. Legacy
# *_mastery levels remain the first-tier research nodes, without losing XP.
const ELEMENTS := ["fire", "ice", "lightning"]


static func find(config: Dictionary, skill_id: String) -> Dictionary:
	for skill in config.get("skills", []):
		if str(skill.get("id", "")) == skill_id:
			return skill
	return {}


static func available(config: Dictionary, profile: Dictionary, skill_id: String) -> bool:
	var skill := find(config, skill_id)
	if skill.is_empty():
		return false
	return int(skill.get("tier", 1)) == 1 or int(profile.get("upgrades", {}).get(str(skill.get("upgrade_id", "")), 0)) > 0


static func loadout(config: Dictionary, profile: Dictionary) -> Dictionary:
	var result := {}
	for skill in config.get("skills", []):
		if int(skill.get("tier", 1)) == 1:
			result[str(skill.get("element", ""))] = str(skill.get("id", ""))
	var stored: Variant = profile.get("equipped_skills", {})
	if stored is Dictionary:
		for element in ELEMENTS:
			var skill_id := str(stored.get(element, ""))
			if available(config, profile, skill_id) and str(find(config, skill_id).get("element", "")) == element:
				result[element] = skill_id
	return result


static func effective(config: Dictionary, profile: Dictionary, skill_id: String) -> Dictionary:
	var skill := find(config, skill_id).duplicate(true)
	if skill.is_empty():
		return skill
	var upgrade_id := str(skill.get("upgrade_id", ""))
	var node := ResearchCatalog.find(config, upgrade_id)
	var level := ResearchCatalog.level(config, profile, upgrade_id)
	var points := level if int(skill.get("tier", 1)) == 1 else maxi(0, level - 1)
	var secondary_level := mini(level, int(node.get("secondary_max_level", node.get("max_level", 0))))
	var secondary_points := secondary_level if int(skill.get("tier", 1)) == 1 else maxi(0, secondary_level - 1)
	var effect := 0
	var radius_bonus := 0
	var cooldown_bonus := 0
	for definition in config.get("upgrades", []):
		var id := str(definition.get("id", ""))
		var amount := int(definition.get("effect_per_level", 0))
		if id == upgrade_id:
			effect = amount
		elif id == "spell_radius":
			radius_bonus = ResearchCatalog.bonus(config, profile, id)
		elif id == "cooldown_mastery":
			cooldown_bonus = ResearchCatalog.bonus(config, profile, id)
	var damage_bonus := 0
	for honor in config.get("honors", []):
		if str(honor.get("bonus_type", "")) == str(skill.get("element", "")) + "_damage_pct":
			damage_bonus = clampi(int(profile.get("honors", {}).get(str(honor.get("id", "")), 0)), 0, 3) * int(honor.get("bonus_per_level", 0)) * 10
	skill["research_level"] = level
	skill["damage"] = ResearchCatalog.multiply_ratio(ResearchCatalog.add_scaled(int(skill.get("damage", 0)), effect, points), 1000 + damage_bonus)
	# Research changes one impact, never the barrage footprint/count/schedule.
	for field in ["radius_milli", "splash_radius_milli"]:
		skill[field] = maxi(1, (int(skill.get(field, 1)) + secondary_points * int(skill.get(field + "_per_level", 0))) * (1000 + radius_bonus) / 1000)
	for field in ["splash_damage", "burn_damage"]:
		if skill.has(field):
			skill[field] = ResearchCatalog.multiply_ratio(ResearchCatalog.add_scaled(int(skill[field]), int(skill.get(field + "_per_level", 0)), points), 1000 + damage_bonus)
	skill["cooldown_ticks"] = maxi(1, int(skill.get("cooldown_ticks", 1)) - cooldown_bonus)
	for field in ["burn_duration_ticks", "freeze_ticks", "stun_ticks", "slow_duration_ticks"]:
		if skill.has(field):
			skill[field] = int(skill[field]) + secondary_points * int(skill.get(field + "_per_level", 0))
	if skill.has("slow_permille"):
		skill["slow_permille"] = clampi(int(skill["slow_permille"]) + secondary_points * int(skill.get("slow_permille_per_level", 0)), 100, 1000)
	return skill
