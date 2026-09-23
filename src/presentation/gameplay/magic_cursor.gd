extends RefCounted
## Tier-specific painted spell art centered on the actual cast coordinate.
const Icons = preload("res://src/presentation/art/spell_icons.gd")


static func draw(canvas: CanvasItem, center: Vector2, element: String, tier: int, valid: bool, elapsed: float) -> void:
	var tint := Color("ff963f")
	if element == "ice":
		tint = Color("79dcff")
	elif element == "lightning":
		tint = Color("dab5ff")
	canvas.draw_circle(center, 33.0, Color(0.025, 0.055, 0.11, 0.86))
	canvas.draw_arc(center, 33.0, 0, TAU, 48, tint if valid else Color("ff6659"), 2.5, true)
	var phase := elapsed * 0.6
	for index in range(3):
		var start := phase + index * TAU / 3.0
		canvas.draw_arc(center, 38.0, start, start + 0.8, 10, Color(tint, 0.7), 2.0, true)
	Icons.draw(canvas, center, element, tier, 56, Color.WHITE if valid else Color(0.7, 0.7, 0.7))
	var badge := center + Vector2(25, 27)
	canvas.draw_circle(badge, 13, Color("16263c"))
	canvas.draw_string(ThemeDB.fallback_font, badge + Vector2(-12, 6), ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(tier, 1, 3) - 1], HORIZONTAL_ALIGNMENT_CENTER, 24, 17, tint)
	if not valid:
		canvas.draw_circle(center + Vector2(-27, 26), 10, Color("bd3934"))
		canvas.draw_line(center + Vector2(-33, 26), center + Vector2(-21, 26), Color.WHITE, 3, true)


static func draw_symbol(canvas: CanvasItem, center: Vector2, element: String, tint: Color, tier: int = 1) -> void:
	Icons.draw(canvas, center, element, tier, 62, tint)
