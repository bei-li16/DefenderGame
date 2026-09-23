extends RefCounted
## Texture-based presentation only. Authoritative launch/impact ticks, positions,
## damage and status lifetimes come exclusively from the combat model.
const Art = preload("res://src/presentation/art/game_art.gd")
const ELEMENTS := ["fire", "ice", "lightning"]
const DURATIONS := {"fire": 1.05, "ice": 1.15, "lightning": 0.55}


static func duration(element: String) -> float:
	return float(DURATIONS.get(element, 0.6))


static func cell(element: String, index: int) -> AtlasTexture:
	# Half-texel inset keeps bilinear sampling inside each source cell. The
	# generated sheets have real alpha; no black-key or runtime image rewriting.
	var inset := 0.0005
	return Art.region("vfx_" + element, Rect2(Vector2(index % 2, index / 2) * 0.5 + Vector2.ONE * inset, Vector2.ONE * (0.5 - inset * 2)))


static func _sprite(canvas: CanvasItem, element: String, index: int, anchor: Vector2, size: Vector2, pivot: Vector2 = Vector2(0.5, 0.5), opacity: float = 1.0, angle: float = 0.0) -> void:
	if opacity <= 0.001:
		return
	var center := anchor + ((Vector2(0.5, 0.5) - pivot) * size).rotated(angle)
	Art.draw_sprite(canvas, cell(element, index), center, size, angle, Color(1, 1, 1, clampf(opacity, 0, 1)))


static func flight(canvas: CanvasItem, falling: Dictionary, tick: float) -> void:
	var target := Vector2(float(falling["x_milli"]), float(falling["y_milli"])) / 1000.0
	var span := maxf(1.0, int(falling["impact_tick"]) - int(falling["launch_tick"]))
	var p := clampf((tick - int(falling["launch_tick"])) / span, 0, 1)
	var element := str(falling["element"])
	var tier := int(falling["tier"])
	var origin := Vector2(target.x - 155, -85)
	if element == "lightning":
		origin.x = target.x
	var position := origin.lerp(target, p * p)
	var direction := (target - origin).normalized()
	var angle := direction.angle() - PI * 0.5
	var growth := 0.85 + tier * 0.06
	if element == "lightning":
		# A branching leader descends first; the bright return stroke is drawn
		# only on the real skill_pulse, never early or at extra enemy positions.
		_bolt(canvas, position, 0.20 + p * 0.35, tick, target.x)
	else:
		var size := Vector2(148, 218) if element == "fire" else Vector2(112, 226)
		var pivot := Vector2(0.5, 0.83) if element == "fire" else Vector2(0.51, 0.95)
		_sprite(canvas, element, 0, position, size * growth, pivot, minf(1, p * 6), angle)


static func ground(canvas: CanvasItem, effect: Dictionary) -> void:
	if str(effect.get("kind", "")) != "spell":
		return
	var element := str(effect["element"])
	var center: Vector2 = effect["position"]
	var p := clampf(float(effect["age"]) / float(effect["duration"]), 0, 1)
	var radius := clampf(float(effect.get("radius", 75)), 40, 130)
	var spread := clampf(float(effect.get("splash_radius", radius)), radius, 190)
	var fade := sin(PI * pow(p, 0.45))
	if element == "fire":
		_sprite(canvas, element, 2, center, Vector2(spread * 1.9, spread * 1.1) * (0.8 + p * 0.3), Vector2(0.5, 0.62), fade * 0.70)
	elif element == "ice":
		_sprite(canvas, element, 2, center, Vector2(spread * 1.9, spread * 1.1) * (0.65 + p * 0.4), Vector2(0.5, 0.60), fade * 0.65)
	else:
		_sprite(canvas, element, 3, center, Vector2(radius * 2.3, radius * 1.05), Vector2(0.5, 0.5), (1 - p) * 0.48, sin(center.x) * 0.1)


static func impact(canvas: CanvasItem, effect: Dictionary, detail: float) -> void:
	var element := str(effect["element"])
	var center: Vector2 = effect["position"]
	var age := float(effect["age"])
	var p := clampf(age / float(effect["duration"]), 0, 1)
	var radius := clampf(float(effect.get("radius", 75)), 40, 130)
	var phase := center.x * 0.13 + center.y * 0.07
	var fade := 1.0 - smoothstep(0.25, 1.0, p)
	var parts := 3 if detail >= 0.9 else (2 if detail >= 0.6 else 0)
	if element == "fire":
		var swell := (0.35 + 0.65 * (1 - exp(-age * 25))) * (1 + p * 0.25)
		_sprite(canvas, element, 1, center + Vector2(0, -p * 24), Vector2(radius * 2.65, radius * 2.8) * swell, Vector2(0.5, 0.79), fade * 0.92, sin(phase) * 0.12)
		# Independently moving flame fragments, not rings or filled triangles.
		for i in range(parts):
			var direction := Vector2.from_angle(phase + i * 2.4)
			var ember := center + Vector2(direction.x * radius * p, -30 - sin(p * PI) * (55 + i * 15))
			_sprite(canvas, element, 3, ember, Vector2(25, 43) * (1 - p * 0.65), Vector2(0.5, 0.85), fade * 0.75, direction.x * 0.5)
	elif element == "ice":
		var grow := 0.3 + 0.7 * (1 - exp(-age * 32))
		_sprite(canvas, element, 1, center, Vector2(radius * 2.35, radius * 2.75) * Vector2(1 + p * 0.12, grow * (1 - p * 0.15)), Vector2(0.5, 0.90), fade * 0.9)
		for i in range(parts):
			var sign_x := -1.0 if i % 2 == 0 else 1.0
			var shard := center + Vector2(sign_x * radius * p * (0.6 + i * 0.3), -radius * sin(p * PI) * (0.6 + i * 0.15))
			_sprite(canvas, element, 0, shard, Vector2(28, 65) * (1 - p * 0.45), Vector2(0.5, 0.75), fade * 0.72, sign_x * (0.8 + p * 1.3))
	else:
		var return_stroke := exp(-age * 14)
		_bolt(canvas, center, return_stroke, age * 30, phase)
		_sprite(canvas, element, 1, center, Vector2(radius * 2.65, radius * 2.25) * (0.72 + p * 0.45), Vector2(0.46, 0.80), fade * 0.90)


static func _bolt(canvas: CanvasItem, target: Vector2, opacity: float, clock: float, phase: float) -> void:
	var frame := 0 if int(clock / 2 + phase) % 2 == 0 else 2
	var bottom := 0.89 if frame == 0 else 0.86
	var top := 0.10 if frame == 0 else 0.06
	var height := maxf(15, (target.y + 85) / (bottom - top))
	_sprite(canvas, "lightning", frame, target, Vector2(155, height), Vector2(0.53 if frame == 0 else 0.5, bottom), opacity)


static func cage(canvas: CanvasItem, center: Vector2, radius: float, opacity: float) -> void:
	_sprite(canvas, "ice", 3, center + Vector2(0, radius * 0.55), Vector2(radius * 2.7, radius * 2.8), Vector2(0.5, 0.86), opacity)


static func status(canvas: CanvasItem, enemy: Dictionary, center: Vector2, radius: float, clock: float) -> void:
	var phase := float(enemy.get("entity_id", 0)) * 2.17
	if int(enemy.get("burn_ticks", 0)) > 0:
		for i in range(2):
			var pulse := 0.9 + sin(clock * 14 + phase + i * 2.7) * 0.1
			var anchor := center + Vector2((i * 2 - 1) * radius * 0.35, radius * 0.45)
			_sprite(canvas, "fire", 3, anchor, Vector2(radius * 1.0, radius * 1.7 * pulse), Vector2(0.5, 0.85), 0.72)
	if int(enemy.get("freeze_ticks", 0)) > 0:
		cage(canvas, center, radius + 12, 0.70)
	if int(enemy.get("stun_ticks", 0)) > 0:
		_sprite(canvas, "lightning", 3, center, Vector2(radius * 2.7, radius * 2.2), Vector2(0.5, 0.5), 0.55 + sin(clock * 17 + phase) * 0.12, sin(clock * 3 + phase) * 0.18)
