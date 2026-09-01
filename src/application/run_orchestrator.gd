class_name DefenderRunOrchestrator
extends RefCounted


func prepare(config: Dictionary, stage_id: String, seed: int, profile: Dictionary) -> Dictionary:
	var stage := _find_by_id(config.get("stages", []), stage_id)
	if stage.is_empty():
		return {"ok": false, "error_code": "unknown_stage", "field_path": "stage_id"}
	if int(stage.get("number", 1)) > int(profile.get("highest_unlocked_stage", 1)):
		return {"ok": false, "error_code": "stage_locked", "field_path": "stage_id"}
	return {
		"ok": true,
		"config": config.duplicate(true),
		"stage_id": stage_id,
		"seed": seed,
		"profile_snapshot": profile.duplicate(true)
	}


static func _find_by_id(items: Array, item_id: String) -> Dictionary:
	for item in items:
		if item is Dictionary and str(item.get("id", "")) == item_id:
			return item
	return {}

