class_name DefenderResearchTree
extends Control

signal node_selected(upgrade_id: String)

# Tree-shaped research layout matching the classic Defender II research pages:
# root upgrades on the left, each prerequisite→child pair linked by an arrow,
# the selected node highlighted with a gold frame.
const NODE_SIZE := Vector2(250, 88)
const COLUMN_GAP := 278.0
const ROW_GAP := 118.0
const ORIGIN := Vector2(24, 24)

var _definitions: Array = []
var _levels: Dictionary = {}
var _coins: int = 0
var _selected_id: String = ""
var _node_buttons: Dictionary = {}
var _node_rects: Dictionary = {}
var _edges: Array = []


func build(definitions: Array, levels: Dictionary, coins: int, selected_id: String = "") -> void:
	_definitions = definitions
	_levels = levels
	_coins = coins
	for child in get_children():
		child.queue_free()
	_node_buttons.clear()
	_node_rects.clear()
	_edges.clear()
	var depths := {}
	var by_id := {}
	for definition in _definitions:
		by_id[str(definition.get("id", ""))] = definition
	for definition in _definitions:
		var upgrade_id := str(definition.get("id", ""))
		depths[upgrade_id] = _depth_of(upgrade_id, by_id, depths)
	var column_rows := {}
	var max_depth := 0
	for definition in _definitions:
		var upgrade_id := str(definition.get("id", ""))
		var depth: int = depths[upgrade_id]
		max_depth = maxi(max_depth, depth)
		var row := int(column_rows.get(depth, 0))
		column_rows[depth] = row + 1
		_node_rects[upgrade_id] = Rect2(ORIGIN + Vector2(depth * COLUMN_GAP, row * ROW_GAP), NODE_SIZE)
		for prerequisite in definition.get("prerequisites", []):
			if by_id.has(str(prerequisite)):
				_edges.append([str(prerequisite), upgrade_id])
	for definition in _definitions:
		var upgrade_id := str(definition.get("id", ""))
		var button := Button.new()
		button.position = _node_rects[upgrade_id].position
		button.size = NODE_SIZE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		var level := int(_levels.get(upgrade_id, 0))
		var max_level := int(definition.get("max_level", 0))
		button.text = "%s\nLv %d/%d" % [GameApp.text(str(definition.get("name_key", upgrade_id))), level, max_level]
		var unlocked := _prerequisites_met(definition)
		button.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.55, 0.6, 0.68, 1)
		button.pressed.connect(func() -> void: select(upgrade_id))
		add_child(button)
		_node_buttons[upgrade_id] = button
	var rows_total := 0
	for depth in column_rows.keys():
		rows_total = maxi(rows_total, int(column_rows[depth]))
	custom_minimum_size = Vector2((max_depth + 1) * COLUMN_GAP + 60, rows_total * ROW_GAP + 80)
	_selected_id = ""
	select(selected_id if _node_buttons.has(selected_id) else (str(_definitions[0].get("id", "")) if not _definitions.is_empty() else ""))


func select(upgrade_id: String) -> void:
	if upgrade_id.is_empty() or not _node_buttons.has(upgrade_id):
		return
	_selected_id = upgrade_id
	for id in _node_buttons.keys():
		var button: Button = _node_buttons[id]
		button.add_theme_stylebox_override("normal", _node_box(id == _selected_id))
		button.add_theme_stylebox_override("hover", _node_box(id == _selected_id))
	queue_redraw()
	node_selected.emit(upgrade_id)


func selected() -> String:
	return _selected_id


func _depth_of(upgrade_id: String, by_id: Dictionary, depths: Dictionary) -> int:
	if depths.has(upgrade_id):
		return depths[upgrade_id]
	var definition: Dictionary = by_id.get(upgrade_id, {})
	var depth := 0
	for prerequisite in definition.get("prerequisites", []):
		var prerequisite_id := str(prerequisite)
		if by_id.has(prerequisite_id) and prerequisite_id != upgrade_id:
			depth = maxi(depth, _depth_of(prerequisite_id, by_id, depths) + 1)
	depths[upgrade_id] = depth
	return depth


func _prerequisites_met(definition: Dictionary) -> bool:
	for prerequisite in definition.get("prerequisites", []):
		if int(_levels.get(str(prerequisite), 0)) <= 0:
			return false
	return true


func _draw() -> void:
	for edge in _edges:
		var from_rect: Rect2 = _node_rects.get(edge[0], Rect2())
		var to_rect: Rect2 = _node_rects.get(edge[1], Rect2())
		if from_rect.size == Vector2.ZERO or to_rect.size == Vector2.ZERO:
			continue
		var start := Vector2(from_rect.position.x + from_rect.size.x, from_rect.get_center().y)
		var end := Vector2(to_rect.position.x, to_rect.get_center().y)
		var child_definition: Dictionary = {}
		for definition in _definitions:
			if str(definition.get("id", "")) == edge[1]:
				child_definition = definition
				break
		var met := _prerequisites_met(child_definition)
		var color := Color("e6b85c") if met else Color("4b5666")
		var mid := Vector2((start.x + end.x) * 0.5, start.y)
		var mid2 := Vector2(mid.x, end.y)
		draw_line(start, mid, color, 3.0, true)
		draw_line(mid, mid2, color, 3.0, true)
		draw_line(mid2, end, color, 3.0, true)
		var head := PackedVector2Array([end, end + Vector2(-10, -6), end + Vector2(-10, 6)])
		draw_colored_polygon(head, color)


func _node_box(highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1d3050") if highlighted else Color("263a54")
	style.border_color = Color("ffd166") if highlighted else Color("768aa4")
	style.set_border_width_all(3 if highlighted else 2)
	style.set_corner_radius_all(10)
	return style
