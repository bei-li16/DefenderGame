class_name DefenderSkillButton
extends Control
const Icons = preload("res://src/presentation/art/spell_icons.gd")
const UiAssets = preload("res://src/presentation/art/ui_assets.gd")

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
var cooldown_seconds: int = 0
var element: String = "fire"


func _init() -> void:
	custom_minimum_size = Vector2(112, 112)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


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
	draw_texture_rect(UiAssets.chrome("socket"), Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), false, Color.WHITE if mana_ok else Color(0.65, 0.6, 0.6))
	if selected or hovering or has_focus():
		draw_arc(center, radius + 1, 0.0, TAU, 64, Color("a6dac5") if has_focus() else Color("e8cc85"), 2.0, true)
	Icons.draw(self, center + Vector2(0, -5), element, tier, radius * 1.33, Color.WHITE if mana_ok else Color(0.48, 0.48, 0.52))
	if cooldown_ratio > 0.0:
		# Paint only the remaining sector OVER the illustration. The recovered
		# part reveals the actual art, rather than replacing it with a flat fill.
		var recovered := 1.0 - cooldown_ratio
		var top := -PI * 0.5
		var start := top + TAU * recovered
		var end := top + TAU
		var points := PackedVector2Array([center])
		var steps := 24
		for i in range(steps + 1):
			var angle := start + (end - start) * float(i) / float(steps)
			points.append(center + Vector2(cos(angle), sin(angle)) * (radius - 2.0))
		draw_colored_polygon(points, Color(0.02, 0.03, 0.06, 0.78))
		var cooldown_ring := Color("ffd166") if mana_ok else Color("ff6b5e")
		if recovered > 0.001:
			draw_arc(center, radius + 3.0, top, start, 48, cooldown_ring, 4.0, true)
	var font := ThemeDB.fallback_font
	if cooldown_seconds > 0:
		draw_circle(center + Vector2(0, -6), 25, Color(0.02, 0.04, 0.08, 0.9))
		draw_string(font, center + Vector2(-25, 3), str(cooldown_seconds), HORIZONTAL_ALIGNMENT_CENTER, 50, 26, Color("fff2cf"))
	if not hotkey.is_empty():
		# Numbered keybind badge (参考 skill buttons show the hotkey); top-right
		# chip so keyboard players can match the 1/2/3 keys without guessing.
		var badge_center := center + Vector2(radius * 0.62, -radius * 0.62)
		var badge_radius := radius * 0.24
		draw_circle(badge_center, badge_radius + 1.5, Color(0.02, 0.05, 0.09, 0.9))
		draw_circle(badge_center, badge_radius, Color("242c27"))
		draw_arc(badge_center, badge_radius, 0, TAU, 24, Color("ad9c6e"), 1.2, true)
		var badge_size := int(badge_radius * 1.7)
		draw_string(font, badge_center + Vector2(-badge_radius, badge_size * 0.34), hotkey, HORIZONTAL_ALIGNMENT_CENTER, badge_radius * 2.0, badge_size, Color("eadbbc"))
	if not mana_ok:
		var text_size := 15
		draw_string(font, center + Vector2(-radius, radius * 0.4), low_mana_text, HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, text_size, Color("ff6b5e"))
	draw_string(font, center + Vector2(-radius, radius * 0.78), str(mana_cost), HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, 17, Color("91d9ff"))
	draw_circle(center + Vector2(-radius * 0.6, -radius * 0.57), 13, Color("142235"))
	draw_string(font, center + Vector2(-radius * 0.83, -radius * 0.45), ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(tier, 1, 3) - 1], HORIZONTAL_ALIGNMENT_CENTER, 26, 18, Color("ffd166"))


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		accept_event()
		pressed.emit()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		pressed.emit()
