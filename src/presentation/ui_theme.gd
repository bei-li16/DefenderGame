class_name DefenderUiTheme
extends RefCounted


static func create() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 22
	theme.set_color("font_color", "Label", Color("f4ead5"))
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.7))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	theme.set_font_size("font_size", "Button", 22)
	theme.set_color("font_color", "Button", Color("fff2cf"))
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color("ffd166"))
	theme.set_stylebox("normal", "Button", _box(Color("263a54"), Color("768aa4"), 2, 12))
	theme.set_stylebox("hover", "Button", _box(Color("35547b"), Color("e6b85c"), 3, 12))
	theme.set_stylebox("pressed", "Button", _box(Color("18283e"), Color("ffd166"), 3, 12))
	theme.set_stylebox("disabled", "Button", _box(Color("1c2734"), Color("4b5666"), 2, 12))
	theme.set_stylebox("panel", "PanelContainer", _box(Color(0.045, 0.082, 0.13, 0.94), Color("657a96"), 2, 18))
	theme.set_stylebox("panel", "Panel", _box(Color(0.035, 0.065, 0.105, 0.95), Color("657a96"), 2, 18))
	# Progress bars are used for XP, wave, boss and honour progress.  Godot's
	# default track is almost black on our navy panels, so zero/low progress
	# becomes effectively invisible.  Give every bar a restrained, bordered
	# track and an amber fill; specialised bars (wall/mana) still override the
	# fill colour at the point of use.
	theme.set_stylebox("background", "ProgressBar", _progress_box(Color("101d2d"), Color("536b86")))
	theme.set_stylebox("fill", "ProgressBar", _progress_box(Color("c8942f"), Color("ffd166")))
	theme.set_color("font_color", "CheckButton", Color("f4ead5"))
	theme.set_color("font_color", "OptionButton", Color("f4ead5"))
	return theme


static func panel_box(color: Color = Color(0.035, 0.065, 0.105, 0.94), border: Color = Color("657a96")) -> StyleBoxFlat:
	return _box(color, border, 2, 18)


static func _box(color: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 22.0
	style.content_margin_right = 22.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	return style


static func _progress_box(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 0.0
	style.content_margin_right = 0.0
	style.content_margin_top = 0.0
	style.content_margin_bottom = 0.0
	return style
