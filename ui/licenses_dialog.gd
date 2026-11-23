class_name LicensesDialog
extends Control
## Settings -> Licenses…: TarotTerminal's own license (LICENSE, packed into the build)
## and the Godot Engine's, with the third-party libraries the engine includes. A build
## must carry Godot's notice; this is where it does.

const LICENSE_PATH := "res://LICENSE"

var text_view: RichTextLabel
var close_button: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open() -> void:
	text_view.text = licenses_text()
	text_view.scroll_to_line(0)
	visible = true
	close_button.grab_focus()


func close() -> void:
	visible = false


## Everything shown, as plain text: ours, then Godot's, then each library's.
static func licenses_text() -> String:
	var parts: PackedStringArray = []
	parts.append("TarotTerminal\n\n" + FileAccess.get_file_as_string(LICENSE_PATH).strip_edges())
	parts.append("Godot Engine\n\n" + Engine.get_license_text().strip_edges())
	var credits: PackedStringArray = []
	for component: Dictionary in Engine.get_copyright_info():
		var lines: PackedStringArray = [str(component.get("name", ""))]
		for part: Dictionary in component.get("parts", []):
			for holder: Variant in part.get("copyright", []):
				lines.append("    © %s" % holder)
			lines.append("    License: %s" % part.get("license", ""))
		credits.append("\n".join(lines))
	parts.append("Components of the Godot Engine\n\n" + "\n\n".join(credits))
	var texts: Dictionary = Engine.get_license_info()
	var names: Array = texts.keys()
	names.sort()
	for license_name: Variant in names:
		parts.append("License: %s\n\n%s" % [license_name, str(texts[license_name]).strip_edges()])
	return "\n\n————————————————————\n\n".join(parts)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var dialog: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = ReaderTheme.panel()
	style.bg_color = ReaderTheme.BACKGROUND.lightened(0.04)
	style.border_color = Color(ReaderTheme.BRASS, 0.5)
	style.set_content_margin_all(22)
	dialog.add_theme_stylebox_override("panel", style)
	dialog.custom_minimum_size = Vector2(900, 560)
	centre.add_child(dialog)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog.add_child(column)

	var title: Label = Label.new()
	title.text = "Licenses"
	title.theme_type_variation = ReaderTheme.TITLE
	column.add_child(title)
	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = false
	text_view.selection_enabled = true
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_view.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(text_view)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
