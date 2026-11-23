class_name SpreadDesigner
extends Control
## Designs added spreads: a table of card backs to place (SpreadCanvas), the spread's
## and the selected position's fields, and the problems that would stop the spread
## loading. Saves into the added-spreads folder (SpreadDraft.save), never to the
## built-in spreads, which open as copies.

## A spread was saved: its id. The spread menu rescans when it next opens.
signal saved(spread_id: String)

const HELP := "Double-click the table to add a card (up to 12). Drag to move (Shift: snap to the grid; Alt: straight). " \
		+ "Ctrl+drag or the knob turns it in eighths. Drag from a card's glowing edge (or a node) onto " \
		+ "another card for a dignity line. Delete removes the selected card or line; arrows nudge. " \
		+ "Wheel zooms, middle-drag pans, middle double-click shows the whole layout."

var db: CardDb
## Where added spreads are saved and read (ReadingScreen.spreads_folder).
var spreads_folder: String = SpreadLibrary.default_folder()
var draft: SpreadDraft
var canvas: SpreadCanvas
## Unsaved changes.
var dirty: bool = false

var id_input: LineEdit
var name_input: LineEdit
var source_input: LineEdit
var words_input: LineEdit
var card_height_input: AutoSpinBox
var columns_input: AutoSpinBox
var compact_input: CheckBox
var position_list: ItemList
var up_button: Button
var down_button: Button
var position_box: VBoxContainer
var position_id_input: LineEdit
var position_name_input: LineEdit
var meaning_input: TextEdit
var rotation_input: SpinBox
var over_input: OptionButton
var line_box: HBoxContainer
var line_label: Label
var problems_label: Label
var status_label: Label
var save_button: Button
var open_button: MenuButton
var table_input: OptionButton
var grid_input: OptionButton
var over_dialog: ConfirmationDialog
var discard_dialog: ConfirmationDialog

## Spreads in the Open menu: {id, data, builtin, file}.
var _open_entries: Array[Dictionary] = []
## Run after "discard changes?" is confirmed.
var _pending: Callable = Callable()
var _pending_over: Vector2i = Vector2i(-1, -1)
## True while fields are being filled from the draft, so they don't edit it back.
var _filling: bool = false


func _init(card_db: CardDb = null) -> void:
	db = card_db
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background: Panel = Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fill: StyleBoxFlat = StyleBoxFlat.new()
	fill.bg_color = ReaderTheme.BACKGROUND
	background.add_theme_stylebox_override("panel", fill)
	add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	margin.add_child(columns)

	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_build_toolbar())
	canvas = SpreadCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.edited.connect(_on_canvas_edited)
	canvas.selection_changed.connect(func(_card: int, _chosen_line: int) -> void: _fill_selection())
	canvas.dropped_on.connect(_on_dropped_on)
	canvas.full.connect(_say_full)
	left.add_child(canvas)
	var help: Label = Label.new()
	help.text = HELP
	help.theme_type_variation = ReaderTheme.MUTED_LABEL
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 13)
	left.add_child(help)
	problems_label = Label.new()
	problems_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(problems_label)

	var side_scroll: ScrollContainer = ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 380
	side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(side_scroll)
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 8)
	side_scroll.add_child(side)
	_build_spread_fields(side)
	_build_position_fields(side)

	over_dialog = ConfirmationDialog.new()
	over_dialog.title = "Lay it over?"
	over_dialog.ok_button_text = "Lay it over"
	over_dialog.cancel_button_text = "No"
	over_dialog.confirmed.connect(_lay_over)
	add_child(over_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "Unsaved changes"
	discard_dialog.dialog_text = "Discard the changes to this spread?"
	discard_dialog.ok_button_text = "Discard"
	discard_dialog.confirmed.connect(func() -> void:
		var action: Callable = _pending
		_pending = Callable()
		if action.is_valid():
			action.call())
	add_child(discard_dialog)
	new_spread()


func set_images(images: DeckImages) -> void:
	canvas.set_images(images)
	_update_problems()


## Starts an empty spread (asks first if there are unsaved changes).
func new_spread() -> void:
	_unless_unsaved(func() -> void: _load_draft(SpreadDraft.new()))


## Opens a spread to edit: an added one by id, or a copy of a built-in one.
func open_spread(spread_id: String) -> void:
	_refresh_open_menu()
	for entry: Dictionary in _open_entries:
		if entry["id"] == spread_id:
			_unless_unsaved(func() -> void:
				_load_draft(SpreadDraft.from_spread(spread_id, entry["data"], entry["builtin"], entry["file"])))
			return
	status_label.text = "No spread \"%s\"." % spread_id


## Everything that would stop the spread loading or fitting the table.
func problems() -> PackedStringArray:
	var found: PackedStringArray = draft.id_problems(_builtin_ids(), _taken_ids())
	found.append_array(SpreadLibrary.validate(draft.to_data()))
	if draft.size() > 0:
		found.append_array(SpreadLayout.problems(draft.spread(), canvas.aspect()))
	return found


## Saves the spread if it has no problems. Returns "" or why not.
func save() -> String:
	var found: PackedStringArray = problems()
	if not found.is_empty():
		status_label.text = "Not saved: fix the problems below first."
		return found[0]
	var error: String = draft.save(spreads_folder)
	if error != "":
		status_label.text = "Not saved: %s" % error
		return error
	dirty = false
	status_label.text = "Saved as %s. It is in the spread menu now." % draft.file
	saved.emit(draft.id)
	_refresh_open_menu()
	return ""


func _build_toolbar() -> HBoxContainer:
	var bar: HBoxContainer = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var new_button: Button = Button.new()
	new_button.text = "New"
	new_button.pressed.connect(new_spread)
	bar.add_child(new_button)
	open_button = MenuButton.new()
	open_button.text = "Open ▾"
	open_button.flat = false
	open_button.about_to_popup.connect(_refresh_open_menu)
	open_button.get_popup().id_pressed.connect(func(item: int) -> void:
		open_spread(_open_entries[item]["id"]))
	bar.add_child(open_button)
	var add_button: Button = Button.new()
	add_button.text = "Add card"
	add_button.pressed.connect(func() -> void:
		var added: int = draft.add_position(Vector2(0.5, 0.5))
		if added < 0:
			_say_full()
			return
		canvas.refresh()
		canvas.select(added)
		_on_canvas_edited())
	bar.add_child(add_button)
	var delete_button: Button = Button.new()
	delete_button.text = "Delete"
	delete_button.tooltip_text = "Remove the selected card or dignity line"
	delete_button.pressed.connect(_delete_selected)
	bar.add_child(delete_button)
	table_input = OptionButton.new()
	for table_size: Vector2 in SpreadLayout.TABLE_SIZES:
		table_input.add_item("Table %d×%d" % [table_size.x, table_size.y])
	table_input.tooltip_text = "The reading table's shape in a 1280×720 window, and a smaller one. " \
			+ "The spread must fit both."
	table_input.item_selected.connect(func(index: int) -> void:
		canvas.table_size = SpreadLayout.TABLE_SIZES[index])
	bar.add_child(table_input)
	grid_input = OptionButton.new()
	for step: int in SpreadCanvas.GRID_SIZES:
		grid_input.add_item("Grid %d" % step)
	grid_input.select(SpreadCanvas.GRID_SIZES.find(32))
	grid_input.tooltip_text = "Hold Shift while dragging a card to snap its centre to this grid. " 			+ "It starts at the deck's centre."
	grid_input.item_selected.connect(func(index: int) -> void:
		canvas.grid = SpreadCanvas.GRID_SIZES[index])
	bar.add_child(grid_input)
	status_label = Label.new()
	status_label.theme_type_variation = ReaderTheme.MUTED_LABEL
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	bar.add_child(status_label)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(func() -> void: save())
	bar.add_child(save_button)
	return bar


func _build_spread_fields(side: VBoxContainer) -> void:
	side.add_child(_heading("Spread"))
	var grid: GridContainer = _grid(side)
	id_input = _line(grid, "Id", "one_word_id", "Its key in the file and the file's name.")
	id_input.text_changed.connect(func(text: String) -> void:
		if not _filling:
			draft.id = text.strip_edges()
			_changed())
	name_input = _line(grid, "Name", "My spread", "Shown in the spread menu.")
	name_input.text_changed.connect(func(text: String) -> void: _set_spread("name", text))
	source_input = _line(grid, "Source", "where it comes from (optional)", "Credit or notes; not sent to the model.")
	source_input.text_changed.connect(func(text: String) -> void: _set_spread("source", text))
	words_input = _line(grid, "Length", Spread.DEFAULT_READING_WORDS,
			"Words asked of the reader, such as \"700 to 1000\".")
	words_input.text_changed.connect(func(text: String) -> void: _set_spread("reading_words", text))
	card_height_input = _auto_spin(grid, "Card height", 0.0, 1.0, 0.01,
			"A share of the table's height (1 is as tall as the table). Auto is %s.
Cards are also kept narrow enough for Columns to fit across, so a big height may need fewer columns." % TableView.CARD_HEIGHT)
	card_height_input.auto_text = "Auto (%s)" % TableView.CARD_HEIGHT
	card_height_input.value_changed.connect(func(value: float) -> void: _set_spread("card_height", value))
	columns_input = _auto_spin(grid, "Columns", 0.0, 30.0, 0.5,
			"Card widths that must fit across the table. Auto is the number of cards + 1.5.
Fewer columns allow bigger cards.")
	columns_input.value_changed.connect(func(value: float) -> void: _set_spread("columns", value))
	compact_input = CheckBox.new()
	compact_input.text = "Number the cards"
	compact_input.tooltip_text = "Number and dignity mark on each card instead of name labels underneath, for close-packed spreads."
	compact_input.toggled.connect(func(on: bool) -> void: _set_spread("compact_labels", on))
	_add_row(grid, "Labels", compact_input)

	side.add_child(_heading("Positions, in reading order"))
	position_list = ItemList.new()
	position_list.custom_minimum_size.y = 150
	position_list.item_selected.connect(func(index: int) -> void: canvas.select(index))
	side.add_child(position_list)
	var order_row: HBoxContainer = HBoxContainer.new()
	up_button = Button.new()
	up_button.text = "Move up"
	up_button.pressed.connect(func() -> void: _move_selected(-1))
	order_row.add_child(up_button)
	down_button = Button.new()
	down_button.text = "Move down"
	down_button.pressed.connect(func() -> void: _move_selected(1))
	order_row.add_child(down_button)
	side.add_child(order_row)


func _build_position_fields(side: VBoxContainer) -> void:
	position_box = VBoxContainer.new()
	side.add_child(position_box)
	position_box.add_child(_heading("Selected position"))
	var grid: GridContainer = _grid(position_box)
	position_id_input = _line(grid, "Id", "p1", "Used for dignity lines; one word.")
	position_id_input.text_submitted.connect(func(_text: String) -> void: _rename_selected())
	position_id_input.focus_exited.connect(_rename_selected)
	position_name_input = _line(grid, "Name", "shown on the table and to the reader",
			"Lower case, as it sits mid-sentence: \"hopes and fears\". Empty: the id.")
	position_name_input.text_changed.connect(func(text: String) -> void: _set_position_text("name", text))
	rotation_input = _spin(grid, "Rotation", -360.0, 360.0, 1.0, "Degrees, clockwise.")
	rotation_input.suffix = "°"
	rotation_input.value_changed.connect(func(value: float) -> void:
		if not _filling and canvas.selected >= 0:
			draft.set_rotation(canvas.selected, value)
			canvas.refresh()
			_changed())
	over_input = OptionButton.new()
	over_input.tooltip_text = "This card lies over that one, as the Celtic Cross's crossing card does."
	over_input.item_selected.connect(func(index: int) -> void:
		_set_position_text("over", "" if index == 0 else over_input.get_item_text(index)))
	_add_row(grid, "Lies over", over_input)
	var meaning_label: Label = Label.new()
	meaning_label.text = "Meaning (sent to the reader)"
	position_box.add_child(meaning_label)
	meaning_input = TextEdit.new()
	meaning_input.custom_minimum_size.y = 110
	meaning_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	meaning_input.text_changed.connect(func() -> void: _set_position_text("meaning", meaning_input.text))
	position_box.add_child(meaning_input)
	line_box = HBoxContainer.new()
	line_label = Label.new()
	line_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_box.add_child(line_label)
	var remove_line: Button = Button.new()
	remove_line.text = "Remove line"
	remove_line.pressed.connect(_delete_selected)
	line_box.add_child(remove_line)
	side.add_child(line_box)


func _load_draft(value: SpreadDraft) -> void:
	draft = value
	dirty = false
	canvas.set_draft(draft)
	_fill_spread()
	_fill_selection()
	_update_problems()
	status_label.text = "Editing %s." % (draft.file if draft.file != "" else "a new spread")


func _fill_spread() -> void:
	_filling = true
	id_input.text = draft.id
	name_input.text = str(draft.data.get("name", ""))
	source_input.text = str(draft.data.get("source", ""))
	words_input.text = str(draft.data.get("reading_words", ""))
	card_height_input.value = float(draft.data.get("card_height", 0.0))
	columns_input.value = float(draft.data.get("columns", 0.0))
	compact_input.button_pressed = draft.data.get("compact_labels", false) == true
	_update_auto_columns()
	_filling = false


func _fill_selection() -> void:
	_filling = true
	position_list.clear()
	for i: int in draft.size():
		var entry: Dictionary = draft.position(i)
		position_list.add_item("%d. %s" % [i + 1, Spread.title(Spread.label(entry))])
	var card: int = canvas.selected
	if card >= 0:
		position_list.select(card)
		position_list.ensure_current_is_visible()
	position_box.visible = card >= 0
	up_button.disabled = card <= 0
	down_button.disabled = card < 0 or card >= draft.size() - 1
	if card >= 0:
		var entry: Dictionary = draft.position(card)
		if not position_id_input.has_focus():
			position_id_input.text = str(entry.get("id", ""))
		if not position_name_input.has_focus():
			position_name_input.text = str(entry.get("name", ""))
		if not meaning_input.has_focus():
			meaning_input.text = str(entry.get("meaning", ""))
		rotation_input.set_value_no_signal(draft.rotation_of(card))
		over_input.clear()
		over_input.add_item("(none)")
		for other: Dictionary in draft.positions():
			if other != entry:
				over_input.add_item(str(other.get("id")))
				if entry.get("over") == other.get("id"):
					over_input.select(over_input.item_count - 1)
	var line: int = canvas.selected_line
	line_box.visible = line >= 0
	if line >= 0:
		var pair: Array = draft.pairs()[line]
		line_label.text = "Dignity line: %s – %s" % [pair[0], pair[1]]
	_filling = false


func _update_problems() -> void:
	var found: PackedStringArray = problems()
	var size_note: String = shown_size_note()
	if found.is_empty():
		problems_label.text = "✓ Ready to save." + ("" if size_note == "" else " " + size_note)
		problems_label.add_theme_color_override("font_color", ReaderTheme.WELL)
	else:
		problems_label.text = "Before saving:\n• " + "\n• ".join(found)
		problems_label.add_theme_color_override("font_color", ReaderTheme.ILL)
	save_button.disabled = not found.is_empty()


## For a spread laid out past the table: the size readings will show it at, on each
## table shape. "" when it fits the table as it is.
func shown_size_note() -> String:
	if draft == null or draft.size() == 0:
		return ""
	var spread: Spread = draft.spread()
	var shares: PackedStringArray = []
	var smaller: bool = false
	for table_size: Vector2 in SpreadLayout.TABLE_SIZES:
		var scale_shown: float = SpreadLayout.fit_scale(
				SpreadLayout.bounds(spread, table_size, canvas.aspect()), table_size)
		smaller = smaller or scale_shown < 0.995
		shares.append("%d%% at %d×%d" % [roundi(scale_shown * 100.0), table_size.x, table_size.y])
	if not smaller:
		return ""
	return "It reaches past the table, so readings show the whole spread smaller: %s." % ", ".join(shares)


func _changed() -> void:
	dirty = true
	_update_auto_columns()
	_update_problems()


## Columns' Auto follows the number of cards (TableView.card_height_for).
func _update_auto_columns() -> void:
	columns_input.auto_text = "Auto (%s)" % (draft.size() + 1.5)


func _on_canvas_edited() -> void:
	_fill_selection()
	_changed()


func _set_spread(key: String, value: Variant) -> void:
	if _filling:
		return
	draft.set_spread_field(key, value)
	if key in ["card_height", "columns"]:
		canvas.refresh()
	_changed()


func _set_position_text(key: String, value: String) -> void:
	if _filling or canvas.selected < 0:
		return
	draft.set_position_field(canvas.selected, key, value)
	canvas.refresh()
	if key != "meaning":
		_fill_selection()
	_changed()


func _rename_selected() -> void:
	if _filling or canvas.selected < 0:
		return
	var error: String = draft.rename_position(canvas.selected, position_id_input.text.strip_edges())
	if error != "":
		status_label.text = error
		position_id_input.text = str(draft.position(canvas.selected).get("id"))
		return
	_fill_selection()
	_changed()


func _move_selected(delta: int) -> void:
	if canvas.selected < 0:
		return
	var to: int = draft.move_in_order(canvas.selected, delta)
	canvas.refresh()
	canvas.select(to)
	_changed()


func _delete_selected() -> void:
	if canvas.selected >= 0:
		draft.remove_position(canvas.selected)
		canvas.refresh()
		canvas.select(-1)
	elif canvas.selected_line >= 0:
		draft.disconnect_pair(canvas.selected_line)
		canvas.select(-1)
	else:
		return
	_on_canvas_edited()


func _say_full() -> void:
	status_label.text = "A spread can have at most %d cards; more would overload the reader." % SpreadLibrary.MAX_POSITIONS


func _on_dropped_on(card: int, under: int) -> void:
	_pending_over = Vector2i(card, under)
	over_dialog.dialog_text = "Lay \"%s\" over \"%s\", as the Celtic Cross's crossing card lies over the first?\nOtherwise they count as overlapping." % [
			draft.position(card).get("id"), draft.position(under).get("id")]
	if is_inside_tree():
		over_dialog.popup_centered()


func _lay_over() -> void:
	var card: int = _pending_over.x
	var under: int = _pending_over.y
	if card < 0 or card >= draft.size() or under < 0 or under >= draft.size():
		return
	# Exactly on top, as the crossing card is.
	var target: Dictionary = draft.position(under)
	draft.move_position(card, Vector2(target["x"], target["y"]))
	draft.set_position_field(card, "over", str(target.get("id")))
	# It goes above the card it covers.
	var to: int = card
	if card < under:
		to = draft.move_in_order(card, under - card)
	canvas.refresh()
	canvas.select(to)
	_on_canvas_edited()


func _unless_unsaved(action: Callable) -> void:
	if not dirty or draft == null:
		action.call()
		return
	_pending = action
	if is_inside_tree():
		discard_dialog.popup_centered()


func _builtin_ids() -> PackedStringArray:
	return db.builtin_spread_ids if db != null else PackedStringArray()


## Ids already used by added spreads: id -> file.
func _taken_ids() -> Dictionary:
	var taken: Dictionary = {}
	for entry: Dictionary in SpreadLibrary.scan(spreads_folder, _builtin_ids()):
		if not taken.has(entry["id"]):
			taken[entry["id"]] = entry["file"]
	return taken


func _refresh_open_menu() -> void:
	_open_entries.clear()
	var popup: PopupMenu = open_button.get_popup()
	popup.clear()
	if db != null:
		for spread_id: String in db.builtin_spread_ids:
			_open_entries.append({"id": spread_id, "data": db.spread(spread_id), "builtin": true, "file": ""})
			popup.add_item("%s (built in: opens a copy)" % db.spread(spread_id).get("name", spread_id),
					_open_entries.size() - 1)
	var added: Array[Dictionary] = SpreadLibrary.scan(spreads_folder, _builtin_ids())
	if not added.is_empty():
		popup.add_separator("Your spreads")
	for entry: Dictionary in added:
		if (entry["data"] as Dictionary).is_empty():
			continue
		_open_entries.append({"id": entry["id"], "data": entry["data"], "builtin": false, "file": entry["file"]})
		popup.add_item("%s  (%s)" % [entry["name"], entry["file"]], _open_entries.size() - 1)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = ReaderTheme.HEADING
	return label


func _grid(parent: Control) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	parent.add_child(grid)
	return grid


func _add_row(grid: GridContainer, title: String, field: Control, tip: String = "") -> void:
	var label: Label = Label.new()
	label.text = title
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tip != "" and field.tooltip_text == "":
		field.tooltip_text = tip
	grid.add_child(field)


func _line(grid: GridContainer, title: String, placeholder: String, tip: String) -> LineEdit:
	var input: LineEdit = LineEdit.new()
	input.placeholder_text = placeholder
	_add_row(grid, title, input, tip)
	return input


## A number field whose 0 means "automatic" and says so.
func _auto_spin(grid: GridContainer, title: String, low: float, high: float, step: float, tip: String) -> AutoSpinBox:
	var input: AutoSpinBox = AutoSpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	_add_row(grid, title, input, tip)
	return input


func _spin(grid: GridContainer, title: String, low: float, high: float, step: float, tip: String) -> SpinBox:
	var input: SpinBox = SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	_add_row(grid, title, input, tip)
	return input
