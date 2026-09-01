extends Node

signal initialization_finished(ok: bool, error: Dictionary)
signal profile_changed(profile: Dictionary)
signal settings_changed(settings: Dictionary)

const ContentService = preload("res://src/application/content_service.gd")
const SaveService = preload("res://src/application/save_service.gd")
const UpgradeService = preload("res://src/application/upgrade_service.gd")
const ProceduralAudio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const DiagnosticService = preload("res://src/infrastructure/diagnostic_service.gd")

var content := ContentService.new()
var save_service := SaveService.new()
var upgrade_service := UpgradeService.new()
var diagnostics := DiagnosticService.new()
var profile: Dictionary = {}
var settings: Dictionary = {}
var current_stage_id: String = "stage_001"
var current_seed: int = 1
var current_run_id: String = ""
var initialized_ok: bool = false
var initialization_error: Dictionary = {}
var audio: DefenderProceduralAudio


func _ready() -> void:
	diagnostics.start_session(
		str(ProjectSettings.get_setting("application/config/version", "unknown")),
		str(Engine.get_version_info().get("string", "unknown"))
	)
	audio = ProceduralAudio.new()
	audio.name = "ProceduralAudio"
	add_child(audio)
	initialize()


func initialize() -> void:
	initialized_ok = false
	initialization_error = {}
	var content_result := content.load_builtin()
	if not bool(content_result.get("ok", false)):
		initialization_error = content_result
		_record_failure("content_load", content_result, "Bootstrap")
		initialization_finished.emit(false, initialization_error)
		return
	diagnostics.update_config_version(content.rules.get("config_version", "unknown"))
	var profile_result := save_service.load_profile(_default_profile())
	if not bool(profile_result.get("ok", false)):
		profile = profile_result.get("default_payload", _default_profile())
		initialization_error = profile_result
		_record_failure("profile_load", profile_result, "Bootstrap")
		initialization_finished.emit(false, initialization_error)
		return
	profile = profile_result["payload"]
	if bool(profile_result.get("needs_save", false)) or bool(profile_result.get("migrated", false)):
		var profile_save := save_service.save_profile(profile, int(content.rules["config_version"]))
		if not bool(profile_save.get("ok", false)):
			initialization_error = profile_save
			_record_failure("profile_save", profile_save, "Bootstrap")
			initialization_finished.emit(false, initialization_error)
			return
	var settings_result := save_service.load_settings(_default_settings())
	if bool(settings_result.get("ok", false)):
		settings = settings_result["payload"]
		if bool(settings_result.get("needs_save", false)):
			var default_settings_save := save_service.save_settings(settings, int(content.rules["config_version"]))
			if not bool(default_settings_save.get("ok", false)):
				initialization_error = default_settings_save
				_record_failure("settings_save", default_settings_save, "Bootstrap")
				initialization_finished.emit(false, initialization_error)
				return
	else:
		settings = _default_settings()
		var recovered_settings_save := save_service.save_settings(settings, int(content.rules["config_version"]))
		if not bool(recovered_settings_save.get("ok", false)):
			initialization_error = recovered_settings_save
			_record_failure("settings_recovery", recovered_settings_save, "Bootstrap")
			initialization_finished.emit(false, initialization_error)
			return
	initialized_ok = true
	_apply_settings()
	diagnostics.record("initialization_complete", "", "MainMenu")
	initialization_finished.emit(true, {})


func start_new_profile() -> Dictionary:
	if content.rules.is_empty():
		return {"ok": false, "error_code": "content_unavailable", "field_path": "content/config"}
	profile = _default_profile()
	var result := save_service.save_profile(profile, int(content.rules.get("config_version", 0)))
	if not bool(result.get("ok", false)):
		initialization_error = result
		_record_failure("new_profile", result, "Bootstrap")
		return result
	if settings.is_empty():
		settings = _default_settings()
		var settings_save := save_service.save_settings(settings, int(content.rules.get("config_version", 0)))
		if not bool(settings_save.get("ok", false)):
			initialization_error = settings_save
			_record_failure("settings_save", settings_save, "Bootstrap")
			return settings_save
	initialized_ok = true
	initialization_error = {}
	_apply_settings()
	profile_changed.emit(profile.duplicate(true))
	initialization_finished.emit(true, {})
	return {"ok": true}


func text(key: String) -> String:
	return content.text(key, str(settings.get("language", "zh_CN")))


func start_stage(stage_id: String, run_seed: int = 0) -> void:
	current_stage_id = stage_id
	current_seed = run_seed if run_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff
	current_run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	diagnostics.record("run_start", "", "Gameplay", {"stage_id": stage_id})
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


func return_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func settle_run(result: Dictionary) -> Dictionary:
	var reward_result := upgrade_service.apply_run_reward(profile, result)
	if not bool(reward_result.get("ok", false)):
		_record_failure("settle_reward", reward_result, "Gameplay")
		return reward_result
	if bool(reward_result.get("duplicate", false)):
		return reward_result
	var updated: Dictionary = reward_result["profile"].duplicate(true)
	var stage_number := int(result.get("stage_number", 1))
	if str(result.get("status", "")) == "victory":
		updated["highest_unlocked_stage"] = mini(10, maxi(int(updated.get("highest_unlocked_stage", 1)), stage_number + 1))
	var best_results: Dictionary = updated.get("best_results", {}).duplicate(true)
	var stage_id := str(result.get("stage_id", ""))
	var previous: Dictionary = best_results.get(stage_id, {})
	if previous.is_empty() or int(result.get("wall_percent", 0)) > int(previous.get("wall_percent", -1)):
		best_results[stage_id] = {
			"status": result.get("status", ""),
			"kills": result.get("kills", 0),
			"wall_percent": result.get("wall_percent", 0),
			"tick": result.get("tick", 0)
		}
	updated["best_results"] = best_results
	var save_result := save_service.save_profile(updated, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("settle_save", save_result, "Gameplay")
		var failure := save_result.duplicate(true)
		failure["profile"] = profile.duplicate(true)
		failure["operation"] = "settle_run"
		return failure
	profile = updated
	reward_result["profile"] = profile.duplicate(true)
	reward_result["save"] = save_result
	profile_changed.emit(profile.duplicate(true))
	diagnostics.record("run_settled", "", "Gameplay", {"stage_id": stage_id, "status": str(result.get("status", ""))})
	return reward_result


func purchase_upgrade(upgrade_id: String) -> Dictionary:
	var result := upgrade_service.purchase(profile, content.rules, upgrade_id)
	if bool(result.get("ok", false)):
		var updated: Dictionary = result["profile"]
		var save_result := save_service.save_profile(updated, int(content.rules["config_version"]))
		if not bool(save_result.get("ok", false)):
			_record_failure("upgrade_save", save_result, "MainMenu")
			var failure := save_result.duplicate(true)
			failure["profile"] = profile.duplicate(true)
			failure["operation"] = "purchase_upgrade"
			return failure
		profile = updated
		result["profile"] = profile.duplicate(true)
		result["save"] = save_result
		profile_changed.emit(profile.duplicate(true))
	return result


func complete_tutorial() -> Dictionary:
	var updated := profile.duplicate(true)
	updated["tutorial_complete"] = true
	var result := save_service.save_profile(updated, int(content.rules.get("config_version", 0)))
	if bool(result.get("ok", false)):
		profile = updated
		profile_changed.emit(profile.duplicate(true))
	else:
		_record_failure("tutorial_save", result, "Tutorial")
	return result


func update_setting(key: String, value: Variant) -> Dictionary:
	var previous := settings.duplicate(true)
	var updated := settings.duplicate(true)
	updated[key] = value
	settings = updated
	_apply_settings()
	var save_result := save_service.save_settings(settings, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("settings_save", save_result, "Settings")
		settings = previous
		_apply_settings()
		return save_result
	settings_changed.emit(settings.duplicate(true))
	return save_result


func export_diagnostics() -> Dictionary:
	return diagnostics.export_zip()


func _record_failure(operation: String, result: Dictionary, scene_name: String) -> void:
	diagnostics.record("operation_failed", str(result.get("error_code", "unknown")), scene_name, {"operation": operation})


func _apply_settings() -> void:
	var master_db := linear_to_db(clampf(float(settings.get("master_volume", 0.8)), 0.0, 1.0))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_db)
	if audio != null:
		audio.set_music_volume(float(settings.get("music_volume", 0.65)))
	if not DisplayServer.get_name().contains("headless"):
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if bool(settings.get("fullscreen", false)) else DisplayServer.WINDOW_MODE_WINDOWED
		DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, bool(settings.get("borderless", false)) and mode == DisplayServer.WINDOW_MODE_WINDOWED)
		if mode == DisplayServer.WINDOW_MODE_WINDOWED:
			var resolution_parts := str(settings.get("resolution", "1280x720")).split("x")
			if resolution_parts.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(resolution_parts[0]), int(resolution_parts[1])))
	get_tree().root.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), 0.85, 1.25)


func _default_profile() -> Dictionary:
	var bytes := Crypto.new().generate_random_bytes(16)
	return {
		"install_id": bytes.hex_encode(),
		"coins": 180,
		"xp": 0,
		"crystals": 0,
		"highest_unlocked_stage": 1,
		"upgrades": {"strength": 0, "agility": 0, "fire_mastery": 0, "ice_mastery": 0, "lightning_mastery": 0},
		"best_results": {},
		"reward_ledger": [],
		"tutorial_complete": false
	}


func _default_settings() -> Dictionary:
	return {
		"master_volume": 0.8,
		"music_volume": 0.65,
		"sfx_volume": 0.85,
		"language": "zh_CN",
		"fullscreen": false,
		"borderless": false,
		"resolution": "1920x1080",
		"quality": "medium",
		"aim_assist": true,
		"screen_shake": true,
		"ui_scale": 1.0
	}
