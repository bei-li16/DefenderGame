class_name DefenderHonorService
extends RefCounted

# Honor chains in the original Defender II style: each honor has three
# milestone levels, every newly reached level pays coin/xp rewards once
# (ledger keys "id:level") and grants a permanent passive bonus that the run
# model reads from the profile snapshot.


static func stat_value(condition_type: String, stats: Dictionary) -> int:
	if condition_type == "weapons_used_count":
		return stats.get("weapons_used", []).size()
	return int(stats.get(condition_type, 0))


static func honor_level(definition: Dictionary, stats: Dictionary) -> int:
	var current := stat_value(str(definition.get("condition_type", "")), stats)
	var level := 0
	for milestone in definition.get("milestones", []):
		if current >= int(milestone):
			level += 1
		else:
			break
	return level


func apply_result(profile: Dictionary, result: Dictionary, config: Dictionary) -> Dictionary:
	var updated := profile.duplicate(true)
	var stats: Dictionary = updated.get("stats", {}).duplicate(true)
	stats["total_kills"] = int(stats.get("total_kills", 0)) + int(result.get("kills", 0))
	stats["bosses_defeated"] = int(stats.get("bosses_defeated", 0)) + int(result.get("bosses_slain", 0))
	stats["spells_cast"] = int(stats.get("spells_cast", 0)) + int(result.get("spells_cast", 0))
	stats["fire_casts"] = int(stats.get("fire_casts", 0)) + int(result.get("fire_casts", 0))
	stats["ice_casts"] = int(stats.get("ice_casts", 0)) + int(result.get("ice_casts", 0))
	stats["lightning_casts"] = int(stats.get("lightning_casts", 0)) + int(result.get("lightning_casts", 0))
	stats["total_coins_earned"] = int(stats.get("total_coins_earned", 0)) + int(result.get("coins", 0))
	stats["highest_stage_reached"] = maxi(int(stats.get("highest_stage_reached", 0)), int(result.get("stage_number", 0)))
	var victory := str(result.get("status", "")) == "victory"
	# Status-page battle record (参考 Status screen: Win/Lose/Win%).
	if victory:
		stats["battles_won"] = int(stats.get("battles_won", 0)) + 1
	else:
		stats["battles_lost"] = int(stats.get("battles_lost", 0)) + 1
	var perfect_victory := victory and int(result.get("wall_percent", 0)) >= 100
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

	var evaluation := evaluate(updated, config)
	updated["honors"] = evaluation["honors"]
	updated["honor_reward_ledger"] = evaluation["ledger"]
	updated["coins"] = int(updated.get("coins", 0)) + evaluation["coins"]
	updated["xp"] = int(updated.get("xp", 0)) + evaluation["xp"]
	# Perfect guards earn one crystal (参考 Stage Complete bonus column); the
	# surrounding reward-ledger duplicate check makes this idempotent per run.
	var crystals_awarded := 1 if perfect_victory else 0
	updated["crystals"] = int(updated.get("crystals", 0)) + crystals_awarded
	if crystals_awarded > 0:
		var crystal_stats: Dictionary = updated.get("stats", {})
		crystal_stats["crystals_earned"] = int(crystal_stats.get("crystals_earned", 0)) + crystals_awarded
	return {
		"ok": true,
		"profile": updated,
		"new_honors": evaluation["new_honors"],
		"honor_coins": evaluation["coins"],
		"honor_xp": evaluation["xp"],
		"crystals_awarded": crystals_awarded
	}


# Brings an arbitrary profile's honor levels and ledger up to what its stats
# already justify, paying the level rewards exactly once.  Used at startup to
# absorb legacy saves and to grant chains after stat backfills.
func reconcile(profile: Dictionary, config: Dictionary) -> Dictionary:
	var evaluation := evaluate(profile, config)
	var updated := profile.duplicate(true)
	updated["honors"] = evaluation["honors"]
	updated["honor_reward_ledger"] = evaluation["ledger"]
	if evaluation["coins"] > 0 or evaluation["xp"] > 0:
		updated["coins"] = int(updated.get("coins", 0)) + evaluation["coins"]
		updated["xp"] = int(updated.get("xp", 0)) + evaluation["xp"]
	return {"ok": true, "profile": updated, "honor_coins": evaluation["coins"], "honor_xp": evaluation["xp"], "new_honors": evaluation["new_honors"]}


func evaluate(profile: Dictionary, config: Dictionary) -> Dictionary:
	var stats: Dictionary = profile.get("stats", {})
	var honors_value: Dictionary = profile.get("honors", {})
	var honors := {}
	for honor_id in honors_value.keys():
		var value: Variant = honors_value[honor_id]
		honors[str(honor_id)] = (1 if bool(value) else 0) if value is bool else clampi(int(value), 0, 3)
	var ledger: Array = profile.get("honor_reward_ledger", []).duplicate()
	var new_honors: Array[String] = []
	var coins := 0
	var xp := 0
	for definition in config.get("honors", []):
		if not definition is Dictionary:
			continue
		var honor_id := str(definition.get("id", ""))
		if honor_id.is_empty():
			continue
		var achieved := honor_level(definition, stats)
		var reward_coins: Array = definition.get("reward_coins", [])
		var reward_xp: Array = definition.get("reward_xp", [])
		# A legacy single-level unlock has already paid its level-1 reward.
		var legacy_value: Variant = honors_value.get(honor_id, 0)
		if legacy_value is bool and bool(legacy_value) and not ledger.has(honor_id + ":1"):
			ledger.append(honor_id + ":1")
		var recorded := clampi(int(honors.get(honor_id, 0)), 0, 3)
		var level := maxi(recorded, achieved)
		for milestone_level in range(1, achieved + 1):
			var key := honor_id + ":" + str(milestone_level)
			if ledger.has(key):
				continue
			ledger.append(key)
			if milestone_level <= reward_coins.size():
				coins += int(reward_coins[milestone_level - 1])
			if milestone_level <= reward_xp.size():
				xp += int(reward_xp[milestone_level - 1])
			new_honors.append(key)
		honors[honor_id] = level
	return {"honors": honors, "ledger": ledger, "coins": coins, "xp": xp, "new_honors": new_honors}
