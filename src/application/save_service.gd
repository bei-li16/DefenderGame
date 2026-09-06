class_name DefenderSaveService
extends RefCounted

const CURRENT_SCHEMA_VERSION := 5
const APP_VERSION := "1.0.6-windows"

var base_directory: String


func _init(directory: String = "user://") -> void:
	base_directory = directory
	while base_directory.ends_with("//") and not base_directory.ends_with("://"):
		base_directory = base_directory.trim_suffix("/")


func save_profile(payload: Dictionary, config_version: int) -> Dictionary:
	return _save_envelope("profile.json", payload, config_version)


func load_profile(default_payload: Dictionary) -> Dictionary:
	return _load_envelope("profile.json", default_payload)


func save_settings(payload: Dictionary, config_version: int) -> Dictionary:
	return _save_envelope("settings.json", payload, config_version)


func load_settings(default_payload: Dictionary) -> Dictionary:
	return _load_envelope("settings.json", default_payload)


func _save_envelope(file_name: String, payload: Dictionary, config_version: int) -> Dictionary:
	var directory_result := _ensure_directory()
	if not bool(directory_result.get("ok", false)):
		return directory_result
	var main_path := _path(file_name)
	var temporary_path := main_path + ".tmp"
	var backup_path := main_path + ".bak"
	var envelope := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"app_version": APP_VERSION,
		"config_version": config_version,
		"payload": payload.duplicate(true),
		"payload_hash": _payload_hash(payload),
		"saved_at_utc": Time.get_datetime_string_from_system(true)
	}
	var write_result := _write_json(temporary_path, envelope)
	if not bool(write_result.get("ok", false)):
		return write_result
	var verification := _read_and_validate(temporary_path)
	if not bool(verification.get("ok", false)):
		return {"ok": false, "error_code": "temporary_verification_failed", "field_path": temporary_path}
	if FileAccess.file_exists(main_path):
		var current_main := _read_and_validate(main_path)
		if bool(current_main.get("ok", false)):
			if FileAccess.file_exists(backup_path):
				# A stale/corrupt backup must not disappear silently when the next
				# valid save rotates the main file.  Preserve it beside the save so
				# support tooling can still diagnose the previous failure.
				var existing_backup := _read_and_validate(backup_path)
				if not bool(existing_backup.get("ok", false)):
					_preserve_corrupt(backup_path)
				var remove_backup_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
				if remove_backup_error != OK:
					return {"ok": false, "error_code": "backup_remove_failed", "field_path": backup_path}
			var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(main_path), ProjectSettings.globalize_path(backup_path))
			if backup_error != OK:
				return {"ok": false, "error_code": "backup_replace_failed", "field_path": main_path}
		else:
			_preserve_corrupt(main_path)
			var remove_corrupt_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(main_path))
			if remove_corrupt_error != OK:
				return {"ok": false, "error_code": "corrupt_main_remove_failed", "field_path": main_path}
	var replace_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(main_path))
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(main_path))
		return {"ok": false, "error_code": "main_replace_failed", "field_path": main_path}
	var final_verification := _read_and_validate(main_path)
	if not bool(final_verification.get("ok", false)):
		_preserve_corrupt(main_path)
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(main_path))
		return {"ok": false, "error_code": "final_verification_failed", "field_path": main_path}
	return {"ok": true, "path": main_path, "payload_hash": envelope["payload_hash"]}


func _load_envelope(file_name: String, default_payload: Dictionary) -> Dictionary:
	var main_path := _path(file_name)
	var backup_path := main_path + ".bak"
	if not FileAccess.file_exists(main_path):
		if FileAccess.file_exists(backup_path):
			var backup_only := _read_and_validate(backup_path)
			if bool(backup_only.get("ok", false)):
				return _migrate_loaded(backup_only["envelope"], "backup", true, default_payload)
		return {"ok": true, "payload": default_payload.duplicate(true), "source": "default", "needs_save": true}
	var main_result := _read_and_validate(main_path)
	if bool(main_result.get("ok", false)):
		var migrated_main := _migrate_loaded(main_result["envelope"], "main", false, default_payload)
		if bool(migrated_main.get("ok", false)):
			return migrated_main
		if FileAccess.file_exists(backup_path):
			var migration_backup := _read_and_validate(backup_path)
			if bool(migration_backup.get("ok", false)):
				var migrated_backup := _migrate_loaded(migration_backup["envelope"], "backup", true, default_payload)
				if bool(migrated_backup.get("ok", false)):
					return migrated_backup
		migrated_main["default_payload"] = default_payload.duplicate(true)
		return migrated_main
	_preserve_corrupt(main_path)
	if FileAccess.file_exists(backup_path):
		var backup_result := _read_and_validate(backup_path)
		if bool(backup_result.get("ok", false)):
			return _migrate_loaded(backup_result["envelope"], "backup", true, default_payload)
		# Keep a diagnostic copy of a bad backup as well.  The main file may be
		# recoverable on a later launch, and losing the backup would erase the
		# only evidence of the second failure.
		_preserve_corrupt(backup_path)
	return {
		"ok": false,
		"error_code": "no_valid_save",
		"field_path": main_path,
		"default_payload": default_payload.duplicate(true)
	}


func _migrate_loaded(envelope: Dictionary, source: String, recovered: bool, default_payload: Dictionary) -> Dictionary:
	var migration := migrate_envelope(envelope)
	if not bool(migration.get("ok", false)):
		return migration
	var migrated_envelope: Dictionary = migration["envelope"]
	var payload: Dictionary = migrated_envelope.get("payload", {}).duplicate(true)
	var defaults_added := false
	for key in default_payload.keys():
		if not payload.has(key):
			payload[key] = default_payload[key].duplicate(true) if default_payload[key] is Array or default_payload[key] is Dictionary else default_payload[key]
			defaults_added = true
	if defaults_added:
		migrated_envelope["payload"] = payload
		migrated_envelope["payload_hash"] = _payload_hash(payload)
	return {
		"ok": true,
		"payload": payload,
		"source": source,
		"recovered": recovered,
		"migrated": bool(migration.get("migrated", false)),
		"needs_save": defaults_added or recovered,
		"schema_version": CURRENT_SCHEMA_VERSION
	}


static func migrate_envelope(source_envelope: Dictionary) -> Dictionary:
	var envelope := source_envelope.duplicate(true)
	var version := int(envelope.get("schema_version", 1))
	if version < 1 or version > CURRENT_SCHEMA_VERSION:
		return {"ok": false, "error_code": "unsupported_schema", "field_path": "schema_version"}
	var migrated := false
	while version < CURRENT_SCHEMA_VERSION:
		match version:
			1:
				var payload_v1: Dictionary = envelope.get("payload", {})
				if not payload_v1.has("reward_ledger"):
					payload_v1["reward_ledger"] = []
				if not payload_v1.has("best_results"):
					payload_v1["best_results"] = {}
				envelope["payload"] = payload_v1
				version = 2
			2:
				var payload_v2: Dictionary = envelope.get("payload", {})
				if not payload_v2.has("crystals"):
					payload_v2["crystals"] = 0
				if not payload_v2.has("tutorial_complete"):
					payload_v2["tutorial_complete"] = false
				envelope["payload"] = payload_v2
				version = 3
			3:
				var payload_v3: Dictionary = envelope.get("payload", {})
				if payload_v3.has("coins") or payload_v3.has("upgrades"):
					if not payload_v3.has("current_weapon_id"):
						payload_v3["current_weapon_id"] = "basic_bow"
					if not payload_v3.has("unlocked_weapons"):
						payload_v3["unlocked_weapons"] = ["basic_bow"]
					if not payload_v3.has("stats"):
						payload_v3["stats"] = {}
					if not payload_v3.has("honors"):
						payload_v3["honors"] = {}
					if not payload_v3.has("honor_reward_ledger"):
						payload_v3["honor_reward_ledger"] = []
					envelope["payload"] = payload_v3
				version = 4
			4:
				# v5 backfills the Status battle record and the display name.
				# battles_won is honestly approximated by stages_completed: every
				# completed stage was a victory, defeats were never recorded.
				var payload_v4: Dictionary = envelope.get("payload", {})
				if not payload_v4.has("player_name"):
					payload_v4["player_name"] = ""
				var stats_v4: Dictionary = payload_v4.get("stats", {})
				if not stats_v4.has("battles_won"):
					stats_v4["battles_won"] = int(stats_v4.get("stages_completed", 0))
				if not stats_v4.has("battles_lost"):
					stats_v4["battles_lost"] = 0
				payload_v4["stats"] = stats_v4
				envelope["payload"] = payload_v4
				version = 5
		envelope["schema_version"] = version
		migrated = true
	var payload: Dictionary = envelope.get("payload", {})
	envelope["payload_hash"] = _payload_hash(payload)
	return {"ok": true, "envelope": envelope, "migrated": migrated}


func _read_and_validate(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error_code": "file_missing", "field_path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error_code": "file_open_failed", "field_path": path}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {"ok": false, "error_code": "json_parse_failed", "field_path": path}
	var envelope: Dictionary = parser.data
	if not envelope.has("payload") or not envelope["payload"] is Dictionary:
		return {"ok": false, "error_code": "missing_payload", "field_path": path}
	# Early schema files (v1-v3) shipped before payload hashes were added.  They
	# remain migratable when the hash is absent, while current-schema files still
	# require an integrity hash.  If a legacy file does contain a hash, verify it
	# just like a current file so a tampered envelope is never accepted.
	var schema_version := int(envelope.get("schema_version", 1))
	if schema_version < 1 or schema_version > CURRENT_SCHEMA_VERSION:
		return {"ok": false, "error_code": "unsupported_schema", "field_path": path + ".schema_version"}
	var stored_hash := str(envelope.get("payload_hash", ""))
	if stored_hash.is_empty() and schema_version >= CURRENT_SCHEMA_VERSION:
		return {"ok": false, "error_code": "missing_payload_hash", "field_path": path + ".payload_hash"}
	if not stored_hash.is_empty() and stored_hash != _payload_hash(envelope["payload"]):
		return {"ok": false, "error_code": "hash_mismatch", "field_path": path}
	return {"ok": true, "envelope": envelope}


func _write_json(path: String, data: Dictionary) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error_code": "file_write_failed", "field_path": path}
	file.store_string(JSON.stringify(data, "  ", true))
	file.flush()
	return {"ok": true}


func _ensure_directory() -> Dictionary:
	var absolute := ProjectSettings.globalize_path(base_directory)
	var error := DirAccess.make_dir_recursive_absolute(absolute)
	return {"ok": error == OK or error == ERR_ALREADY_EXISTS, "error_code": "directory_create_failed", "field_path": base_directory}


func _preserve_corrupt(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		return
	# Use a microsecond token and a collision check.  Startup/retry loops can
	# inspect the same broken file several times within one second; each copy is
	# useful evidence and must not overwrite the previous one.
	var unix_micros := int(Time.get_unix_time_from_system() * 1000000.0)
	var diagnostic_path := path + ".corrupt-%d-%d" % [unix_micros, Time.get_ticks_usec()]
	var suffix := 1
	var candidate := diagnostic_path
	while FileAccess.file_exists(candidate):
		candidate = "%s-%d" % [diagnostic_path, suffix]
		suffix += 1
	diagnostic_path = candidate
	var target := FileAccess.open(diagnostic_path, FileAccess.WRITE)
	if target != null:
		target.store_buffer(source.get_buffer(source.get_length()))
		target.flush()


func _path(file_name: String) -> String:
	return base_directory + file_name if base_directory.ends_with("/") else base_directory + "/" + file_name


static func _payload_hash(payload: Dictionary) -> String:
	# JSON parsing normalizes numeric variants (for example int to float). Hash the
	# normalized representation so a freshly written file verifies after reload.
	var normalized: Variant = JSON.parse_string(JSON.stringify(payload, "", true))
	return JSON.stringify(normalized, "", true).sha256_text()
