extends RefCounted
## Code-native elemental emblem: independent of platform emoji fonts, centered
## on the actual cast coordinate. Shared by all three tiers of each family.


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
	if element == "fire":
		_polygon(canvas, center, [Vector2(0, -25), Vector2(11, -8), Vector2(10, -15), Vector2(21, 2), Vector2(19, 14), Vector2(10, 23), Vector2(-7, 23), Vector2(-18, 14), Vector2(-20, 3), Vector2(-10, -15), Vector2(-9, 1)], tint)
		_polygon(canvas, center, [Vector2(2, -5), Vector2(11, 11), Vector2(7, 21), Vector2(-5, 21), Vector2(-10, 13)], Color("ffe598"))
	elif element == "ice":
		for index in range(6):
			var direction := Vector2.UP.rotated(index * TAU / 6.0)
			canvas.draw_line(center, center + direction * 24, tint, 3.5, true)
			for sign_value in [-1, 1]:
				canvas.draw_line(center + direction * 14, center + direction * 14 + direction.rotated(sign_value * PI / 3) * 9, tint, 2.5, true)
		canvas.draw_circle(center, 4, Color("e6faff"))
	else:
		_polygon(canvas, center, [Vector2(3, -25), Vector2(-17, 5), Vector2(-2, 5), Vector2(-7, 25), Vector2(19, -7), Vector2(5, -7), Vector2(12, -25)], tint)
		canvas.draw_line(center + Vector2(2, -15), center + Vector2(-7, 1), Color("fff2c4"), 3.0, true)
	var badge := center + Vector2(25, 27)
	canvas.draw_circle(badge, 13, Color("16263c"))
	canvas.draw_string(ThemeDB.fallback_font, badge + Vector2(-12, 6), ["Ⅰ", "Ⅱ", "Ⅲ"][clampi(tier, 1, 3) - 1], HORIZONTAL_ALIGNMENT_CENTER, 24, 17, tint)
	if not valid:
		canvas.draw_circle(center + Vector2(-27, 26), 10, Color("bd3934"))
		canvas.draw_line(center + Vector2(-33, 26), center + Vector2(-21, 26), Color.WHITE, 3, true)


static func _polygon(canvas: CanvasItem, center: Vector2, points: Array, color: Color) -> void:
	var vertices := PackedVector2Array()
	for point in points:
		vertices.append(center + point)
	canvas.draw_colored_polygon(vertices, color)
