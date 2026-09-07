class_name DefenderSkillButton
extends Control

signal pressed

# Circular skill button matching the classic Defender II battle HUD: a gold
# ring, the spell glyph in the middle, a dark radial sweep for the remaining
# cooldown, a draining cooldown ring just outside the circle, and a red
# "low mana" state when the spell is unaffordable.
var skill_id: String = ""
var glyph: String = ""
var hotkey: String = ""
var cooldown_ratio: float = 0.0
var mana_ok: bool = true
var selected: bool = false
var low_mana_text: String = "Low Mana"
var tier: int = 1
var mana_cost: int = 0


func _init() -> void:
	custom_minimum_size = Vector2(112, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_state(p_cooldown_ratio: float, p_mana_ok: bool, p_selected: bool) -> void:
	var clamped := clampf(p_cooldown_ratio, 0.0, 1.0)
	if clamped == cooldown_ratio and p_mana_ok == mana_ok and p_selected == selected:
		return
	cooldown_ratio = clamped
	mana_ok = p_mana_ok
	selected = p_selected
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	var hovering := get_viewport() != null and get_viewport().gui_get_hovered_control() == self
	var base := Color("16263c") if mana_ok else Color("3c1f1f")
	if not mana_ok:
		base = Color("3a1d24")
	draw_circle(center, radius, base)
	var ring := Color("ffd166") if selected else (Color("e6b85c") if hovering else Color("768aa4"))
	draw_arc(center, radius, 0.0, TAU, 48, ring, 4.0, true)
	draw_arc(center, radius - 6.0, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 1.5, true)
	if cooldown_ratio > 0.0:
		# 顺时针由缺到满：施放后整钮压暗，已恢复的份额从顶部顺时针补亮，
		# 冷却结束时整钮复原；外圈亮弧同步生长（施放时无，就绪前接近满圈）。
		draw_circle(center, radius - 2.0, Color(0.02, 0.03, 0.06, 0.78))
		var recovered := 1.0 - cooldown_ratio
		var start := -PI * 0.5
		var end := start + TAU * recovered
		var points := PackedVector2Array([center])
		var steps := 24
		for i in range(steps + 1):
			var angle := start + (end - start) * float(i) / float(steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
		draw_colored_polygon(points, base.lightened(0.08))
		var cooldown_ring := Color("ffd166") if mana_ok else Color("ff6b5e")
		draw_arc(center, radius + 3.0, start, end, 48, cooldown_ring, 4.0, true)
	var font := ThemeDB.fallback_font
	var glyph_size := int(radius * 0.72)
	var glyph_color := Color.WHITE if mana_ok else Color("ff8d7a")
	draw_string(font, center + Vector2(-radius, glyph_size * 0.15), glyph, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, glyph_size, glyph_color)
	if not hotkey.is_empty():
		# Numbered keybind badge (参考 skill buttons show the hotkey); top-right
		# chip so keyboard players can match the 1/2/3 keys without guessing.
		var badge_center := center + Vector2(radius * 0.62, -radius * 0.62)
		var badge_radius := radius * 0.24
		draw_circle(badge_center, badge_radius + 1.5, Color(0.02, 0.05, 0.09, 0.9))
		draw_circle(badge_center, badge_radius, Color("ffd166") if mana_ok else Color("8a6a3a"))
		var badge_size := int(badge_radius * 1.7)
		draw_string(font, badge_center + Vector2(-badge_radius, badge_size * 0.34), hotkey, HORIZONTAL_ALIGNMENT_CENTER, badge_radius * 2.0, badge_size, Color("101d2d"))
	if not mana_ok:
		var text_size := 15
		draw_string(font, center + Vector2(-radius, radius * 0.4), low_mana_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, text_size, Color("ff6b5e"))
	draw_string(font, center + Vector2(-radius, radius * 0.78), "◈ %d" % mana_cost, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 18, Color("91d9ff"))
	draw_string(font, center + Vector2(-radius * 0.75, -radius * 0.45), ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(tier, 1, 3) - 1], HORIZONTAL_ALIGNMENT_LEFT, 30, 20, Color("ffd166"))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		pressed.emit()
