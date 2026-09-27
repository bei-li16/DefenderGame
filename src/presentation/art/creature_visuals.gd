extends RefCounted
## Read-only presentation: authored frames, authoritative release events,
## independent actor clocks and bounded corpses. No combat RNG.
const Art = preload("res://src/presentation/art/game_art.gd")
const Motion = preload("res://src/presentation/art/creature_animation.gd")
const Effects = preload("res://src/presentation/art/creature_effects.gd")
const CORPSE_LIMIT := 48
var actors: Dictionary = {}
var retired: Array[Dictionary] = []


func sync(enemies: Array) -> void:
	var present := {}
	for enemy in enemies:
		var id := int(enemy["entity_id"])
		present[id] = true
		var target := Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0
		if not actors.has(id):
			actors[id] = {"enemy": enemy.duplicate(true), "clock": float(id % 17) * 0.19, "attack": 0.0, "special": 0.0, "hurt": 0.0, "flash": 0.0, "age": 0.0, "position": target}
		actors[id]["from"] = actors[id]["position"]
		actors[id]["target"] = target
		actors[id]["blend"] = 0.0
		actors[id]["enemy"] = enemy.duplicate(true)
	for id in actors.keys():
		if not present.has(id):
			actors.erase(id)


func event(value: Dictionary) -> void:
	var id := int(value.get("entity_id", -1))
	if not actors.has(id) or actors[id].get("dead", false):
		return
	var actor: Dictionary = actors[id]
	match str(value.get("type", "")):
		"damage", "hit":
			actor["flash"] = 0.09
			# Rapid arrows must not pin the actor in hurt frame zero.
			if float(actor["hurt"]) <= 0.0:
				actor["hurt"] = 0.24
			actor["damage_source"] = value.get("source", "arrow")
		"wall_damage":
			if str(value.get("source", "enemy")) != "boss_special":
				actor["attack"] = Motion.attack_seconds(actor["enemy"])
		"boss_special":
			actor["special"] = 0.85
			actor["attack"] = 0.0
		"death":
			actor["dead"] = true
			var corpse := actor.duplicate(true)
			corpse["death"] = 0.0
			retired.append(corpse)
			while retired.size() > CORPSE_LIMIT:
				retired.pop_front()


func advance(delta: float) -> void:
	for actor in actors.values():
		var enemy: Dictionary = actor["enemy"]
		actor["blend"] = minf(1.0, float(actor["blend"]) + delta * 30.0)
		actor["position"] = (actor["from"] as Vector2).lerp(actor["target"], float(actor["blend"]))
		actor["age"] = float(actor["age"]) + delta
		actor["flash"] = maxf(0.0, float(actor["flash"]) - delta)
		if int(enemy.get("freeze_ticks", 0)) > 0 or int(enemy.get("stun_ticks", 0)) > 0:
			continue
		var speed := float(enemy.get("slow_permille", 1000)) / 1000.0 if int(enemy.get("slow_ticks", 0)) > 0 else 1.0
		actor["clock"] = float(actor["clock"]) + delta * speed
		# Slow affects gait only. Recovery follows the real attack interval.
		for timer in ["attack", "special", "hurt"]:
			actor[timer] = maxf(0.0, float(actor[timer]) - delta)
	for index in range(retired.size() - 1, -1, -1):
		retired[index]["death"] = float(retired[index]["death"]) + delta
		if float(retired[index]["death"]) >= Motion.death_seconds(retired[index]["enemy"]):
			retired.remove_at(index)


func draw_ground(canvas: CanvasItem, detail: float) -> void:
	for actor in actors.values():
		Effects.telegraph(canvas, actor, detail)


func draw_enemy(canvas: CanvasItem, enemy: Dictionary) -> void:
	var actor: Dictionary = actors.get(int(enemy["entity_id"]), {"enemy": enemy, "clock": 0.0, "age": 1.0})
	if not actor.get("dead", false):
		_draw_actor(canvas, actor)


func draw_retired(canvas: CanvasItem) -> void:
	for actor in retired:
		_draw_actor(canvas, actor)


func _draw_actor(canvas: CanvasItem, actor: Dictionary) -> void:
	var enemy: Dictionary = actor["enemy"]
	var definition := Art.creature(enemy)
	var art := str(definition["art"])
	var center: Vector2 = actor.get("position", Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0)
	center = Motion.visual_center(art, center)
	var pose := Motion.pose(actor)
	var tint: Color = definition.get("tint", Color.WHITE)
	var alpha := minf(1.0, float(actor["age"]) / 0.12)
	if actor.has("death"):
		alpha = 1.0 - smoothstep(0.66, 1.0, float(pose["progress"]))
	elif float(actor.get("flash", 0.0)) > 0.0:
		tint = tint.lerp(Color(1.75, 1.5, 1.35), float(actor["flash"]) / 0.09 * 0.7)
	if int(enemy.get("freeze_ticks", 0)) > 0 and not actor.has("death"):
		tint = tint.lerp(Color(0.4, 0.8, 1.3), 0.55)
	tint.a = alpha
	var settings: Dictionary = Motion.SETTINGS[art]
	var feet := center + Vector2(0, float(settings["floor"]))
	Effects.shadow(canvas, feet, float(settings["size"]) * 0.28, alpha)
	var rect := Motion.rectangle(art, int(pose["row"]), int(pose["frame"]), center)
	# Preserve the authored pixel aspect ratio and per-frame foot pivot.
	Art.draw_sprite(canvas, Motion.cell(art, int(pose["row"]), int(pose["frame"])), rect.get_center(), rect.size, 0, tint)
	if actor.has("death"):
		Effects.collapse(canvas, actor, feet, art)
	else:
		Effects.accent(canvas, actor, pose, rect, art)
