extends RefCounted
## Normalized regions survive import size limits and exported resource remaps.
const Art = preload("res://src/presentation/art/game_art.gd")
const SYMBOLS := {
	"coin": 0, "crystal": 1, "health": 2, "mana": 3,
	"battle": 4, "skull": 5, "settings": 6, "honor": 7,
	"research": 8, "save": 9, "tutorial": 10, "tower": 11,
	"back": 12, "next": 13, "check": 14, "close": 15,
}
const CHROME := {
	"panel": Rect2(32, 32, 568, 546),
	"button": Rect2(686, 58, 510, 491),
	"primary": Rect2(55, 662, 523, 491),
	"socket": Rect2(669, 632, 541, 538),
}


static func icon(key: String) -> Texture2D:
	var index := int(SYMBOLS.get(key, 10))
	return Art.region("ui_symbols", Rect2(Vector2(index % 4, index / 4) * 0.25, Vector2.ONE * 0.25))


static func chrome(key: String) -> Texture2D:
	var rect: Rect2 = CHROME[key]
	return Art.region("ui_chrome", Rect2(rect.position / 1254.0, rect.size / 1254.0))


static func image(key: String, side: float = 32.0) -> TextureRect:
	var node := TextureRect.new()
	node.texture = icon(key)
	node.custom_minimum_size = Vector2.ONE * side
	node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node


static func decorate(button: Button, key: String, side: int = 30) -> void:
	button.icon = icon(key)
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", side)
	button.add_theme_constant_override("h_separation", 12)
