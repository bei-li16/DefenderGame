class_name DefenderUpgradeService
extends RefCounted

func purchase(profile: Dictionary, config: Dictionary, upgrade_id: String) -> Dictionary:
	var definition := _find_upgrade(config.get("upgrades", []), upgrade_id)
	if definition.is_empty():
		return {"ok": false, "error_code": "unknown_upgrade", "profile": profile}
	var current_upgrades: Dictionary = profile.get("upgrades", {})
	var current_level := int(current_upgrades.get(upgrade_id, 0))
	if current_level >= int(definition.get("max_level", 0)):
		return {"ok": false, "error_code": "max_level", "profile": profile}
	for prerequisite in definition.get("prerequisites", []):
		if int(current_upgrades.get(str(prerequisite), 0)) < int(definition.get("prerequisite_levels", {}).get(str(prerequisite), 1)):
			return {"ok": false, "error_code": "missing_prerequisite", "profile": profile}
	var price := price_for_level(definition, current_level)
	var currency := str(definition.get("currency", "coins"))
	if currency != "coins" and currency != "crystals":
		return {"ok": false, "error_code": "unknown_currency", "price": price, "profile": profile}
	if int(profile.get(currency, 0)) < price:
		return {"ok": false, "error_code": "insufficient_" + currency, "price": price, "currency": currency, "profile": profile}
	var updated := profile.duplicate(true)
	updated[currency] = int(updated.get(currency, 0)) - price
	var updated_upgrades: Dictionary = updated.get("upgrades", {}).duplicate(true)
	updated_upgrades[upgrade_id] = current_level + 1
	updated["upgrades"] = updated_upgrades
	return {"ok": true, "price": price, "currency": currency, "new_level": current_level + 1, "profile": updated}


func apply_run_reward(profile: Dictionary, result: Dictionary) -> Dictionary:
	var run_id := str(result.get("run_id", ""))
	var reward_version := str(result.get("reward_version", ""))
	if run_id.is_empty() or reward_version.is_empty():
		return {"ok": false, "error_code": "missing_reward_identity", "profile": profile.duplicate(true)}
	var key := run_id + ":" + reward_version
	var ledger: Array = profile.get("reward_ledger", [])
	if ledger.has(key):
		return {"ok": true, "duplicate": true, "profile": profile.duplicate(true)}
	var updated := profile.duplicate(true)
	updated["coins"] = int(updated.get("coins", 0)) + int(result.get("coins", 0))
	updated["xp"] = int(updated.get("xp", 0)) + int(result.get("xp", 0))
	var updated_ledger: Array = updated.get("reward_ledger", []).duplicate()
	if not updated_ledger.has(key):
		updated_ledger.append(key)
	updated["reward_ledger"] = updated_ledger
	# Reward identities are permanent profile data. Never prune this ledger:
	# replaying an old result must remain a no-op after any number of runs.
	updated["reward_ledger_pruned"] = 0
	return {"ok": true, "duplicate": false, "profile": updated}


static func price_for_level(definition: Dictionary, current_level: int) -> int:
	var price := int(definition.get("base_cost", 0))
	var growth := int(definition.get("cost_growth_permille", 1000))
	# Growth 1000 documents "no growth": the price stays flat at every level.
	if growth <= 1000:
		return price
	for ignored in range(current_level):
		price = maxi(price + 1, int(round(float(price) * float(growth) / 1000.0)))
	return price


static func _find_upgrade(upgrades: Array, upgrade_id: String) -> Dictionary:
	for definition in upgrades:
		if definition is Dictionary and str(definition.get("id", "")) == upgrade_id:
			return definition
	return {}
