extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _draw() -> void:
	var size := get_viewport_rect().size
	for band in range(12):
		var ratio := float(band) / 11.0
		var color := Color("132a46").lerp(Color("07101d"), ratio)
		draw_rect(Rect2(0, size.y * ratio, size.x, size.y / 10.0 + 2.0), color)
	var moon_center := Vector2(size.x * 0.72, size.y * 0.22)
	draw_circle(moon_center, size.y * 0.105, Color(0.93, 0.78, 0.48, 0.15))
	draw_circle(moon_center, size.y * 0.078, Color(0.98, 0.88, 0.66, 0.22))
	var ridge := PackedVector2Array([
		Vector2(0, size.y * 0.72), Vector2(size.x * 0.12, size.y * 0.52),
		Vector2(size.x * 0.25, size.y * 0.70), Vector2(size.x * 0.40, size.y * 0.46),
		Vector2(size.x * 0.58, size.y * 0.69), Vector2(size.x * 0.75, size.y * 0.51),
		Vector2(size.x, size.y * 0.72), Vector2(size.x, size.y), Vector2(0, size.y)
	])
	draw_colored_polygon(ridge, Color("101b29"))
	for tower_x in [size.x * 0.08, size.x * 0.16, size.x * 0.26]:
		draw_rect(Rect2(tower_x, size.y * 0.48, size.x * 0.055, size.y * 0.34), Color("1d3045"))
		draw_colored_polygon(PackedVector2Array([Vector2(tower_x - 8, size.y * 0.48), Vector2(tower_x + size.x * 0.0275, size.y * 0.40), Vector2(tower_x + size.x * 0.055 + 8, size.y * 0.48)]), Color("283e55"))
	for ember in range(24):
		var x := fmod(float(ember * 193), size.x)
		var y := size.y * 0.72 + fmod(float(ember * 71), size.y * 0.25)
		draw_circle(Vector2(x, y), 2.0 + float(ember % 3), Color(1.0, 0.38, 0.12, 0.22 + 0.03 * float(ember % 4)))

