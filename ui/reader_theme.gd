class_name ReaderTheme
## The app's look: dark and quiet, midnight indigo with brass. Built once and set on
## App, so every control inherits it. Adapted from KitsuTarot's KitsuTheme.

const BACKGROUND: Color = Color("#12121f")
const PANEL: Color = Color(Color("#1b1b2e"), 0.85)
const BRASS: Color = Color("#c9a96b")
const TEXT: Color = Color("#ebe4d3")
const MUTED: Color = Color("#8f8aa3")
const ILL: Color = Color("#c0605a")
const WELL: Color = Color("#8fae7e")
const BUTTON: Color = Color("#232338")

## Label variations: set `theme_type_variation` to one of these.
const TITLE: StringName = &"TitleLabel"
const HEADING: StringName = &"HeadingLabel"
const MUTED_LABEL: StringName = &"MutedLabel"

const SERIF: PackedStringArray = ["Palatino Linotype", "Book Antiqua", "Palatino", "Georgia", "serif"]


static func serif(weight: int = 400) -> SystemFont:
	var font: SystemFont = SystemFont.new()
	font.font_names = SERIF
	font.font_weight = weight
	return font


static func build() -> Theme:
	var theme: Theme = Theme.new()
	theme.default_font = serif()
	theme.default_font_size = 17
	var bold: SystemFont = serif(700)

	theme.set_color("font_color", "Label", TEXT)
	theme.set_type_variation(TITLE, "Label")
	theme.set_font("font", TITLE, bold)
	theme.set_font_size("font_size", TITLE, 26)
	theme.set_color("font_color", TITLE, BRASS)
	theme.set_type_variation(HEADING, "Label")
	theme.set_font("font", HEADING, bold)
	theme.set_font_size("font_size", HEADING, 18)
	theme.set_color("font_color", HEADING, BRASS)
	theme.set_type_variation(MUTED_LABEL, "Label")
	theme.set_color("font_color", MUTED_LABEL, MUTED)
	theme.set_font_size("font_size", MUTED_LABEL, 15)

	for type: StringName in [&"Button", &"OptionButton"]:
		theme.set_color("font_color", type, TEXT)
		theme.set_color("font_hover_color", type, Color.WHITE)
		theme.set_color("font_pressed_color", type, BRASS)
		theme.set_color("font_focus_color", type, TEXT)
		theme.set_color("font_disabled_color", type, Color(MUTED, 0.6))
		theme.set_stylebox("normal", type, _box(BUTTON, BRASS.darkened(0.45)))
		theme.set_stylebox("hover", type, _box(BUTTON.lightened(0.1), BRASS))
		theme.set_stylebox("pressed", type, _box(BUTTON.darkened(0.3), BRASS))
		theme.set_stylebox("disabled", type, _box(Color(BUTTON, 0.45), Color(BRASS, 0.15)))
		theme.set_stylebox("focus", type, _box(Color.TRANSPARENT, Color(BRASS, 0.7), 1))
	theme.set_constant("h_separation", "Button", 6)

	theme.set_stylebox("panel", "PanelContainer", panel())
	theme.set_stylebox("panel", "Panel", panel())
	theme.set_stylebox("normal", "LineEdit", _box(PANEL, BRASS.darkened(0.5)))
	theme.set_stylebox("focus", "LineEdit", _box(Color.TRANSPARENT, BRASS, 1))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.8))
	theme.set_color("caret_color", "LineEdit", BRASS)
	theme.set_stylebox("normal", "TextEdit", _box(PANEL, BRASS.darkened(0.5)))
	theme.set_stylebox("focus", "TextEdit", _box(Color.TRANSPARENT, BRASS, 1))
	theme.set_color("font_color", "TextEdit", TEXT)
	theme.set_color("caret_color", "TextEdit", BRASS)
	theme.set_color("selection_color", "TextEdit", Color(BRASS, 0.3))
	theme.set_stylebox("panel", "ItemList", _box(PANEL, BRASS.darkened(0.5)))
	theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	theme.set_stylebox("selected", "ItemList", _box(BUTTON, BRASS.darkened(0.3)))
	theme.set_stylebox("selected_focus", "ItemList", _box(BUTTON, BRASS))
	theme.set_stylebox("hovered", "ItemList", _box(Color(BUTTON, 0.6), Color.TRANSPARENT))
	theme.set_color("font_color", "ItemList", TEXT)
	theme.set_color("font_selected_color", "ItemList", BRASS)
	theme.set_color("font_hovered_color", "ItemList", Color.WHITE)
	theme.set_constant("v_separation", "ItemList", 6)
	# Toggles inherit from Button, so they would otherwise get its frame.
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_pressed_color", "CheckBox", TEXT)
	theme.set_color("font_hover_pressed_color", "CheckBox", Color.WHITE)
	theme.set_color("font_focus_color", "CheckBox", TEXT)
	theme.set_color("checkbox_unchecked_color", "CheckBox", TEXT)
	theme.set_color("checkbox_checked_color", "CheckBox", BRASS)
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		empty.set_content_margin_all(4)
		theme.set_stylebox(state, "CheckBox", empty)
	theme.set_stylebox("focus", "CheckBox", _box(Color.TRANSPARENT, Color(BRASS, 0.5)))
	theme.set_icon("unchecked", "CheckBox", _check_icon(false))
	theme.set_icon("checked", "CheckBox", _check_icon(true))
	theme.set_icon("unchecked_disabled", "CheckBox", _check_icon(false))
	theme.set_icon("checked_disabled", "CheckBox", _check_icon(true))
	var track: StyleBoxFlat = _box(BUTTON, Color(BRASS, 0.3))
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", track)
	var filled: StyleBoxFlat = _box(Color(BRASS, 0.55), Color.TRANSPARENT)
	filled.content_margin_top = 2
	filled.content_margin_bottom = 2
	theme.set_stylebox("grabber_area", "HSlider", filled)
	theme.set_stylebox("grabber_area_highlight", "HSlider", filled)
	theme.set_color("default_color", "RichTextLabel", TEXT)
	theme.set_font("bold_font", "RichTextLabel", bold)
	var italic: SystemFont = serif()
	italic.font_italic = true
	theme.set_font("italics_font", "RichTextLabel", italic)
	theme.set_font_size("normal_font_size", "RichTextLabel", 17)
	theme.set_font_size("bold_font_size", "RichTextLabel", 17)
	theme.set_font_size("italics_font_size", "RichTextLabel", 17)
	theme.set_stylebox("normal", "RichTextLabel", StyleBoxEmpty.new())
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "TooltipPanel", _box(BACKGROUND, Color(BRASS, 0.5)))
	theme.set_stylebox("panel", "PopupMenu", _box(BACKGROUND, Color(BRASS, 0.4)))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", BRASS)
	theme.set_stylebox("hover", "PopupMenu", _box(BUTTON, Color.TRANSPARENT))
	return theme


## The table: lighter in the middle, darker toward the edges.
static func background() -> TextureRect:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, BACKGROUND.lightened(0.08))
	gradient.set_color(1, BACKGROUND.darkened(0.55))
	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.4, 0.45)
	texture.fill_to = Vector2(1.2, 1.2)
	texture.width = 256
	texture.height = 256
	var rect: TextureRect = TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func panel() -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = Color(BRASS, 0.22)
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12)
	return box


## The colour for a dignity state from Dignities.
static func dignity_color(state: String) -> Color:
	match state:
		Dignities.WELL:
			return WELL
		Dignities.ILL:
			return ILL
	return MUTED


## An 18 px brass square, filled with a smaller square when checked. Godot's default
## icon is dark and vanishes on this background.
static func _check_icon(checked: bool) -> ImageTexture:
	const SIDE: int = 18
	var image: Image = Image.create(SIDE, SIDE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for i: int in SIDE:
		for edge: int in [0, SIDE - 1]:
			image.set_pixel(i, edge, BRASS)
			image.set_pixel(edge, i, BRASS)
	if checked:
		image.fill_rect(Rect2i(4, 4, SIDE - 8, SIDE - 8), BRASS)
	return ImageTexture.create_from_image(image)


static func _box(fill: Color, border: Color, border_width: int = 1) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(5)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	return box
