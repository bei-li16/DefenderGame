extends RefCounted
## Opaque castle interior, separate from the exterior battle/moat plate.
## The edge sits underneath the new fortress, continuing beyond both screen ends.
## All clipped paving and foundation geometry is built once, never per frame.
const Art = preload("res://src/presentation/art/game_art.gd")
const BLEED := 48.0
const EDGE := [Vector2(183, -48), Vector2(183, 355), Vector2(205, 505), Vector2(224, 685), Vector2(254, 885), Vector2(283, 1128)]
const GROUT := Color("28323e")
const TILE_AXIS_U := Vector2(190, 95)
const TILE_AXIS_V := Vector2(-190, 95)
const PAVING_TINT := Color(0.78, 0.82, 0.87, 1)
static var _floor_mesh: ArrayMesh
static var _paving_mesh: ArrayMesh
static var _trim_mesh: ArrayMesh
static var _shadow_mesh: ArrayMesh


static func boundary_x(y: float) -> float:
	for index in range(1, EDGE.size()):
		var previous: Vector2 = EDGE[index - 1]
		var next: Vector2 = EDGE[index]
		if y <= next.y:
			return lerpf(previous.x, next.x, clampf((y - previous.y) / (next.y - previous.y), 0, 1))
	return EDGE[-1].x


static func polygon() -> PackedVector2Array:
	var points := PackedVector2Array([Vector2(-BLEED, -BLEED)])
	for point in EDGE:
		points.append(point)
	points.append(Vector2(-BLEED, 1080 + BLEED))
	return points


static func draw(canvas: CanvasItem) -> void:
	prepare()
	canvas.draw_mesh(_shadow_mesh, null)
	canvas.draw_mesh(_floor_mesh, null)
	canvas.draw_mesh(_paving_mesh, Art.texture("courtyard"))
	canvas.draw_mesh(_trim_mesh, null)


static func prepare() -> void:
	if _floor_mesh != null:
		return
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var clip := polygon()
	# A continuous alpha=1 underlay seals grout and transparent PNG gaps.
	_append_polygon(vertices, colors, indices, clip, GROUT)
	_floor_mesh = _mesh(vertices, colors, indices)
	_prepare_paving(clip)
	vertices = PackedVector3Array()
	colors = PackedColorArray()
	indices = PackedInt32Array()
	# Segmented perimeter footing anchors the wall, following its projection,
	# not the rectangular transparent padding of its source PNG.
	for step in range(30):
		var y := -BLEED + step * 40.0
		var near_x := boundary_x(y)
		var far_x := boundary_x(y + 40)
		var stone := PackedVector2Array([Vector2(near_x - 26, y), Vector2(near_x, y), Vector2(far_x, y + 40), Vector2(far_x - 26, y + 40)])
		_append_clipped(vertices, colors, indices, stone, clip, Color("738091") if step % 3 == 0 else Color("657383"))
		var seam := PackedVector2Array([Vector2(near_x - 26, y), Vector2(near_x, y), Vector2(near_x, y + 2), Vector2(near_x - 26, y + 2)])
		_append_clipped(vertices, colors, indices, seam, clip, GROUT)
	# Inner contact shade darkens the paving towards the wall.
	for index in range(1, EDGE.size()):
		var a: Vector2 = EDGE[index - 1]
		var b: Vector2 = EDGE[index]
		_append_gradient_quad(vertices, colors, indices, a - Vector2(66, 0), a - Vector2(26, 0), b - Vector2(26, 0), b - Vector2(66, 0), Color(0.04, 0.06, 0.09, 0), Color(0.04, 0.06, 0.09, 0.36))
	_trim_mesh = _mesh(vertices, colors, indices)
	vertices = PackedVector3Array()
	colors = PackedColorArray()
	indices = PackedInt32Array()
	# Exterior foundation shadow goes UNDER the opaque city layer.
	for index in range(1, EDGE.size()):
		var a: Vector2 = EDGE[index - 1]
		var b: Vector2 = EDGE[index]
		_append_gradient_quad(vertices, colors, indices, a, a + Vector2(30, 6), b + Vector2(30, 6), b, Color(0.015, 0.025, 0.04, 0.55), Color(0.015, 0.025, 0.04, 0))
	_shadow_mesh = _mesh(vertices, colors, indices)


static func _prepare_paving(clip: PackedVector2Array) -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var uvs := PackedVector2Array()
	for row in range(-2, 8):
		for column in range(-2, 8):
			var tile := PackedVector2Array()
			for corner in [Vector2(column, row), Vector2(column + 1, row), Vector2(column + 1, row + 1), Vector2(column, row + 1)]:
				tile.append(_tile_to_world(corner))
			for part in Geometry2D.intersect_polygons(tile, clip):
				if Geometry2D.triangulate_polygon(part).is_empty():
					continue
				_append_polygon(vertices, colors, indices, part, PAVING_TINT)
				for point in part:
					var uv := Vector2((point.x / TILE_AXIS_U.x + point.y / TILE_AXIS_U.y) * 0.5 - column, (point.y / TILE_AXIS_U.y - point.x / TILE_AXIS_U.x) * 0.5 - row)
					# Reflect ONLY the ground texture at repeat boundaries: same
					# edge texels meet even if generated art is not pixel-seamless.
					# The fortress sprite itself is never reflected or repeated.
					if posmod(column, 2) == 1:
						uv.x = 1.0 - uv.x
					if posmod(row, 2) == 1:
						uv.y = 1.0 - uv.y
					uvs.append(uv.clamp(Vector2.ZERO, Vector2.ONE))
	_paving_mesh = _mesh(vertices, colors, indices, uvs)


static func _tile_to_world(point: Vector2) -> Vector2:
	return point.x * TILE_AXIS_U + point.y * TILE_AXIS_V


static func _append_clipped(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, points: PackedVector2Array, clip: PackedVector2Array, color: Color) -> void:
	for part in Geometry2D.intersect_polygons(points, clip):
		_append_polygon(vertices, colors, indices, part, color)


static func _append_polygon(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, points: PackedVector2Array, color: Color) -> void:
	var triangles := Geometry2D.triangulate_polygon(points)
	if triangles.is_empty():
		return
	var offset := vertices.size()
	for point in points:
		vertices.append(Vector3(point.x, point.y, 0))
		colors.append(color)
	for index in triangles:
		indices.append(offset + index)


static func _append_gradient_quad(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, a: Vector2, b: Vector2, c: Vector2, d: Vector2, inner: Color, outer: Color) -> void:
	var offset := vertices.size()
	for point in [a, b, c, d]:
		vertices.append(Vector3(point.x, point.y, 0))
	colors.append_array(PackedColorArray([inner, outer, outer, inner]))
	indices.append_array(PackedInt32Array([offset, offset + 1, offset + 2, offset, offset + 2, offset + 3]))


static func _mesh(vertices: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
