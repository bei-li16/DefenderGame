extends SceneTree

const Art = preload("res://src/presentation/art/game_art.gd")
const Castle = preload("res://src/presentation/art/castle_view.gd")
const Courtyard = preload("res://src/presentation/art/courtyard_view.gd")
var failures: Array[String] = []
var passes := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var app := root.get_node("GameApp")
	app.set_process(false)
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	app.set("profile", profile)
	app.get("settings")["auto_fire"] = false
	_expect(Castle.floor_key({}) == "battle", "missing upgrades use the complete normal floor")
	for level in [0, 1, 5]:
		_expect(Castle.floor_key({"defenses": {"lava_moat_level": level}}) == ("battle" if level == 0 else "lava"), "whole-plate selection at moat level %d" % level)
	_expect(Art.FILES["wall"] == "主城墙new", "wall resolves to the new complete fortress asset")
	var wall := Art.texture("wall")
	_expect(wall != null and wall.get_height() <= 1024, "replacement uses the bounded Godot import")
	var wall_image := wall.get_image()
	_expect(wall_image.has_mipmaps(), "wall import keeps mipmaps for small gameplay scale")
	_expect(wall_image.get_pixel(0, 0).a == 0.0, "new fortress padding remains truly transparent")
	_expect(Castle.source_to_world(Castle.MOUNT_SOURCE).is_equal_approx(Castle.MOUNT_POSITION), "painted platform aligns to the ballista pedestal")
	_expect(is_equal_approx(Castle.PEDESTAL_POSITION.y + Castle.PEDESTAL_SIZE.y * 0.5, Castle.MOUNT_POSITION.y), "pedestal rests on the existing platform, not a second stone tower")
	_expect(Castle.SPRITE_RECT.size.is_equal_approx(Castle.SOURCE_SIZE * Castle.SPRITE_SCALE), "whole fortress retains uniform scale and original projection")
	_expect(Castle.SPRITE_RECT.position.y > 145.0 and Castle.SPRITE_RECT.end.y <= 1080.0, "both roofs and foundations fit inside the gameplay canvas")
	_expect(Castle.magic_origin().is_equal_approx(Castle.source_to_world(Castle.FAR_CRYSTAL_SOURCE)), "magic beam starts at the new far crystal")
	_expect(Castle.magic_origin().y < Castle.BOW_ORIGIN.y and Castle.source_to_world(Castle.NEAR_CRYSTAL_SOURCE).y > Castle.BOW_ORIGIN.y, "the two original upright bastions bracket the firing seat")
	for height in [200.0, 450.0, 595.0, 850.0, 1000.0]:
		var impact := Castle.impact_position(height)
		_expect(impact.y == height and impact.x > 200.0 and impact.x < 320.0, "contact effects follow the new wall at y=%d" % int(height))
	var player: Dictionary = app.get("content").rules["player"]
	_expect(Castle.BOW_ORIGIN == Vector2(float(player["bow_origin_x_milli"]), float(player["bow_origin_y_milli"])) / 1000.0, "composition preserves the actual combat firing origin")
	var tower_arrays := Art.quad().surface_get_arrays(0)
	var vertices: PackedVector3Array = tower_arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = tower_arrays[Mesh.ARRAY_TEX_UV]
	_expect(vertices[0].y < vertices[-1].y and uvs[0].y < uvs[-1].y, "entire fortress remains upright, not vertically mirrored")
	_expect(uvs[0] == Vector2.ZERO and uvs[2] == Vector2.ONE, "wall uses the entire new sprite, not old tower cutouts")
	_expect(Art.quad() == Art.quad(), "castle quad is shared, not rebuilt each frame")
	_check_courtyard_geometry()

	var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.get("session").set_physics_process(false)
	var snapshot: Dictionary = game.get("snapshot").duplicate(true)
	var interior_samples := {}
	for level in [0, 1]:
		snapshot["defenses"] = {"lava_moat_level": level, "magic_tower_level": 1}
		game.call("_on_snapshot", snapshot)
		game.set("_aim_visual_angle", 0.0)
		game.queue_redraw()
		for frame in range(3):
			await process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var screenshot := root.get_texture().get_image()
			var interior_stable := true
			var sample_count := 0
			for y in [155.0, 350.0, 550.0, 750.0, 890.0, 1030.0]:
				for x in [2.0, 45.0, 90.0, 120.0, 165.0, 200.0, 240.0]:
					if x > Courtyard.boundary_x(y) - 4.0:
						continue
					var position := Vector2(x, y)
					var pixel := Vector2i(position * Vector2(screenshot.get_size()) / Vector2(1920, 1080))
					var actual := screenshot.get_pixelv(pixel)
					if level == 0:
						interior_samples[position] = actual
					else:
						var previous: Color = interior_samples[position]
						interior_stable = interior_stable and _color_distance(actual, previous) < 0.012
					sample_count += 1
			_expect(sample_count >= 30 and interior_stable, "all city interior pixels are independent of the exterior plate at moat level %d" % level)
			# A sample unobscured by fortress/trim must be our painted paving,
			# not just any uniform opaque rectangle or the outside battle floor.
			var paving_position := Vector2(25, 525)
			var paving_uv := Vector2((paving_position.x / Courtyard.TILE_AXIS_U.x + paving_position.y / Courtyard.TILE_AXIS_U.y) * 0.5, (paving_position.y / Courtyard.TILE_AXIS_U.y - paving_position.x / Courtyard.TILE_AXIS_U.x) * 0.5)
			var tile := Vector2i(paving_uv.floor())
			paving_uv -= Vector2(tile)
			if posmod(tile.x, 2) == 1:
				paving_uv.x = 1.0 - paving_uv.x
			if posmod(tile.y, 2) == 1:
				paving_uv.y = 1.0 - paving_uv.y
			var paving_image := Art.texture("courtyard").get_image()
			var paving_expected := paving_image.get_pixelv(Vector2i(paving_uv * Vector2(paving_image.get_size()))) * Courtyard.PAVING_TINT
			var paving_actual := screenshot.get_pixelv(Vector2i(paving_position * Vector2(screenshot.get_size()) / Vector2(1920, 1080)))
			_expect(_color_distance(paving_actual, paving_expected) < 0.09, "interior visibly uses the painted flagstone material")
			# Sample both bastions and the connecting wall away from the HUD,
			# ballista and crystal overlays; guards against the old UV composition.
			for source_point in [Vector2(490, 320), Vector2(505, 615), Vector2(610, 1200)]:
				var world_point := Castle.source_to_world(source_point)
				var screen_point := Vector2i(world_point * Vector2(screenshot.get_size()) / Vector2(1920, 1080))
				var texel := Vector2i(source_point / Castle.SOURCE_SIZE * Vector2(wall_image.get_size()))
				var expected_wall := wall_image.get_pixelv(texel)
				var actual_wall := screenshot.get_pixelv(screen_point)
				var wall_difference := Vector3(actual_wall.r - expected_wall.r, actual_wall.g - expected_wall.g, actual_wall.b - expected_wall.b).length()
				_expect(expected_wall.a > 0.95 and wall_difference < 0.18, "scene renders the replacement fortress at " + str(source_point))
			# Pixels away from UI/castle must come from the chosen FULL plate.
			# This catches the previous narrow lava-strip-on-normal-floor bug.
			var key := Castle.floor_key(snapshot)
			var source := Art.texture(key).get_image()
			var destination_size := Vector2(screenshot.get_size())
			var factor := maxf(destination_size.x / source.get_width(), destination_size.y / source.get_height())
			var crop := (Vector2(source.get_size()) - destination_size / factor) * 0.5
			for normalized in [Vector2(0.20, 0.36), Vector2(0.22, 0.70), Vector2(0.68, 0.42), Vector2(0.83, 0.64)]:
				var point := Vector2i(normalized * destination_size)
				var uv := Vector2i(crop + Vector2(point) / factor)
				var expected := source.get_pixelv(uv) * Color(0.86, 0.9, 0.98)
				var actual := screenshot.get_pixelv(point)
				var difference := Vector3(actual.r - expected.r, actual.g - expected.g, actual.b - expected.b).length()
				_expect(difference < 0.07, "battlefield pixels belong to the full %s plate" % key)
			if OS.get_cmdline_user_args().has("--capture"):
				var directory := "res://Builds/castle-review"
				DirAccess.make_dir_recursive_absolute(directory)
				_expect(screenshot.save_png(directory.path_join("%s.png" % key)) == OK, "saved " + key + " comparison")
	game.free()
	print("[CASTLE] %d passed, %d failed" % [passes, failures.size()])
	for message in failures:
		printerr("[CASTLE FAIL] " + message)
	quit(0 if failures.is_empty() else 1)


func _check_courtyard_geometry() -> void:
	var paving := Art.texture("courtyard")
	_expect(paving != null and maxi(paving.get_width(), paving.get_height()) <= 512, "courtyard resource resolves through a bounded import")
	var paving_image := paving.get_image()
	_expect(paving_image.detect_alpha() == Image.ALPHA_NONE and paving_image.has_mipmaps(), "paving material is fully opaque and mipmapped")
	Courtyard.prepare()
	var base: ArrayMesh = Courtyard._floor_mesh
	var paving_mesh: ArrayMesh = Courtyard._paving_mesh
	var trim: ArrayMesh = Courtyard._trim_mesh
	Courtyard.prepare()
	_expect(base == Courtyard._floor_mesh and paving_mesh == Courtyard._paving_mesh and trim == Courtyard._trim_mesh, "interior geometry is cached across redraws")
	var arrays := base.surface_get_arrays(0)
	var opaque := true
	for color in arrays[Mesh.ARRAY_COLOR]:
		opaque = opaque and color.a == 1.0
	_expect(opaque and not arrays[Mesh.ARRAY_INDEX].is_empty(), "continuous opaque underlay seals even the paving joints")
	for y in [0, 155, 550, 890, 1079]:
		_expect(Geometry2D.is_point_in_polygon(Vector2(0, y), Courtyard.polygon()) and not Geometry2D.is_point_in_polygon(Vector2(350, y), Courtyard.polygon()), "interior covers screen edge but leaves the moat outside at y=%d" % y)
	_expect(Courtyard.BLEED >= 32.0, "interior extends past viewport edges for combat shake")
	var texture_arrays := paving_mesh.surface_get_arrays(0)
	var bounded_uvs := true
	for uv in texture_arrays[Mesh.ARRAY_TEX_UV]:
		bounded_uvs = bounded_uvs and uv.x >= 0 and uv.y >= 0 and uv.x <= 1 and uv.y <= 1
	_expect(bounded_uvs and texture_arrays[Mesh.ARRAY_VERTEX].size() < 1024, "clipped paving uses bounded UVs and lightweight shared geometry")


func _color_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _expect(condition: bool, message: String) -> void:
	if condition:
		passes += 1
	else:
		failures.append(message)
