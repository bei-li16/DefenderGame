extends RefCounted
## Bounded presentation-only animation. No particles/nodes spawned per frame,
## no combat RNG, no scheduling damage and no changes to collision anchors.
const Art = preload("res://src/presentation/art/game_art.gd")
const Castle = preload("res://src/presentation/art/castle_view.gd")
const Spell = preload("res://src/presentation/art/spell_visuals.gd")
const LAVA_UV := Rect2(0.0, 0.5, 0.5, 0.5)
const CHIPS_UV := Rect2(0.5, 0.5, 0.5, 0.5)
# Source-space outlines separate the original upper assembly and pedestal.
# Unlike a rectangular crop, this excludes the old hinge/tower without cutting
# through the lower bowstring. UVs still sample the untouched imported PNG.
const UPPER_OUTLINE := [Vector2(100, 0), Vector2(1448, 0), Vector2(1448, 600), Vector2(870, 600), Vector2(770, 500), Vector2(720, 450), Vector2(636, 394), Vector2(568, 403), Vector2(535, 425), Vector2(455, 439), Vector2(300, 447), Vector2(266, 477), Vector2(147, 477), Vector2(100, 415)]
const BASE_OUTLINE := [Vector2(516, 519), Vector2(730, 519), Vector2(763, 553), Vector2(789, 676), Vector2(728, 693), Vector2(530, 693), Vector2(476, 677), Vector2(493, 560)]
const BASE_FOOT_SOURCE := Vector2(635, 693)
static var _upper_mesh: ArrayMesh
static var _base_mesh: ArrayMesh


static func terrain(canvas: CanvasItem, moat: bool, clock: float, detail: float) -> void:
	if not moat:
		return
	# Decorations remain INSIDE the painted channel. No vertical overlay strip,
	# no tint over the courtyard, and no screen-wide flash or refraction pass.
	for index in range(maxi(3, int(7 * detail))):
		var phase := fposmod(clock * 0.28 + index * 0.618, 1.0)
		var y := 185.0 + fposmod(index * 173.0 + clock * 8.0, 880.0)
		var x := 365.0 + y * 0.046 + sin(y * 0.008) * 12.0
		var alpha := sin(PI * phase) * 0.23
		Art.draw_sprite(canvas, Art.region("fortress_fx", LAVA_UV), Vector2(x, y), Vector2(38, 25) * (0.6 + phase), 0, Color(1, 0.8, 0.6, alpha))
	for index in range(maxi(4, int(14 * detail))):
		var phase := fposmod(clock * 0.22 + index * 0.382, 1.0)
		var y := 160.0 + fposmod(index * 97.0, 910.0) - phase * 45.0
		var point := Vector2(360.0 + y * 0.047 + sin(index * 3.7 + clock) * 20, y)
		var tint := Color(1, 0.49, 0.12, sin(phase * PI) * 0.65)
		canvas.draw_line(point, point + Vector2(1, 4), tint, 1.6, true)


static func tower(canvas: CanvasItem, clock: float, flash: float, detail: float) -> void:
	for point in Castle.crystal_origins():
		# The structure layer already draws its crowns. Light the existing
		# crystal instead of stacking a second crown and orbital ring on top.
		var pulse := 0.08 + sin(clock * 2.2) * 0.025 + flash * 0.3
		Art.draw_sprite(canvas, Spell.cell("lightning", 1), point, Vector2(39, 48), 0, Color(0.42, 0.8, 1, pulse))
		for index in range(maxi(2, int(4 * detail))):
			var angle := clock * 0.85 + index * TAU / 4
			var orbit := point + Vector2(cos(angle) * 12, sin(angle) * 7)
			canvas.draw_line(orbit, orbit + Vector2(0, -2), Color(0.65, 0.9, 1, 0.2 + flash * 0.35), 1.2, true)


static func ballista(canvas: CanvasItem, angle: float, recoil: float) -> void:
	prepare_ballista()
	var axis := Vector2.RIGHT.rotated(angle)
	var pivot := Castle.BOW_ORIGIN - axis * recoil * 6.0
	var rotation := angle - Castle.BOW_RAIL_ANGLE
	var scale := Vector2.ONE * Castle.BOW_SCALE
	var part := Art.texture("ballista")
	# The foot is fixed at the painted platform for every aim/recoil state.
	canvas.draw_mesh(_base_mesh, part, Transform2D(0, scale, 0, Castle.MOUNT_POSITION), Color(0.73, 0.84, 0.86))
	# Rigid translation preserves the metal bow's proportions during a shot.
	canvas.draw_mesh(_upper_mesh, part, Transform2D(rotation, scale, 0, pivot + Vector2(2, 3)), Color(0.015, 0.025, 0.04, 0.22))
	canvas.draw_mesh(_upper_mesh, part, Transform2D(rotation, scale, 0, pivot), Color(0.73, 0.84, 0.86))
	# The original upper assembly includes its nocked bolt; do not add another.
	if recoil > 0.35:
		Art.draw_sprite(canvas, Spell.cell("lightning", 1), pivot + axis * 115, Vector2(27, 20), angle, Color(0.6, 0.85, 1, (recoil - 0.35) * 0.5))


static func prepare_ballista() -> void:
	if _upper_mesh == null:
		_upper_mesh = _source_mesh(PackedVector2Array(UPPER_OUTLINE), Castle.BOW_RAIL_SOURCE)
		_base_mesh = _source_mesh(PackedVector2Array(BASE_OUTLINE), BASE_FOOT_SOURCE)


static func _source_mesh(outline: PackedVector2Array, origin: Vector2) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	for point in outline:
		vertices.append(Vector3(point.x - origin.x, point.y - origin.y, 0))
		uvs.append(point / Castle.BOW_SOURCE_SIZE)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = Geometry2D.triangulate_polygon(outline)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func defense(canvas: CanvasItem, defense_id: String, target: Vector2, progress: float, detail: float) -> void:
	if defense_id == "lava_moat":
		Art.draw_sprite(canvas, Art.region("fortress_fx", LAVA_UV), target - Vector2(0, 14), Vector2(90, 94) * (0.65 + progress * 0.5), 0, Color(1, 1, 1, 1 - progress))
		return
	var origin := Castle.magic_origin()
	var axis := target - origin
	var perpendicular := axis.normalized().orthogonal()
	var points := PackedVector2Array()
	for index in range(13):
		var ratio := float(index) / 12.0
		var flutter := sin(index * 2.7 + floor(progress * 8) * 1.6) * 9 * sin(PI * ratio)
		points.append(origin + axis * ratio + perpendicular * flutter)
	var alpha := pow(1 - progress, 1.7)
	canvas.draw_polyline(points, Color(0.16, 0.5, 1, alpha * 0.22), 13, true)
	canvas.draw_polyline(points, Color(0.35, 0.77, 1, alpha * 0.7), 4, true)
	canvas.draw_polyline(points, Color(0.85, 0.98, 1, alpha), 1.4, true)
	Art.draw_sprite(canvas, Spell.cell("lightning", 1), target, Vector2(88, 72) * (0.65 + progress * 0.5), 0, Color(0.5, 0.86, 1, alpha))
	for index in range(maxi(2, int(5 * detail))):
		var point := origin + axis * fposmod(progress * 2 + index * 0.23, 1.0)
		Art.draw_sprite(canvas, Spell.cell("lightning", 1), point, Vector2(23, 18), 0, Color(0.55, 0.86, 1, alpha * 0.65))


static func wall_hit(canvas: CanvasItem, position: Vector2, progress: float) -> void:
	Art.draw_sprite(canvas, Art.region("fortress_fx", CHIPS_UV), position + Vector2(progress * 18, progress * progress * 20), Vector2(82, 70) * (0.55 + progress * 0.7), 0, Color(1, 1, 1, 1 - progress))
