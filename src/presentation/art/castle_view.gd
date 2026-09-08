extends RefCounted
## The replacement PNG is one connected fortress. Preserve its projection and
## transparency: no copied towers, tiled wall faces or stretching. The opaque
## courtyard is a separate ground layer, not a modification of this sprite.
const Art = preload("res://src/presentation/art/game_art.gd")
const SOURCE_SIZE := Vector2(1024, 1536)
const SPRITE_SCALE := 0.6
const BOW_ORIGIN := Vector2(245, 555)
const MOUNT_SOURCE := Vector2(633, 740)
const MOUNT_POSITION := BOW_ORIGIN + Vector2(0, 40)
const SPRITE_POSITION := MOUNT_POSITION - MOUNT_SOURCE * SPRITE_SCALE
const SPRITE_RECT := Rect2(SPRITE_POSITION, SOURCE_SIZE * SPRITE_SCALE)
const FAR_CRYSTAL_SOURCE := Vector2(489, 103)
const NEAR_CRYSTAL_SOURCE := Vector2(626, 1032)
const PEDESTAL_UV := Rect2(0.32, 0.46, 0.22, 0.175)
const PEDESTAL_SIZE := Vector2(62, 37)
const PEDESTAL_POSITION := MOUNT_POSITION - Vector2(0, PEDESTAL_SIZE.y * 0.5)
const BOW_SIZE := Vector2(200, 91)
# Battlefield-facing silhouette, measured in the unmodified source PNG.
# Contact VFX follow the masonry instead of the old fixed x=315 line.
const IMPACT_EDGE := [Vector2(600, 225), Vector2(584, 440), Vector2(608, 620), Vector2(711, 760), Vector2(620, 898), Vector2(730, 1195), Vector2(740, 1410)]


static func floor_key(snapshot: Dictionary) -> String:
	return "lava" if int(snapshot.get("defenses", {}).get("lava_moat_level", 0)) > 0 else "battle"


static func source_to_world(point: Vector2) -> Vector2:
	return SPRITE_POSITION + point * SPRITE_SCALE


static func magic_origin() -> Vector2:
	return source_to_world(FAR_CRYSTAL_SOURCE)


static func impact_position(world_y: float) -> Vector2:
	var source_y := (world_y - SPRITE_POSITION.y) / SPRITE_SCALE
	var source_x: float = IMPACT_EDGE[0].x
	for index in range(1, IMPACT_EDGE.size()):
		var previous: Vector2 = IMPACT_EDGE[index - 1]
		var next: Vector2 = IMPACT_EDGE[index]
		var weight := clampf((source_y - previous.y) / (next.y - previous.y), 0.0, 1.0)
		source_x = lerpf(previous.x, next.x, weight)
		if source_y <= next.y:
			break
	return Vector2(source_to_world(Vector2(source_x, 0)).x, world_y)


static func draw_structure(canvas: CanvasItem, tower_active: bool, clock: float) -> void:
	Art.draw_sprite(canvas, Art.texture("wall"), SPRITE_RECT.get_center(), SPRITE_RECT.size)
	if tower_active:
		for point in [FAR_CRYSTAL_SOURCE, NEAR_CRYSTAL_SOURCE]:
			var crystal := source_to_world(point)
			canvas.draw_circle(crystal, 17, Color(0.3, 0.75, 1, 0.2 + sin(clock * 3.0) * 0.06))
			canvas.draw_arc(crystal, 14, 0, TAU, 24, Color(0.6, 0.9, 1, 0.6), 1.5)
