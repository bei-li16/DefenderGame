extends RefCounted
## Read-only snapshot consumer: locomotion deforms a shared UV grid, attack
## recovery follows authoritative wall_damage events. No gameplay timers/RNG.
const Art = preload("res://src/presentation/art/game_art.gd")
const FRAMES := 16
const GRID := 8
const DEATH_SECONDS := 0.48
const CORPSE_LIMIT := 48
static var _meshes: Dictionary = {}
var actors: Dictionary = {}
var retired: Array[Dictionary] = []


func sync(enemies: Array) -> void:
	var present := {}
	for enemy in enemies:
		var id := int(enemy["entity_id"])
		present[id] = true
		var target := Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0
		if not actors.has(id):
			actors[id] = {"enemy": enemy.duplicate(true), "clock": float(id % 17) * 0.19, "attack": 0.0, "hurt": 0.0, "age": 0.0, "position": target}
		actors[id]["from"] = actors[id]["position"]
		actors[id]["target"] = target
		actors[id]["blend"] = 0.0
		actors[id]["enemy"] = enemy.duplicate(true)
	for id in actors.keys():
		if not present.has(id):
			actors.erase(id)


func event(event_value: Dictionary) -> void:
	var id := int(event_value.get("entity_id", -1))
	if not actors.has(id):
		return
	match str(event_value.get("type", "")):
		"damage", "hit":
			actors[id]["hurt"] = 0.14
		"wall_damage", "boss_special":
			actors[id]["attack"] = 0.32
		"death":
			var corpse: Dictionary = actors[id].duplicate(true)
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
		actor["hurt"] = maxf(0.0, float(actor["hurt"]) - delta)
		if int(enemy.get("freeze_ticks", 0)) > 0 or int(enemy.get("stun_ticks", 0)) > 0:
			continue
		var speed := 1.0
		if int(enemy.get("slow_ticks", 0)) > 0:
			speed = float(enemy.get("slow_permille", 1000)) / 1000.0
		actor["clock"] = float(actor["clock"]) + delta * speed
		actor["attack"] = maxf(0.0, float(actor["attack"]) - delta)
	for index in range(retired.size() - 1, -1, -1):
		retired[index]["death"] = float(retired[index]["death"]) + delta
		if float(retired[index]["death"]) >= DEATH_SECONDS:
			retired.remove_at(index)


func draw_enemy(canvas: CanvasItem, enemy: Dictionary) -> void:
	var actor: Dictionary = actors.get(int(enemy["entity_id"]), {"enemy": enemy, "clock": 0.0, "attack": 0.0, "hurt": 0.0, "age": 1.0})
	_draw_actor(canvas, actor)


func draw_retired(canvas: CanvasItem) -> void:
	for actor in retired:
		_draw_actor(canvas, actor)


func _draw_actor(canvas: CanvasItem, actor: Dictionary) -> void:
	var enemy: Dictionary = actor["enemy"]
	var definition := Art.creature(enemy)
	var motion := str(definition["motion"])
	var asset := Art.texture(str(definition["art"]))
	var width := float(definition["width"])
	var dimensions := Vector2(width, width * asset.get_height() / asset.get_width())
	var center: Vector2 = actor.get("position", Vector2(float(enemy["x_milli"]), float(enemy["y_milli"])) / 1000.0)
	var moving := int(enemy["x_milli"]) > int(enemy.get("attack_x_milli", 350000))
	var phase := float(actor["clock"]) * (10.0 if motion in ["scuttle", "flutter", "roll"] else 6.0)
	var attack := float(actor["attack"])
	var pose := "walk" if moving else "idle"
	var angle := 0.0
	var displacement := Vector2.ZERO
	if moving:
		displacement.y = sin(phase * 2.0) * (4.0 if motion == "flutter" else 1.5)
		angle = sin(phase) * (0.035 if motion != "roll" else 0.23)
	if attack > 0.0:
		pose = "attack"
		phase = (1.0 - attack / 0.32) * PI
		displacement.x = -sin(phase) * 12.0
		angle = -sin(phase) * 0.08
	elif not moving and int(enemy.get("attack_cooldown", 20)) <= 6:
		# Last six simulation ticks are anticipation; damage is never generated here.
		displacement.x = (1.0 - float(enemy.get("attack_cooldown", 0)) / 6.0) * 7.0
	var tint: Color = definition.get("tint", Color.WHITE)
	if float(actor["hurt"]) > 0.0:
		tint = tint.lerp(Color(1.8, 1.3, 1.2), float(actor["hurt"]) / 0.14)
	if int(enemy.get("freeze_ticks", 0)) > 0:
		tint = tint.lerp(Color(0.4, 0.8, 1.3), 0.55)
	tint.a = minf(1.0, float(actor["age"]) / 0.15)
	if actor.has("death"):
		var death := float(actor["death"]) / DEATH_SECONDS
		angle += death * 0.6
		dimensions *= 1.0 - death * 0.3
		displacement.y += death * 24.0
		tint.a = 1.0 - death
		pose = "idle"
	# Shadows remain on the ground while flying bodies flap above it.
	var shadow_center := center + Vector2(0, dimensions.y * 0.37 + (12.0 if motion == "flutter" else 0.0))
	var shadow := PackedVector2Array()
	for index in range(16):
		var a := TAU * index / 16.0
		shadow.append(shadow_center + Vector2(cos(a) * width * 0.29, sin(a) * 8.0))
	canvas.draw_colored_polygon(shadow, Color(0.025, 0.02, 0.04, tint.a * 0.32))
	var frame := posmod(int(phase / TAU * FRAMES), FRAMES)
	canvas.draw_mesh(_pose_mesh(motion, pose, frame), asset, Transform2D(angle, dimensions, 0.0, center + displacement), tint)


static func _pose_mesh(motion: String, pose: String, frame: int) -> ArrayMesh:
	var key := "%s:%s:%d" % [motion, pose, frame]
	if _meshes.has(key):
		return _meshes[key]
	var phase := TAU * frame / FRAMES
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in range(GRID + 1):
		for column in range(GRID + 1):
			var uv := Vector2(float(column) / GRID, float(row) / GRID)
			var p := uv - Vector2(0.5, 0.5)
			if pose == "attack":
				p.x -= sin(phase) * 0.065 * (1.0 - uv.x)
				p.y += sin(phase) * 0.035 * (0.5 - uv.y)
			elif pose == "walk":
				match motion:
					"flutter":
						p.y += sin(phase) * pow(1.0 - uv.y, 2.0) * absf(uv.x - 0.45) * 0.48
					"tentacle":
						p.y += sin(phase + uv.y * 5.0) * maxf(0.0, uv.x - 0.5) * 0.14
						p.x += sin(phase + uv.x * PI) * maxf(0.0, uv.y - 0.65) * 0.07
					"roll":
						p.y *= 1.0 + sin(phase * 2.0) * 0.025
					_:
						p.x += sin(phase + uv.x * TAU) * maxf(0.0, uv.y - 0.55) * 0.08
						p.y += sin(phase) * maxf(0.0, 0.65 - uv.y) * 0.018
			else:
				p.x *= 1.0 + sin(phase) * 0.008
			vertices.append(Vector3(p.x, p.y, 0))
			uvs.append(uv)
	for row in range(GRID):
		for column in range(GRID):
			var i := row * (GRID + 1) + column
			indices.append_array(PackedInt32Array([i, i + 1, i + GRID + 2, i, i + GRID + 2, i + GRID + 1]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_meshes[key] = mesh
	return mesh
