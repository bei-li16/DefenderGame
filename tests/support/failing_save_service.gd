extends "res://src/application/save_service.gd"


func save_profile_slot(_slot_id: int, _payload: Dictionary, _config_version: int) -> Dictionary:
	return {"ok": false, "error_code": "simulated_write_failure", "field_path": "user://test/slot_1.json"}


func save_settings(_payload: Dictionary, _config_version: int) -> Dictionary:
	return {"ok": false, "error_code": "simulated_write_failure", "field_path": "user://test/settings.json"}
