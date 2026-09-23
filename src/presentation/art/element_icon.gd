extends Control
## Shared tier-specific atlas icon, never reads or advances combat state.
const Icons = preload("res://src/presentation/art/spell_icons.gd")
var element := "fire"
var tier := 1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	Icons.draw(self, size * 0.5, element, tier, minf(size.x, size.y))
	draw_set_transform(Vector2.ZERO)
