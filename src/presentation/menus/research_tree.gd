class_name DefenderResearchTree
extends Control

const Art = preload("res://src/presentation/art/game_art.gd")
const ResearchCatalog = preload("res://src/core/rules/research_catalog.gd")
const ResearchText = preload("res://src/presentation/research_text.gd")

signal node_selected(upgrade_id: String)

# Tree-shaped research layout matching the classic Defender II research pages:
# root upgrades on the left, each prerequisite→child pair linked by an arrow,
# the selected node highlighted with a gold frame.  Each node bar carries an
# element-tinted icon square with the level badge (top-right) and the
# next-level price (bottom-left), then the upgrade name.
const NODE_SIZE := Vector2(280, 92)
const COLUMN_GAP := 308.0
const ROW_GAP := 118.0
const ORIGIN := Vector2(24, 24)
const ICON_SIZE := 64.0

const NODE_GLYPHS := {
	"strength": "💪", "agility": "🎯", "power_mastery": "💥", "hurricane_mastery": "🌪",
	"power_shot": "💥", "poisoned_arrow": "☠", "fatal_blow": "ϟ", "multiple_arrows": "➶", "senior_hunter": "★",
	"phantom_mastery": "👻", "fire_mastery": "🔥", "ice_mastery": "❄", "lightning_mastery": "⚡",
	"meteor": "☄", "armageddon": "☄", "frost_nova": "❄", "ice_age": "❄", "thunder_storm": "ϟ", "ragnarok": "ϟ",
	"mana_capacity": "🔮", "mana_regen": "✨", "spell_radius": "🔆", "cooldown_mastery": "⏱",
	"wall_armor": "🛡", "wall_repair": "🔨", "lava_moat": "🌋", "magic_tower": "🗼",
	"coin_bounty": "🪙", "xp_bounty": "⭐"
}

var _definitions: Array = []
var _levels: Dictionary = {}
var _balances: Dictionary = {}
var _selected_id: String = ""
var _node_buttons: Dictionary = {}
var _node_rects: Dictionary = {}
var _edges: Array = []


func build(definitions: Array, levels: Dictionary, balances: Dictionary, selected_id: String = "") -> void:
	_definitions = definitions
	_levels = levels
	_balances = balances
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
	# Richer spell comparisons need a little more vertical room (especially
	# English descriptions); retain all three primary rows without scrolling.
	var row_gap := 110.0 if not _definitions.is_empty() and str(_definitions[0].get("page", "")) == "magic" else ROW_GAP
	for definition in _definitions:
		var upgrade_id := str(definition.get("id", ""))
		var depth: int = int(definition.get("tree_column", depths[upgrade_id]))
		max_depth = maxi(max_depth, depth)
		var row := int(definition.get("tree_row", column_rows.get(depth, 0)))
		column_rows[depth] = maxi(int(column_rows.get(depth, 0)), row + 1)
		_node_rects[upgrade_id] = Rect2(ORIGIN + Vector2(depth * COLUMN_GAP, row * row_gap), NODE_SIZE)
		for prerequisite in definition.get("prerequisites", []):
			if by_id.has(str(prerequisite)):
				_edges.append([str(prerequisite), upgrade_id])
	for definition in _definitions:
		var upgrade_id := str(definition.get("id", ""))
		var button := Button.new()
		button.name = "Research_" + upgrade_id
		button.position = _node_rects[upgrade_id].position
		button.size = NODE_SIZE
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		_populate_node(button, definition)
		var unlocked := _prerequisites_met(definition)
		button.modulate = Color(1, 1, 1, 1) if unlocked else Color(0.55, 0.6, 0.68, 1)
		button.pressed.connect(func() -> void: select(upgrade_id))
		add_child(button)
		_node_buttons[upgrade_id] = button
	var rows_total := 0
	for depth in column_rows.keys():
		rows_total = maxi(rows_total, int(column_rows[depth]))
	custom_minimum_size = Vector2((max_depth + 1) * COLUMN_GAP + 60, rows_total * row_gap + 80)
	_selected_id = ""
	select(selected_id if _node_buttons.has(selected_id) else (str(_definitions[0].get("id", "")) if not _definitions.is_empty() else ""))


# Original-style node bar: icon square (glyph, level badge, price badge) plus
# the display name; children ignore the mouse so the Button keeps ownership.
func _populate_node(button: Button, definition: Dictionary) -> void:
	var upgrade_id := str(definition.get("id", ""))
	var level := ResearchCatalog.normalize_level(definition, int(_levels.get(upgrade_id, 0)))
	var icon_origin := Vector2(14, 14)
	var icon := ColorRect.new()
	icon.position = icon_origin
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.color = _icon_color(upgrade_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	var glyph := Label.new()
	glyph.text = str(NODE_GLYPHS.get(upgrade_id, "✦"))
	glyph.position = Vector2.ZERO
	glyph.size = icon.size
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.add_theme_font_size_override("font_size", 34)
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.add_child(glyph)
	if not str(definition.get("weapon_ref", "")).is_empty():
		glyph.hide()
		var illustration := TextureRect.new()
		illustration.texture = Art.texture(str(definition["weapon_ref"]))
		illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		illustration.size = icon.size
		illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(illustration)
	var level_badge := Label.new()
	level_badge.name = "ResearchLevel"
	level_badge.text = "Lv %s" % ResearchText.compact(level)
	if definition.has("skill_ref"):
		var skill := GameApp.content.find_by_id("skills", str(definition["skill_ref"]))
		level_badge.text = "%s · %s" % [["Ⅰ", "Ⅱ", "Ⅲ"][clampi(int(skill.get("tier", 1)), 1, 3) - 1], ResearchText.compact(level)]
	if ResearchCatalog.is_endless(definition):
		level_badge.text += " ∞"
	level_badge.position = icon_origin + Vector2(-6, -6)
	level_badge.size = Vector2(84, 18)
	level_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_badge.add_theme_font_size_override("font_size", 13)
	level_badge.add_theme_color_override("font_color", Color("8ce99a"))
	level_badge.add_theme_color_override("font_outline_color", Color("101d2d"))
	level_badge.add_theme_constant_override("outline_size", 4)
	level_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(level_badge)
	var price_badge := Label.new()
	price_badge.name = "ResearchPrice"
	if not ResearchCatalog.can_upgrade(definition, level):
		price_badge.text = GameApp.text("common.max")
		price_badge.add_theme_color_override("font_color", Color("9fb2c8"))
	else:
		var price := GameApp.upgrade_service.price_for_level(definition, level)
		var currency := str(definition.get("currency", "coins"))
		var glyph_symbol := "✦" if currency == "crystals" else "◆"
		var affordable_color := Color("8fd3ff") if currency == "crystals" else Color("ffd166")
		price_badge.text = "%s %s" % [glyph_symbol, ResearchText.compact(price)]
		button.tooltip_text = "Lv.%d · %s %d" % [level, glyph_symbol, price]
		price_badge.add_theme_color_override("font_color", affordable_color if int(_balances.get(currency, 0)) >= price else Color("8693a6"))
	price_badge.position = icon_origin + Vector2(-2.0, ICON_SIZE - 4.0)
	price_badge.size = Vector2(84, 18)
	price_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_badge.add_theme_font_size_override("font_size", 13)
	price_badge.add_theme_color_override("font_outline_color", Color("101d2d"))
	price_badge.add_theme_constant_override("outline_size", 4)
	price_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(price_badge)
	var name_label := Label.new()
	name_label.text = GameApp.text(str(definition.get("name_key", upgrade_id)))
	name_label.position = Vector2(icon_origin.x + ICON_SIZE + 12.0, 0.0)
	name_label.size = Vector2(NODE_SIZE.x - icon_origin.x - ICON_SIZE - 24.0, NODE_SIZE.y)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 25)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(name_label)


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
		if int(_levels.get(str(prerequisite), 0)) < int(definition.get("prerequisite_levels", {}).get(str(prerequisite), 1)):
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


func _icon_color(upgrade_id: String) -> Color:
	var upgrade := GameApp.content.find_by_id("upgrades", upgrade_id)
	var skill := GameApp.content.find_by_id("skills", str(upgrade.get("skill_ref", "")))
	match str(skill.get("element", "")):
		"fire": return Color("a8543a")
		"ice": return Color("3a7d8c")
		"lightning": return Color("7a5aa8")
	if upgrade_id.contains("fire") or upgrade_id == "strength":
		return Color("a8543a")
	if upgrade_id.contains("ice") or upgrade_id == "agility":
		return Color("3a7d8c")
	if upgrade_id.contains("lightning"):
		return Color("7a5aa8")
	if upgrade_id == "poisoned_arrow":
		return Color("477d39")
	if upgrade_id == "fatal_blow":
		return Color("a64355")
	if upgrade_id == "multiple_arrows":
		return Color("7150a2")
	if upgrade_id == "senior_hunter":
		return Color("947a3a")
	if upgrade_id.contains("mana") or upgrade_id.contains("spell") or upgrade_id.contains("cooldown"):
		return Color("44549c")
	if upgrade_id.contains("wall") or upgrade_id.contains("moat") or upgrade_id.contains("tower"):
		return Color("56684a")
	if upgrade_id.contains("bounty"):
		return Color("8a7a3a")
	return Color("4a5a6a")
