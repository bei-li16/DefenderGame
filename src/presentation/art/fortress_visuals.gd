extends RefCounted
## Bounded presentation-only animation. No particles/nodes spawned per frame,
## no combat RNG, no scheduling damage and no changes to collision anchors.
const Art = preload("res://src/presentation/art/game_art.gd")
const Castle = preload("res://src/presentation/art/castle_view.gd")
const Spell = preload("res://src/presentation/art/spell_visuals.gd")
const CROWN_UV := Rect2(0.025, 0.015, 0.425, 0.475)
const LAVA_UV := Rect2(0.0, 0.5, 0.5, 0.5)
const CHIPS_UV := Rect2(0.5, 0.5, 0.5, 0.5)


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
	for source_point in [Castle.FAR_CRYSTAL_SOURCE, Castle.NEAR_CRYSTAL_SOURCE]:
		var point := Castle.source_to_world(source_point)
		Art.draw_sprite(canvas, Art.region("fortress_fx", CROWN_UV), point + Vector2(0, 8), Vector2(72, 85))
		var pulse := 0.16 + sin(clock * 2.2) * 0.045 + flash * 0.3
		Art.draw_sprite(canvas, Spell.cell("lightning", 1), point - Vector2(0, 9), Vector2(65, 50), 0, Color(0.42, 0.8, 1, pulse))
		for index in range(maxi(2, int(4 * detail))):
			var angle := clock * 0.85 + index * TAU / 4
			var orbit := point + Vector2(cos(angle) * 30, sin(angle) * 10 + 18)
			canvas.draw_line(orbit, orbit + Vector2(0, -3), Color(0.65, 0.9, 1, 0.55), 2.0, true)


static func ballista(canvas: CanvasItem, angle: float, recoil: float) -> void:
	var axis := Vector2.RIGHT.rotated(angle)
	var pivot := Castle.BOW_ORIGIN - axis * recoil * 10.0
	# Offset relative to the measured winding pivot; the stock stays over the
	# original empty mounting seat and all arrows retain the core's origin.
	# Rail origin (700,410) and swivel foot (708,594) were measured on the
	# 1577x997 source; the foot lands on the empty platform, 32px below aim.
	var center := pivot + ((Castle.BOW_SOURCE_SIZE * 0.5 - Castle.BOW_RAIL_SOURCE) * Castle.BOW_SIZE.x / Castle.BOW_SOURCE_SIZE.x).rotated(angle)
	var dimensions := Castle.BOW_SIZE * Vector2(1 - recoil * 0.035, 1 + recoil * 0.055)
	var part := Art.texture("ballista")
	Art.draw_sprite(canvas, part, center + Vector2(5, 7), dimensions, angle, Color(0.015, 0.025, 0.04, 0.45))
	Art.draw_sprite(canvas, part, center, dimensions, angle)
	# A separately rendered loaded bolt withdraws during recoil, then returns.
	# The source assembly deliberately contains no baked-in arrow.
	var ready := clampf(1.0 - recoil * 2.0, 0.0, 1.0)
	Art.draw_sprite(canvas, Art.texture("arrow"), pivot + axis * (35 + ready * 18), Vector2(92, 26), angle + PI, Color(0.85, 0.96, 1, ready))
	if recoil > 0.35:
		Art.draw_sprite(canvas, Spell.cell("lightning", 1), pivot + axis * 110, Vector2(35, 27), angle, Color(0.6, 0.85, 1, (recoil - 0.35) * 0.65))


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
