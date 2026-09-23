extends RefCounted
## One screen-vertical wall, shared by both sides of every fixture, extending
## beyond the viewport. Tower artwork does not determine the wall's projection.
const Art = preload("res://src/presentation/art/game_art.gd")
const BOW_ORIGIN := Vector2(245, 555)
const MOUNT_POSITION := BOW_ORIGIN + Vector2(0, 32)
const MOUNT_SURFACE := [Vector2(188, 564), Vector2(281, 564), Vector2(304, 597), Vector2(210, 597)]
const FLOOR_TINT := Color(1.04, 1.02, 0.86)
const WALL_INNER_X := 142.0
const WALL_CREST_X := 206.0
const WALL_FRONT_X := 264.0
const WALL_TOP := -96.0
const WALL_BOTTOM := 1176.0
const WALL_RECT := Rect2(WALL_INNER_X, WALL_TOP, WALL_FRONT_X - WALL_INNER_X, WALL_BOTTOM - WALL_TOP)
const STRUCTURE_BOUNDS := Rect2(118, WALL_TOP, 190, WALL_BOTTOM - WALL_TOP)
const TOWER_SOURCE_SIZE := Vector2(1024, 1536)
const TOWER_SOCKET_SOURCE := Vector2(662, 1165)
const TOWER_SCALE := 0.42
const TOWER_TINT := Color(0.69, 0.83, 0.88)
const TOWER_ORIGINS := [Vector2(199, 235), Vector2(199, 833)]
const TOWER_OUTLINE := [Vector2(539, 1060), Vector2(758, 1060), Vector2(820, 1101), Vector2(840, 1430), Vector2(837, 1505), Vector2(760, 1533), Vector2(525, 1533), Vector2(492, 1487), Vector2(507, 1346), Vector2(520, 1240), Vector2(522, 1118)]
const BOW_SOURCE_SIZE := Vector2(1448, 1086)
const BOW_SCALE := 0.18
const BOW_RAIL_SOURCE := Vector2(650, 294)
const BOW_RAIL_ANGLE := -0.035
static var _wall_mesh: ArrayMesh
static var _platform_mesh: ArrayMesh
static var _tower_mesh: ArrayMesh


static func floor_key(snapshot: Dictionary) -> String:
	return "lava" if int(snapshot.get("defenses", {}).get("lava_moat_level", 0)) > 0 else "battle"


static func magic_origin() -> Vector2:
	return TOWER_ORIGINS[0] - Vector2(0, 14)


static func crystal_origins() -> Array[Vector2]:
	return [magic_origin(), TOWER_ORIGINS[1] - Vector2(0, 14)]


static func tower_bounds(index: int) -> Rect2:
	return Rect2(TOWER_ORIGINS[index] + (Vector2(492, 1060) - TOWER_SOCKET_SOURCE) * TOWER_SCALE, Vector2(348, 473) * TOWER_SCALE)


static func impact_position(world_y: float) -> Vector2:
	return Vector2(WALL_FRONT_X, world_y)


static func draw_structure(canvas: CanvasItem) -> void:
	prepare()
	canvas.draw_rect(Rect2(WALL_FRONT_X, WALL_TOP, 14, WALL_BOTTOM - WALL_TOP), Color(0.025, 0.045, 0.05, 0.27))
	canvas.draw_mesh(_wall_mesh, Art.texture("masonry"))
	for origin in TOWER_ORIGINS:
		var scale := Vector2.ONE * TOWER_SCALE
		canvas.draw_mesh(_tower_mesh, Art.texture("wall"), Transform2D(0, scale, 0, origin + Vector2(6, 7)), Color(0.02, 0.04, 0.045, 0.3))
		canvas.draw_mesh(_tower_mesh, Art.texture("wall"), Transform2D(0, scale, 0, origin), TOWER_TINT)
		# A small crystal fits the original socket instead of a tall blue spire.
		Art.draw_sprite(canvas, Art.region("fortress_fx", Rect2(0.025, 0.015, 0.425, 0.475)), origin - Vector2(0, 9), Vector2(42, 51), 0, Color(0.72, 0.84, 0.9))
	canvas.draw_mesh(_platform_mesh, Art.texture("masonry"))


static func prepare() -> void:
	if _wall_mesh != null:
		return
	var data := _data()
	# Opaque mortar seals the same continuous vertical footprint at every y.
	_quad(data, Rect2(142, WALL_TOP, 122, WALL_BOTTOM - WALL_TOP), Color(0.32, 0.40, 0.43))
	for row in range(-3, 25):
		_stone(data, Rect2(145, row * 52.0 + 1, 59, 50), Color(0.85, 0.97, 0.98), row)
	for course in range(2):
		for row in range(-3, 29):
			var y := row * 44.0 + course * 22.0
			_stone(data, Rect2(218 + course * 22, y + 1, 21, 42), Color(0.66, 0.79, 0.81) * (1.0 - course * 0.1), row + course)
	for row in range(-3, 28):
		_stone(data, Rect2(204, row * 48.0, 16, 47), Color(1.14, 1.23, 1.20), row)
	for row in range(-2, 18):
		var y := row * 70.0
		if y > 510 and y < 635:
			continue
		# Identical merlons; the x coordinates never advance towards the viewer.
		_poly(data, PackedVector2Array([Vector2(205, y + 2), Vector2(228, y + 2), Vector2(241, y + 13), Vector2(218, y + 13)]), Color(1.28, 1.35, 1.28), row)
		_stone(data, Rect2(218, y + 13, 23, 31), Color(0.96, 1.08, 1.05), row)
		_poly(data, PackedVector2Array([Vector2(205, y + 2), Vector2(218, y + 13), Vector2(218, y + 44), Vector2(205, y + 33)]), Color(0.76, 0.89, 0.91), row)
	_wall_mesh = _mesh(data)
	data = _data()
	# The projecting seat overlays the wall, without offsetting either section.
	_poly(data, PackedVector2Array(MOUNT_SURFACE), Color(1.03, 1.15, 1.13))
	_poly(data, PackedVector2Array([Vector2(188, 564), Vector2(210, 597), Vector2(210, 627), Vector2(188, 594)]), Color(0.55, 0.67, 0.71))
	for column in range(3):
		_stone(data, Rect2(210 + column * 31.3, 598, 30, 28), Color(0.70, 0.82, 0.84), column)
	_stone(data, Rect2(190, 548, 19, 27), Color(0.99, 1.10, 1.08))
	_stone(data, Rect2(280, 573, 18, 27), Color(0.99, 1.10, 1.08))
	_platform_mesh = _mesh(data)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for point in TOWER_OUTLINE:
		var local: Vector2 = point - TOWER_SOCKET_SOURCE
		vertices.append(Vector3(local.x, local.y, 0))
		uvs.append(point / TOWER_SOURCE_SIZE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(PackedVector2Array(TOWER_OUTLINE))
	_tower_mesh = ArrayMesh.new()
	_tower_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


static func _data() -> Dictionary:
	return {"vertices": PackedVector3Array(), "uvs": PackedVector2Array(), "colors": PackedColorArray(), "indices": PackedInt32Array()}


static func _quad(data: Dictionary, rect: Rect2, tint: Color, variant: int = 0) -> void:
	_poly(data, PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]), tint, variant)


static func _stone(data: Dictionary, rect: Rect2, tint: Color, variant: int = 0) -> void:
	_quad(data, rect, tint, variant)
	_quad(data, Rect2(rect.position, Vector2(rect.size.x, 1.5)), tint * 1.20, variant)
	_quad(data, Rect2(rect.position, Vector2(1.2, rect.size.y)), tint * 1.10, variant)
	_quad(data, Rect2(rect.position.x, rect.end.y - 1.5, rect.size.x, 1.5), tint * 0.62, variant)


static func _poly(data: Dictionary, points: PackedVector2Array, tint: Color, variant: int = 0) -> void:
	var offset: int = data.vertices.size()
	var atlas_uv := Vector2(0.02 + posmod(variant, 2) * 0.5, 0.02 + posmod(variant / 2, 2) * 0.5)
	var corners := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
	for index in range(points.size()):
		var point := points[index]
		data.vertices.append(Vector3(point.x, point.y, 0))
		data.uvs.append(atlas_uv + corners[index] * 0.46)
		data.colors.append(Color(tint.r, tint.g, tint.b, 1.0))
	for index in Geometry2D.triangulate_polygon(points):
		data.indices.append(offset + index)


static func _mesh(data: Dictionary) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.vertices
	arrays[Mesh.ARRAY_TEX_UV] = data.uvs
	arrays[Mesh.ARRAY_COLOR] = data.colors
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
