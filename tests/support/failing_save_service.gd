extends "res://src/application/save_service.gd"


func save_profile(_payload: Dictionary, _config_version: int) -> Dictionary:
	return {"ok": false, "error_code": "simulated_write_failure", "field_path": "user://test/profile.json"}


func save_settings(_payload: Dictionary, _config_version: int) -> Dictionary:
	return {"ok": false, "error_code": "simulated_write_failure", "field_path": "user://test/settings.json"}
