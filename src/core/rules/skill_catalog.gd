class_name DefenderSkillCatalog
extends RefCounted

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
	var upgrades: Dictionary = profile.get("upgrades", {})
	var upgrade_id := str(skill.get("upgrade_id", ""))
	var level := maxi(0, int(upgrades.get(upgrade_id, 0)))
	var points := level if int(skill.get("tier", 1)) == 1 else maxi(0, level - 1)
	var effect := 0
	var radius_bonus := 0
	var cooldown_bonus := 0
	for definition in config.get("upgrades", []):
		var id := str(definition.get("id", ""))
		var amount := int(definition.get("effect_per_level", 0))
		if id == upgrade_id:
			effect = amount
		elif id == "spell_radius":
			radius_bonus = int(upgrades.get(id, 0)) * amount
		elif id == "cooldown_mastery":
			cooldown_bonus = int(upgrades.get(id, 0)) * amount
	var damage_bonus := 0
	for honor in config.get("honors", []):
		if str(honor.get("bonus_type", "")) == str(skill.get("element", "")) + "_damage_pct":
			damage_bonus = clampi(int(profile.get("honors", {}).get(str(honor.get("id", "")), 0)), 0, 3) * int(honor.get("bonus_per_level", 0)) * 10
	skill["research_level"] = level
	skill["damage"] = (int(skill.get("damage", 0)) + points * effect) * (1000 + damage_bonus) / 1000
	skill["radius_milli"] = maxi(1, int(skill.get("radius_milli", 1)) * (1000 + radius_bonus) / 1000)
	skill["cooldown_ticks"] = maxi(1, int(skill.get("cooldown_ticks", 1)) - cooldown_bonus)
	for field in ["burn_duration_ticks", "freeze_ticks", "stun_ticks"]:
		if skill.has(field):
			skill[field] = int(skill[field]) + points * int(skill.get(field + "_per_level", 0))
	return skill
