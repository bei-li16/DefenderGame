extends ProgressBar
## Fill is measured inside a fixed metal housing; it cannot paint over caps
## at 100%, or disappear under them at low health.
const UiTheme = preload("res://src/presentation/ui_theme.gd")
const Art = preload("res://src/presentation/art/game_art.gd")
var enamel := Color("bc9752")
var _liquid: StyleBoxTexture
var _track: StyleBoxFlat
var _cap: Texture2D


func _ready() -> void:
	show_percentage = false
	add_theme_stylebox_override("background", UiTheme.empty())
	add_theme_stylebox_override("fill", UiTheme.empty())
	_track = UiTheme.inset(Color("101b17"), 0)
	_track.border_color = Color("a4a48c")
	_track.shadow_color = Color(0, 0, 0, 0.7)
	_track.shadow_size = 2
	_liquid = UiTheme.meter_fill(enamel)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		_liquid.set_expand_margin(side, 0)
	_cap = Art.region("ui_chrome", Rect2(Vector2(686, 58) / 1254.0, Vector2(62, 62) / 1254.0))
	value_changed.connect(func(_value: float) -> void: queue_redraw())
	resized.connect(queue_redraw)
	queue_redraw()


func fill_rect() -> Rect2:
	var ratio := clampf((value - min_value) / maxf(0.001, max_value - min_value), 0, 1)
	return Rect2(12, 4, maxf(0, size.x - 24) * ratio, maxf(0, size.y - 8))


func _draw() -> void:
	if _liquid == null:
		return
	draw_style_box(_track, Rect2(5, 1, maxf(0, size.x - 10), size.y - 2))
	var filled := fill_rect()
	if filled.size.x > 0:
		draw_style_box(_liquid, filled)
	var cap_size := minf(12, size.y)
	for x in [0.0, size.x - cap_size]:
		draw_texture_rect(_cap, Rect2(x, (size.y - cap_size) * 0.5, cap_size, cap_size), false)
