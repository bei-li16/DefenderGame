extends SceneTree

const RunModel = preload("res://src/core/combat/run_model.gd")
const SkillCatalog = preload("res://src/core/rules/skill_catalog.gd")
const SkillSystem = preload("res://src/core/combat/skill_system.gd")
const FailingSaveService = preload("res://tests/support/failing_save_service.gd")

var app: Node
var config: Dictionary
var failures: Array[String] = []
var passes := 0
var menu: Node


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	config = app.get("content").rules
	_check_rainfall()
	_check_ranges()
	await _check_dropdowns()
	await _check_cursors_and_effects()
	app.get("audio").stop_all()
	for failure in failures:
		push_error("[SKILL INTERACTION FAIL] " + failure)
	print("[SKILL INTERACTION] %d passed, %d failed" % [passes, failures.size()])
	quit(1 if not failures.is_empty() else 0)


func _profile(tier: int = 3, level: int = 1) -> Dictionary:
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["upgrades"]["mana_capacity"] = 20
	for skill in config["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = level
		if int(skill["tier"]) == tier:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	return profile


func _check_rainfall() -> void:
	var world: Dictionary = config["world"]
	var left := int(world["castle_x_milli"])
	var width := int(world["width_milli"]) - left
	var height := int(world["height_milli"])
	for id in ["armageddon", "ice_age", "ragnarok"]:
		var definition := SkillCatalog.find(config, id)
		_expect(int(definition["barrage_duration_ticks"]) == 90 and int(definition["impact_count"]) >= 52, id + " delivers over fifty impacts in three seconds")
		var baseline_plans := {}
		for level in [1, 20, 200]:
			var profile := _profile(3, level)
			if level > 1:
				profile["upgrades"]["spell_radius"] = 5
			var skill := SkillCatalog.effective(config, profile, id)
			var cells := {}
			for seed_value in range(1, 13):
				var model := RunModel.new()
				model.setup(config, "stage_001", seed_value, profile)
				model.step([{"type": "cast_skill", "skill_id": id, "x_milli": -100, "y_milli": -100}])
				var plan: Array = model.active_spells[0]["impacts"]
				var reference := RunModel.new()
				reference.setup(config, "stage_001", seed_value, profile)
				var expected_offsets := SkillSystem.launch_offsets(reference._spell_rng, int(skill["impact_count"]), int(skill["barrage_duration_ticks"]))
				var uniform := true
				var valid := plan.size() == int(skill["impact_count"])
				var last_tick := -1
				var gaps := {}
				for index in range(plan.size()):
					var impact: Dictionary = plan[index]
					var point := Vector2i(impact["x_milli"], impact["y_milli"])
					# Exact independent uniform rolls: no artificial center gap,
					# spacing grid, minimum distance, or coverage-driven rejection.
					var expected := Vector2i(reference._spell_rng.range_exclusive(left, left + width + 1), reference._spell_rng.range_exclusive(0, height + 1))
					uniform = uniform and point == expected
					var cell := Vector2i(mini(2, (point.x - left) * 3 / width), mini(2, point.y * 3 / height))
					cells[cell] = int(cells.get(cell, 0)) + 1
					var tick := int(impact["launch_tick"]) - model.tick
					valid = valid and point.x >= left and point.x <= left + width and point.y >= 0 and point.y <= height and tick == expected_offsets[index] and tick > last_tick and tick < 90
					if last_tick >= 0:
						gaps[tick - last_tick] = true
					last_tick = tick
				_expect(valid and uniform and gaps.size() > 1, "%s L%d seed%d independent uniform points and irregular launches" % [id, level, seed_value])
				if level == 1:
					baseline_plans[seed_value] = plan
				else:
					_expect(plan == baseline_plans[seed_value], id + " upgrading range never moves landing points")
			_expect(cells.size() == 9 and int(cells.get(Vector2i(1, 1), 0)) > 0, "%s L%d samples include all regions and the center" % [id, level])


func _check_ranges() -> void:
	for skill in config["skills"]:
		var id := str(skill["id"])
		var initial_level := 0 if int(skill["tier"]) == 1 else 1
		var initial := SkillCatalog.effective(config, _profile(3, initial_level), id)
		var next := SkillCatalog.effective(config, _profile(3, initial_level + 1), id)
		_expect(int(next["radius_milli"]) - int(initial["radius_milli"]) == 1000 and int(next["splash_radius_milli"]) - int(initial["splash_radius_milli"]) == 1000, id + " each research adds only one pixel to either radius")
		var max_profile := _profile(3, 20)
		var no_bonus := SkillCatalog.effective(config, max_profile, id)
		max_profile["upgrades"]["spell_radius"] = 5
		var maximum := SkillCatalog.effective(config, max_profile, id)
		_expect(int(maximum["radius_milli"]) == int(no_bonus["radius_milli"]) * 1150 / 1000 and int(maximum["splash_radius_milli"]) == int(no_bonus["splash_radius_milli"]) * 1150 / 1000, id + " general range research adds at most fifteen percent")
		_expect(int(maximum["radius_milli"]) <= 126000 and int(maximum["splash_radius_milli"]) <= 201000 and int(maximum["splash_radius_milli"]) > int(maximum["radius_milli"]), id + " max research keeps individual impact compact")
		var deep_profile := _profile(3, 200)
		deep_profile["upgrades"]["spell_radius"] = 5
		var deep := SkillCatalog.effective(config, deep_profile, id)
		_expect(deep["radius_milli"] == maximum["radius_milli"] and deep["splash_radius_milli"] == maximum["splash_radius_milli"] and int(deep["damage"]) > int(maximum["damage"]), id + " endless damage still grows but radius stays capped")
		if int(skill["tier"]) == 3:
			print("[SPELL RANGE] %s base=%d/%d max=%.1f/%.1f px" % [id, int(initial["radius_milli"]) / 1000, int(initial["splash_radius_milli"]) / 1000, int(maximum["radius_milli"]) / 1000.0, int(maximum["splash_radius_milli"]) / 1000.0])


func _check_dropdowns() -> void:
	app.set("profile", _profile())
	var saves: Variant = app.get("save_service")
	menu = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await _frames()
	for element in SkillCatalog.ELEMENTS:
		_expect(_slot(element) != null and _slot(element).get_popup().item_count == 3, element + " menu has three tiers")
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var slot := _slot(element)
			var text_width := slot.get_theme_font("font").get_string_size(slot.text, HORIZONTAL_ALIGNMENT_LEFT, -1, slot.get_theme_font_size("font_size")).x
			_expect(text_width + slot.get_theme_stylebox(state).get_minimum_size().x <= slot.size.x, element + " icon/tier/arrow fit in " + state)
		var definitions: Array = []
		for skill in config["skills"]:
			if skill["element"] == element:
				definitions.append(skill)
		for tier_index in range(3):
			var before := SkillCatalog.loadout(config, app.get("profile"))
			await _choose(element, tier_index)
			var expected := str(definitions[tier_index]["id"])
			var equipped := SkillCatalog.loadout(config, app.get("profile"))
			before[element] = expected
			_expect(equipped == before and _slot(element).get_popup().is_item_disabled(tier_index), expected + " dropdown changes only its family")
			var persisted: Dictionary = saves.load_profile_slot(app.get("active_save_slot"), {})
			_expect(persisted["payload"]["equipped_skills"][element] == expected, expected + " persists")
			var model := RunModel.new()
			model.setup(config, "stage_001", 123, persisted["payload"])
			_expect(model.skill_loadout[element] == expected, expected + " is equipped in the next battle")
	menu.call("_show_research_page", "magic", "meteor")
	await _frames()
	await _choose("fire", 1)
	var equip := menu.find_child("ResearchEquipButton", true, false) as Button
	_expect(equip.disabled, "dropdown refreshes open research equipment")
	await _choose("fire", 2)
	_expect(not equip.disabled, "research offers re-equipping after dropdown switch")
	equip.pressed.emit()
	await _frames()
	_expect(_slot("fire").get_popup().is_item_disabled(1), "research equipment refreshes dropdown")
	app.set("save_service", FailingSaveService.new())
	await _choose("fire", 0)
	_expect(_slot("fire").get_popup().is_item_disabled(1) and menu.get("_loadout_error").visible, "failed save keeps current tier and displays error")
	app.set("save_service", saves)
	await _choose("fire", 0)
	_expect(_slot("fire").get_popup().is_item_disabled(0) and not menu.get("_loadout_error").visible, "retry persists and clears error")
	app.set("save_service", FailingSaveService.new())
	equip.pressed.emit()
	await _frames()
	_expect(_slot("fire").get_popup().is_item_disabled(0) and menu.get("_loadout_error").visible, "research equipment uses the same atomic error feedback")
	app.set("save_service", saves)
	await _choose("fire", 1)
	_expect(equip.disabled and not menu.get("_loadout_error").visible, "dropdown retry clears a research equipment error")
	app.get("profile")["upgrades"]["ice_age"] = 0
	menu.call("_refresh_header")
	await _frames()
	await _choose("ice", 2)
	var selected_research := ""
	for node in menu.find_children("*", "", true, false):
		var script: Variant = node.get_script()
		if script != null and str(script.resource_path).ends_with("research_tree.gd"):
			selected_research = str(node.call("selected"))
	_expect(SkillCatalog.loadout(config, app.get("profile"))["ice"] != "ice_age" and selected_research == "ice_age", "locked tier routes to its exact research node, never equips")
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		menu.call("_refresh_after_language_change")
		menu.call("_show_main_navigation")
		await _frames()
		_expect(_slot("fire").get_popup().get_item_text(1).contains(app.call("text", "skill.meteor")), locale + " dropdown localized after rebuild")
		if not DisplayServer.get_name().contains("headless"):
			root.gui_embed_subwindows = true
			for scale_factor in [0.85, 1.0, 1.25]:
				root.content_scale_factor = scale_factor
				await _frames()
				for element in SkillCatalog.ELEMENTS:
					_slot(element).show_popup()
					await _frames()
					var popup := _slot(element).get_popup()
					var expected := _slot(element).get_screen_transform() * Vector2(0, _slot(element).size.y)
					_expect(popup.visible and Vector2(popup.get_position_with_decorations()).distance_to(expected) < 3, "%s %s %.2f dropdown stays below slot" % [locale, element, scale_factor])
					if element == "fire" and scale_factor == 1.0:
						await _capture("dropdown-" + locale)
					popup.hide()
					await _frames()
	root.content_scale_factor = 1.0
	app.get("settings")["language"] = "zh_CN"
	root.remove_child(menu)
	menu.free()


func _check_cursors_and_effects() -> void:
	for tier in [1, 2, 3]:
		app.set("profile", _profile(tier))
		var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		root.add_child(gameplay)
		gameplay.set_process(false)
		gameplay.set_physics_process(false)
		var session: Node = gameplay.get("session")
		session.set_physics_process(false)
		await _frames()
		_move_pointer(Vector2(1100, 500))
		await _frames()
		gameplay.set("_pointer_inside_window", true)
		_expect(gameplay.call("_pointer_cursor_kind") == "crosshair", "tier%d unselected uses crosshair" % tier)
		for element in SkillCatalog.ELEMENTS:
			var action := InputEventAction.new()
			action.action = "combat_select_" + element
			action.pressed = true
			gameplay.call("_unhandled_input", action)
			session.call("_physics_process", 1.0 / 30)
			gameplay.call("_sync_pointer_cursor")
			_expect(gameplay.call("_pointer_cursor_kind") == element, "%s tier%d selects magic cursor" % [element, tier])
			if not DisplayServer.get_name().contains("headless"):
				_expect(Input.mouse_mode == Input.MOUSE_MODE_HIDDEN, element + " custom cursor replaces OS arrow")
			gameplay.queue_redraw()
			if tier == 3:
				await _capture("cursor-" + element)
			paused = true
			gameplay.call("_sync_pointer_cursor")
			_expect(gameplay.call("_pointer_cursor_kind") == "" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, element + " pause restores OS pointer")
			paused = false
			var model: DefenderRunModel = session.get("_model")
			model.mana = 0
			var selected := model.selected_skill
			session.call("queue_command", {"type": "cast_skill", "skill_id": selected, "x_milli": 1100000, "y_milli": 500000})
			session.call("_physics_process", 1.0 / 30)
			_expect(gameplay.call("_pointer_cursor_kind") == element, element + " failed cast keeps magic cursor")
			model.mana = model.max_mana
			session.call("queue_command", {"type": "cast_skill", "skill_id": selected, "x_milli": 1100000, "y_milli": 500000})
			session.call("_physics_process", 1.0 / 30)
			_expect(gameplay.call("_pointer_cursor_kind") == "crosshair", element + " successful cast returns crosshair")
			gameplay.call("_unhandled_input", action)
			session.call("_physics_process", 1.0 / 30)
			gameplay.call("_cancel_cast_drag")
			session.call("_physics_process", 1.0 / 30)
			_expect(gameplay.call("_pointer_cursor_kind") == "crosshair", element + " cancel returns crosshair")
		# HUD, out-of-window and focus-loss paths must not leak a hidden cursor.
		var hud: Node = gameplay.get("_hud")
		var skill_button: Control = hud.get("skill_buttons").values()[0]
		_move_pointer(skill_button.get_global_rect().get_center())
		await _frames()
		gameplay.call("_sync_pointer_cursor")
		_expect(gameplay.call("_pointer_cursor_kind") == "" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "HUD hover uses normal pointer")
		_move_pointer(Vector2(1100, 500))
		await _frames()
		root.mouse_exited.emit()
		_expect(gameplay.call("_pointer_cursor_kind") == "" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "window exit restores normal pointer")
		root.mouse_entered.emit()
		root.focus_exited.emit()
		_expect(gameplay.call("_pointer_cursor_kind") == "" and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "focus loss restores normal pointer")
		root.focus_entered.emit()
		if tier == 3:
			# All three simultaneous barrages under a live 100-enemy load.
			var model := RunModel.new()
			var rules := config.duplicate(true)
			rules["stages"][0]["groups"] = [{"enemy_id": "melee_basic", "count": 100, "interval_ticks": 1}]
			rules["enemies"][0]["hp"] = 100000000
			rules["enemies"][0]["speed_milli_per_tick"] = 1
			model.setup(rules, "stage_001", 1357, _profile())
			for ignored in range(160):
				model.step([])
			for index in range(model.enemies.size()):
				model.enemies[index]["x_milli"] = 580000 + (index % 10) * 135000
				model.enemies[index]["y_milli"] = 240000 + (index / 10) * 72000
			gameplay.get("effects").clear()
			gameplay.get("floating_texts").clear()
			var commands := []
			for id in ["armageddon", "ice_age", "ragnarok"]:
				commands.append({"type": "cast_skill", "skill_id": id})
			var start := Time.get_ticks_usec()
			var events := model.step(commands)
			var planning_usec := Time.get_ticks_usec() - start
			gameplay.call("_on_snapshot", model.snapshot())
			gameplay.call("_on_events", events)
			var samples: Array[int] = []
			var launches := 0
			var pulses := 0
			# Include initial tick's launches, then every subsequent event.
			for event in events:
				if event["type"] == "skill_launch": launches += 1
			for tick in range(115):
				start = Time.get_ticks_usec()
				events = model.step([])
				samples.append(Time.get_ticks_usec() - start)
				for event in events:
					if event["type"] == "skill_launch": launches += 1
					if event["type"] == "skill_pulse": pulses += 1
				gameplay.call("_process", 1.0 / 30)
				gameplay.call("_on_snapshot", model.snapshot())
				gameplay.call("_on_events", events)
				if tick in [30, 55, 80]:
					await _capture("dense-barrage-%d" % tick)
			_expect(launches == 168 and pulses == 168 and model.active_spells.is_empty(), "all 168 impacts launch and resolve under simultaneous barrage load")
			samples.sort()
			var p95 := samples[int(samples.size() * 0.95)]
			print("[BARRAGE PERF] enemies=%d plan=%.2fms p95=%.2fms" % [model.enemies.size(), planning_usec / 1000.0, p95 / 1000.0])
			_expect(p95 < 10000 and planning_usec < 33333, "dense barrage stays within fixed tick budget")
		_move_pointer(Vector2(1100, 500))
		gameplay.call("_sync_pointer_cursor")
		root.remove_child(gameplay)
		gameplay.free()
		_expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "leaving combat restores OS pointer")


func _slot(element: String) -> MenuButton:
	return menu.find_child("SkillSelector_" + element, true, false) as MenuButton


func _choose(element: String, index: int) -> void:
	_slot(element).get_popup().index_pressed.emit(index)
	await _frames()


func _move_pointer(position: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	if not DisplayServer.get_name().contains("headless"):
		root.warp_mouse(position)


func _capture(label: String) -> void:
	if DisplayServer.get_name().contains("headless") or not OS.get_cmdline_user_args().has("--capture"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://Builds/skill-interaction-review"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func _frames() -> void:
	await process_frame
	await process_frame


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(description)
