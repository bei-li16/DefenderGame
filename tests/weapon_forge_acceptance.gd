extends SceneTree
## Legacy owned weapons can predate their unlock research nodes. All writes
## use the application's isolated --script save directory, never player data.
const Upgrade = preload("res://src/application/upgrade_service.gd")
const FailingSave = preload("res://tests/support/failing_save_service.gd")
const Attack = preload("res://src/core/rules/attack_catalog.gd")
var app: Node
var passes := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _legacy(weapon: String = "power_bow") -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["coins"] = 13500000
	profile["current_weapon_id"] = weapon
	profile["highest_unlocked_stage"] = 53
	profile["unlocked_weapons"] = ["basic_bow", "power_bow", "hurricane_bow", "phantom_bow"]
	profile["upgrades"].merge({"unlock_power_bow": 0, "forge_power_bow": 0, "unlock_hurricane_bow": 1, "forge_hurricane_bow": 10, "unlock_phantom_bow": 1, "forge_phantom_bow": 25}, true)
	profile["upgrades"]["unlock_" + weapon] = 0
	profile["upgrades"]["forge_" + weapon] = 0
	return profile


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	var service := Upgrade.new()
	var rules: Dictionary = app.get("content").rules
	for weapon in ["power_bow", "hurricane_bow", "phantom_bow"]:
		var legacy := _legacy(weapon)
		var original := legacy.duplicate(true)
		var normalized: Dictionary = app.call("_normalize_profile", legacy)
		_expect(int(normalized["upgrades"]["unlock_" + weapon]) == 1, weapon + " load normalizes owned legacy unlock")
		_expect(legacy == original and normalized["coins"] == legacy["coins"] and normalized["stats"] == legacy["stats"], weapon + " migration neither mutates input nor charges currency")
		_expect(app.call("_normalize_profile", normalized) == normalized, weapon + " normalization is idempotent")
		var purchase := service.purchase(legacy, rules, "forge_" + weapon)
		_expect(bool(purchase.get("ok", false)) and int(purchase.get("new_level", 0)) == 1, weapon + " service accepts owned bow without unlock node")
		var repeat := service.purchase(legacy, rules, "unlock_" + weapon)
		_expect(not bool(repeat.get("ok", false)) and repeat.get("error_code", "") == "max_level", weapon + " already-owned unlock cannot be charged twice")
	var locked := _legacy()
	locked["unlocked_weapons"] = ["basic_bow"]
	var missing := service.purchase(locked, rules, "forge_power_bow")
	_expect(missing.get("error_code", "") == "missing_prerequisite", "actually locked bow still requires its unlock")
	app.set("profile", _legacy())
	var saved: Dictionary = app.get("save_service").save_profile_slot(app.get("active_save_slot"), app.get("profile"), int(rules["config_version"]))
	_expect(bool(saved.get("ok", false)), "legacy starting profile saved in isolated slot")
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	menu.call("_show_research_page", "weapons", "forge_power_bow")
	await process_frame
	var button := menu.find_child("ResearchPurchaseButton", true, false) as Button
	_expect(button != null and not button.disabled, "legacy owned bow exposes enabled forge button")
	button.pressed.emit()
	await process_frame
	var updated: Dictionary = app.get("profile")
	_expect(int(updated["upgrades"]["forge_power_bow"]) == 1 and int(updated["coins"]) == 13500000 - 400, "real upgrade button persists first forge level and exactly 400 coins")
	_expect(int(updated["stats"]["coins_spent"]) == 400, "only the forge cost counts as spending")
	_expect(not _has_save_error(menu), "successful forge shows no disk-permission message")
	var reloaded: Dictionary = app.get("save_service").load_profile_slot(app.get("active_save_slot"), {})
	var payload: Dictionary = reloaded.get("payload", {})
	_expect(bool(reloaded.get("ok", false)) and int(payload.get("upgrades", {}).get("forge_power_bow", 0)) == 1 and int(payload.get("upgrades", {}).get("unlock_power_bow", 0)) == 1, "reloaded slot retains forge and migrated unlock")
	var bow: Dictionary = app.get("content").find_by_id("weapons", "power_bow")
	_expect(Attack.effective(rules, payload, bow)["base_damage"] > Attack.effective(rules, _legacy(), bow)["base_damage"], "persisted forge increases actual bow damage")
	await _capture("forge-success")
	var real_save: RefCounted = app.get("save_service")
	var before: Dictionary = app.get("profile").duplicate(true)
	app.set("save_service", FailingSave.new(real_save.base_directory))
	(menu.find_child("ResearchPurchaseButton", true, false) as Button).pressed.emit()
	await process_frame
	_expect(app.get("profile") == before and _has_save_error(menu), "real IO failure remains visible and rolls back level, coins and spending")
	app.set("save_service", real_save)
	# A stale UI click after the entitlement changes must report the actual
	# prerequisite failure, even though it was previously an enabled button.
	app.set("profile", locked)
	(menu.find_child("ResearchPurchaseButton", true, false) as Button).pressed.emit()
	await process_frame
	_expect(not _has_save_error(menu) and _has_text(menu, app.call("text", "feedback.missing_prerequisite")), "missing prerequisite is not misreported as disk failure")
	menu.free()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[FORGE FAIL] " + failure)
	print("[FORGE] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _has_save_error(menu: Node) -> bool:
	return _has_text(menu, app.call("text", "feedback.save_failed"))


func _has_text(menu: Node, value: String) -> bool:
	for label in menu.find_children("*", "Label", true, false):
		if label.is_visible_in_tree() and label.text == value:
			return true
	return false


func _capture(label: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture") or DisplayServer.get_name().contains("headless"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://Builds/bolt-review")
	_expect(root.get_texture().get_image().save_png("res://Builds/bolt-review/" + label + ".png") == OK, "capture " + label)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
