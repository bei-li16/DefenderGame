extends RefCounted
## Authored frames, uniformly scaled. Foot pivots anchor changing silhouettes.
const Art = preload("res://src/presentation/art/game_art.gd")
const COLUMNS := 6
const ROWS := 4
const SETTINGS := {
	"snail": {"size": 140.0, "fps": 9.0, "floor": 36.0},
	"fist": {"size": 174.0, "fps": 8.0, "floor": 44.0},
	"tentacle": {"size": 148.0, "fps": 13.0, "floor": 38.0},
	"spike": {"size": 136.0, "fps": 13.0, "floor": 34.0},
	"mage": {"size": 164.0, "fps": 9.0, "floor": 43.0},
	"bat": {"size": 170.0, "fps": 14.0, "floor": 58.0},
	"dragon": {"size": 354.0, "fps": 8.0, "floor": 77.0},
	"giant": {"size": 332.0, "fps": 7.0, "floor": 84.0},
	"matron": {"size": 352.0, "fps": 8.0, "floor": 81.0},
}
static var _layouts: Dictionary = {}


static func cell(art: String, row: int, frame: int) -> AtlasTexture:
	var texture := Art.texture("anim_" + art)
	var entry: Array = layout(art)["rects"][clampi(row, 0, 3) * COLUMNS + clampi(frame, 0, 5)]
	var source := Rect2(float(entry[0]), float(entry[1]), float(entry[2]), float(entry[3]))
	var inset := Vector2.ONE / texture.get_size() * 0.5
	return Art.region("anim_" + art, Rect2(source.position / texture.get_size() + inset, source.size / texture.get_size() - inset * 2.0))


static func layout(art: String) -> Dictionary:
	if _layouts.is_empty():
		_layouts = JSON.parse_string(FileAccess.get_file_as_string("res://Gamematerials/Creatures/animation-layouts.json"))
	return _layouts[art]


static func pivot(art: String, row: int, frame: int) -> Vector2:
	var entry: Array = layout(art)["pivots"][clampi(row, 0, 3) * COLUMNS + clampi(frame, 0, 5)]
	return Vector2(float(entry[0]), float(entry[1]))


static func rectangle(art: String, row: int, frame: int, center: Vector2) -> Rect2:
	var size := float(SETTINGS[art]["size"])
	var feet := center + Vector2(0, float(SETTINGS[art]["floor"]))
	var entry: Array = layout(art)["rects"][clampi(row, 0, 3) * COLUMNS + clampi(frame, 0, 5)]
	return Rect2(feet - pivot(art, row, frame) * size, Vector2(float(entry[2]), float(entry[3])) * size / float(layout(art)["unit"]))


static func visual_center(art: String, center: Vector2) -> Vector2:
	# Set the body back as a boss closes on the wall, leaving room for its
	# authored extended claw/fist/club to meet the parapet instead of clipping.
	if art in ["dragon", "giant", "matron"]:
		return center + Vector2(clampf((550.0 - center.x) / 160.0, 0, 1) * 42.0, 0)
	return center


static func death_seconds(enemy: Dictionary) -> float:
	return 1.85 if enemy.get("tags", []).has("boss") else 1.1


static func attack_seconds(enemy: Dictionary) -> float:
	return minf(0.34, float(enemy.get("attack_interval_ticks", 25)) / 30.0 * 0.48)


static func special_windup(enemy: Dictionary) -> float:
	var interval := int(enemy.get("special_interval_ticks", 0))
	if interval <= 0:
		return 0.0
	return clampf(1.0 - float(interval - int(enemy.get("special_counter", 0))) / 30.0, 0.0, 1.0)


static func pose(actor: Dictionary) -> Dictionary:
	var enemy: Dictionary = actor["enemy"]
	var art := str(Art.creature(enemy)["art"])
	var boss: bool = enemy.get("tags", []).has("boss")
	if actor.has("death"):
		var collapse := 1.1 if boss else 0.64
		return {"row": 3, "frame": mini(5, int(float(actor["death"]) / collapse * 6.0)), "state": "death", "progress": float(actor["death"]) / death_seconds(enemy)}
	if float(actor.get("special", 0.0)) > 0.0:
		var progress := 1.0 - float(actor["special"]) / 0.85
		return {"row": 2, "frame": 3 if progress < 0.24 else (4 if progress < 0.68 else 5), "state": "special", "progress": progress}
	var windup := special_windup(enemy)
	if boss and windup > 0.0:
		return {"row": 2, "frame": mini(2, int(windup * 3.0)), "state": "special_windup", "progress": windup}
	if float(actor.get("attack", 0.0)) > 0.0:
		var progress := clampf(1.0 - float(actor["attack"]) / attack_seconds(enemy), 0.0, 1.0)
		return {"row": 1, "frame": mini(5, 3 + int(progress * 3.0)), "state": "attack", "progress": progress}
	var moving := int(enemy["x_milli"]) > int(enemy.get("attack_x_milli", 350000))
	var anticipation_ticks := mini(10, int(enemy.get("attack_interval_ticks", 25)) / 2)
	var cooldown := int(enemy.get("attack_cooldown", 25))
	if not moving and cooldown <= anticipation_ticks:
		var progress := clampf(1.0 - float(cooldown) / maxf(1.0, anticipation_ticks), 0, 1)
		return {"row": 1, "frame": mini(2, int(progress * 3.0)), "state": "attack_windup", "progress": progress}
	if not boss and float(actor.get("hurt", 0.0)) > 0.0:
		return {"row": 2, "frame": mini(5, int((1.0 - float(actor["hurt"]) / 0.24) * 6.0)), "state": "hurt", "progress": 0.0}
	var frame := posmod(int(float(actor["clock"]) * float(SETTINGS[art]["fps"])), 6) if moving or art == "bat" else 0
	return {"row": 0, "frame": frame, "state": "walk" if moving else "idle", "progress": fposmod(float(actor["clock"]) * float(SETTINGS[art]["fps"]), 6.0) / 6.0}
