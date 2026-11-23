class_name ExamplesDialog
extends Control
## Example readings: list, edit and delete the few-shot examples, at most
## ReadingExamples.LIMIT. Opened from Settings, or from "Save as example…" with a draft
## of the finished reading added as a new entry. Nothing is written until Save.

signal saved(count: int)

## Where the examples live; tests point this somewhere harmless.
var examples_path: String = ReadingExamples.default_path()

var list: ItemList
var text_input: TextEdit
var note: Label
var status: Label
var delete_button: Button
var save_button: Button
var cancel_button: Button

var _entries: PackedStringArray = []
var _selected: int = -1
## The entry added from the finished reading, or -1.
var _new_index: int = -1


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()


## Shows the saved examples. With a draft, adds it as a new entry and selects it.
func open(draft: String = "") -> void:
	_entries = ReadingExamples.entries(examples_path)
	_new_index = -1
	if draft != "":
		_entries.append(draft)
		_new_index = _entries.size() - 1
	note.text = ("Your own readings, edited into the readings you would want: their voice, "
			+ "length and emphasis teach the model. All of them are sent with every reading. "
			+ "Saved in %s.") % ProjectSettings.globalize_path(examples_path)
	_selected = -1
	_refresh_list()
	_select(_new_index if _new_index >= 0 else 0)
	visible = true
	if _selected >= 0:
		text_input.grab_focus()


func close() -> void:
	visible = false


## The entries as edited so far (for tests).
func entries() -> PackedStringArray:
	return _entries


func delete_selected() -> void:
	if _selected < 0:
		return
	var removed: int = _selected
	_entries.remove_at(removed)
	if _new_index == removed:
		_new_index = -1
	elif _new_index > removed:
		_new_index -= 1
	_selected = -1
	_refresh_list()
	_select(mini(removed, _entries.size() - 1))


func save() -> void:
	var error: Error = ReadingExamples.save_entries(_entries, examples_path)
	if error != OK:
		_set_status("Could not save the examples (%s)." % error_string(error), ReaderTheme.ILL)
		return
	close()
	saved.emit(ReadingExamples.count(examples_path))


func _select(index: int) -> void:
	if index < 0 or index >= _entries.size():
		_selected = -1
		text_input.text = ""
		text_input.editable = false
		list.deselect_all()
	else:
		_selected = index
		text_input.text = _entries[index]
		text_input.editable = true
		text_input.set_caret_line(0)
		text_input.scroll_vertical = 0
		list.select(index)
	_update_state()


func _refresh_list() -> void:
	list.clear()
	for i: int in _entries.size():
		list.add_item(_item_text(i))


func _item_text(index: int) -> String:
	var label_text: String = "%s  ~%d tokens" % [ReadingExamples.title(_entries[index]),
			ReadingPipeline.estimate_tokens(_entries[index])]
	return label_text + ("  (new)" if index == _new_index else "")


func _on_text_changed() -> void:
	if _selected < 0:
		return
	_entries[_selected] = text_input.text
	list.set_item_text(_selected, _item_text(_selected))
	_update_state()


func _update_state() -> void:
	var total: int = _entries.size()
	delete_button.disabled = _selected < 0
	save_button.disabled = total > ReadingExamples.LIMIT
	if total > ReadingExamples.LIMIT:
		_set_status("That makes %d; the limit is %d. Delete one to save." % [
				total, ReadingExamples.LIMIT], ReaderTheme.ILL)
	elif total == 0:
		_set_status("No examples. Finish a reading and use Save as example… to add one.",
				ReaderTheme.MUTED)
	else:
		var tokens: int = 0
		for entry: String in _entries:
			tokens += ReadingPipeline.estimate_tokens(entry)
		_set_status("%d of %d examples, about %d tokens added to every reading." % [
				total, ReadingExamples.LIMIT, tokens], ReaderTheme.MUTED)


func _set_status(text: String, color: Color) -> void:
	status.text = text
	status.add_theme_color_override("font_color", color)


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
	dialog.custom_minimum_size = Vector2(1060, 600)
	centre.add_child(dialog)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog.add_child(column)

	var title: Label = Label.new()
	title.text = "Example readings"
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
	var side: VBoxContainer = VBoxContainer.new()
	side.custom_minimum_size.x = 280
	body.add_child(side)
	list = ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(_select)
	side.add_child(list)
	delete_button = Button.new()
	delete_button.text = "Delete example"
	delete_button.pressed.connect(delete_selected)
	side.add_child(delete_button)
	text_input = TextEdit.new()
	text_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_input.placeholder_text = "Select an example to edit it."
	text_input.text_changed.connect(_on_text_changed)
	body.add_child(text_input)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	status = Label.new()
	status.theme_type_variation = ReaderTheme.MUTED_LABEL
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(status)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(close)
	buttons.add_child(cancel_button)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(save)
	buttons.add_child(save_button)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
