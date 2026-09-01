extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")

const TEST_DIRECTORY := "user://save-crash-acceptance"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var absolute_directory := ProjectSettings.globalize_path(TEST_DIRECTORY)
	_delete_test_directory(absolute_directory)
	var service := SaveService.new(TEST_DIRECTORY)
	var baseline := service.save_profile({"generation": 1, "coins": 73, "blob": "baseline", "reward_ledger": []}, 1)
	if not bool(baseline.get("ok", false)):
		push_error("Could not establish baseline save: " + str(baseline))
		quit(2)
		return
	var marker := FileAccess.open(TEST_DIRECTORY + "/ready.marker", FileAccess.WRITE)
	if marker == null:
		push_error("Could not create ready marker")
		quit(3)
		return
	marker.store_string("ready")
	marker.flush()
	print("[CRASH WRITER] baseline ready")
	await process_frame
	var large_blob := "x".repeat(96 * 1024 * 1024)
	var interrupted_candidate := {"generation": 2, "coins": 999, "blob": large_blob, "reward_ledger": []}
	var result := service.save_profile(interrupted_candidate, 1)
	print("[CRASH WRITER] save completed before termination: " + str(result))
	quit(0)


func _delete_test_directory(absolute_path: String) -> void:
	if not DirAccess.dir_exists_absolute(absolute_path):
		return
	var directory := DirAccess.open(absolute_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var item := directory.get_next()
	while not item.is_empty():
		var item_path := absolute_path.path_join(item)
		if directory.current_is_dir():
			_delete_test_directory(item_path)
		else:
			DirAccess.remove_absolute(item_path)
		item = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(absolute_path)
