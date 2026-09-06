extends SceneTree

const SaveService = preload("res://src/application/save_service.gd")

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
	var original_save_service: Variant = app.get("save_service")
	var test_directory := "user://menu-selection-acceptance-test"
	var absolute_directory := ProjectSettings.globalize_path(test_directory)
	_delete_test_directory(absolute_directory)
	app.set("save_service", SaveService.new(test_directory))
	var test_profile := original_profile.duplicate(true)
	test_profile["tutorial_complete"] = true
	var upgrades: Dictionary = test_profile.get("upgrades", {}).duplicate(true)
	upgrades["coin_bounty"] = 0
	upgrades["xp_bounty"] = 4
	test_profile["upgrades"] = upgrades
	test_profile["coins"] = 100000
	app.set("profile", test_profile)

	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	root.add_child(menu)
	await process_frame
	await process_frame

	menu.call("_show_research_page", "utility")
	await process_frame
	var tree := _research_tree(menu)
	_expect(tree != null, "research page builds a research tree")
	_expect(tree != null and str(tree.call("selected")) == "coin_bounty", "a freshly opened research page selects its first node")

	var purchase_button := _purchase_button(menu)
	_expect(purchase_button != null and not purchase_button.disabled, "the selected node offers an affordable purchase button")
	if tree != null:
		tree.call("select", "xp_bounty")
		await process_frame
	purchase_button = _purchase_button(menu)
	if purchase_button != null:
		purchase_button.emit_signal("pressed")
	await process_frame

	var rebuilt_tree := _research_tree(menu)
	_expect(rebuilt_tree != null and rebuilt_tree != tree, "purchasing rebuilds the research page")
	_expect(rebuilt_tree != null and str(rebuilt_tree.call("selected")) == "xp_bounty", "selection survives the purchase rebuild")
	var updated_upgrades: Dictionary = app.get("profile").get("upgrades", {})
	_expect(int(updated_upgrades.get("xp_bounty", 0)) == 5, "the purchase itself landed on the selected node")

	menu.call("_show_research_page", "magic")
	await process_frame
	var magic_tree := _research_tree(menu)
	_expect(magic_tree != null and str(magic_tree.call("selected")) == "fire_mastery", "switching pages restarts selection at that page's first node")

	root.remove_child(menu)
	menu.free()
	app.set("profile", original_profile)
	app.set("save_service", original_save_service)
	_delete_test_directory(absolute_directory)
	if app.get("audio") != null:
		app.get("audio").stop_all()
	for failure in failures:
		push_error("[MENUSEL FAIL] " + failure)
	print("[MENUSEL] %d passed, %d failed" % [passes, failures.size()])
	quit(failures.size())


func _research_tree(menu: Node) -> Node:
	# Match by script path: preloading the tree script here would compile it
	# before autoload registration and break its GameApp references.
	for child in menu.find_children("*", "", true, false):
		var script: Variant = child.get_script()
		if script != null and str(script.resource_path).ends_with("research_tree.gd"):
			return child
	return null


func _purchase_button(menu: Node) -> Button:
	var upgrade_label: String = str(root.get_node("GameApp").call("text", "common.upgrade"))
	for child in menu.find_children("*", "Button", true, false):
		var button := child as Button
		if button != null and button.text.contains(upgrade_label):
			return button
	return null


func _expect(condition: bool, description: String) -> void:
	if condition:
		passes += 1
		print("[MENUSEL PASS] " + description)
	else:
		failures.append(description)


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
