extends SceneTree

const DiagnosticService = preload("res://src/infrastructure/diagnostic_service.gd")

var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var root_directory := "user://diagnostic-acceptance-test"
	var log_directory := root_directory + "/logs"
	var zip_directory := root_directory + "/diagnostics"
	_delete_test_directory(ProjectSettings.globalize_path(root_directory))
	var service: RefCounted
	for session_number in range(7):
		service = DiagnosticService.new(log_directory, zip_directory)
		var started: Dictionary = service.start_session("test-app", "test-godot", 7)
		_expect(bool(started.get("ok", false)), "diagnostic session %d starts" % (session_number + 1))
	service.record("failure", "C:\\Users\\private-name\\profile.json", "Gameplay", {
		"operation": "save",
		"profile": "secret-profile-payload",
		"path": "C:\\Users\\private-name"
	})
	var log_files := _list_files(log_directory, ".log")
	_expect(log_files.size() == 5, "log rotation retains exactly the newest five session files")
	var privacy_safe := true
	for file_name in log_files:
		var text := FileAccess.get_file_as_string(log_directory.path_join(file_name))
		privacy_safe = privacy_safe and not text.contains("private-name") and not text.contains("secret-profile-payload") and not text.contains("install_id")
		privacy_safe = privacy_safe and FileAccess.get_file_as_bytes(log_directory.path_join(file_name)).size() <= DiagnosticService.MAX_LOG_BYTES
	_expect(privacy_safe, "logs omit user paths and Profile data and remain under the per-file limit")

	var exported: Dictionary = service.export_zip()
	var reader := ZIPReader.new()
	var archive_opened := bool(exported.get("ok", false)) and reader.open(str(exported.get("path", ""))) == OK
	var archive_entries: PackedStringArray = reader.get_files() if archive_opened else PackedStringArray()
	var archived_log_count := 0
	var logs_only := true
	for entry in archive_entries:
		if entry.ends_with("/"):
			continue
		archived_log_count += 1
		logs_only = logs_only and entry.begins_with("logs/") and entry.ends_with(".log")
	_expect(archive_opened and logs_only and archived_log_count == 5, "manual diagnostic ZIP contains only the five privacy-safe logs")
	if archive_opened:
		reader.close()

	_delete_test_directory(ProjectSettings.globalize_path(root_directory))
	for failure in failures:
		push_error("[DIAGNOSTIC FAIL] " + failure)
	print("[DIAGNOSTIC] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _list_files(directory_path: String, suffix: String) -> Array[String]:
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


func _delete_test_directory(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var item := directory.get_next()
	while not item.is_empty():
		var item_path := absolute_path.path_join(item)
		if directory.current_is_dir():
			_delete_test_directory(item_path)
		else:
			DirAccess.remove_absolute(item_path)
		item = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[DIAGNOSTIC PASS] " + description)
	else:
		failures.append(description)
