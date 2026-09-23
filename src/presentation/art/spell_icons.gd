extends RefCounted
## One art source for research, loadout, dropdowns, battle HUD and cast cursor.
## Rows are elements, columns are tiers. Atlas/mesh allocations are cached.
const Art = preload("res://src/presentation/art/game_art.gd")
const ELEMENTS := ["fire", "ice", "lightning"]


static func texture(element: String, tier: int) -> AtlasTexture:
	var row := maxi(0, ELEMENTS.find(element))
	return Art.region("spell_icons", Rect2(float(clampi(tier, 1, 3) - 1) / 3.0, float(row) / 3.0, 1.0 / 3.0, 1.0 / 3.0))


static func draw(canvas: CanvasItem, center: Vector2, element: String, tier: int, diameter: float = 62.0, tint: Color = Color.WHITE) -> void:
	Art.draw_sprite(canvas, texture(element, tier), center, Vector2.ONE * diameter, 0, tint)
