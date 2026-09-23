extends SceneTree
## Serial test. GameApp routes --script runs into isolated automated-app-data.
const Art = preload("res://src/presentation/art/game_art.gd")
const Castle = preload("res://src/presentation/art/castle_view.gd")
const UiAssets = preload("res://src/presentation/art/ui_assets.gd")
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const OUTPUT := "res://Builds/production-ui-review"
var app: Node
var passes := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	profile["highest_unlocked_stage"] = 30
	profile["coins"] = 25000
	profile["crystals"] = 240
	profile["upgrades"]["mana_capacity"] = 30
	profile["upgrades"]["lava_moat"] = 3
	profile["upgrades"]["magic_tower"] = 3
	profile["upgrades"]["wall_repair"] = 1000
	for skill in app.get("content").rules["skills"]:
		profile["upgrades"][skill["upgrade_id"]] = 3
		if int(skill["tier"]) == 3:
			profile["equipped_skills"][skill["element"]] = skill["id"]
	app.set("profile", profile)
	_check_assets()
	for locale in ["zh_CN", "en_US"]:
		app.get("settings")["language"] = locale
		for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
			await _check_views(locale, dimensions)
	for failure in failures:
		push_error("[PRODUCTION UI FAIL] " + failure)
	print("[PRODUCTION UI] %d passed, %d failed" % [passes, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check_assets() -> void:
	for key in ["wall", "ballista", "ui_chrome", "ui_symbols"]:
		var texture := Art.texture(key)
		var image := texture.get_image()
		_expect(image.has_mipmaps() and maxi(image.get_width(), image.get_height()) <= 1024, key + " uses bounded mipmapped imports")
		_expect(image.get_pixel(0, 0).a == 0, key + " has true alpha padding")
	var signatures := {}
	for key in UiAssets.SYMBOLS:
		signatures[hash(UiAssets.icon(key).get_image().get_data())] = true
	_expect(signatures.size() == 16, "sixteen distinct painted UI symbols")
	var theme := UiTheme.create()
	for type in ["Button", "MenuButton", "OptionButton"]:
		var normal := theme.get_stylebox("normal", type)
		_expect(normal is StyleBoxTexture, type + " uses the shared painted skin")
		for state in ["hover", "pressed", "disabled"]:
			_expect(normal.get_minimum_size() == theme.get_stylebox(state, type).get_minimum_size(), type + " stable " + state + " dimensions")
	_expect(theme.get_stylebox("background", "ProgressBar") is StyleBoxTexture, "meters have textured metal tracks")
	_expect(Castle.tower_bounds(0).position.y > 100 and Castle.tower_bounds(1).end.y < 1040, "both complete bastions clear the viewport edges")
	_expect(Geometry2D.is_point_in_polygon(Castle.MOUNT_POSITION, PackedVector2Array(Castle.MOUNT_SURFACE)), "fixed ballista foot lands inside the stone platform")


func _check_views(locale: String, dimensions: Vector2i) -> void:
	var viewport := SubViewport.new()
	viewport.size = dimensions
	viewport.size_2d_override = Vector2i(1920, 1080)
	viewport.size_2d_override_stretch = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var prefix := "%s-%d" % [locale, dimensions.x]
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	viewport.add_child(menu)
	await _capture(viewport, prefix + "-menu")
	_expect(not menu.get("_identity_panel").get_theme_stylebox("panel") is StyleBoxTexture, prefix + " unframed home illustration")
	for page in ["_show_stage_select", "_show_honors", "_show_save_data", "_show_settings", "_show_tutorial"]:
		menu.call(page)
		await _capture(viewport, prefix + page)
		_expect(not menu.get("_identity_panel").visible, prefix + page + " uses the full workspace")
		_check_text_fit(menu, prefix + page)
	for definition in app.get("content").rules["research_pages"]:
		var page := str(definition["id"])
		menu.call("_show_research_page", page)
		if page == "magic":
			menu.call("_show_research_page", page, "armageddon")
		await _capture(viewport, prefix + "-research-" + page)
		_check_text_fit(menu, prefix + page)
	menu.free()
	app.set("current_stage_id", "stage_010")
	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	viewport.add_child(game)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	var model: RefCounted = game.get("session").get("_model")
	for tick in range(900):
		model.step([])
	var snapshot: Dictionary = model.snapshot()
	for index in range(snapshot["enemies"].size()):
		snapshot["enemies"][index]["x_milli"] = 740000 + (index % 6) * 174000
		snapshot["enemies"][index]["y_milli"] = 300000 + (index / 6) * 145000
	snapshot["wall_hp"] = int(snapshot["wall_max_hp"]) / 2
	game.call("_on_snapshot", snapshot)
	game.get("_creatures").advance(0.4)
	game.set("_pointer_inside_window", false)
	game.set("_aim_visual_angle", 0.0)
	game.set_process(false)
	game.queue_redraw()
	await _capture(viewport, prefix + "-battle")
	var hud: Control = game.get("_hud")
	var status := hud.find_child("StatusPanel", true, false) as Control
	_expect(not Castle.STRUCTURE_BOUNDS.intersects(status.get_global_rect()), prefix + " HUD never covers either bastion")
	_expect(status.mouse_filter == Control.MOUSE_FILTER_IGNORE, prefix + " decorative HUD passes battlefield input")
	var dock := hud.find_child("SkillDock", true, false) as Control
	_expect(not status.get_global_rect().intersects(dock.get_global_rect()), prefix + " status and spells remain separate")
	_expect(not hud.get("_boss_panel").get_global_rect().intersects(hud.feedback_label.get_global_rect()), prefix + " boss and alerts remain separate")
	for fraction in [0.0, 0.01, 0.5, 1.0]:
		snapshot["wall_hp"] = int(snapshot["wall_max_hp"] * fraction)
		hud.update_snapshot(snapshot)
		_expect(is_equal_approx(hud.get("_wall_bar").value, snapshot["wall_hp"]), prefix + " meter fraction " + str(fraction))
		var bar: ProgressBar = hud.get("_wall_bar")
		var filled: Rect2 = bar.call("fill_rect")
		_expect(is_equal_approx(filled.size.x, (bar.size.x - 24) * bar.value / bar.max_value), prefix + " inset fill preserves low/full health ratio")
	game.call("_show_pause")
	await _capture(viewport, prefix + "-pause")
	game.call("_show_quick_settings")
	await _capture(viewport, prefix + "-quick-settings")
	game.call("_resume_game")
	var result := {"status": "victory", "stage_number": 10, "wave": 3, "wave_total": 3, "kills": 42, "wall_percent": 67, "coins": 1340, "xp": 246, "tick": 1830}
	game.call("_show_result", result, {"ok": true, "crystals_awarded": 12})
	await _capture(viewport, prefix + "-victory")
	_check_text_fit(game, prefix + "-victory")
	game.get("_result_overlay").free()
	game.set("_result_overlay", null)
	result["status"] = "defeat"
	game.call("_show_result", result, {"ok": false})
	await _capture(viewport, prefix + "-defeat-save-error")
	_check_text_fit(game, prefix + "-defeat-save-error")
	paused = false
	viewport.free()


func _check_text_fit(node: Node, context: String) -> void:
	if node is Label and node.is_visible_in_tree() and node.autowrap_mode == TextServer.AUTOWRAP_OFF and node.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
		_expect(node.get_minimum_size().x <= node.size.x + 1, context + " text fits " + node.name)
	for child in node.get_children():
		_check_text_fit(child, context)


func _capture(viewport: SubViewport, file: String) -> void:
	for frame in range(4):
		await process_frame
	if DisplayServer.get_name() == "headless" or not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var screenshot := viewport.get_texture().get_image()
	var colors := {}
	for y in range(0, screenshot.get_height(), 32):
		for x in range(0, screenshot.get_width(), 32):
			colors[screenshot.get_pixel(x, y).to_html(false)] = true
	_expect(colors.size() > 100, "nonblank rendered pixels " + file)
	_expect(screenshot.save_png(OUTPUT.path_join(file + ".png")) == OK, "capture " + file)


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
