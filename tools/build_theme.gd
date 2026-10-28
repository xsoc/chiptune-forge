extends SceneTree
## Builds res://resources/theme/app_theme.tres, the app's one shared Theme.
##
## Run after changing colours or sizes:
##   godot --headless --path . -s tools/build_theme.gd
## The generated .tres can also be edited in the Theme editor.

const BG := Color("0f1014")
const SURFACE := Color("16171d")
const SURFACE_2 := Color("1e2028")
const SURFACE_3 := Color("272a34")
const BORDER := Color("2c2f3b")
const TEXT := Color("e8e9ed")
const MUTED := Color("9a9daa")
const AMBER := Color("f5b942")
const TEAL := Color("52d1c0")
const DANGER := Color("ff6b6b")
const ON_ACCENT := Color("17130a")

var theme := Theme.new()
var inter: FontVariation
var inter_bold: FontVariation
var grotesk: FontVariation
var mono: FontVariation


func _init() -> void:
	_fonts()
	theme.default_font = inter
	theme.default_font_size = 15
	_base()
	_buttons()
	_inputs()
	_containers()
	_variations()
	var err := ResourceSaver.save(theme, "res://resources/theme/app_theme.tres")
	print("Saved theme: ", error_string(err))
	quit()


func _font(path: String, weight: int) -> FontVariation:
	var file: FontFile = load(path)
	var variation := FontVariation.new()
	variation.base_font = file
	variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return variation


func _fonts() -> void:
	inter = _font("res://assets/fonts/Inter.ttf", 450)
	inter_bold = _font("res://assets/fonts/Inter.ttf", 650)
	grotesk = _font("res://assets/fonts/SpaceGrotesk.ttf", 600)
	mono = _font("res://assets/fonts/JetBrainsMono.ttf", 500)


func _box(bg: Color, radius := 8, border := Color.TRANSPARENT, pad_h := 12, pad_v := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(1)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	box.anti_aliasing = true
	return box


func _empty(pad := 0) -> StyleBoxEmpty:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box


func _base() -> void:
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "RichTextLabel", TEXT)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("bold_font", "RichTextLabel", inter_bold)
	theme.set_font("mono_font", "RichTextLabel", mono)
	theme.set_stylebox("panel", "Panel", _box(BG, 0))
	theme.set_stylebox("panel", "PanelContainer", _empty())
	var tooltip := _box(SURFACE_3, 6, BORDER, 10, 6)
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 13)


func _buttons() -> void:
	theme.set_stylebox("normal", "Button", _box(SURFACE_2, 8, BORDER))
	theme.set_stylebox("hover", "Button", _box(SURFACE_3, 8, BORDER))
	theme.set_stylebox("pressed", "Button", _box(SURFACE_3, 8, AMBER))
	theme.set_stylebox("disabled", "Button", _box(SURFACE, 8, BORDER))
	var focus := _box(Color.TRANSPARENT, 8, AMBER.lerp(TEXT, 0.3))
	focus.draw_center = false
	focus.set_border_width_all(2)
	theme.set_stylebox("focus", "Button", focus)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", AMBER)
	theme.set_color("font_hover_pressed_color", "Button", AMBER)
	theme.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	theme.set_color("icon_normal_color", "Button", TEXT)
	theme.set_color("icon_pressed_color", "Button", AMBER)
	theme.set_constant("h_separation", "Button", 6)
	for type in ["OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type, _box(SURFACE_2, 8, BORDER))
		theme.set_stylebox("hover", type, _box(SURFACE_3, 8, BORDER))
		theme.set_stylebox("pressed", type, _box(SURFACE_3, 8, BORDER))
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, TEXT)
	theme.set_stylebox("panel", "PopupMenu", _box(SURFACE_2, 8, BORDER, 6, 6))
	theme.set_stylebox("hover", "PopupMenu", _box(SURFACE_3, 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_constant("v_separation", "PopupMenu", 8)
	for type in ["CheckBox", "CheckButton"]:
		theme.set_stylebox("normal", type, _empty(4))
		theme.set_stylebox("hover", type, _empty(4))
		theme.set_stylebox("pressed", type, _empty(4))
		theme.set_stylebox("hover_pressed", type, _empty(4))
		theme.set_stylebox("focus", type, focus)
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_pressed_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_hover_pressed_color", type, Color.WHITE)
	theme.set_icon("checked", "CheckBox", load("res://assets/ui/check_on.svg"))
	theme.set_icon("unchecked", "CheckBox", load("res://assets/ui/check_off.svg"))


func _inputs() -> void:
	theme.set_stylebox("normal", "LineEdit", _box(SURFACE_2, 8, BORDER, 10, 8))
	theme.set_stylebox("focus", "LineEdit", _box(SURFACE_2, 8, AMBER, 10, 8))
	theme.set_stylebox("read_only", "LineEdit", _box(SURFACE, 8, BORDER, 10, 8))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme.set_color("caret_color", "LineEdit", AMBER)
	theme.set_stylebox("normal", "TextEdit", _box(SURFACE_2, 8, BORDER, 10, 8))
	theme.set_stylebox("focus", "TextEdit", _box(SURFACE_2, 8, AMBER, 10, 8))
	theme.set_stylebox("read_only", "TextEdit", _box(SURFACE, 8, BORDER, 10, 8))
	theme.set_font("font", "TextEdit", mono)
	theme.set_font_size("font_size", "TextEdit", 13)
	theme.set_color("font_color", "TextEdit", TEXT)
	theme.set_color("font_readonly_color", "TextEdit", TEXT)
	theme.set_stylebox("normal", "SpinBox", _box(SURFACE_2, 8, BORDER))

	var track := _box(SURFACE_3, 3, Color.TRANSPARENT, 0, 3)
	var grabber_area := _box(AMBER, 3, Color.TRANSPARENT, 0, 3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", grabber_area)
	theme.set_stylebox("grabber_area_highlight", "HSlider", grabber_area)
	theme.set_icon("grabber", "HSlider", load("res://assets/ui/grabber.svg"))
	theme.set_icon("grabber_highlight", "HSlider", load("res://assets/ui/grabber_hover.svg"))
	theme.set_constant("center_grabber", "HSlider", 0)
	theme.set_constant("grabber_offset", "HSlider", 0)

	theme.set_stylebox("background", "ProgressBar", _box(SURFACE_3, 3, Color.TRANSPARENT, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(AMBER, 3, Color.TRANSPARENT, 0, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)


func _containers() -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _box(Color(1, 1, 1, 0.02), 4, Color.TRANSPARENT, 4, 4))
		theme.set_stylebox("grabber", type, _box(SURFACE_3, 4, Color.TRANSPARENT, 4, 4))
		theme.set_stylebox("grabber_highlight", type, _box(BORDER.lightened(0.2), 4, Color.TRANSPARENT, 4, 4))
		theme.set_stylebox("grabber_pressed", type, _box(MUTED, 4, Color.TRANSPARENT, 4, 4))
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 8)
	theme.set_constant("h_separation", "HFlowContainer", 6)
	theme.set_constant("v_separation", "HFlowContainer", 6)
	theme.set_constant("h_separation", "GridContainer", 8)
	theme.set_constant("v_separation", "GridContainer", 8)

	theme.set_stylebox("tab_selected", "TabBar", _box(SURFACE_3, 8, BORDER, 12, 6))
	theme.set_stylebox("tab_unselected", "TabBar", _empty(8))
	theme.set_stylebox("tab_hovered", "TabBar", _box(SURFACE_2, 8, Color.TRANSPARENT, 12, 6))
	theme.set_stylebox("tab_focus", "TabBar", _empty())
	theme.set_color("font_selected_color", "TabBar", TEXT)
	theme.set_color("font_unselected_color", "TabBar", MUTED)
	theme.set_color("font_hovered_color", "TabBar", TEXT)
	theme.set_font_size("font_size", "TabBar", 14)
	theme.set_constant("h_separation", "TabBar", 4)

	theme.set_stylebox("panel", "AcceptDialog", _box(SURFACE, 12, BORDER, 16, 16))
	theme.set_stylebox("panel", "Window", _box(SURFACE, 12, BORDER, 16, 16))


func _variations() -> void:
	# Card: the rounded panels every screen is built from.
	theme.add_type("Card")
	theme.set_type_variation("Card", "PanelContainer")
	theme.set_stylebox("panel", "Card", _box(SURFACE, 14, BORDER, 16, 14))

	theme.set_type_variation("Inset", "PanelContainer")
	theme.set_stylebox("panel", "Inset", _box(SURFACE_2, 10, BORDER, 10, 8))

	theme.set_type_variation("HeaderBar", "PanelContainer")
	var header := _box(SURFACE, 0, Color.TRANSPARENT, 16, 10)
	header.border_color = BORDER
	header.border_width_bottom = 1
	theme.set_stylebox("panel", "HeaderBar", header)

	theme.set_type_variation("BottomBar", "PanelContainer")
	var bottom := _box(SURFACE, 0, Color.TRANSPARENT, 8, 6)
	bottom.border_color = BORDER
	bottom.border_width_top = 1
	theme.set_stylebox("panel", "BottomBar", bottom)

	# Labels.
	theme.set_type_variation("TitleLabel", "Label")
	theme.set_font("font", "TitleLabel", grotesk)
	theme.set_font_size("font_size", "TitleLabel", 20)
	theme.set_type_variation("BigTitleLabel", "Label")
	theme.set_font("font", "BigTitleLabel", grotesk)
	theme.set_font_size("font_size", "BigTitleLabel", 26)
	theme.set_type_variation("SectionLabel", "Label")
	theme.set_font("font", "SectionLabel", inter_bold)
	theme.set_font_size("font_size", "SectionLabel", 12)
	theme.set_color("font_color", "SectionLabel", MUTED)
	theme.set_type_variation("MutedLabel", "Label")
	theme.set_color("font_color", "MutedLabel", MUTED)
	theme.set_font_size("font_size", "MutedLabel", 13)
	theme.set_type_variation("MonoLabel", "Label")
	theme.set_font("font", "MonoLabel", mono)
	theme.set_font_size("font_size", "MonoLabel", 13)
	theme.set_type_variation("WarningLabel", "Label")
	theme.set_color("font_color", "WarningLabel", AMBER)
	theme.set_font_size("font_size", "WarningLabel", 13)

	# Chips, in amber for music and teal for sound effects.
	for pair in [["Chip", AMBER], ["SfxChip", TEAL]]:
		var type: String = pair[0]
		var accent: Color = pair[1]
		theme.set_type_variation(type, "Button")
		theme.set_stylebox("normal", type, _box(SURFACE_2, 16, BORDER, 12, 6))
		theme.set_stylebox("hover", type, _box(SURFACE_3, 16, BORDER, 12, 6))
		theme.set_stylebox("pressed", type, _box(accent, 16, accent, 12, 6))
		theme.set_stylebox("hover_pressed", type, _box(accent.lightened(0.1), 16, accent, 12, 6))
		theme.set_color("font_pressed_color", type, ON_ACCENT)
		theme.set_color("font_hover_pressed_color", type, ON_ACCENT)
		theme.set_font_size("font_size", type, 14)

	for pair in [["PrimaryButton", AMBER], ["SfxPrimaryButton", TEAL]]:
		var type: String = pair[0]
		var accent: Color = pair[1]
		theme.set_type_variation(type, "Button")
		theme.set_stylebox("normal", type, _box(accent, 10, Color.TRANSPARENT, 18, 12))
		theme.set_stylebox("hover", type, _box(accent.lightened(0.12), 10, Color.TRANSPARENT, 18, 12))
		theme.set_stylebox("pressed", type, _box(accent.darkened(0.1), 10, Color.TRANSPARENT, 18, 12))
		theme.set_stylebox("disabled", type, _box(accent.darkened(0.5), 10, Color.TRANSPARENT, 18, 12))
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			theme.set_color(state, type, ON_ACCENT)
		theme.set_color("icon_normal_color", type, ON_ACCENT)
		theme.set_color("icon_hover_color", type, ON_ACCENT)
		theme.set_color("icon_pressed_color", type, ON_ACCENT)
		theme.set_font("font", type, inter_bold)
		theme.set_font_size("font_size", type, 16)

	# Navigation tabs and the Music / Sound FX switch.
	for pair in [["NavButton", AMBER], ["SfxNavButton", TEAL]]:
		var type: String = pair[0]
		var accent: Color = pair[1]
		theme.set_type_variation(type, "Button")
		theme.set_stylebox("normal", type, _empty(10))
		theme.set_stylebox("hover", type, _box(SURFACE_2, 8, Color.TRANSPARENT, 10, 10))
		var on := _box(Color(accent, 0.14), 8, Color.TRANSPARENT, 10, 10)
		theme.set_stylebox("pressed", type, on)
		theme.set_stylebox("hover_pressed", type, on)
		theme.set_color("font_color", type, MUTED)
		theme.set_color("font_pressed_color", type, accent)
		theme.set_color("font_hover_pressed_color", type, accent)
		theme.set_color("icon_normal_color", type, MUTED)
		theme.set_color("icon_pressed_color", type, accent)
		theme.set_font("font", type, inter_bold)
		theme.set_font_size("font_size", type, 14)

	theme.set_type_variation("SfxSlider", "HSlider")
	var teal_area := _box(TEAL, 3, Color.TRANSPARENT, 0, 3)
	theme.set_stylebox("grabber_area", "SfxSlider", teal_area)
	theme.set_stylebox("grabber_area_highlight", "SfxSlider", teal_area)

	theme.set_type_variation("FlatButton", "Button")
	theme.set_stylebox("normal", "FlatButton", _empty(6))
	theme.set_stylebox("hover", "FlatButton", _box(SURFACE_2, 6, Color.TRANSPARENT, 6, 6))
	theme.set_stylebox("pressed", "FlatButton", _box(SURFACE_3, 6, Color.TRANSPARENT, 6, 6))
	theme.set_stylebox("hover_pressed", "FlatButton", _box(SURFACE_3, 6, Color.TRANSPARENT, 6, 6))
	theme.set_color("font_pressed_color", "FlatButton", AMBER)
	theme.set_color("icon_pressed_color", "FlatButton", AMBER)

	theme.set_type_variation("LevelButton", "Button")
	theme.set_stylebox("normal", "LevelButton", _box(SURFACE_2, 6, BORDER, 6, 6))
	theme.set_stylebox("hover", "LevelButton", _box(SURFACE_3, 6, BORDER, 6, 6))
	theme.set_font_size("font_size", "LevelButton", 13)
