extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")


func _initialize() -> void:
	var content := ContentService.new()
	var result := content.load_builtin()
	if not bool(result.get("ok", false)):
		push_error("Cannot write manifest because content validation failed")
		quit(1)
		return
	var git_sha := _command_output("git", ["rev-parse", "HEAD"]).strip_edges()
	var godot_version: String = str(Engine.get_version_info().get("string", "unknown"))
	var config_text := FileAccess.get_file_as_string("res://content/config/game_rules.json")
	var manifest := {
		"app_version": str(ProjectSettings.get_setting("application/config/version", "unknown")),
		"godot_version": godot_version,
		"git_commit": git_sha if not git_sha.is_empty() else "unavailable",
		"config_version": content.rules.get("config_version", 0),
		"config_hash": config_text.sha256_text(),
		"build_utc": Time.get_datetime_string_from_system(true)
	}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://content/build"))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Cannot create build manifest directory")
		quit(1)
		return
	var file := FileAccess.open("res://content/build/build-manifest.json", FileAccess.WRITE)
	if file == null:
		push_error("Cannot write build manifest")
		quit(1)
		return
	file.store_string(JSON.stringify(manifest, "  ", true))
	file.flush()
	print("Build manifest written: " + JSON.stringify(manifest))
	quit(0)


func _command_output(command: String, arguments: Array[String]) -> String:
	var output: Array = []
	var exit_code := OS.execute(command, arguments, output, true, false)
	return str(output[0]) if exit_code == 0 and not output.is_empty() else ""
