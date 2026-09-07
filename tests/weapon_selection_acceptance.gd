extends SceneTree

const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

var failures: Array[String] = []
var passes := 0
var app: Node
var menu: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	# --script startup uses GameApp's isolated automated save directory.
	app.set_process(false)
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["coins"] = 10000
	profile["unlocked_weapons"] = ["basic_bow", "power_bow", "hurricane_bow"]
	app.set("profile", profile)
	var save_service: Variant = app.get("save_service")
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames()
	var row := menu.get("_loadout_row") as HBoxContainer
	var button_count := 0
	var spell_count := 0
	for child in row.get_children():
		if child is Button:
			button_count += 1
		if child is Label:
			spell_count += 1
	_expect(button_count == 1 and spell_count == 3, "header has one bow selector and three spell icons")
	_expect(_popup().item_count == 4, "dropdown retains all four bows")
	_expect(_popup().is_item_disabled(0), "equipped bow cannot be selected again")
	_expect(not _popup().is_item_disabled(1), "owned bow is selectable")
	if not DisplayServer.get_name().contains("headless"):
		await _check_popup_layout()
	await _choose(1)
	_expect(_equipped() == "power_bow", "dropdown equips the chosen bow")
	_expect(_slot().tooltip_text.contains(app.call("text", "weapon.power_bow")), "header shows the equipped bow")
	var loaded: Dictionary = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(str(loaded.get("payload", {}).get("current_weapon_id", "")) == "power_bow", "dropdown equipment is persisted")
	await _check_battle("power_bow")

	# An open research page must stay in sync when using the top bar.
	menu.call("_show_research_page", "weapons", "unlock_hurricane_bow")
	await _frames()
	_expect(_equip_button() != null and _equip_button().visible and not _equip_button().disabled, "research offers equipping another owned bow")
	await _choose(2)
	var equip := _equip_button()
	_expect(equip != null and equip.visible and equip.disabled and equip.text == app.call("text", "menu.selected"), "dropdown selection updates research to show the currently equipped bow")
	await _choose(1)
	equip = _equip_button()
	_expect(equip != null and equip.visible and not equip.disabled, "research can re-equip its selected bow after a dropdown switch")
	if equip != null:
		equip.emit_signal("pressed")
	await _frames()
	_expect(_equipped() == "hurricane_bow" and _popup().is_item_disabled(2), "research equipment updates the header and dropdown")
	loaded = save_service.load_profile_slot(app.get("active_save_slot"), {})
	_expect(str(loaded.get("payload", {}).get("current_weapon_id", "")) == "hurricane_bow", "research equipment survives reloading the save")
	await _capture("research-equipped")
	await _check_battle("hurricane_bow")

	await _choose(3)
	_expect(_equipped() == "hurricane_bow", "locked bow cannot replace the equipped bow")
	var tree := _tree()
	_expect(tree != null and tree.call("selected") == "unlock_phantom_bow", "locked bow opens its unlock node in weapon research")
	var buy := _button_with_text(app.call("text", "common.upgrade"))
	_expect(buy != null and not buy.disabled, "locked bow offers its research purchase")
	if buy != null:
		buy.emit_signal("pressed")
	await _frames()
	_expect(app.get("profile").get("unlocked_weapons", []).has("phantom_bow"), "research unlock makes the bow available")
	await _choose(3)
	_expect(_equipped() == "phantom_bow", "newly unlocked bow is selectable immediately")
	await _check_battle("phantom_bow")
	await _choose(0)
	_expect(_equipped() == "basic_bow", "player can switch back to the starter bow")
	await _check_battle("basic_bow")

	# Failed equipment writes must keep the current bow and tell the player.
	app.set("save_service", FailingSaveService.new())
	await _choose(1)
	_expect(_equipped() == "basic_bow" and _popup().is_item_disabled(0), "failed dropdown save keeps the current equipment")
	_expect(_has_save_error(), "failed dropdown selection displays a save error")
	app.set("save_service", save_service)
	await _choose(1)
	_expect(_equipped() == "power_bow" and not _has_save_error(), "successful dropdown retry clears the save error")
	app.set("save_service", FailingSaveService.new())
	menu.call("_show_research_page", "weapons", "unlock_hurricane_bow")
	await _frames()
	equip = _equip_button()
	if equip != null:
		equip.emit_signal("pressed")
	await _frames()
	_expect(_equipped() == "power_bow", "failed research save keeps the current equipment")
	_expect(_has_save_error(), "failed research equipment displays a save error")
	app.set("save_service", save_service)
	if equip != null:
		equip.emit_signal("pressed")
	await _frames()
	_expect(_equipped() == "hurricane_bow" and not _has_save_error(), "retrying equipment succeeds and clears the save error")
	menu.call("_show_main_navigation")
	await _frames()
	await _choose(0)
	_expect(_equipped() == "basic_bow", "equipment still works after leaving research")
	menu.call("_show_settings")
	await _frames()
	var settings: Dictionary = app.get("settings").duplicate(true)
	settings["language"] = "en_US"
	app.set("settings", settings)
	menu.call("_refresh_after_language_change")
	await _frames()
	await _choose(1)
	_expect(_slot().tooltip_text.contains("Impact Bow"), "selector survives a language change and uses localized bow names")

	root.remove_child(menu)
	menu.free()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[WEAPON SELECT FAIL] " + failure)
	print("[WEAPON SELECT] %d passed, %d failed" % [passes, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _slot() -> Button:
	return (menu.get("_loadout_row") as HBoxContainer).get_child(0) as Button


func _popup() -> PopupMenu:
	for child in _slot().get_children(true):
		if child is PopupMenu:
			return child
	return null


func _choose(index: int) -> void:
	_popup().index_pressed.emit(index)
	await _frames()


func _equipped() -> String:
	return str(app.get("profile").get("current_weapon_id", ""))


func _tree() -> Node:
	for child in menu.find_children("*", "", true, false):
		var script: Variant = child.get_script()
		if script != null and str(script.resource_path).ends_with("research_tree.gd"):
			return child
	return null


func _equip_button() -> Button:
	return menu.find_child("ResearchEquipButton", true, false) as Button


func _button_with_text(label: String) -> Button:
	for child in menu.find_children("*", "Button", true, false):
		if child.text == label:
			return child as Button
	return null


func _has_save_error() -> bool:
	for child in menu.find_children("*", "Label", true, false):
		if child.is_visible_in_tree() and child.text == app.call("text", "feedback.save_failed"):
			return true
	return false


func _check_battle(expected_weapon: String) -> void:
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await _frames()
	var snapshot: Dictionary = gameplay.get("session").current_snapshot()
	_expect(str(snapshot.get("weapon_id", "")) == expected_weapon, "battle uses selected " + expected_weapon)
	root.remove_child(gameplay)
	gameplay.free()


func _check_popup_layout() -> void:
	var settings: Dictionary = app.get("settings").duplicate(true)
	settings["resolution"] = "1280x720"
	settings["fullscreen"] = false
	settings["borderless"] = false
	app.set("settings", settings)
	app.call("_apply_settings")
	root.position = Vector2i(70, 65)
	# Check both native game windows and editor-style embedded popups.
	for embedded in [false, true]:
		root.gui_embed_subwindows = embedded
		for scale_factor in [0.85, 1.0, 1.25]:
			root.content_scale_factor = scale_factor
			await _frames()
			if embedded:
				var click := InputEventMouseButton.new()
				click.button_index = MOUSE_BUTTON_LEFT
				click.position = _slot().get_global_rect().get_center()
				click.global_position = click.position
				click.pressed = true
				root.push_input(click, true)
				click = click.duplicate()
				click.pressed = false
				root.push_input(click, true)
				await _frames()
			else:
				# Native popup focus belongs to the OS, not push_input(). Open
				# through MenuButton to check its screen-coordinate placement.
				(_slot() as MenuButton).show_popup()
			_expect(_popup().visible, "bow dropdown opens (embedded=%s scale=%.2f)" % [embedded, scale_factor])
			var expected := _slot().get_screen_transform() * Vector2(0, _slot().size.y)
			var actual := _popup().get_position_with_decorations()
			_expect(Vector2(actual).distance_to(expected) <= 3.0, "dropdown stays below its icon (embedded=%s scale=%.2f) actual=%s expected=%s" % [embedded, scale_factor, actual, expected])
			if embedded and is_equal_approx(scale_factor, 1.0):
				await _capture("bow-dropdown")
			_popup().hide()
			await _frames()
	root.content_scale_factor = 1.0
	root.gui_embed_subwindows = true


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	var directory := "res://Builds/weapon-selection-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var path := directory.path_join(label + ".png")
	root.get_texture().get_image().save_png(path)
	print("[WEAPON SELECT CAPTURE] " + ProjectSettings.globalize_path(path))


func _frames() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[WEAPON SELECT PASS] " + description)
	else:
		failures.append(description)
