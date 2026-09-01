extends SceneTree

const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

var failures: Array[String] = []
var passes: int = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := root.get_node_or_null("GameApp")
	if app == null:
		push_error("GameApp autoload is unavailable")
		quit(1)
		return
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var original_settings: Dictionary = app.get("settings").duplicate(true)
	var original_save_service: Variant = app.get("save_service")
	var test_profile := original_profile.duplicate(true)
	test_profile["coins"] = 500
	test_profile["xp"] = 0
	test_profile["highest_unlocked_stage"] = 1
	test_profile["upgrades"] = {"strength": 0, "agility": 0, "fire_mastery": 0, "ice_mastery": 0, "lightning_mastery": 0}
	test_profile["best_results"] = {}
	test_profile["reward_ledger"] = []
	test_profile["tutorial_complete"] = false
	app.set("profile", test_profile)
	app.set("save_service", FailingSaveService.new())

	var purchase: Dictionary = app.call("purchase_upgrade", "strength")
	_expect(not bool(purchase.get("ok", false)) and int(app.get("profile")["coins"]) == 500 and int(app.get("profile")["upgrades"]["strength"]) == 0, "failed upgrade persistence leaves the in-memory profile unchanged")

	var settlement: Dictionary = app.call("settle_run", {
		"run_id": "transaction-test-run",
		"reward_version": "transaction-v1",
		"stage_id": "stage_001",
		"stage_number": 1,
		"status": "victory",
		"kills": 2,
		"wall_percent": 80,
		"tick": 100,
		"coins": 50,
		"xp": 10
	})
	_expect(not bool(settlement.get("ok", false)) and int(app.get("profile")["coins"]) == 500 and app.get("profile")["reward_ledger"].is_empty(), "failed settlement persistence does not commit rewards or the idempotency key")

	var settings_before: Dictionary = app.get("settings").duplicate(true)
	var scale_before := root.content_scale_factor
	var setting_result: Dictionary = app.call("update_setting", "ui_scale", 1.25 if not is_equal_approx(scale_before, 1.25) else 0.85)
	_expect(not bool(setting_result.get("ok", false)) and app.get("settings") == settings_before and is_equal_approx(root.content_scale_factor, scale_before), "failed setting persistence rolls back memory and the applied UI scale")

	var tutorial_result: Dictionary = app.call("complete_tutorial")
	_expect(not bool(tutorial_result.get("ok", false)) and not bool(app.get("profile")["tutorial_complete"]), "failed tutorial persistence keeps the tutorial incomplete")

	app.set("profile", original_profile)
	app.set("settings", original_settings)
	app.set("save_service", original_save_service)
	app.call("_apply_settings")
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[TRANSACTION FAIL] " + failure)
	print("[TRANSACTION] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[TRANSACTION PASS] " + description)
	else:
		failures.append(description)
