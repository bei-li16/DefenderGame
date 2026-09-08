extends RefCounted
## Presentation-only resource registry. Source PNGs stay untouched; Godot imports
## resize/mipmap them. Never use Image.load: exported games resolve import remaps.

const FILES := {
	"menu": "主菜单背景", "battle": "战斗场地背景", "lava": "熔岩沟场景变体",
	"wall": "主城墙new", "turret": "弩塔", "arrow": "箭矢投射物",
	"courtyard": "城内石板地面",
	"snail": "红蜗牛龟", "fist": "红拳石怪", "tentacle": "粉色触手怪",
	"spike": "刺猬球怪", "mage": "法师怪", "bat": "飞行怪",
	"dragon": "红龙Boss", "giant": "岩石巨人Boss", "matron": "巨型触手领主Boss",
	# Numbered files were inspected: green=Hurricane, blue=Phantom, red=Power.
	"basic_bow": "武器图标1", "hurricane_bow": "武器图标2",
	"phantom_bow": "武器图标3", "power_bow": "武器图标4",
}
const CREATURES := {
	"melee_basic": {"art": "snail", "motion": "scuttle", "width": 116.0},
	"fast_raider": {"art": "tentacle", "motion": "tentacle", "width": 108.0},
	"armored_guard": {"art": "fist", "motion": "heavy", "width": 150.0},
	"ranged_hexer": {"art": "mage", "motion": "cast", "width": 140.0},
	"ember_shaman": {"art": "mage", "motion": "cast", "width": 150.0, "tint": Color(1.0, 0.76, 0.65)},
	"sky_harrier": {"art": "bat", "motion": "flutter", "width": 148.0},
	"ember_warlord": {"art": "dragon", "motion": "heavy", "width": 300.0},
	"frost_titan": {"art": "giant", "motion": "heavy", "width": 282.0, "tint": Color(0.75, 0.9, 1.0)},
	"storm_matron": {"art": "matron", "motion": "tentacle", "width": 282.0},
}
static var _textures: Dictionary = {}
static var _regions: Dictionary = {}
static var _quads: Dictionary = {}


static func texture(key: String) -> Texture2D:
	if not _textures.has(key):
		if not FILES.has(key):
			return null
		_textures[key] = load("res://Gamematerials/%s.png" % FILES[key]) as Texture2D
	return _textures[key]


static func creature(enemy: Dictionary) -> Dictionary:
	var definition: Dictionary = CREATURES.get(str(enemy.get("enemy_id", "")), CREATURES["melee_basic"])
	# Cosmetic variants share precisely the same core fast-raider stats.
	if str(enemy.get("enemy_id", "")) == "fast_raider" and int(enemy.get("entity_id", 0)) % 2 == 0:
		return {"art": "spike", "motion": "roll", "width": 106.0}
	return definition


static func region(key: String, uv: Rect2) -> AtlasTexture:
	var cache_key := key + str(uv)
	if not _regions.has(cache_key):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture(key)
		atlas.region = Rect2(uv.position * atlas.atlas.get_size(), uv.size * atlas.atlas.get_size())
		atlas.filter_clip = true
		_regions[cache_key] = atlas
	return _regions[cache_key]


static func cover(canvas: CanvasItem, key: String, destination: Rect2, tint: Color = Color.WHITE) -> void:
	var asset := texture(key)
	var source_size := asset.get_size()
	var scale_factor := maxf(destination.size.x / source_size.x, destination.size.y / source_size.y)
	var crop_size := destination.size / scale_factor
	canvas.draw_texture_rect_region(asset, destination, Rect2((source_size - crop_size) * 0.5, crop_size), tint)


static func draw_sprite(canvas: CanvasItem, asset: Texture2D, center: Vector2, dimensions: Vector2, angle: float = 0.0, tint: Color = Color.WHITE) -> void:
	var uv := Rect2(0, 0, 1, 1)
	if asset is AtlasTexture:
		# CanvasItem.draw_mesh does NOT apply AtlasTexture.region to mesh UVs.
		# Resolve it explicitly or each turret layer renders the entire tower.
		uv = Rect2(asset.region.position / asset.atlas.get_size(), asset.region.size / asset.atlas.get_size())
		asset = asset.atlas
	canvas.draw_mesh(quad(uv), asset, Transform2D(angle, dimensions, 0.0, center), tint)


static func quad(uv: Rect2 = Rect2(0, 0, 1, 1)) -> ArrayMesh:
	if not _quads.has(uv):
		var mesh := ArrayMesh.new()
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-0.5, -0.5, 0), Vector3(0.5, -0.5, 0), Vector3(0.5, 0.5, 0), Vector3(-0.5, 0.5, 0)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv.position, uv.position + Vector2(uv.size.x, 0), uv.end, uv.position + Vector2(0, uv.size.y)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		_quads[uv] = mesh
	return _quads[uv]
