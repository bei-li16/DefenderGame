extends RefCounted
## Material-specific accents and boss choreography. Effects consume confirmed
## events; telegraphs never create damage, projectiles or status changes.
const Art = preload("res://src/presentation/art/game_art.gd")
const Motion = preload("res://src/presentation/art/creature_animation.gd")
const Spell = preload("res://src/presentation/art/spell_visuals.gd")
const Fortress = preload("res://src/presentation/art/fortress_visuals.gd")
const Castle = preload("res://src/presentation/art/castle_view.gd")
const COLORS := {"war_cry": Color("ff9a46"), "frost_nova": Color("92e8ff"), "storm_surge": Color("d59bff")}


static func shadow(canvas: CanvasItem, center: Vector2, width: float, opacity: float) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle := float(i) * TAU / 20.0
		points.append(center + Vector2(cos(angle) * width, sin(angle) * width * 0.17))
	canvas.draw_colored_polygon(points, Color(0.025, 0.02, 0.04, opacity * 0.3))


static func telegraph(canvas: CanvasItem, actor: Dictionary, detail: float) -> void:
	var enemy: Dictionary = actor["enemy"]
	if not enemy.get("tags", []).has("boss") or actor.get("dead", false):
		return
	var charge := Motion.special_windup(enemy)
	if charge <= 0.0 or float(actor.get("special", 0.0)) > 0.0:
		return
	var art := str(Art.creature(enemy)["art"])
	var center := Motion.visual_center(art, actor["position"])
	var feet := center + Vector2(0, float(Motion.SETTINGS[art]["floor"]))
	var special := str(enemy.get("special", ""))
	var tint: Color = COLORS.get(special, Color.WHITE)
	# A small ground seal identifies a cast, rather than washing out the field.
	var points := PackedVector2Array()
	for i in range(33):
		var angle := float(i) * TAU / 32.0
		points.append(feet + Vector2(cos(angle) * 108, sin(angle) * 28))
	canvas.draw_polyline(points, Color(tint, charge * 0.65), 2, true)
	for i in range(8):
		var angle := float(i) * TAU / 8.0
		var p := feet + Vector2(cos(angle) * 97, sin(angle) * 25)
		canvas.draw_line(p, p + Vector2(cos(angle) * 10, sin(angle) * 4), Color(tint, charge * 0.8), 3, true)
	if special == "frost_nova":
		Spell._sprite(canvas, "ice", 2, feet, Vector2(220, 72), Vector2(0.5, 0.62), charge * 0.45)
	elif special == "war_cry":
		Spell._sprite(canvas, "fire", 2, feet, Vector2(185, 58), Vector2(0.5, 0.62), charge * 0.35)
	for i in range(maxi(3, int(7 * detail))):
		var p := fposmod(float(actor["clock"]) * 0.8 + i * 0.173, 1.0)
		var point := feet + Vector2(sin(i * 2.4) * 76, -p * 115)
		canvas.draw_line(point, point + Vector2(0, -5), Color(tint, sin(p * PI) * charge * 0.7), 2, true)


static func accent(canvas: CanvasItem, actor: Dictionary, pose: Dictionary, rect: Rect2, art: String) -> void:
	var state := str(pose["state"])
	var enemy: Dictionary = actor["enemy"]
	if state == "special_windup":
		var charge := float(pose["progress"])
		var element := "fire" if art == "dragon" else ("ice" if art == "giant" else "lightning")
		var anchor := rect.position + rect.size * (Vector2(0.25, 0.34) if art == "dragon" else Vector2(0.42, 0.22))
		Spell._sprite(canvas, element, 1 if element == "lightning" else 3, anchor, Vector2.ONE * (20 + 34 * charge), Vector2(0.5, 0.5), charge * 0.68)
	elif art == "mage" and state == "attack_windup":
		var charge := float(pose["progress"])
		var flame := str(enemy.get("enemy_id", "")) == "ember_shaman"
		Spell._sprite(canvas, "fire" if flame else "lightning", 1, rect.position + rect.size * Vector2(0.23, 0.50), Vector2.ONE * (15 + charge * 24), Vector2(0.5, 0.5), charge * 0.78)
	elif state == "walk" and art in ["fist", "giant", "dragon"]:
		var step := fposmod(float(actor["clock"]) * float(Motion.SETTINGS[art]["fps"]) / 3.0, 1.0)
		if step < 0.3:
			var feet: Vector2 = actor["position"] + Vector2(-12, float(Motion.SETTINGS[art]["floor"]))
			Art.draw_sprite(canvas, Art.region("fortress_fx", Fortress.CHIPS_UV), feet, Vector2(40, 22) * (0.6 + step), 0, Color(0.65, 0.66, 0.63, (1 - step / 0.3) * 0.3))


static func collapse(canvas: CanvasItem, actor: Dictionary, feet: Vector2, art: String) -> void:
	var age := float(actor["death"])
	var boss: bool = actor["enemy"].get("tags", []).has("boss")
	var delay := 0.5 if boss else 0.24
	var p := clampf((age - delay) / 0.6, 0, 1)
	if p <= 0 or p >= 1:
		return
	var size := 175.0 if boss else 65.0
	var tint := Color(0.7, 0.74, 0.78, sin(p * PI) * 0.6)
	Art.draw_sprite(canvas, Art.region("fortress_fx", Fortress.CHIPS_UV), feet + Vector2(0, -10 + p * 13), Vector2(size, size * 0.5) * (0.65 + p * 0.65), 0, tint)
	if art in ["dragon", "giant", "matron"]:
		var element := "fire" if art == "dragon" else ("ice" if art == "giant" else "lightning")
		for i in range(5):
			var position := feet + Vector2(sin(i * 2.7) * p * 115, -sin(p * PI) * (30 + i * 12))
			Spell._sprite(canvas, element, 3 if element != "ice" else 0, position, Vector2(20, 37) * (1 - p * 0.4), Vector2(0.5, 0.7), (1 - p) * 0.6, sin(i * 3.2) * p)


static func duration(special: String) -> float:
	return 1.3 if special == "frost_nova" else (0.82 if special == "war_cry" else 0.9)


static func strike(canvas: CanvasItem, effect: Dictionary, progress: float, detail: float) -> void:
	var center: Vector2 = effect["position"]
	var art := str(effect.get("art", "snail"))
	var target := Castle.impact_position(center.y)
	Fortress.wall_hit(canvas, target, progress)
	var fade := pow(1 - progress, 2.0)
	if art == "mage":
		var flame := str(effect.get("enemy_id", "")) == "ember_shaman"
		var color := Color("ffb15c") if flame else Color("bdb4ff")
		arc(canvas, center + Vector2(-38, -14), target, progress, color, fade, 2.4)
		Spell._sprite(canvas, "fire" if flame else "lightning", 1, target, Vector2(82, 95), Vector2(0.5, 0.7), fade * 0.75)
	elif art in ["dragon", "matron", "tentacle", "bat"]:
		var count := 3 if art in ["dragon", "bat"] else 1
		for i in range(count):
			var points := PackedVector2Array()
			for j in range(12):
				var a := lerpf(-1.4, 0.7, float(j) / 11.0)
				points.append(target + Vector2(24 + i * 10 + cos(a) * (48 + i * 8), sin(a) * 47))
			canvas.draw_polyline(points, Color(1.0, 0.85, 0.63, fade * 0.7), 3.0 if count > 1 else 6.0, true)
	else:
		Art.draw_sprite(canvas, Art.region("fortress_fx", Fortress.CHIPS_UV), target + Vector2(15, 7), Vector2(90, 70) * (0.7 + progress * 0.4), 0, Color(0.8, 0.84, 0.87, fade * detail))


static func special(canvas: CanvasItem, effect: Dictionary, detail: float) -> void:
	var kind := str(effect["special"])
	var p := clampf(float(effect["age"]) / float(effect["duration"]), 0, 1)
	var center: Vector2 = effect["position"]
	var target := Castle.impact_position(center.y)
	match kind:
		"war_cry":
			center = Motion.visual_center("dragon", center)
			var origin := center + Vector2(-148, -52)
			var axis := target - origin
			var fade := (1 - smoothstep(0.40, 0.69, p)) * minf(1, p * 24 + 0.2)
			var count := maxi(5, int(clampf(axis.length() / 53.0, 5, 16) * detail))
			for i in range(count):
				var t := float(i) / maxf(1, count - 1)
				var anchor := origin + axis * t + Vector2(0, sin(i * 2.1 + p * 38) * 7 * t)
				var size := Vector2(135 + t * 170, 120 + t * 125)
				Spell._sprite(canvas, "fire", 0, anchor, size, Vector2(0.5, 0.75), fade * (0.60 + t * 0.2), axis.angle() - PI * 0.5)
			Spell._sprite(canvas, "fire", 3, origin, Vector2(54, 74), Vector2(0.5, 0.5), fade * 0.9, axis.angle() - PI * 0.5)
			Spell._sprite(canvas, "fire", 1, target, Vector2(135, 182), Vector2(0.5, 0.72), fade * 0.85)
			Fortress.wall_hit(canvas, target, p)
		"frost_nova":
			center = Motion.visual_center("giant", center)
			var feet := center + Vector2(-45, 78)
			var fade := 1 - smoothstep(0.65, 1, p)
			Spell._sprite(canvas, "ice", 2, feet, Vector2(310, 106) * (0.7 + p * 0.6), Vector2(0.5, 0.65), fade * 0.78)
			# Jagged ground fronts spread from the slam; defenses encase on the
			# confirmed release, matching their actual freeze rather than damage.
			for i in range(maxi(5, int(12 * detail))):
				var t := float(i) / maxf(1, int(12 * detail) - 1)
				var local := clampf(p * 4.0 - t * 1.3, 0, 1)
				if local <= 0:
					continue
				var anchor := feet.lerp(Vector2(290, feet.y + sin(i * 2.6) * 56), t)
				var scale := sin(minf(1.0, local * 2) * PI * 0.5)
				Spell._sprite(canvas, "ice", 1, anchor, Vector2(74, 115) * scale, Vector2(0.5, 0.90), fade * 0.76, sin(i * 5.1) * 0.18)
			for point in Castle.crystal_origins():
				Spell._sprite(canvas, "ice", 1, point + Vector2(0, 38), Vector2(118, 150), Vector2(0.5, 0.90), fade * 0.8)
		"storm_surge":
			center = Motion.visual_center("matron", center)
			var origin := center + Vector2(-175, -79)
			var fade := (1 - smoothstep(0.4, 1, p)) * (0.7 + sin(p * 65) * 0.2)
			arc(canvas, origin, target, p, Color("c697ff"), fade, 4.0)
			# The tentacles feed the club; its head emits the return stroke.
			for tip in [Vector2(-6, -202), Vector2(113, -190)]:
				arc(canvas, center + tip, origin, p + tip.x, Color("ce8eff"), fade * 0.5, 1.6)
			for i in range(maxi(2, int(4 * detail))):
				var branch_target := target + Vector2(18, (i - 1.5) * 58)
				arc(canvas, origin.lerp(target, 0.38 + i * 0.12), branch_target, p + i * 0.2, Color("a7c9ff"), fade * 0.6, 1.8)
			Spell._sprite(canvas, "lightning", 1, target, Vector2(178, 165), Vector2(0.5, 0.7), fade * 0.88)
			Spell._sprite(canvas, "lightning", 3, center + Vector2(0, 77), Vector2(238, 95), Vector2(0.5, 0.5), fade * 0.65)


static func arc(canvas: CanvasItem, start: Vector2, end: Vector2, phase: float, color: Color, opacity: float, width: float) -> void:
	var axis := end - start
	var normal := axis.normalized().orthogonal()
	var points := PackedVector2Array()
	for i in range(17):
		var t := float(i) / 16.0
		var jag := sin(i * 8.17 + floor(phase * 18) * 1.7) * sin(PI * t) * 16.0
		points.append(start + axis * t + normal * jag)
	canvas.draw_polyline(points, Color(color, opacity * 0.18), width * 4, true)
	canvas.draw_polyline(points, Color(color, opacity * 0.85), width, true)
	canvas.draw_polyline(points, Color(0.94, 0.96, 1.0, opacity), maxf(1, width * 0.33), true)
