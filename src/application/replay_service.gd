class_name DefenderReplayService
extends RefCounted

var replay_directory: String


func _init(directory: String = "user://replays") -> void:
	replay_directory = directory


func export_record(record: Dictionary, requested_name: String = "") -> Dictionary:
	var absolute_directory := ProjectSettings.globalize_path(replay_directory)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return {"ok": false, "error_code": "directory_create_failed", "field_path": replay_directory}
	var safe_name := requested_name.validate_filename()
	if safe_name.is_empty():
		safe_name = str(record.get("run_id", "replay")).validate_filename()
	if not safe_name.ends_with(".json"):
		safe_name += ".json"
	var path := replay_directory.path_join(safe_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error_code": "file_write_failed", "field_path": path}
	file.store_string(JSON.stringify(record, "  ", true))
	file.flush()
	return {"ok": true, "path": path, "event_hash": record.get("event_hash", "")}


func load_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error_code": "file_missing", "field_path": path}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK or not parser.data is Dictionary:
		return {"ok": false, "error_code": "json_parse_failed", "field_path": path}
	return {"ok": true, "record": parser.data}
