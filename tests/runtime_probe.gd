extends SceneTree

const TEST_SECONDS := 8.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name().contains("headless"):
		push_error("Runtime probe requires a real display server")
		quit(2)
		return
	var app := root.get_node("GameApp")
	var original_profile: Dictionary = app.get("profile").duplicate(true)
	var original_stage: String = str(app.get("current_stage_id"))
	var original_seed: int = int(app.get("current_seed"))
	var probe_profile := original_profile.duplicate(true)
	probe_profile["tutorial_complete"] = true
	probe_profile["highest_unlocked_stage"] = 10
	probe_profile["upgrades"] = {"strength": 12, "agility": 6, "fire_mastery": 8, "ice_mastery": 8, "lightning_mastery": 8}
	app.set("profile", probe_profile)
	app.set("current_stage_id", "stage_007")
	app.set("current_seed", 707070)
	var gameplay := (load("res://scenes/gameplay.tscn") as PackedScene).instantiate()
	root.add_child(gameplay)
	await create_timer(1.0).timeout
	var session: Node = gameplay.get("session")
	session.call("queue_command", {"type": "aim", "x_milli": 1500000, "y_milli": 540000})
	session.call("queue_command", {"type": "fire_started"})
	var frame_intervals_usec: Array[int] = []
	var started_usec := Time.get_ticks_usec()
	var previous_frame_usec := started_usec
	while float(Time.get_ticks_usec() - started_usec) / 1000000.0 < TEST_SECONDS:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		frame_intervals_usec.append(now_usec - previous_frame_usec)
		previous_frame_usec = now_usec
	var elapsed_usec := Time.get_ticks_usec() - started_usec
	frame_intervals_usec.sort()
	var p95_usec := frame_intervals_usec[int(floor(float(frame_intervals_usec.size() - 1) * 0.95))]
	var average_fps := float(frame_intervals_usec.size()) * 1000000.0 / float(elapsed_usec)
	var static_memory := OS.get_static_memory_usage()
	var peak_static_memory := OS.get_static_memory_peak_usage()
	var snapshot: Dictionary = session.call("current_snapshot")
	print("[RUNTIME] renderer=%s fps_avg=%.2f frame_p95=%.2fms engine_fps=%.2f static=%.2fMiB peak_static=%.2fMiB enemies=%d projectiles=%d nodes=%d" % [
		RenderingServer.get_current_rendering_method(),
		average_fps,
		float(p95_usec) / 1000.0,
		Engine.get_frames_per_second(),
		float(static_memory) / (1024.0 * 1024.0),
		float(peak_static_memory) / (1024.0 * 1024.0),
		snapshot.get("enemies", []).size(),
		snapshot.get("projectiles", []).size(),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	])
	var valid := average_fps >= 55.0 and p95_usec <= 25000 and peak_static_memory < 750 * 1024 * 1024 and RenderingServer.get_current_rendering_method() == "gl_compatibility"
	paused = false
	root.remove_child(gameplay)
	gameplay.free()
	app.set("profile", original_profile)
	app.set("current_stage_id", original_stage)
	app.set("current_seed", original_seed)
	if app.get("audio") != null:
		app.get("audio").shutdown()
	await process_frame
	await process_frame
	if not valid:
		push_error("Runtime frame, memory, or renderer gate failed")
	quit(0 if valid else 1)
