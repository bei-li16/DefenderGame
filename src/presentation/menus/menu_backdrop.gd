extends Control

const Art = preload("res://src/presentation/art/game_art.gd")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)


func _draw() -> void:
	Art.cover(self, "menu", Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.08, 0.18))
	# Bottom vignette keeps the title readable without hiding the illustration.
	draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.48), Vector2(size.x, size.y * 0.48), size, Vector2(0, size.y)]),
		PackedColorArray([Color(0.015, 0.025, 0.055, 0), Color(0.015, 0.025, 0.055, 0), Color(0.015, 0.025, 0.055, 0.78), Color(0.015, 0.025, 0.055, 0.78)]))
