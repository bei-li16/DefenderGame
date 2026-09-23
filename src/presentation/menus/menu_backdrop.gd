extends Control

const Art = preload("res://src/presentation/art/game_art.gd")
var _clock := 0.0


func _process(delta: float) -> void:
	_clock = fmod(_clock + delta, 120.0)
	if str(GameApp.settings.get("quality", "medium")) != "low":
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	resized.connect(queue_redraw)


func _draw() -> void:
	Art.cover(self, "menu", Rect2(Vector2.ZERO, size))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.08, 0.18))
	# Shade the command side of the illustration without boxing the hero art.
	draw_polygon(PackedVector2Array([Vector2(size.x * 0.40, 0), Vector2(size.x, 0), size, Vector2(size.x * 0.40, size.y)]),
		PackedColorArray([Color(0.02, 0.025, 0.02, 0), Color(0.02, 0.025, 0.02, 0.52), Color(0.02, 0.025, 0.02, 0.52), Color(0.02, 0.025, 0.02, 0)]))
	# Bottom vignette keeps the title readable without hiding the illustration.
	draw_polygon(PackedVector2Array([Vector2(0, size.y * 0.48), Vector2(size.x, size.y * 0.48), size, Vector2(0, size.y)]),
		PackedColorArray([Color(0.015, 0.025, 0.055, 0), Color(0.015, 0.025, 0.055, 0), Color(0.015, 0.025, 0.055, 0.78), Color(0.015, 0.025, 0.055, 0.78)]))
	# Only 20 ambient motes; arithmetic phases never consume gameplay RNG.
	if str(GameApp.settings.get("quality", "medium")) != "low":
		for index in range(20):
			var phase := fposmod(_clock * (0.045 + (index % 3) * 0.012) + index * 0.137, 1.0)
			var point := Vector2(size.x * (0.06 + fposmod(index * 0.173, 0.84)) + sin(phase * TAU + index) * 30, size.y * (1.0 - phase))
			var tint := Color("f8b45b") if index % 3 else Color("99dfff")
			draw_circle(point, 2.0 + index % 3, Color(tint, sin(phase * PI) * 0.25))
