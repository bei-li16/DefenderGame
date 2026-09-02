extends SceneTree

const REQUIRED_PATHS: Array[String] = [
	"res://content/build/build-manifest.json",
	"res://content/config/game_rules.json",
	"res://content/catalogs/localization.json",
	"res://scenes/bootstrap.tscn",
	"res://scenes/main_menu.tscn",
	"res://scenes/gameplay.tscn",
	"res://src/autoload/game_app.gd"
]

const EXCLUDED_PATHS: Array[String] = [
	"res://tests/run_all.gd",
	"res://tests/support/failing_save_service.gd",
	"res://tools/build_windows.ps1",
	"res://tools/verify_export_pack.gd",
	"res://docs/implementation-status.md",
	"res://参考/来源清单.csv",
	"res://参考/01_官方/app-store_01_主菜单.webp"
]


func _initialize() -> void:
	var failures: Array[String] = []
	for path in REQUIRED_PATHS:
		if not _path_exists(path):
			failures.append("missing:" + path)
	for path in EXCLUDED_PATHS:
		if _path_exists(path):
			failures.append("unexpected:" + path)

	var manifest_text := FileAccess.get_file_as_string("res://content/build/build-manifest.json")
	var manifest: Variant = JSON.parse_string(manifest_text)
	var config_text := FileAccess.get_file_as_string("res://content/config/game_rules.json")
	var config: Variant = JSON.parse_string(config_text)
	if not manifest is Dictionary:
		failures.append("invalid_manifest")
	elif not config is Dictionary:
		failures.append("invalid_config")
	else:
		if str(manifest.get("config_hash", "")) != config_text.sha256_text():
			failures.append("config_hash_mismatch")
		if int(manifest.get("config_version", -1)) != int(config.get("config_version", -2)):
			failures.append("config_version_mismatch")
		if str(manifest.get("app_version", "")) != str(ProjectSettings.get_setting("application/config/version", "")):
			failures.append("app_version_mismatch")
		if str(manifest.get("godot_version", "")) != str(Engine.get_version_info().get("string", "")):
			failures.append("godot_version_mismatch")
		if str(manifest.get("build_utc", "")).is_empty():
			failures.append("missing_build_time")
		var expected_git_sha := _user_argument("expected-git-sha")
		if expected_git_sha.is_empty() or str(manifest.get("git_commit", "")) != expected_git_sha:
			failures.append("git_commit_mismatch")

	for failure in failures:
		push_error("[PACK PROBE] " + failure)
	print("[PACK PROBE] required=%d excluded=%d failures=%d" % [REQUIRED_PATHS.size(), EXCLUDED_PATHS.size(), failures.size()])
	quit(failures.size())


static func _path_exists(path: String) -> bool:
	return FileAccess.file_exists(path) or ResourceLoader.exists(path)


static func _user_argument(argument_name: String) -> String:
	var prefix := "--%s=" % argument_name
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(prefix):
			return argument.trim_prefix(prefix)
	return ""
