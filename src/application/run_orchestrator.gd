class_name DefenderRunOrchestrator
extends RefCounted

const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")

func prepare(config: Dictionary, stage_id: String, seed: int, profile: Dictionary) -> Dictionary:
	var stage := StageCatalog.describe(config, StageCatalog.number_from_id(stage_id))
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
