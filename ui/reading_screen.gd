class_name ReadingScreen
extends Control
## The one screen: question and spread, the table, the reading and the correspondences.
## It wires buttons to ReadingSession and the session's signals to the views.

## Card images load at least this tall, and at most CARD_IMAGE_MAX (see card_image_height).
const CARD_IMAGE_HEIGHT: int = 720
const CARD_IMAGE_MAX: int = 1440
const WEIGHING: String = "The reader is weighing your question…"

signal settings_requested()
## "Save as example…": a draft of the finished reading for the Example readings dialog.
signal example_requested(draft: String)
## "History…": the saved readings.
signal history_requested()

var session: ReadingSession
var db: CardDb
var settings: AppSettings
var motion: float = 1.0

var question_input: LineEdit
var spread_input: OptionButton
## "Shuffle for me" or "My own cards" (AppSettings.draw_mode).
var draw_input: OptionButton
## Own cards: which card is in this position?
var card_picker: CardPickerDialog
## The deck is fanned for picking cards face down (not for cutting).
var picking: bool = false
var deck_picker: DeckPicker
var table: TableView
var reading_panel: ReadingPanel
var correspondences: CorrespondencePanel
var shuffle_button: Button
var cut_button: Button
var deal_button: Button
var turn_all_button: Button
var new_button: Button
var reread_button: Button
var settings_button: Button
var history_button: Button
var example_button: Button
var export_button: Button
var _export_dialog: FileDialog
var status: Label

var _spread_ids: PackedStringArray = []
## Where added spreads are read from (SpreadLibrary); tests point it elsewhere.
var spreads_folder: String = SpreadLibrary.default_folder()
## Where finished readings are kept (ReadingHistory); tests point it elsewhere.
var history_folder: String = ReadingHistory.DEFAULT_FOLDER
## The file this reading is saved in, once saved: a retry or a critique rewrites it.
var history_path: String = ""
## The added spreads found by the last rescan, usable or not.
var added_spreads: Array[Dictionary] = []


func _init(reading_session: ReadingSession, app_settings: AppSettings, scale_motion: float) -> void:
	session = reading_session
	db = session.db
	settings = app_settings
	motion = scale_motion
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_connect_session()


func _ready() -> void:
	_on_spread_selected(spread_input.selected)
	_update_buttons()


func _build() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var top: HBoxContainer = HBoxContainer.new()
	column.add_child(top)
	var title: Label = Label.new()
	title.text = "TarotTerminal"
	title.theme_type_variation = ReaderTheme.TITLE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var deck_label: Label = Label.new()
	deck_label.text = "Deck"
	deck_label.theme_type_variation = ReaderTheme.MUTED_LABEL
	top.add_child(deck_label)
	deck_picker = DeckPicker.new()
	deck_picker.settings = settings
	deck_picker.custom_minimum_size.x = 240
	deck_picker.deck_changed.connect(_on_deck_changed)
	top.add_child(deck_picker)
	history_button = _button(top, "History…", func() -> void: history_requested.emit())
	history_button.tooltip_text = "Your saved readings: open, export or delete them"
	settings_button = _button(top, "Settings", func() -> void: settings_requested.emit())

	var ask: HBoxContainer = HBoxContainer.new()
	column.add_child(ask)
	question_input = LineEdit.new()
	question_input.placeholder_text = "What would you like to ask the cards?"
	question_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	question_input.text_submitted.connect(func(_t: String) -> void: _on_shuffle())
	ask.add_child(question_input)
	spread_input = OptionButton.new()
	refresh_spreads()
	spread_input.get_popup().about_to_popup.connect(refresh_spreads)
	spread_input.item_selected.connect(_on_spread_chosen)
	ask.add_child(spread_input)
	draw_input = OptionButton.new()
	draw_input.add_item("Shuffle for me")
	draw_input.add_item("My own cards")
	draw_input.tooltip_text = "Let the app shuffle and deal, or lay out your own deck and tell the app which cards came up"
	draw_input.select(1 if settings.draw_mode == "own" else 0)
	draw_input.item_selected.connect(func(index: int) -> void:
		settings.draw_mode = "own" if index == 1 else "app"
		settings.save()
		_update_buttons())
	ask.add_child(draw_input)

	var middle: HBoxContainer = HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 14)
	column.add_child(middle)
	table = TableView.new()
	table.db = db
	table.motion = motion
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.size_flags_stretch_ratio = 1.6
	table.slot_pressed.connect(_on_slot_pressed)
	table.cut_chosen.connect(_on_cut_chosen)
	table.pile_pressed.connect(_on_pile_pressed)
	table.fan_card_picked.connect(_on_fan_card_picked)
	middle.add_child(table)
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	middle.add_child(side)
	reading_panel = ReadingPanel.new()
	reading_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	reading_panel.retry_pressed.connect(session.retry)
	side.add_child(reading_panel)
	correspondences = CorrespondencePanel.new()
	side.add_child(correspondences)

	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	column.add_child(bottom)
	shuffle_button = _button(bottom, "Shuffle", _on_shuffle)
	shuffle_button.tooltip_text = "Shuffle the deck for the question (Enter)"
	cut_button = _button(bottom, "Cut", _on_cut)
	cut_button.tooltip_text = "Fan the deck and choose where to cut it"
	deal_button = _button(bottom, "Deal", session.deal)
	deal_button.tooltip_text = "Deal the cards face down (Space)"
	turn_all_button = _button(bottom, "Turn all", session.turn_all)
	turn_all_button.tooltip_text = "Turn every card over (Ctrl+Enter). Space turns the next one."
	# The keys drive these steps (_unhandled_key_input); a focused button would take
	# Space and Enter first.
	for step_button: Button in [shuffle_button, cut_button, deal_button, turn_all_button]:
		step_button.focus_mode = Control.FOCUS_NONE
	new_button = _button(bottom, "New reading", _on_new_reading)
	reread_button = _button(bottom, "Re-read", reread)
	reread_button.tooltip_text = "Read these cards again, with the model now chosen in Settings"
	example_button = _button(bottom, "Save as example…", _on_save_example)
	example_button.tooltip_text = "Edit this reading into an example the model learns your style from"
	export_button = _button(bottom, "Export reading…", _on_export)
	export_button.tooltip_text = "Save the deal, the reading and the dignities as a Markdown file"
	_export_dialog = FileDialog.new()
	_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_dialog.use_native_dialog = true
	_export_dialog.title = "Export the reading"
	_export_dialog.filters = PackedStringArray(["*.md ; Markdown"])
	_export_dialog.file_selected.connect(export_to)
	add_child(_export_dialog)
	card_picker = CardPickerDialog.new(db)
	card_picker.card_chosen.connect(_on_card_chosen)
	status = Label.new()
	status.theme_type_variation = ReaderTheme.MUTED_LABEL
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(status)
	# Last, so it covers the whole screen.
	add_child(card_picker)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _connect_session() -> void:
	session.step_changed.connect(func(_s: ReadingSession.Step) -> void: _update_buttons())
	session.deck_changed.connect(func(_d: Array[int]) -> void: _update_buttons())
	session.classified.connect(_on_classified)
	session.refused.connect(_on_refused)
	session.unweighed.connect(func(message: String) -> void: reading_panel.set_note(message))
	session.dealt.connect(_on_dealt)
	session.card_turned.connect(_on_card_turned)
	session.card_placed.connect(func(slot: int, card: int) -> void: table.set_slot_card(slot, card))
	session.summary_ready.connect(_on_summary_ready)
	session.reading_started.connect(func() -> void:
		if session.is_weighing():
			_show_weighing()  # a Re-read weighs the question again first
			return
		reading_panel.begin()
		table.set_studying(true))
	session.token.connect(func(piece: String) -> void:
		if table.studying:
			table.set_studying(false)
		reading_panel.append(piece))
	session.failed.connect(func(_m: String) -> void: table.set_studying(false))
	session.reading_finished.connect(func(_t: String) -> void: table.set_studying(false))
	session.thinking.connect(reading_panel.add_thinking)
	session.reading_finished.connect(func(_t: String) -> void: reading_panel.finish())
	session.critique_finished.connect(_on_critique)
	session.reading_finished.connect(func(_t: String) -> void: save_to_history())
	session.critique_finished.connect(func(_v: Dictionary) -> void: save_to_history())
	session.failed.connect(reading_panel.show_error)
	session.budget_warning.connect(func(message: String) -> void:
		reading_panel.set_meter(message, ReaderTheme.BRASS))
	session.usage_reported.connect(func(line: String) -> void: reading_panel.set_meter(line))


func _update_buttons() -> void:
	var step: ReadingSession.Step = session.step
	var asking: bool = step == ReadingSession.Step.ASK
	question_input.editable = asking
	spread_input.disabled = not asking
	shuffle_button.disabled = not asking
	cut_button.disabled = step != ReadingSession.Step.SHUFFLED or table.is_fanned()
	# Dealing waits until the question is sorted, so a question about harm deals nothing.
	var weighing: bool = session.is_weighing()
	deal_button.disabled = step != ReadingSession.Step.SHUFFLED or picking or weighing
	table.set_pile_clickable(step == ReadingSession.Step.SHUFFLED and not table.is_fanned()
			and not weighing)
	turn_all_button.disabled = step != ReadingSession.Step.DEALT or session.own_cards
	draw_input.disabled = not asking
	var own: bool = settings.draw_mode == "own" if asking else session.own_cards
	shuffle_button.text = "Lay out" if own else "Shuffle"
	shuffle_button.tooltip_text = ("Show the positions, then choose the card you laid in each (Enter)"
			if own else "Shuffle the deck for the question (Enter)")
	new_button.disabled = asking
	reread_button.disabled = not session.can_reread()
	example_button.disabled = step != ReadingSession.Step.DONE or session.reading_text == ""
	export_button.disabled = example_button.disabled
	match step:
		ReadingSession.Step.ASK:
			status.text = ""
		ReadingSession.Step.SHUFFLED:
			var wanted: int = session.spread.size()
			if picking:
				var left: int = wanted - session.picked.size()
				status.text = "Pick %d more card%s from the fan." % [left, "" if left == 1 else "s"]
			elif table.is_fanned():
				status.text = "Pick a card in the fan to cut there, or deal."
			elif weighing:
				status.text = WEIGHING
			else:
				status.text = "Shuffled. Cut, deal, or click the deck to pick your %d card%s." % [
						wanted, "" if wanted == 1 else "s"]
		ReadingSession.Step.DEALT:
			if weighing:
				status.text = WEIGHING
			elif session.own_cards:
				status.text = "Click each position and choose the card you laid there."
			else:
				status.text = "Turn the cards over, one at a time or all at once."
		ReadingSession.Step.READING:
			status.text = WEIGHING if weighing else ""
		ReadingSession.Step.DONE:
			status.text = "Ask another question with New reading." if session.refusal != "" \
					else "Click a card to see its correspondences."


func _on_shuffle() -> void:
	var own: bool = settings.draw_mode == "own"
	var problem: String = session.start(question_input.text, _spread_ids[spread_input.selected], -1, own)
	if problem != "":
		status.text = problem
		question_input.grab_focus()
		return
	question_input.release_focus()
	history_path = ""
	var deck: DeckInfo = deck_picker.selected_deck()
	# Own cards come from the querent's deck, not the one on screen.
	session.reading_deck = deck.name if deck != null and not own else ""
	if session.refusal != "":
		return  # already refused: only a client that answers at once
	if session.is_weighing():
		_show_weighing()
	if own:
		_prompt_own_cards()
		return
	table.riffle()
	reading_panel.set_status("Shuffled.")


## The question is being weighed, which also loads the model: the glow and the panel's
## timer show that the reader is at work.
func _show_weighing() -> void:
	reading_panel.begin_weighing()
	table.set_weighing(true)


## Own cards: what to do now, once the question has been weighed.
func _prompt_own_cards() -> void:
	reading_panel.set_status("" if session.is_weighing() else
			"Lay out your cards, then click each position to say which card is there.")


func _on_classified() -> void:
	table.set_weighing(false)
	if session.step == ReadingSession.Step.READING:
		# A Re-read: the question was weighed again, and now the cards are read.
		reading_panel.begin()
		table.set_studying(true)
	else:
		reading_panel.end_weighing()
		if session.step == ReadingSession.Step.DEALT and session.own_cards:
			_prompt_own_cards()
	_update_buttons()


func _on_refused(message: String) -> void:
	picking = false
	table.set_studying(false)
	table.set_weighing(false)
	if session.layout.is_empty():
		# Own cards: the empty positions go. Cards read again stay.
		table.set_spread(session.spread)
	reading_panel.show_refusal(message)


## Reads the cards on the table again, with the model now in Settings. The earlier
## reading stays in the history: this one is saved as its own.
func reread() -> void:
	if not session.can_reread():
		return
	history_path = ""
	correspondences.set_expanded(false)
	session.reread()


func _on_cut() -> void:
	table.show_fan()
	_update_buttons()


## A cut leaves the deck shuffled: deal it, or click it to pick the cards.
func _on_cut_chosen(at: int) -> void:
	session.cut(at)
	table.hide_fan()
	reading_panel.set_status(("Cut with %d cards lifted." % at if at > 0 else "Left uncut.")
			+ " Deal, or click the deck to pick your cards.")
	_update_buttons()


## The deck was clicked: fan it face down to pick the cards from.
func _on_pile_pressed() -> void:
	if session.step != ReadingSession.Step.SHUFFLED or table.is_fanned() or not session.picked.is_empty() \
			or session.is_weighing():
		return
	picking = true
	table.show_fan(session.deck.size(), true)
	reading_panel.set_status("Choose your cards from the fan, one for each position in turn.")
	_update_buttons()


func _on_fan_card_picked(at: int) -> void:
	var card: int = session.pick(at)
	if card < 0:
		return
	table.take_from_fan(at, session.picked.size() - 1, card)
	if session.step == ReadingSession.Step.DEALT:
		picking = false
		table.end_pick()
	_update_buttons()


func _on_dealt(layout: Array[Dictionary]) -> void:
	# Picked cards are already on their way to the positions (take_from_fan).
	if session.draw != "picked":
		table.deal(layout)
	reading_panel.set_status("Turn the cards to begin the reading.")


func _on_card_turned(slot: int) -> void:
	table.turn(slot)


func _on_slot_pressed(slot: int) -> void:
	if session.step == ReadingSession.Step.DEALT and session.own_cards:
		if not session.is_weighing():
			ask_card(slot)
	elif session.step == ReadingSession.Step.DEALT and not session.turned[slot]:
		session.turn(slot)
	elif session.summary != null:
		table.highlight(slot)
		correspondences.show_slot(slot)
		table.show_lightbox(slot)


## Own cards: opens the picker for `slot`, with the cards laid elsewhere greyed out.
func ask_card(slot: int) -> void:
	var used: Array[int] = []
	for i: int in session.layout.size():
		var card: int = session.layout[i]["card"]
		if i != slot and card >= 0:
			used.append(card)
	var position_data: Dictionary = session.layout[slot]["position"]
	card_picker.open(slot, Spread.title(Spread.label(position_data)), used, session.layout[slot]["card"])


func _on_card_chosen(slot: int, card: int) -> void:
	var problem: String = session.place(slot, card)
	if problem != "":
		reading_panel.set_status(problem, ReaderTheme.ILL)


func _on_summary_ready(summary: ReadingSummary) -> void:
	table.show_dignities(summary)
	correspondences.show_summary(summary)


func _on_critique(verdict: Dictionary) -> void:
	if verdict["passed"]:
		reading_panel.set_status("Checked: the reading addresses every card.", ReaderTheme.WELL)
	else:
		reading_panel.set_reading(verdict["reading"])
		reading_panel.set_status("Revised after a check: %s" % verdict["reason"], ReaderTheme.BRASS)


func _on_save_example() -> void:
	if session.summary != null and session.reading_text != "":
		example_requested.emit(ReadingExamples.draft(session.summary, session.reading_text))


## The finished reading as Markdown (see ReadingExport).
func export_markdown() -> String:
	var deck_name: String = session.reading_deck
	if deck_name == "" and not session.own_cards:
		var deck: DeckInfo = deck_picker.selected_deck()
		deck_name = deck.name if deck != null else ""
	return ReadingExport.to_markdown(session.summary, session.reading_text, {
		"date": session.finished_at,
		"deck": deck_name,
		"cards": session.draw,
		"model": session.reading_model,
	})


## Saves the finished reading (Settings -> History). The first save makes a new file;
## a retry or a critique of the same reading rewrites it.
func save_to_history() -> void:
	if not settings.keep_history or session.summary == null or session.reading_text == "":
		return
	var record: Dictionary = ReadingHistory.record_from(session, _spread_definition(session.spread))
	var written: String = ReadingHistory.save(record, history_folder, history_path)
	if written == "":
		reading_panel.set_status("Could not save the reading to the history.", ReaderTheme.ILL)
		return
	history_path = written


## A spread's definition rebuilt from the Spread on the table: a reopened reading keeps its
## own, even when the spread has changed or gone from the menu since.
static func _spread_definition(spread: Spread) -> Dictionary:
	var pairs: Array = []
	for pair: PackedStringArray in spread.adjacency:
		pairs.append(Array(pair))
	var data: Dictionary = {"name": spread.name, "positions": spread.positions.duplicate(true),
			"dignity_adjacency": pairs, "reading_words": spread.reading_words,
			"compact_labels": spread.compact_labels}
	if spread.card_height > 0.0:
		data["card_height"] = spread.card_height
	if spread.columns > 0.0:
		data["columns"] = spread.columns
	return data


## Lays a saved reading out again: its cards face up, its dignities and its text, as
## when it finished. Returns an error message, or "" when it opened.
func open_record(path: String) -> String:
	var record: Dictionary = ReadingHistory.load_record(path)
	var problem: String = "That reading could not be read."
	if not record.is_empty():
		problem = session.restore(record)
	if problem != "":
		reading_panel.set_status(problem, ReaderTheme.ILL)
		return problem
	history_path = path
	question_input.text = session.question
	table.set_spread(session.spread)
	var saved_motion: float = table.motion
	table.motion = 0.0
	table.deal(session.layout)
	for slot: int in session.layout.size():
		table.turn(slot)
	table.motion = saved_motion
	_on_summary_ready(session.summary)
	correspondences.set_expanded(false)
	reading_panel.clear()
	reading_panel.set_reading(session.reading_text)
	reading_panel.finish()
	reading_panel.set_status("A saved reading from %s." % session.finished_at)
	_update_buttons()
	return ""


## Export…, for the reading on the table.
func export_reading() -> void:
	_on_export()


func _on_export() -> void:
	if session.summary == null or session.reading_text == "":
		return
	var folder: String = settings.export_folder
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		folder = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	_export_dialog.current_dir = folder
	_export_dialog.current_file = ReadingExport.file_name(session.question,
			session.finished_at.get_slice(" ", 0))
	_export_dialog.popup_centered_ratio(0.6)


## Writes the export to `path` and remembers its folder for next time.
func export_to(path: String) -> Error:
	if not path.get_extension().to_lower() in ["md", "markdown", "txt"]:
		path += ".md"
	var error: Error = ReadingExport.save(path, export_markdown())
	if error != OK:
		reading_panel.set_status("Could not export the reading (%s)." % error_string(error), ReaderTheme.ILL)
		return error
	settings.export_folder = path.get_base_dir()
	settings.save()
	reading_panel.set_status("Exported to %s" % path, ReaderTheme.WELL)
	return OK


func _on_new_reading() -> void:
	picking = false
	session.reset()
	history_path = ""
	table.set_spread(Spread.from_db(db, _spread_ids[spread_input.selected]))
	reading_panel.clear()
	correspondences.clear()
	correspondences.set_expanded(false)
	question_input.select_all()
	question_input.grab_focus()


## Rescans the spreads folder and rebuilds the menu: the built-in spreads, then the
## added ones; an added spread with problems is listed but cannot be chosen.
## The chosen spread stays chosen while it still exists.
func refresh_spreads() -> void:
	# At start, the spread chosen last time.
	var chosen: String = settings.spread
	if spread_input.selected >= 0 and spread_input.selected < _spread_ids.size():
		chosen = _spread_ids[spread_input.selected]
	added_spreads = SpreadLibrary.scan(spreads_folder, db.builtin_spread_ids)
	db.set_added_spreads(added_spreads)
	spread_input.clear()
	_spread_ids.clear()
	for spread_id: String in db.spreads:
		_spread_ids.append(spread_id)
		spread_input.add_item(str(db.spreads[spread_id].get("name", spread_id)))
	for entry: Dictionary in added_spreads:
		var problems: PackedStringArray = entry["errors"]
		if problems.is_empty():
			var index: int = _spread_ids.find(entry["id"])
			spread_input.set_item_tooltip(index, "Added from %s" % entry["file"])
			continue
		_spread_ids.append(entry["id"])
		spread_input.add_item("%s (cannot load)" % entry["name"])
		var last: int = spread_input.item_count - 1
		spread_input.set_item_disabled(last, true)
		spread_input.set_item_tooltip(last, "%s:\n%s" % [entry["file"], "\n".join(problems)])
	var keep: int = _spread_ids.find(chosen)
	if keep < 0 or spread_input.is_item_disabled(keep):
		keep = 0
	spread_input.select(keep)
	if chosen != "" and _spread_ids[keep] != chosen:
		_on_spread_selected(keep)


## Chosen from the menu: remembered for next time. (A fallback after a spread file
## went missing is not, so the spread comes back with its file.)
func _on_spread_chosen(index: int) -> void:
	if index >= 0 and index < _spread_ids.size() and settings.spread != _spread_ids[index]:
		settings.spread = _spread_ids[index]
		settings.save()
	_on_spread_selected(index)


## Space or Enter takes the next step (shuffle, deal, turn the next card); Ctrl+Enter
## turns them all. Only while the reading screen has the keyboard: not while typing,
## in a dialog, or with a card shown large.
func _unhandled_key_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo or not is_visible_in_tree():
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if (focus != null and not is_ancestor_of(focus)) or table.lightbox_slot >= 0 or card_picker.visible:
		return
	var enter: bool = key.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if not enter and key.keycode != KEY_SPACE:
		return
	if enter and key.ctrl_pressed:
		if session.step == ReadingSession.Step.DEALT:
			session.turn_all()
			get_viewport().set_input_as_handled()
		return
	if next_step():
		get_viewport().set_input_as_handled()


## What Space / Enter does now. Returns false when there is no next step.
func next_step() -> bool:
	match session.step:
		ReadingSession.Step.ASK:
			if question_input.text.strip_edges() == "":
				question_input.grab_focus()
				return true
			_on_shuffle()
			return true
		ReadingSession.Step.SHUFFLED:
			if picking:
				return false  # the cards are yours to choose
			if table.is_fanned():
				table.hide_fan()
			session.deal()
			return true
		ReadingSession.Step.DEALT:
			var slot: int = session.turned.find(false)
			if slot >= 0 and session.own_cards:
				if not session.is_weighing():
					ask_card(slot)
				return true
			if slot >= 0:
				session.turn(slot)
				return true
	return false


func _on_spread_selected(index: int) -> void:
	if index >= 0 and index < _spread_ids.size():
		table.set_spread(Spread.from_db(db, _spread_ids[index]))


## After Settings is saved: the deck folder may have changed.
func settings_changed() -> void:
	deck_picker.refresh()
	_on_deck_changed(deck_picker.selected_deck())


func _on_deck_changed(deck: DeckInfo) -> void:
	var images: DeckImages = null if deck == null else DeckImages.new(deck, card_image_height())
	table.set_images(images)


## How tall card images are loaded: no card is drawn taller than about half the screen
## (more at a bigger interface size), so loading more would only cost memory. Images
## smaller than this load at their own size.
func card_image_height() -> int:
	var screen_height: float = float(DisplayServer.screen_get_size().y)
	return clampi(roundi(screen_height * 0.5 * settings.ui_scale), CARD_IMAGE_HEIGHT, CARD_IMAGE_MAX)
