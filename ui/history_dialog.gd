class_name HistoryDialog
extends Control
## The saved readings (ReadingHistory), newest first: reopen one on the table, export it
## again, or delete it. Opened from the History… button.

## Open the reading in `path` on the table.
signal open_requested(path: String)
## Open the reading in `path`, then export it.
signal export_requested(path: String)

## Where the readings are kept; tests point this somewhere harmless.
var history_folder: String = ReadingHistory.DEFAULT_FOLDER

var list: ItemList
var preview: Label
var note: Label
var open_button: Button
var export_button: Button
var delete_button: Button
var close_button: Button

var _entries: Array[Dictionary] = []
var _selected: int = -1
## Delete asks once: the path waiting for a second press.
var _confirm_path: String = ""


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


func open() -> void:
	refresh()
	visible = true
	if not _entries.is_empty():
		list.grab_focus()


func close() -> void:
	visible = false


func refresh() -> void:
	_entries = ReadingHistory.list(history_folder)
	list.clear()
	for entry: Dictionary in _entries:
		list.add_item("%s  ·  %s  ·  %s" % [_short_date(entry["date"]), entry["spread_name"], entry["question"]])
	note.text = ("%d saved reading%s, in %s." % [_entries.size(), "" if _entries.size() == 1 else "s",
			ProjectSettings.globalize_path(history_folder)]) if not _entries.is_empty() \
			else "No saved readings yet. Every finished reading is kept here (Settings → History)."
	_select(0 if not _entries.is_empty() else -1)


## The saved readings as listed (for tests).
func entries() -> Array[Dictionary]:
	return _entries


func open_selected() -> void:
	if _selected >= 0:
		close()
		open_requested.emit(_entries[_selected]["path"])


func export_selected() -> void:
	if _selected >= 0:
		close()
		export_requested.emit(_entries[_selected]["path"])


## First press asks, second press deletes.
func delete_selected() -> void:
	if _selected < 0:
		return
	var path: String = _entries[_selected]["path"]
	if _confirm_path != path:
		_confirm_path = path
		delete_button.text = "Delete? Press again"
		return
	var at: int = _selected
	ReadingHistory.delete(path)
	refresh()
	_select(mini(at, _entries.size() - 1))


func _select(index: int) -> void:
	_confirm_path = ""
	delete_button.text = "Delete"
	if index < 0 or index >= _entries.size():
		_selected = -1
		list.deselect_all()
		preview.text = ""
	else:
		_selected = index
		list.select(index)
		list.ensure_current_is_visible()
		var entry: Dictionary = _entries[index]
		preview.text = "%s\n%s · %s\n\n%s" % [entry["question"], entry["spread_name"],
				entry["date"], entry["preview"]]
	for button: Button in [open_button, export_button, delete_button]:
		button.disabled = _selected < 0


## "2026-11-20 16:07:50" -> "2026-11-20 16:07".
static func _short_date(date: String) -> String:
	return date.left(16) if date.length() >= 16 else date


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
	dialog.custom_minimum_size = Vector2(1060, 560)
	centre.add_child(dialog)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog.add_child(column)

	var title: Label = Label.new()
	title.text = "Reading history"
	title.theme_type_variation = ReaderTheme.TITLE
	column.add_child(title)
	note = Label.new()
	note.theme_type_variation = ReaderTheme.MUTED_LABEL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)

	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	column.add_child(body)
	list = ItemList.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.size_flags_stretch_ratio = 1.3
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(_select)
	list.item_activated.connect(func(_i: int) -> void: open_selected())
	body.add_child(list)
	var preview_panel: PanelContainer = PanelContainer.new()
	preview_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override("panel", ReaderTheme.panel())
	body.add_child(preview_panel)
	preview = Label.new()
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_child(preview)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(delete_selected)
	buttons.add_child(delete_button)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	close_button = Button.new()
	close_button.text = "Close"
	close_button.pressed.connect(close)
	buttons.add_child(close_button)
	export_button = Button.new()
	export_button.text = "Export…"
	export_button.tooltip_text = "Open the reading and save it as a Markdown file"
	export_button.pressed.connect(export_selected)
	buttons.add_child(export_button)
	open_button = Button.new()
	open_button.text = "Open"
	open_button.tooltip_text = "Lay the reading out on the table again (double-click works too)"
	open_button.pressed.connect(open_selected)
	buttons.add_child(open_button)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
