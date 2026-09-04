class_name DefenderHonorService
extends RefCounted


func apply_result(profile: Dictionary, result: Dictionary, config: Dictionary) -> Dictionary:
	var updated := profile.duplicate(true)
	var stats: Dictionary = updated.get("stats", {}).duplicate(true)
	stats["total_kills"] = int(stats.get("total_kills", 0)) + int(result.get("kills", 0))
	stats["bosses_defeated"] = int(stats.get("bosses_defeated", 0)) + int(result.get("bosses_slain", 0))
	stats["spells_cast"] = int(stats.get("spells_cast", 0)) + int(result.get("spells_cast", 0))
	stats["total_coins_earned"] = int(stats.get("total_coins_earned", 0)) + int(result.get("coins", 0))
	stats["highest_stage_reached"] = maxi(int(stats.get("highest_stage_reached", 0)), int(result.get("stage_number", 0)))
	var victory := str(result.get("status", "")) == "victory"
	# Status-page battle record (参考 Status screen: Win/Lose/Win%).
	if victory:
		stats["battles_won"] = int(stats.get("battles_won", 0)) + 1
	else:
		stats["battles_lost"] = int(stats.get("battles_lost", 0)) + 1
	if victory:
		stats["stages_completed"] = int(stats.get("stages_completed", 0)) + 1
		if int(result.get("wall_percent", 0)) >= 100:
			stats["perfect_stages"] = int(stats.get("perfect_stages", 0)) + 1
	var weapons_used: Array = stats.get("weapons_used", []).duplicate()
	var weapon_id := str(result.get("weapon_id", ""))
	if not weapon_id.is_empty() and not weapons_used.has(weapon_id):
		weapons_used.append(weapon_id)
	stats["weapons_used"] = weapons_used
	updated["stats"] = stats

	var honors: Dictionary = updated.get("honors", {}).duplicate(true)
	var honor_reward_ledger: Array = updated.get("honor_reward_ledger", []).duplicate()
	var new_honors: Array[String] = []
	var honor_coins := 0
	var honor_xp := 0
	for definition in config.get("honors", []):
		if not definition is Dictionary:
			continue
		var honor_id := str(definition.get("id", ""))
		if honor_id.is_empty() or bool(honors.get(honor_id, false)) or honor_reward_ledger.has(honor_id):
			continue
		if _condition_met(definition, stats):
			honors[honor_id] = true
			honor_reward_ledger.append(honor_id)
			new_honors.append(honor_id)
			honor_coins += int(definition.get("reward_coins", 0))
			honor_xp += int(definition.get("reward_xp", 0))
	updated["honors"] = honors
	updated["honor_reward_ledger"] = honor_reward_ledger
	updated["coins"] = int(updated.get("coins", 0)) + honor_coins
	updated["xp"] = int(updated.get("xp", 0)) + honor_xp
	return {
		"ok": true,
		"profile": updated,
		"new_honors": new_honors,
		"honor_coins": honor_coins,
		"honor_xp": honor_xp
	}


static func _condition_met(definition: Dictionary, stats: Dictionary) -> bool:
	var condition_type := str(definition.get("condition_type", ""))
	var current := int(stats.get(condition_type, 0))
	if condition_type == "weapons_used_count":
		current = stats.get("weapons_used", []).size()
	return current >= int(definition.get("threshold", 0))
