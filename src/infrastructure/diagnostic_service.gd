class_name DefenderDiagnosticService
extends RefCounted

const MAX_LOG_FILES := 5
const MAX_LOG_BYTES := 256 * 1024
const MAX_DIAGNOSTIC_ZIPS := 5

var log_directory: String
var diagnostic_directory: String
var _session_path: String = ""
var _base_context: Dictionary = {}


func _init(log_path: String = "user://logs", diagnostic_path: String = "user://diagnostics") -> void:
	log_directory = log_path
	diagnostic_directory = diagnostic_path


func start_session(app_version: String, godot_version: String, config_version: Variant = "unknown") -> Dictionary:
	var directory_result := _ensure_directory(log_directory)
	if not bool(directory_result.get("ok", false)):
		return directory_result
	_prune_files(log_directory, ".log", MAX_LOG_FILES - 1)
	_session_path = log_directory.path_join("session-%d-%d.log" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	_base_context = {
		"app_version": app_version,
		"godot_version": godot_version,
		"config_version": config_version
	}
	return record("session_start", "", "Bootstrap")


func update_config_version(config_version: Variant) -> void:
	_base_context["config_version"] = config_version


func record(event_name: String, error_code: String = "", scene_name: String = "", details: Dictionary = {}) -> Dictionary:
	if _session_path.is_empty():
		return {"ok": false, "error_code": "diagnostic_session_not_started"}
	var existing_size := FileAccess.get_file_as_bytes(_session_path).size() if FileAccess.file_exists(_session_path) else 0
	if existing_size >= MAX_LOG_BYTES:
		return {"ok": false, "error_code": "diagnostic_log_size_limit"}
	var entry := _base_context.duplicate(true)
	entry["utc"] = Time.get_datetime_string_from_system(true)
	entry["event"] = _safe_token(event_name)
	entry["error_code"] = _safe_token(error_code)
	entry["scene"] = _safe_token(scene_name)
	entry["details"] = _safe_details(details)
	var encoded := JSON.stringify(entry) + "\n"
	if existing_size + encoded.to_utf8_buffer().size() > MAX_LOG_BYTES:
		return {"ok": false, "error_code": "diagnostic_log_size_limit"}
	var file := FileAccess.open(_session_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_session_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error_code": "diagnostic_log_open_failed"}
	file.seek_end()
	file.store_string(encoded)
	file.flush()
	return {"ok": true, "path": _session_path, "bytes": FileAccess.get_file_as_bytes(_session_path).size()}


func export_zip() -> Dictionary:
	var directory_result := _ensure_directory(diagnostic_directory)
	if not bool(directory_result.get("ok", false)):
		return directory_result
	_prune_files(diagnostic_directory, ".zip", MAX_DIAGNOSTIC_ZIPS - 1)
	var archive_path := diagnostic_directory.path_join("aegis-diagnostics-%d-%d.zip" % [int(Time.get_unix_time_from_system()), Time.get_ticks_usec()])
	var packer := ZIPPacker.new()
	var open_error := packer.open(archive_path)
	if open_error != OK:
		return {"ok": false, "error_code": "diagnostic_zip_open_failed"}
	var log_files := _list_files(log_directory, ".log")
	for file_name in log_files:
		var start_error := packer.start_file("logs/" + file_name.validate_filename())
		if start_error != OK:
			packer.close()
			return {"ok": false, "error_code": "diagnostic_zip_entry_failed"}
		packer.write_file(FileAccess.get_file_as_bytes(log_directory.path_join(file_name)))
		packer.close_file()
	packer.close()
	return {"ok": true, "path": archive_path, "log_count": log_files.size()}


func _safe_details(details: Dictionary) -> Dictionary:
	var safe: Dictionary = {}
	for key in ["operation", "stage_id", "status", "renderer"]:
		if details.has(key):
			safe[key] = _safe_token(str(details[key]))
	return safe


static func _safe_token(value: String) -> String:
	if value.contains("\\") or value.contains("/"):
		return "redacted_path"
	var safe := value.replace("\\", "_").replace("/", "_").replace(":", "_")
	return safe.left(120)


static func _ensure_directory(path: String) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	return {"ok": true} if error == OK or error == ERR_ALREADY_EXISTS else {"ok": false, "error_code": "diagnostic_directory_failed"}


func _prune_files(directory_path: String, suffix: String, keep_count: int) -> void:
	var files := _list_files(directory_path, suffix)
	files.sort()
	while files.size() > keep_count:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory_path.path_join(files.pop_front())))


static func _list_files(directory_path: String, suffix: String) -> Array[String]:
	var files: Array[String] = []
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return files
	directory.list_dir_begin()
	var item := directory.get_next()
	while not item.is_empty():
		if not directory.current_is_dir() and item.ends_with(suffix):
			files.append(item)
		item = directory.get_next()
	directory.list_dir_end()
	return files
