extends Node

const StageCatalog = preload("res://src/core/rules/stage_catalog.gd")
const ResearchCatalog = preload("res://src/core/rules/research_catalog.gd")

const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const AttackCatalog = preload("res://src/core/rules/attack_catalog.gd")

signal initialization_finished(ok: bool, error: Dictionary)
signal profile_changed(profile: Dictionary)
signal settings_changed(settings: Dictionary)

const ContentService = preload("res://src/application/content_service.gd")
const SaveService = preload("res://src/application/save_service.gd")
const UpgradeService = preload("res://src/application/upgrade_service.gd")
const HonorService = preload("res://src/application/honor_service.gd")
const ReplayService = preload("res://src/application/replay_service.gd")
const ProceduralAudio = preload("res://src/infrastructure/audio/procedural_audio.gd")
const DiagnosticService = preload("res://src/infrastructure/diagnostic_service.gd")

var content := ContentService.new()
var save_service := SaveService.new()
var upgrade_service := UpgradeService.new()
var honor_service := HonorService.new()
var replay_service := ReplayService.new()
var diagnostics := DiagnosticService.new()
var profile: Dictionary = {}
var settings: Dictionary = {}
var active_save_slot: int = 1
var _playtime_buffer: float = 0.0
var current_stage_id: String = "stage_001"
var current_seed: int = 1
var current_run_id: String = ""
var initialized_ok: bool = false
var initialization_error: Dictionary = {}
var audio: DefenderProceduralAudio


func _ready() -> void:
	# Scripted runs (headless tests and tools via --script) must never load or
	# write the player's real profile: isolate the default save directory and
	# start it fresh. The shipped game never runs with --script.
	if OS.get_cmdline_args().has("--script"):
		_reset_isolated_save_directory()
	else:
		save_service = SaveService.new(_default_save_directory())
	diagnostics.start_session(
		str(ProjectSettings.get_setting("application/config/version", "unknown")),
		str(Engine.get_version_info().get("string", "unknown"))
	)
	audio = ProceduralAudio.new()
	audio.name = "ProceduralAudio"
	add_child(audio)
	initialize()


func _notification(what: int) -> void:
	# Playtime accrued since the last flush must reach the active slot file even
	# when the game is closed straight from the window chrome.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_flush_playtime()


# Portable saves live next to the EXE (savedata/slot_N.json) so the folder can
# be copied between machines.  Editor runs keep them inside the project.
func _default_save_directory() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://savedata")
	return OS.get_executable_path().get_base_dir().path_join("savedata")


func _process(delta: float) -> void:
	if not initialized_ok:
		return
	_playtime_buffer += delta
	if _playtime_buffer >= 30.0:
		_flush_playtime()


# Merge buffered playtime into the active slot.  No profile_changed emission:
# the UI never needs a full rebuild for a silently ticking counter.
func _flush_playtime() -> Dictionary:
	var whole_seconds := int(_playtime_buffer)
	if whole_seconds <= 0:
		return {"ok": true, "skipped": true}
	_playtime_buffer -= float(whole_seconds)
	var updated := profile.duplicate(true)
	var stats: Dictionary = updated.get("stats", {})
	stats["playtime_seconds"] = int(stats.get("playtime_seconds", 0)) + whole_seconds
	updated["stats"] = stats
	var save_result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("playtime_save", save_result, "MainMenu")
		_playtime_buffer += float(whole_seconds)
		return save_result
	profile = updated
	return save_result


func _reset_isolated_save_directory() -> void:
	var directory_path := "user://automated-app-data"
	var absolute_path := ProjectSettings.globalize_path(directory_path)
	if DirAccess.dir_exists_absolute(absolute_path):
		var directory := DirAccess.open(absolute_path)
		if directory != null:
			for file_name in directory.get_files():
				directory.remove(file_name)
			for subdirectory_name in directory.get_directories():
				_remove_directory_recursive(absolute_path.path_join(subdirectory_name))
				directory.remove(subdirectory_name)
	save_service = SaveService.new(directory_path)


func _remove_directory_recursive(absolute_path: String) -> void:
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	for file_name in directory.get_files():
		directory.remove(file_name)
	for subdirectory_name in directory.get_directories():
		_remove_directory_recursive(absolute_path.path_join(subdirectory_name))
		directory.remove(subdirectory_name)


func initialize() -> void:
	initialized_ok = false
	initialization_error = {}
	# Show the app version in the window title so screenshots and bug reports
	# identify the running build without opening the diagnostics export.
	var window := get_window()
	if window != null:
		window.title = "%s v%s" % [ProjectSettings.get_setting("application/config/name", "Aegis of Ember"), save_service.APP_VERSION.trim_suffix("-windows")]
	var content_result := content.load_builtin()
	if not bool(content_result.get("ok", false)):
		initialization_error = content_result
		_record_failure("content_load", content_result, "Bootstrap")
		initialization_finished.emit(false, initialization_error)
		return
	diagnostics.update_config_version(content.rules.get("config_version", "unknown"))
	# Settings load first: the active save slot lives there and decides which
	# slot file the profile is read from.
	var settings_result := save_service.load_settings(_default_settings())
	if bool(settings_result.get("ok", false)):
		settings = settings_result["payload"]
	else:
		settings = _default_settings()
		var recovered_settings_save := save_service.save_settings(settings, int(content.rules["config_version"]))
		if not bool(recovered_settings_save.get("ok", false)):
			initialization_error = recovered_settings_save
			_record_failure("settings_recovery", recovered_settings_save, "Bootstrap")
			initialization_finished.emit(false, initialization_error)
			return
	active_save_slot = clampi(int(settings.get("active_save_slot", 1)), 1, SaveService.SAVE_SLOT_COUNT)
	var profile_result := save_service.load_profile_slot(active_save_slot, _default_profile())
	if not bool(profile_result.get("ok", false)):
		profile = profile_result.get("default_payload", _default_profile())
		initialization_error = profile_result
		_record_failure("profile_load", profile_result, "Bootstrap")
		initialization_finished.emit(false, initialization_error)
		return
	var loaded_profile: Dictionary = profile_result["payload"]
	profile = _normalize_profile(loaded_profile)
	# Honor chains: pay any levels the loaded stats already justify (legacy
	# saves and backfilled counters) before the next save refreshes them.
	var reconcile_result: Dictionary = honor_service.reconcile(profile, content.rules)
	profile = reconcile_result["profile"]
	if bool(profile_result.get("needs_save", false)) or bool(profile_result.get("migrated", false)) or profile != loaded_profile:
		var profile_save := save_service.save_profile_slot(active_save_slot, profile, int(content.rules["config_version"]))
		if not bool(profile_save.get("ok", false)):
			initialization_error = profile_save
			_record_failure("profile_save", profile_save, "Bootstrap")
			initialization_finished.emit(false, initialization_error)
			return
	if bool(settings_result.get("needs_save", false)):
		var default_settings_save := save_service.save_settings(settings, int(content.rules["config_version"]))
		if not bool(default_settings_save.get("ok", false)):
			initialization_error = default_settings_save
			_record_failure("settings_save", default_settings_save, "Bootstrap")
			initialization_finished.emit(false, initialization_error)
			return
	initialized_ok = true
	_apply_settings()
	diagnostics.record("initialization_complete", "", "MainMenu")
	initialization_finished.emit(true, {})


func start_new_profile() -> Dictionary:
	if content.rules.is_empty():
		return {"ok": false, "error_code": "content_unavailable", "field_path": "content/config"}
	# Build and persist a candidate first. A failed write must leave the active
	# in-memory profile untouched; the recovery UI can then safely offer retry or
	# exit without silently discarding the player's current session.
	var candidate := _default_profile()
	var result := save_service.save_profile_slot(active_save_slot, candidate, int(content.rules.get("config_version", 0)))
	if not bool(result.get("ok", false)):
		initialization_error = result
		_record_failure("new_profile", result, "Bootstrap")
		return result
	profile = candidate
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



func start_stage(stage_id: String, run_seed: int = 0) -> Dictionary:
	# Keep the unlock check at the application boundary as well as in the run
	# orchestrator. Menu buttons are not the only callers (result actions,
	# automation and integrations can invoke this method directly), so a locked
	# stage must never cause a scene transition or mutate run identity.
	if not initialized_ok or content.rules.is_empty():
		var unavailable := {"ok": false, "error_code": "content_unavailable", "field_path": "content/config"}
		_record_failure("start_stage", unavailable, "MainMenu")
		return unavailable
	var stage := content.find_by_id("stages", stage_id)
	if stage.is_empty():
		var unknown := {"ok": false, "error_code": "unknown_stage", "field_path": "stage_id"}
		_record_failure("start_stage", unknown, "MainMenu")
		return unknown
	var stage_number := int(stage.get("number", 0))
	var highest_unlocked := int(profile.get("highest_unlocked_stage", 1))
	if stage_number < 1 or stage_number > highest_unlocked:
		var locked := {"ok": false, "error_code": "stage_locked", "field_path": "stage_id", "stage_number": stage_number, "highest_unlocked_stage": highest_unlocked}
		_record_failure("start_stage", locked, "MainMenu")
		return locked
	current_stage_id = stage_id
	current_seed = run_seed if run_seed != 0 else int(Time.get_unix_time_from_system()) & 0x7fffffff
	current_run_id = Crypto.new().generate_random_bytes(16).hex_encode()
	diagnostics.record("run_start", "", "Gameplay", {"stage_id": stage_id})
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")
	return {"ok": true, "stage_id": current_stage_id, "seed": current_seed, "run_id": current_run_id}


func return_to_menu() -> void:
	_flush_playtime()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func save_slot_summaries() -> Array:
	return save_service.list_slot_summaries()


func save_directory_display() -> String:
	return ProjectSettings.globalize_path(save_service.base_directory)


func open_save_directory() -> Dictionary:
	var directory := save_directory_display()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error_code": "directory_create_failed", "field_path": directory}
	OS.shell_show_in_file_manager(directory, true)
	return {"ok": true, "path": directory}


# Switch the active save: the current slot's pending playtime is flushed first,
# the target profile is loaded from its own file (a fresh slot immediately
# materializes as a new save), and only then does the selection commit.  A
# failed settings write leaves the old slot active.
func switch_save_slot(slot_id: int) -> Dictionary:
	if not initialized_ok or content.rules.is_empty():
		var unavailable := {"ok": false, "error_code": "content_unavailable", "field_path": "content/config"}
		_record_failure("switch_save_slot", unavailable, "MainMenu")
		return unavailable
	var slot := clampi(int(slot_id), 1, SaveService.SAVE_SLOT_COUNT)
	if slot == active_save_slot:
		return {"ok": true, "already_active": true, "profile": profile.duplicate(true)}
	_flush_playtime()
	var load_result := save_service.load_profile_slot(slot, _default_profile())
	if not bool(load_result.get("ok", false)):
		_record_failure("slot_load", load_result, "MainMenu")
		return load_result
	var new_profile := _normalize_profile(load_result["payload"])
	# Legacy slots also need the honor/crystal reconciliation the startup path
	# applies (one-time crystal top-up for the v1.2.0 magic research economy).
	new_profile = honor_service.reconcile(new_profile, content.rules)["profile"]
	var slot_save := save_service.save_profile_slot(slot, new_profile, int(content.rules["config_version"]))
	if not bool(slot_save.get("ok", false)):
		_record_failure("slot_save", slot_save, "MainMenu")
		return slot_save
	var settings_save := update_setting("active_save_slot", slot)
	if not bool(settings_save.get("ok", false)):
		_record_failure("slot_select_save", settings_save, "MainMenu")
		return settings_save
	active_save_slot = slot
	profile = new_profile
	profile_changed.emit(profile.duplicate(true))
	diagnostics.record("save_slot_switched", "", "MainMenu", {"slot": slot})
	return {"ok": true, "slot": slot, "profile": profile.duplicate(true)}


func settle_run(result: Dictionary) -> Dictionary:
	_flush_playtime()
	var reward_result := upgrade_service.apply_run_reward(profile, result)
	if not bool(reward_result.get("ok", false)):
		_record_failure("settle_reward", reward_result, "Gameplay")
		return reward_result
	if bool(reward_result.get("duplicate", false)):
		return reward_result
	var updated: Dictionary = reward_result["profile"].duplicate(true)
	var honor_result := honor_service.apply_result(updated, result, content.rules)
	if not bool(honor_result.get("ok", false)):
		_record_failure("settle_honors", honor_result, "Gameplay")
		return honor_result
	updated = honor_result["profile"].duplicate(true)
	var stage_number := int(result.get("stage_number", 1))
	if str(result.get("status", "")) == "victory":
		var unlocked_next := stage_number + 1 if StageCatalog.has_next(content.rules, stage_number) else stage_number
		updated["highest_unlocked_stage"] = maxi(int(updated.get("highest_unlocked_stage", 1)), unlocked_next)
	updated = _ensure_equipped_weapon_unlocked(updated)
	var best_results: Dictionary = updated.get("best_results", {}).duplicate(true)
	var stage_id := str(result.get("stage_id", ""))
	var previous: Dictionary = best_results.get(stage_id, {})
	if previous.is_empty() or int(result.get("wall_percent", 0)) > int(previous.get("wall_percent", -1)):
		best_results[stage_id] = {
			"status": result.get("status", ""),
			"kills": result.get("kills", 0),
			"wall_percent": result.get("wall_percent", 0),
			"tick": result.get("tick", 0),
			"weapon_id": result.get("weapon_id", "basic_bow")
		}
	updated["best_results"] = best_results
	var save_result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("settle_save", save_result, "Gameplay")
		var failure := save_result.duplicate(true)
		failure["profile"] = profile.duplicate(true)
		failure["operation"] = "settle_run"
		return failure
	profile = updated
	reward_result["profile"] = profile.duplicate(true)
	reward_result["save"] = save_result
	reward_result["new_honors"] = honor_result.get("new_honors", [])
	reward_result["honor_coins"] = honor_result.get("honor_coins", 0)
	reward_result["honor_xp"] = honor_result.get("honor_xp", 0)
	reward_result["crystals_awarded"] = honor_result.get("crystals_awarded", 0)
	profile_changed.emit(profile.duplicate(true))
	diagnostics.record("run_settled", "", "Gameplay", {"stage_id": stage_id, "status": str(result.get("status", ""))})
	return reward_result


func purchase_upgrade(upgrade_id: String) -> Dictionary:
	var result := upgrade_service.purchase(profile, content.rules, upgrade_id)
	if bool(result.get("ok", false)):
		var updated: Dictionary = result["profile"]
		# Big Spender tracks lifetime coin spending; crystal research has its own counter.
		var updated_stats: Dictionary = updated.get("stats", {}).duplicate(true)
		if str(result.get("currency", "coins")) == "crystals":
			updated_stats["crystals_spent"] = int(updated_stats.get("crystals_spent", 0)) + int(result.get("price", 0))
		else:
			updated_stats["coins_spent"] = int(updated_stats.get("coins_spent", 0)) + int(result.get("price", 0))
		updated["stats"] = updated_stats
		var upgrade := content.find_by_id("upgrades", upgrade_id)
		var skill_id := str(upgrade.get("skill_ref", ""))
		# Learning an advanced spell equips it in its elemental slot. Subsequent
		# upgrades preserve the player's choice of a cheaper spell in that slot.
		if not skill_id.is_empty() and int(result.get("new_level", 0)) == 1:
			var equipped := SkillCatalog.loadout(content.rules, updated)
			equipped[str(SkillCatalog.find(content.rules, skill_id).get("element", ""))] = skill_id
			updated["equipped_skills"] = equipped
		# Weapon research: buying an "unlock_<weapon>" node grants the bow.
		if upgrade_id.begins_with("unlock_"):
			var weapon_id := upgrade_id.trim_prefix("unlock_")
			var unlocked: Array = updated.get("unlocked_weapons", []).duplicate()
			if not unlocked.has(weapon_id):
				unlocked.append(weapon_id)
			updated["unlocked_weapons"] = unlocked
		var save_result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
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


func select_weapon(weapon_id: String) -> Dictionary:
	var weapon := content.find_by_id("weapons", weapon_id)
	if weapon.is_empty():
		return {"ok": false, "error_code": "unknown_weapon", "profile": profile.duplicate(true)}
	var unlocked: Array = profile.get("unlocked_weapons", [])
	if not unlocked.has(weapon_id):
		return {"ok": false, "error_code": "weapon_locked", "profile": profile.duplicate(true)}
	var updated := profile.duplicate(true)
	updated["current_weapon_id"] = weapon_id
	var save_result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("weapon_save", save_result, "MainMenu")
		var failure := save_result.duplicate(true)
		failure["profile"] = profile.duplicate(true)
		failure["operation"] = "select_weapon"
		return failure
	profile = updated
	profile_changed.emit(profile.duplicate(true))
	return {"ok": true, "weapon_id": weapon_id, "profile": profile.duplicate(true), "save": save_result}


func select_skill(skill_id: String) -> Dictionary:
	if not SkillCatalog.available(content.rules, profile, skill_id):
		return {"ok": false, "error_code": "skill_locked"}
	var updated := profile.duplicate(true)
	var equipped := SkillCatalog.loadout(content.rules, updated)
	equipped[str(SkillCatalog.find(content.rules, skill_id).get("element", ""))] = skill_id
	updated["equipped_skills"] = equipped
	var saved := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
	if not bool(saved.get("ok", false)):
		_record_failure("skill_save", saved, "MainMenu")
		return saved
	profile = updated
	profile_changed.emit(profile.duplicate(true))
	return {"ok": true, "profile": profile.duplicate(true)}


func complete_tutorial() -> Dictionary:
	var updated := profile.duplicate(true)
	updated["tutorial_complete"] = true
	var result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules.get("config_version", 0)))
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


func update_profile_field(key: String, value: Variant) -> Dictionary:
	# Save-first transaction, mirroring update_setting: the in-memory profile
	# only moves forward when persistence succeeded.
	var previous := profile.duplicate(true)
	var updated := profile.duplicate(true)
	updated[key] = value
	var save_result := save_service.save_profile_slot(active_save_slot, updated, int(content.rules["config_version"]))
	if not bool(save_result.get("ok", false)):
		_record_failure("profile_field_save", save_result, "MainMenu")
		profile = previous
		return save_result
	profile = updated
	profile_changed.emit(profile.duplicate(true))
	return save_result


func export_diagnostics() -> Dictionary:
	return diagnostics.export_zip()


func export_debug_replay(record: Dictionary) -> Dictionary:
	if not OS.is_debug_build():
		return {"ok": false, "error_code": "debug_only"}
	var result := replay_service.export_record(record)
	if not bool(result.get("ok", false)):
		_record_failure("replay_export", result, "Gameplay")
	return result


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
	var upgrades: Dictionary = {}
	for definition in content.rules.get("upgrades", []):
		if definition is Dictionary:
			upgrades[str(definition.get("id", ""))] = 0
	return {
		"install_id": bytes.hex_encode(),
		"player_name": "",
		"coins": 180,
		"xp": 0,
		"crystals": 0,
		"highest_unlocked_stage": 1,
		"current_weapon_id": "basic_bow",
		"unlocked_weapons": ["basic_bow"],
		"equipped_skills": SkillCatalog.loadout(content.rules, {}),
		"upgrades": upgrades,
		"best_results": {},
		"reward_ledger": [],
		"reward_ledger_pruned": 0,
		"stats": {"total_kills": 0, "stages_completed": 0, "battles_won": 0, "battles_lost": 0, "coins_spent": 0, "crystals_spent": 0, "fire_casts": 0, "ice_casts": 0, "lightning_casts": 0, "crystals_earned": 0, "bosses_defeated": 0, "perfect_stages": 0, "spells_cast": 0, "total_coins_earned": 0, "highest_stage_reached": 0, "weapons_used": []},
		"honors": {},
		"honor_reward_ledger": [],
		"tutorial_complete": false
	}


func _normalize_profile(source: Dictionary) -> Dictionary:
	var normalized := AttackCatalog.normalize_profile(source)
	var defaults := _default_profile()
	for key in defaults.keys():
		if not normalized.has(key):
			normalized[key] = defaults[key].duplicate(true) if defaults[key] is Array or defaults[key] is Dictionary else defaults[key]
	var upgrades: Dictionary = normalized.get("upgrades", {}).duplicate(true)
	for definition in content.rules.get("upgrades", []):
		if definition is Dictionary:
			var upgrade_id := str(definition.get("id", ""))
			upgrades[upgrade_id] = ResearchCatalog.normalize_level(definition, int(upgrades.get(upgrade_id, 0)))
	normalized["upgrades"] = upgrades
	normalized["equipped_skills"] = SkillCatalog.loadout(content.rules, normalized)
	var highest := clampi(int(normalized.get("highest_unlocked_stage", 1)), 1, StageCatalog.MAX_STAGE_NUMBER)
	# Old releases capped a completed stage-30 save at 30. Recover its next
	# unlock from recorded victories, without inventing wins or paying rewards.
	for stage_id in normalized.get("best_results", {}):
		var record: Variant = normalized["best_results"][stage_id]
		var number := StageCatalog.number_from_id(str(stage_id))
		if record is Dictionary and str(record.get("status", "")) == "victory" and StageCatalog.has_next(content.rules, number) and number > 0:
			highest = maxi(highest, number + 1)
	normalized["highest_unlocked_stage"] = highest
	normalized = _ensure_equipped_weapon_unlocked(normalized)
	var stats: Dictionary = normalized.get("stats", {}).duplicate(true)
	for stat_key in defaults["stats"].keys():
		if not stats.has(stat_key):
			stats[stat_key] = defaults["stats"][stat_key].duplicate(true) if defaults["stats"][stat_key] is Array or defaults["stats"][stat_key] is Dictionary else defaults["stats"][stat_key]
	normalized["stats"] = stats
	return normalized


# Weapons are unlocked through the weapons research page now; stage progress
# no longer grants them.  Only keep the equipped bow valid (a legacy profile
# may still list a bow its slot no longer considers unlocked).
func _ensure_equipped_weapon_unlocked(source: Dictionary) -> Dictionary:
	var updated := source.duplicate(true)
	var unlocked: Array = updated.get("unlocked_weapons", []).duplicate()
	if not unlocked.has("basic_bow"):
		unlocked.append("basic_bow")
	updated["unlocked_weapons"] = unlocked
	if not unlocked.has(str(updated.get("current_weapon_id", "basic_bow"))):
		updated["current_weapon_id"] = "basic_bow"
	return updated


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
		"auto_fire": true,
		"screen_shake": true,
		"ui_scale": 1.0,
		# Machine-level preference: which portable slot file the game loads.
		"active_save_slot": 1
	}
