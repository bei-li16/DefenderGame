extends SceneTree
## Visual fixture using the actual gameplay renderer and isolated --script saves.
## Deliberately arranged enemies/poses; not a continuous gameplay recording.
const OUTPUT := "res://Builds/straight-wall-review"
var app: Node
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name().contains("headless"):
		push_error("Fortress capture requires a graphical renderer; omit --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	app = root.get_node("GameApp")
	app.set_process(false)
	app.get("settings")["auto_fire"] = false
	app.get("settings")["screen_shake"] = false
	app.get("settings")["quality"] = "high"
	var profile: Dictionary = app.call("_default_profile")
	profile["tutorial_complete"] = true
	app.set("profile", profile)
	for dimensions in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		var viewport := SubViewport.new()
		viewport.size = dimensions
		viewport.size_2d_override = Vector2i(1920, 1080)
		viewport.size_2d_override_stretch = true
		viewport.disable_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var game := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
		viewport.add_child(game)
		game.set_process(false)
		game.set_physics_process(false)
		game.get("session").set_physics_process(false)
		game.set("_pointer_inside_window", false)
		var model: RefCounted = game.get("session").get("_model")
		for tick in range(330):
			model.step([])
		var snapshot: Dictionary = model.snapshot()
		for index in range(snapshot["enemies"].size()):
			snapshot["enemies"][index]["x_milli"] = 950000 + (index % 5) * 160000
			snapshot["enemies"][index]["y_milli"] = 400000 + (index % 3) * 165000
		for level in [0, 1]:
			snapshot["defenses"] = {"lava_moat_level": level, "magic_tower_level": level}
			game.call("_on_snapshot", snapshot)
			game.get("_creatures").advance(0.4)
			for pose in [{"name": "level", "angle": 0.0, "recoil": 0.0}, {"name": "up", "angle": -55.0, "recoil": 0.0}, {"name": "down", "angle": 55.0, "recoil": 0.0}, {"name": "recoil", "angle": -25.0, "recoil": 1.0}]:
				game.set("_aim_visual_angle", deg_to_rad(pose.angle))
				game.set("_bow_recoil", pose.recoil)
				game.set("_tower_flash", pose.recoil)
				game.queue_redraw()
				for frame in range(4):
					await process_frame
				await RenderingServer.frame_post_draw
				var screenshot := viewport.get_texture().get_image()
				var name := "%d-%s-%s" % [dimensions.x, "lava" if level > 0 else "ordinary", pose.name]
				if screenshot.save_png(OUTPUT.path_join(name + ".png")) != OK:
					failures += 1
				# Detail crops are taken from the actual renderer output.
				var scale := float(dimensions.x) / 1920.0
				var detail := screenshot.get_region(Rect2i(Vector2i(Vector2(135, 410) * scale), Vector2i(Vector2(260, 290) * scale)))
				if detail.save_png(OUTPUT.path_join(name + "-detail.png")) != OK:
					failures += 1
		viewport.free()
	app.get("audio").stop_all()
	print("[POSE REVIEW] 16 actual gameplay captures, 16 detail crops; failures=%d" % failures)
	quit(0 if failures == 0 else 1)
