class_name DefenderUiTheme
extends RefCounted

const Assets = preload("res://src/presentation/art/ui_assets.gd")
static var _icons: Dictionary = {}


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", Color("edece1"))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.55))
	theme.set_constant("shadow_offset_y", "Label", 1)
	for type in ["Button", "MenuButton", "OptionButton"]:
		theme.set_font_size("font_size", type, 22)
		theme.set_color("font_color", type, Color("e8e6d9"))
		theme.set_color("font_hover_color", type, Color("fff4d7"))
		theme.set_color("font_pressed_color", type, Color.WHITE)
		theme.set_color("font_disabled_color", type, Color("8c9590"))
		theme.set_stylebox("normal", type, frame("button"))
		theme.set_stylebox("hover", type, frame("button", Color(1.22, 1.18, 1.05)))
		theme.set_stylebox("pressed", type, frame("primary", Color(0.8, 0.9, 0.9)))
		theme.set_stylebox("hover_pressed", type, frame("primary"))
		theme.set_stylebox("disabled", type, frame("button", Color(0.55, 0.6, 0.57)))
		theme.set_stylebox("focus", type, focus_box())
	for type in ["PanelContainer", "Panel", "PopupPanel", "PopupMenu", "TooltipPanel"]:
		theme.set_stylebox("panel", type, panel_box())
	theme.set_stylebox("hover", "PopupMenu", frame("button"))
	theme.set_color("font_color", "PopupMenu", Color("edece1"))
	theme.set_color("font_hover_color", "PopupMenu", Color("fff0c9"))
	theme.set_constant("v_separation", "PopupMenu", 14)
	theme.set_stylebox("normal", "LineEdit", inset(Color("131b19")))
	theme.set_stylebox("focus", "LineEdit", focus_box())
	theme.set_color("font_color", "LineEdit", Color("edece1"))
	theme.set_color("caret_color", "LineEdit", Color("d4b574"))
	theme.set_color("selection_color", "LineEdit", Color("45665d"))
	theme.set_stylebox("background", "ProgressBar", meter_track())
	theme.set_stylebox("fill", "ProgressBar", meter_fill(Color("bc9752")))
	for type in ["HSlider", "VSlider"]:
		var rail := inset(Color("101915"), 3)
		var active_rail := inset(Color("789c8a"), 3)
		theme.set_stylebox("slider", type, rail)
		theme.set_stylebox("grabber_area", type, active_rail)
		theme.set_stylebox("grabber_area_highlight", type, inset(Color("a9cdb8"), 3))
		theme.set_icon("grabber", type, _small_icon("coin", 24))
		theme.set_icon("grabber_highlight", type, _small_icon("coin", 28))
	for type in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, inset(Color("101713"), 2))
		theme.set_stylebox("grabber", type, inset(Color("64766c"), 4))
		theme.set_stylebox("grabber_highlight", type, inset(Color("95a894"), 4))
		theme.set_stylebox("grabber_pressed", type, inset(Color("bbab74"), 4))
		theme.set_icon("increment", type, _blank_icon())
		theme.set_icon("decrement", type, _blank_icon())
	for type in ["CheckButton", "CheckBox"]:
		theme.set_color("font_color", type, Color("edece1"))
		theme.set_stylebox("normal", type, empty(4))
		theme.set_stylebox("hover", type, empty(4))
		theme.set_stylebox("pressed", type, empty(4))
		theme.set_stylebox("focus", type, focus_box())
		for state in ["on", "checked"]:
			theme.set_icon(state, type, _small_icon("check", 32))
		for state in ["off", "unchecked"]:
			theme.set_icon(state, type, _small_icon("close", 32))
	var separator := StyleBoxLine.new()
	separator.color = Color("5f675a")
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_constant("separation", "HSeparator", 8)
	return theme


static func frame(kind: String = "button", tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = Assets.chrome(kind)
	style.modulate_color = tint
	var ratio := style.texture.get_width() / float(Assets.CHROME[kind].size.x)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, (80 if kind == "panel" else 58) * ratio)
		style.set_content_margin(side, 24 if side == SIDE_LEFT or side == SIDE_RIGHT else 12)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	return style


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", frame("primary"))
	button.add_theme_stylebox_override("hover", frame("primary", Color(1.3, 1.2, 1.1)))
	button.add_theme_stylebox_override("pressed", frame("primary", Color(0.75, 0.8, 0.8)))
	button.add_theme_color_override("font_color", Color("fff1d1"))


static func hud_box() -> StyleBoxTexture:
	var style := frame("button")
	style.set_content_margin_all(16)
	style.content_margin_left = 28
	style.content_margin_right = 28
	return style


static func panel_box(_color: Color = Color.WHITE, _border: Color = Color.WHITE) -> StyleBoxTexture:
	return frame("panel")


static func empty(margin: float = 0) -> StyleBoxEmpty:
	var style := StyleBoxEmpty.new()
	style.set_content_margin_all(margin)
	return style


static func inset(color: Color, margin: float = 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("657267")
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(margin)
	return style


static func focus_box() -> StyleBoxFlat:
	var style := inset(Color.TRANSPARENT, 0)
	style.border_color = Color("a9d9c1")
	style.set_border_width_all(2)
	return style


static func meter_track() -> StyleBoxTexture:
	var style := frame("button")
	style.set_content_margin_all(0)
	return style


static func meter_fill(color: Color) -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.18, 0.48, 0.53, 1.0])
	gradient.colors = PackedColorArray([color.lightened(0.38), color, color, color.darkened(0.25), color.darkened(0.5)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 32
	texture.fill_from = Vector2.ZERO
	texture.fill_to = Vector2.DOWN
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.set_content_margin_all(0)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_expand_margin(side, -4)
	return style


static func _small_icon(key: String, side: int) -> Texture2D:
	var id := key + str(side)
	if not _icons.has(id):
		var image := Assets.icon(key).get_image()
		image.resize(side, side, Image.INTERPOLATE_LANCZOS)
		_icons[id] = ImageTexture.create_from_image(image)
	return _icons[id]


static func _blank_icon() -> Texture2D:
	return ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
