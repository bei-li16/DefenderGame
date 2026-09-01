extends SceneTree

const ContentService = preload("res://src/application/content_service.gd")


func _initialize() -> void:
	var service := ContentService.new()
	var result := service.load_builtin()
	if bool(result.get("ok", false)):
		print("Content valid: config_version=%s ruleset=%s" % [result["config_version"], result["ruleset_version"]])
		quit(0)
		return
	for error in result.get("errors", [result]):
		push_error("%s: %s" % [error.get("field_path", "unknown"), error.get("error_code", "invalid")])
	quit(1)
