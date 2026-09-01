extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")

const TEST_DIRECTORY := "user://save-crash-acceptance"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var service := SaveService.new(TEST_DIRECTORY)
	var loaded := service.load_profile({"generation": 0})
	var generation := int(loaded.get("payload", {}).get("generation", 0))
	var valid := bool(loaded.get("ok", false)) and generation in [1, 2]
	if valid:
		print("[CRASH VERIFY] valid generation=%d source=%s recovered=%s" % [generation, loaded.get("source", "unknown"), loaded.get("recovered", false)])
	else:
		push_error("[CRASH VERIFY] no valid main or backup: " + str(loaded))
	_delete_test_directory(ProjectSettings.globalize_path(TEST_DIRECTORY))
	quit(0 if valid else 1)


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
