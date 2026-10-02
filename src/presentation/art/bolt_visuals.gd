extends RefCounted
## Shared, rigid projectile sprites. A weapon owns one color and silhouette;
## combat flags never select or tint a different bolt.
const Art = preload("res://src/presentation/art/game_art.gd")
const ROWS := {"basic_bow": 0, "power_bow": 1, "hurricane_bow": 2, "phantom_bow": 3}
const WIDTH := 96.0
# Measured transparent gutters and opaque head tips in the 1536x1024 source.
# The authored rows are uneven; equal-quarter slicing would clip the fins.
const SOURCE_SIZE := Vector2(1536, 1024)
const BANDS := [Vector2(0, 304), Vector2(304, 533), Vector2(533, 746), Vector2(746, 1024)]
const TIPS := [Vector2(108, 193), Vector2(98, 420), Vector2(110, 643), Vector2(100, 862)]


static func weapon_key(projectile: Dictionary, fallback: String = "basic_bow") -> String:
	var key := str(projectile.get("weapon_id", fallback))
	return key if ROWS.has(key) else "basic_bow"


static func sprite(weapon: String) -> AtlasTexture:
	var row := int(ROWS.get(weapon, 0))
	var band: Vector2 = BANDS[row]
	return Art.region("bolt_types", Rect2(Vector2(0, band.x) / SOURCE_SIZE, Vector2(SOURCE_SIZE.x, band.y - band.x) / SOURCE_SIZE))


static func draw(canvas: CanvasItem, projectile: Dictionary, fallback: String = "basic_bow") -> void:
	var position := Vector2(float(projectile["x_milli"]), float(projectile["y_milli"])) / 1000.0
	var velocity := Vector2(float(projectile["vx_milli"]), float(projectile["vy_milli"])).normalized()
	var weapon := weapon_key(projectile, fallback)
	var asset := sprite(weapon)
	var row := int(ROWS[weapon])
	var band: Vector2 = BANDS[row]
	var dimensions := Vector2(WIDTH, WIDTH * asset.get_height() / asset.get_width())
	var tip_offset: Vector2 = (TIPS[row] - Vector2(SOURCE_SIZE.x * 0.5, (band.x + band.y) * 0.5)) * WIDTH / SOURCE_SIZE.x
	var angle := velocity.angle() + PI
	Art.draw_sprite(canvas, asset, position - tip_offset.rotated(angle), dimensions, angle)
