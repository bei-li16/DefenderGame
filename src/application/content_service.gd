class_name DefenderContentService
extends RefCounted

const ContentValidator = preload("res://src/core/rules/content_validator.gd")

var rules: Dictionary = {}
var localization: Dictionary = {}
var validation_errors: Array[Dictionary] = []


func load_builtin(force_release_fallback: bool = false) -> Dictionary:
	var allow_fallback := force_release_fallback or not OS.is_debug_build()
	var rules_result := _load_json("res://content/config/game_rules.json")
	var primary_rules_error: Dictionary = {}
	if not bool(rules_result.get("ok", false)):
		primary_rules_error = rules_result.duplicate(true)
	else:
		var primary_validation: Array[Dictionary] = ContentValidator.validate(rules_result["data"])
		if primary_validation.is_empty():
			rules_result["validation_errors"] = []
		else:
			primary_rules_error = {"ok": false, "error_code": "invalid_content", "field_path": primary_validation[0]["field_path"], "errors": primary_validation}
	if not primary_rules_error.is_empty():
		if not allow_fallback:
			return primary_rules_error
		rules_result = _load_json("res://content/config/game_rules_fallback.json")
		if not bool(rules_result.get("ok", false)):
			return rules_result
		var fallback_errors: Array[Dictionary] = ContentValidator.validate(rules_result["data"])
		if not fallback_errors.is_empty():
			return {"ok": false, "error_code": "invalid_fallback_content", "field_path": fallback_errors[0]["field_path"], "errors": fallback_errors}
	var localization_result := _load_json("res://content/catalogs/localization.json")
	var localization_error: Dictionary = {}
	if bool(localization_result.get("ok", false)):
		var primary_localization_errors: Array[Dictionary] = ContentValidator.validate_localization(localization_result["data"], rules_result["data"])
		if not primary_localization_errors.is_empty():
			localization_error = {"ok": false, "error_code": "invalid_localization", "field_path": primary_localization_errors[0]["field_path"], "errors": primary_localization_errors}
	else:
		localization_error = localization_result.duplicate(true)
	if not localization_error.is_empty():
		if not allow_fallback:
			return localization_error
		localization_result = _load_json("res://content/catalogs/localization_fallback.json")
		if not bool(localization_result.get("ok", false)):
			return localization_result
	rules = rules_result["data"]
	localization = localization_result["data"]
	validation_errors = ContentValidator.validate(rules)
	validation_errors.append_array(ContentValidator.validate_localization(localization, rules))
	if not validation_errors.is_empty():
		return {
			"ok": false,
			"error_code": "invalid_content",
			"field_path": validation_errors[0]["field_path"],
			"errors": validation_errors
		}
	var result := {"ok": true, "config_version": rules["config_version"], "ruleset_version": rules["ruleset_version"]}
	if not primary_rules_error.is_empty() or not localization_error.is_empty():
		result["used_fallback"] = true
		result["fallback_reason"] = primary_rules_error if not primary_rules_error.is_empty() else localization_error
	return result


func text(key: String, locale: String = "zh_CN") -> String:
	var selected: Dictionary = localization.get(locale, localization.get("zh_CN", {}))
	return str(selected.get(key, key))


func find_by_id(collection_name: String, item_id: String) -> Dictionary:
	for item in rules.get(collection_name, []):
		if item is Dictionary and str(item.get("id", "")) == item_id:
			return item.duplicate(true)
	return {}


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error_code": "file_missing", "field_path": path}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error_code": "file_open_failed", "field_path": path}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		return {
			"ok": false,
			"error_code": "json_parse_failed",
			"field_path": "%s:%d" % [path, parser.get_error_line()],
			"message": parser.get_error_message()
		}
	if not parser.data is Dictionary:
		return {"ok": false, "error_code": "json_root_not_object", "field_path": path}
	return {"ok": true, "data": parser.data}
