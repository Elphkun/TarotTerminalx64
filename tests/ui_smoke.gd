extends SceneTree
## Runs whole readings through the real screen by pressing its real buttons, with a
## fake LLM, and fails on any error. Run separately from the unit tests (it needs frames):
##
##   godot --headless --script tests/ui_smoke.gd -- --readings=4
##
## --live=1 uses the real LLM from user://llm.json instead of the fake (one reading).
## Without --headless, --shots=<folder> also saves a screenshot of each step.
## Adapted from KitsuTarot's ui_smoke.gd.

const ErrorCapture := preload("res://tests/error_capture.gd")
const FakeLlmClient := preload("res://tests/fake_llm_client.gd")
const MAX_WAIT_SECONDS: float = 10.0
const LIVE_WAIT_SECONDS: float = 300.0
const SETTINGS_PATH := "user://test_smoke_settings.json"
const LLM_PATH := "user://test_smoke_llm.json"
const EXAMPLES_PATH := "user://test_smoke_examples.txt"
const HISTORY_FOLDER := "user://test_smoke_history"

var _app: App
var _fake: FakeLlmClient
var _capture: ErrorCapture = ErrorCapture.new()
var _failures: Array[String] = []
var _shots_dir: String = ""
var _readings: int = 4
var _live: bool = false
var _spread: String = ""
var _last_mouse: Vector2 = Vector2.ZERO
var _middle_down: bool = false
## --deck=<folder name>: the deck to use (default: the first one found).
var _deck: String = ""
## --ui_scale=1.5: the interface size for the readings (screenshots at other sizes).
var _ui_scale: float = 1.0


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=")
		if parts.size() == 2 and parts[0] == "readings":
			_readings = parts[1].to_int()
		elif parts.size() == 2 and parts[0] == "shots":
			_shots_dir = parts[1]
		elif parts.size() == 2 and parts[0] == "ui_scale":
			_ui_scale = parts[1].to_float()
		elif parts.size() == 2 and parts[0] == "deck":
			_deck = parts[1]
		elif parts.size() == 2 and parts[0] == "spread":
			_spread = parts[1]
		elif parts.size() == 2 and parts[0] == "live":
			_live = parts[1] == "1"
			_readings = 1
	OS.add_logger(_capture)
	_run()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))
	_fake = FakeLlmClient.new()
	_fake.frames_per_token = 1
	_app = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_app.motion = 0.0 if _shots_dir == "" else 0.3
	_app.settings_path = SETTINGS_PATH
	_app.examples_path = EXAMPLES_PATH
	_app.history_folder = HISTORY_FOLDER
	_app.window_place_path = "user://test_smoke_window.json"
	_clear_folder(HISTORY_FOLDER)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(EXAMPLES_PATH))
	if not _live:
		_app.client = _fake
		_app.llm_config_path = LLM_PATH
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LLM_PATH))
		# Settings' Test connection talks to a server running the default 4096 window.
		_app.make_test_client = func(_config: LlmConfig) -> LlmClient:
			var test_client: FakeLlmClient = FakeLlmClient.new()
			test_client.context_window = 4096
			return test_client
	root.add_child(_app)
	await _frames(3)
	await _notice()
	_app.settings.ui_scale = _ui_scale
	_app.apply_ui_scale(true)
	if _deck != "":
		_app.settings.deck = _deck
		_app.screen.settings_changed()
	await _frames(2)
	if DisplayServer.get_name() != "headless":
		# The window grows to hold the design size at the chosen interface size.
		var minimum: Vector2 = Vector2(root.min_size)
		_check(root.size.x >= minimum.x and root.size.y >= minimum.y,
				"the window grew to %s (got %s)" % [minimum, root.size])
		_check(is_equal_approx(root.content_scale_factor, App.scale_for(Vector2(root.size), _ui_scale)),
				"the scale follows the window")
		print("Window %s, minimum %s, scale %.3f" % [root.size, root.min_size, root.content_scale_factor])
	await _shot("0_ask")
	if not _live:
		await _settings()
		await _added_spreads()

	for n: int in _readings:
		await _reading(n)
		if not _capture.take_all().is_empty():
			break
	if not _live:
		await _history()
		await _own_cards()
		await _refused()
		await _designer()
		await _table_zoom()
	_clear_folder(HISTORY_FOLDER)

	for error: String in _capture.take_all():
		_failures.append("error: %s" % error)
	for failure: String in _failures:
		print("FAIL  %s" % failure)
	print("%d reading(s), %d failure(s)" % [_readings, _failures.size()])
	OS.remove_logger(_capture)
	quit(0 if _failures.is_empty() else 1)


## One reading. Odd readings cut and turn cards one by one; reading 2 fails once and
## retries; reading 3 runs the critique.
func _reading(n: int) -> void:
	var screen: ReadingScreen = _app.screen
	var session: ReadingSession = _app.session
	if not _live:
		_app.llm_config.critique = n == 3

	# Reading 1 is a Celtic Cross; --spread=<id> picks the spread for a live run.
	var spread_id: String = _spread if _spread != "" else ("celtic_cross" if n == 1 else "three_card")
	var spread_index: int = screen._spread_ids.find(spread_id)
	_check(spread_index >= 0, "the spread menu offers %s" % spread_id)
	screen.spread_input.select(spread_index)
	screen.spread_input.item_selected.emit(spread_index)
	_check(AppSettings.load_from(SETTINGS_PATH).spread == spread_id, "the chosen spread is remembered")
	var card_count: int = Spread.from_db(_app.db, spread_id).size()

	screen.question_input.text = ""
	_press(screen.shuffle_button, "shuffle with no question")
	_check(session.step == ReadingSession.Step.ASK, "an empty question does not start a reading")
	screen.question_input.text = "Smoke question %d: should I take the job?" % n
	# Reading 4 runs from the keyboard: Enter shuffles, Space deals and turns the next
	# card, Ctrl+Enter turns the rest.
	var keys: bool = n == 4
	if keys:
		screen.question_input.release_focus()
		await _key(KEY_ENTER)
	else:
		_press(screen.shuffle_button)
	_check(session.step == ReadingSession.Step.SHUFFLED, "shuffle starts the reading")
	_check(not screen.question_input.has_focus(), "the question gives up the keyboard once shuffled")
	await _frames(2)

	if keys:
		await _key(KEY_SPACE)
	elif n % 2 == 1:
		_press(screen.cut_button)
		await _frames(2)
		_check(screen.table.is_fanned(), "cut shows the fan")
		await _shot("1_cut_fan")
		var view: CardView = screen.table.fan_view(20)
		view.pressed.emit(view)
		await _frames(2)
		_check(session.step == ReadingSession.Step.SHUFFLED and not screen.table.is_fanned(),
				"a cut leaves the deck shuffled, to deal or pick from")
		# Reading 1 picks its cards from the fan; reading 3 deals after the cut.
		if n == 1:
			await _pick_cards(card_count)
		else:
			_press(screen.deal_button)
	else:
		_press(screen.deal_button)
	_check(session.step == ReadingSession.Step.DEALT, "dealt (reading %d)" % n)
	_check(screen.table.dealt_count() == card_count, "%d cards on the table" % card_count)
	await _frames(2)
	await _shot("2_dealt_%s" % spread_id)

	if n == 2 and not _live:
		_fake.fail_next = "HTTP 503: the fake server is down"
	# Reading 3 runs out of room once: the server's window fills mid-reply.
	_fake.finish_length = n == 3 and not _live
	# Reading 1 comes from a "thinking" model: the status must say so before the text arrives.
	_fake.thinking_reply = "Weighing the cards against each other before writing." if n == 1 else ""
	var thinking_status: Array[String] = []
	var watch_thinking: Callable = func(_text: String) -> void:
		if thinking_status.is_empty():
			thinking_status.append(screen.reading_panel.waiting_text())
	session.thinking.connect(watch_thinking)
	if keys:
		await _key(KEY_SPACE)
		_check(session.turned.count(true) == 1, "Space turns one card (got %d)" % session.turned.count(true))
		await _key(KEY_ENTER, true)
		_check(session.all_turned(), "Ctrl+Enter turns the rest")
	elif n % 2 == 1:
		for slot: int in card_count:
			var card: CardView = screen.table.slot_view(slot)
			card.pressed.emit(card)
			await _frames(1)
	else:
		_press(screen.turn_all_button)
		if not _live and n != 2:  # reading 2's server fails at once
			# Before the first words: the table and the panel show the reader at work.
			_check(screen.table.studying, "the cards show the reader studying them")
			_check(screen.reading_panel.waiting_text().contains("studying the spread"),
					"the empty reading says the reader is studying the spread (got %s)"
					% screen.reading_panel.waiting_text())
			_check(screen.reading_panel.status.text == "", "the status line does not repeat it")
	await _shot("3_reading")
	if _shots_dir != "":
		# A moment later, if the reader is still studying, the glow should be on the cards.
		await _frames(100)
		if screen.table.studying:
			await _shot("3b_studying")

	if n == 2 and not _live:
		await _until(func() -> bool: return screen.reading_panel.retry_button.visible)
		_check(screen.reading_panel.retry_button.visible, "an LLM error shows Retry")
		await _shot("4_error")
		_check(screen.correspondences.text_view.get_parsed_text().contains("Patterns"),
				"correspondences still show when the LLM fails")
		_press(screen.reading_panel.retry_button)
	if n == 3 and not _live:
		await _until(func() -> bool: return screen.reading_panel.retry_button.visible)
		_check(screen.reading_panel.status.text.contains("ran out of room"),
				"a full window says so (got %s)" % screen.reading_panel.status.text)
		_check(screen.example_button.disabled, "a cut-off reading cannot be saved as an example")
		await _shot("4_out_of_room")
		_fake.finish_length = false
		_press(screen.reading_panel.retry_button)

	await _until(func() -> bool: return session.step == ReadingSession.Step.DONE)
	_check(session.step == ReadingSession.Step.DONE, "the reading finishes (reading %d)" % n)
	_check(not screen.table.studying, "the studying glow stops (reading %d)" % n)
	if _live:
		_check(screen.reading_panel.reading().length() > 200, "a live reading streams into the panel")
		print("Live reading: %d characters. Status: %s Meter: %s" % [
			screen.reading_panel.reading().length(), screen.reading_panel.status.text,
			screen.reading_panel.meter.text])
	else:
		_check(screen.reading_panel.reading().contains("canned reading"),
				"the reading streams into the panel")
		_check(screen.reading_panel.meter.text.begins_with("Prompt 1,000 · reply 200 · window 12,288 tokens · ")
				and screen.reading_panel.meter.text.ends_with(" s"),
				"the usage line shows (got %s)" % screen.reading_panel.meter.text)
	session.thinking.disconnect(watch_thinking)
	if n == 1 and not _live:
		_check(not thinking_status.is_empty() and thinking_status[0].contains("thinking it over"),
				"a thinking model shows the thinking status (got %s)" % str(thinking_status))
		_check(not screen.reading_panel.reading().contains("Weighing"), "thinking is not shown as reading")
		_check(screen.reading_panel.phase() == "", "the thinking status ends with the reading")
	for slot: int in card_count:
		_check(screen.table.is_face_up(slot), "card %d is face up" % slot)
	if spread_id == "celtic_cross":
		_check(screen.table.slot_view(1).badge == "2" and screen.table.slot_view(1).mark_text != "",
				"Celtic Cross cards carry their number and dignity mark")
		_check(screen.correspondences.text_view.get_parsed_text().contains("— Hopes and fears"),
				"the correspondences name the positions")
	if _live and _shots_dir != "":
		screen.export_to(_shots_dir.path_join("reading.md"))
	if not _live and n == 1:
		_check(not screen.export_button.disabled, "a finished reading can be exported")
		var export_path: String = "user://test_smoke_export.md"
		_check(screen.export_to(export_path) == OK, "Export writes the file")
		var exported: String = FileAccess.get_file_as_string(export_path)
		_check(exported.contains("9. **Hopes and fears:** ") and exported.contains("canned reading")
				and exported.contains("**Model:** fake-model"),
				"the export holds the deal, the reading and the model")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(export_path))
	var card_zero: CardView = screen.table.slot_view(0)
	card_zero.pressed.emit(card_zero)
	await _frames(2)
	_check(screen.correspondences.is_expanded(), "clicking a card opens its correspondences")
	_check(not screen.correspondences.text_view.get_parsed_text().contains("GD "),
			"no GD rank labels in the UI")
	# The clicked card is shown large over the table; clicking it lays it down again.
	var big: CardView = screen.table.lightbox_card()
	_check(screen.table.lightbox_slot == 0 and big != null and big.index == card_zero.index,
			"clicking a card shows it large over the table")
	if big != null:
		_check(big.size.y > card_zero.size.y and big.size.y >= screen.table.size.y * 0.5,
				"the lightbox card fills the table (%s of %s, laid card %s)"
				% [big.size.y, screen.table.size.y, card_zero.size.y])
		await _shot("5b_lightbox_%d" % n)
		big.pressed.emit(big)
		await _frames(2)
	_check(screen.table.lightbox_slot == -1 and screen.table.lightbox_card() == null,
			"clicking the large card lays it down")
	_check(screen.correspondences.is_expanded(), "the correspondences stay open")
	await _shot("5_done_%d" % n)
	if n == 1 and not _live:
		await _save_example(n)

	_press(screen.new_button)
	_check(session.step == ReadingSession.Step.ASK, "new reading resets")
	_check(screen.reading_panel.reading() == "", "new reading clears the text")
	await _frames(2)


## Save as example: the draft is added as a new entry and saved as edited; at the
## limit, Save waits until one is deleted.
func _save_example(n: int) -> void:
	var screen: ReadingScreen = _app.screen
	var dialog: ExamplesDialog = _app.examples_dialog
	_press(screen.example_button)
	await _frames(2)
	_check(dialog.visible, "Save as example opens Example readings")
	_check(dialog.entries().size() == 1 and dialog.list.get_item_text(0).ends_with("(new)"),
			"the draft is a new entry")
	_check(dialog.text_input.text.begins_with("Question: Smoke question %d" % n),
			"the example starts with the question")
	_check(dialog.text_input.text.contains("canned reading"), "the example holds the reading")
	dialog.text_input.text += "\nEdited by the author."
	dialog.text_input.text_changed.emit()
	await _shot("7_example")
	_press(dialog.save_button)
	_check(not dialog.visible, "saving closes the dialog")
	var saved: PackedStringArray = ReadingExamples.entries(EXAMPLES_PATH)
	_check(saved.size() == 1 and saved[0].ends_with("Edited by the author."),
			"the edited example is saved (got %s)" % str(saved))

	ReadingExamples.save_entries(PackedStringArray(["Question: a\n\nOne.", "Question: b\n\nTwo.",
			"Question: c\n\nThree."]), EXAMPLES_PATH)
	_press(screen.example_button)
	await _frames(2)
	_check(dialog.save_button.disabled, "a fourth example cannot be saved")
	await _shot("8_example_limit")
	dialog.list.select(0)
	dialog.list.item_selected.emit(0)
	_press(dialog.delete_button)
	_check(not dialog.save_button.disabled, "deleting one allows saving")
	_press(dialog.save_button)
	saved = ReadingExamples.entries(EXAMPLES_PATH)
	_check(saved.size() == 3 and saved[0].begins_with("Question: b") and saved[2].contains("canned"),
			"the first was deleted and the new one kept (got %s)" % str(saved))


## Settings: Cancel throws edits away; Save applies them and writes both files.
func _settings() -> void:
	var panel: SettingsPanel = _app.settings_panel
	_press(_app.screen.settings_button)
	await _frames(2)
	_check(panel.visible, "Settings opens")
	await _until(func() -> bool: return panel.model_input.item_count > 1)
	_check(panel.connection_status.text.begins_with("Connected"), "Test connection lists models")
	_check(panel.connection_status.text.contains("4096-token context window")
			and panel.connection_status.text.contains("OLLAMA_CONTEXT_LENGTH=16384"),
			"Test connection flags a server window smaller than the setting (got %s)"
			% panel.connection_status.text)
	await _shot("6_settings")
	_press(panel.licenses_button)
	await _frames(2)
	var licenses: LicensesDialog = _app.licenses_dialog
	_check(licenses.visible and licenses.text_view.get_parsed_text().contains("MIT License"),
			"Licenses… shows the licenses")
	_check(licenses.get_index() > panel.get_index(), "the licenses sit above Settings")
	await _shot("6_licenses")
	_press(licenses.close_button)
	await _frames(1)
	_check(not licenses.visible and panel.visible, "Close goes back to Settings")
	panel.temperature_input.value = 0.3
	_press(panel.cancel_button)
	_check(not panel.visible, "Cancel closes Settings")
	_check(is_equal_approx(_app.llm_config.temperature, 0.8), "Cancel keeps the old temperature")

	_press(_app.screen.settings_button)
	await _until(func() -> bool: return panel.model_input.item_count > 1)
	panel.temperature_input.value = 0.4
	panel.max_tokens_input.value = 8192
	panel.context_input.value = 12288
	panel.critique_input.button_pressed = true
	panel.ui_scale_input.select(2)  # 150%
	for i: int in panel.model_input.item_count:
		if panel.model_input.get_item_text(i) == "fake-large":
			panel.model_input.select(i)
	_press(panel.save_button)
	_check(not panel.visible, "Save closes Settings")
	_check(is_equal_approx(_app.llm_config.temperature, 0.4), "Save applies the temperature")
	_check(_app.llm_config.model == "fake-large", "Save applies the model")
	_check(_app.llm_config.max_tokens == 8192, "Save applies max tokens")
	_check(_app.llm_config.context_tokens == 12288, "Save applies the context window")
	_check(is_equal_approx(_app.settings.ui_scale, 1.5), "Save applies the interface size")
	_check(is_equal_approx(root.content_scale_factor, App.scale_for(Vector2(root.size), 1.5)),
			"the interface size reaches the window (got %s)" % root.content_scale_factor)
	# Back to 100% (or --ui_scale) so the readings and their screenshots run at the design size.
	_app.settings.ui_scale = _ui_scale
	_app.apply_ui_scale()
	var saved: LlmConfig = LlmConfig.load_from(LLM_PATH)
	_check(saved.model == "fake-large" and saved.critique, "Save writes llm.json")
	_check(FileAccess.file_exists(SETTINGS_PATH), "Save writes settings.json")
	_check(_app.screen.deck_picker.selected_deck() != null, "the deck survives saving settings")

	_press(_app.screen.settings_button)
	await _frames(2)
	_check(panel.examples_count.text == "None saved", "Settings shows no examples")
	_press(panel.examples_button)
	await _frames(2)
	_check(_app.examples_dialog.visible and panel.visible, "Manage opens Example readings over Settings")
	_check(_app.examples_dialog.save_button.disabled == false and _app.examples_dialog.delete_button.disabled,
			"with no examples there is nothing to delete")
	_press(_app.examples_dialog.cancel_button)
	_press(panel.cancel_button)
	await _frames(2)


## A spread file dropped into the spreads folder shows in the menu the next time it
## opens; a broken one is listed but can't be chosen; both go when the files do.
func _added_spreads() -> void:
	var screen: ReadingScreen = _app.screen
	var folder: String = ProjectSettings.globalize_path("user://smoke_spreads")
	DirAccess.make_dir_recursive_absolute(folder)
	screen.spreads_folder = folder
	var good: Dictionary = {"pair": {"name": "Smoke pair", "positions": [
		{"id": "a", "meaning": "One", "x": 0.3, "y": 0.5}, {"id": "b", "meaning": "Two", "x": 0.7, "y": 0.5}],
		"dignity_adjacency": [["a", "b"]]}}
	var bad: Dictionary = {"wobbly": {"name": "Smoke wobbly", "positions": []}}
	for pair: Array in [["good.json", good], ["bad.json", bad]]:
		var file: FileAccess = FileAccess.open(folder.path_join(pair[0]), FileAccess.WRITE)
		file.store_string(JSON.stringify(pair[1]))
		file.close()
	var menu: OptionButton = screen.spread_input
	var built_in: int = _app.db.builtin_spread_ids.size()
	menu.show_popup()
	await _frames(2)
	menu.get_popup().hide()
	_check(menu.item_count == built_in + 2, "the menu lists the added spreads (got %d items)" % menu.item_count)
	var good_index: int = screen._spread_ids.find("pair")
	var bad_index: int = screen._spread_ids.find("wobbly")
	_check(good_index >= 0 and not menu.is_item_disabled(good_index), "the good spread can be chosen")
	_check(bad_index >= 0 and menu.is_item_disabled(bad_index) and menu.get_item_text(bad_index).contains("cannot load"),
			"the broken spread is listed but disabled")
	_check(menu.get_item_tooltip(bad_index).contains("positions"), "the broken spread says why")
	menu.select(good_index)
	menu.item_selected.emit(good_index)
	await _frames(2)
	_check(screen.table._spread != null and screen.table._spread.id == "pair", "the table shows the added spread")
	for file_name: String in ["good.json", "bad.json"]:
		DirAccess.remove_absolute(folder.path_join(file_name))
	DirAccess.remove_absolute(folder)
	screen.refresh_spreads()
	await _frames(1)
	_check(menu.item_count == built_in, "the added spreads go with their files")
	_check(screen.table._spread.id == screen._spread_ids[menu.selected], "the table follows the menu back")


## Every finished reading was saved; History… reopens one on the table, face up with
## its text, and deletes one after asking.
func _history() -> void:
	var screen: ReadingScreen = _app.screen
	var dialog: HistoryDialog = _app.history_dialog
	_press(screen.history_button)
	await _frames(2)
	_check(dialog.visible, "History opens")
	var saved: int = dialog.entries().size()
	_check(saved == _readings, "every finished reading is in the history (%d of %d)" % [saved, _readings])
	if saved == 0:
		return
	await _shot("7_history")
	var record: Dictionary = ReadingHistory.load_record(dialog.entries()[0]["path"])
	var cards: int = (record.get("layout", []) as Array).size()
	_check(str(record.get("deck", "")) != "" or screen.deck_picker.selected_deck() == null,
			"the record names the deck")
	_press(dialog.open_button)
	await _frames(3)
	_check(not dialog.visible, "Open closes the history")
	_check(_app.session.step == ReadingSession.Step.DONE, "the reopened reading is finished")
	_check(screen.table.dealt_count() == cards, "its %d cards are on the table" % cards)
	var face_up: bool = true
	for slot: int in cards:
		face_up = face_up and screen.table.is_face_up(slot)
	_check(face_up, "all of them face up")
	_check(screen.reading_panel.reading() == str(record["reading"]), "its reading is shown")
	_check(screen.question_input.text == str(record["question"]), "its question is shown")
	_check(not screen.export_button.disabled, "it can be exported again")
	await _shot("8_reopened")
	_press(screen.history_button)
	await _frames(2)
	_press(dialog.delete_button)
	_check(dialog.entries().size() == saved, "Delete asks first")
	_press(dialog.delete_button)
	_check(dialog.entries().size() == saved - 1, "a second press deletes")
	_press(dialog.close_button)
	_press(screen.new_button)
	await _frames(2)


## A reading with the querent's own cards: empty positions, the picker for each (by
## click, by code, by Space), a card that is laid already refused, then the reading.
func _own_cards() -> void:
	var screen: ReadingScreen = _app.screen
	var session: ReadingSession = _app.session
	var picker: CardPickerDialog = screen.card_picker
	var spread_index: int = screen._spread_ids.find("three_card")
	screen.spread_input.select(spread_index)
	screen.spread_input.item_selected.emit(spread_index)
	screen.draw_input.select(1)
	screen.draw_input.item_selected.emit(1)
	_check(_app.settings.draw_mode == "own", "My own cards is remembered")
	_check(screen.shuffle_button.text == "Lay out", "the button says Lay out")
	screen.question_input.text = "Smoke question: my own cards?"
	_press(screen.shuffle_button)
	await _frames(2)
	_check(session.step == ReadingSession.Step.DEALT and session.own_cards, "the positions wait for the cards")
	_check(screen.table.dealt_count() == 3 and screen.table.slot_view(0).empty, "three empty positions")
	_check(screen.turn_all_button.disabled, "nothing to turn")
	await _shot("9_own_empty")

	var first: CardView = screen.table.slot_view(0)
	first.pressed.emit(first)
	await _frames(2)
	_check(picker.visible, "clicking a position asks for its card")
	await _shot("9b_own_picker")
	picker.set_filter("7w")
	picker.choose()
	await _frames(2)
	_check(not picker.visible and session.layout[0]["card"] == 28, "7w puts the Seven of Wands in position 1")
	_check(not screen.table.slot_view(0).empty, "and the position shows it")

	await _key(KEY_SPACE)
	_check(picker.visible, "Space asks for the next empty position")
	picker.set_filter("7w")
	picker.choose()
	_check(picker.visible, "a card laid already can't be chosen again")
	picker.set_filter("tower")
	picker.choose()
	await _frames(2)
	_check(session.layout[1]["card"] == 16, "the Tower in position 2")

	var last: CardView = screen.table.slot_view(2)
	last.pressed.emit(last)
	await _frames(1)
	picker.set_filter("ace cups")
	picker.choose()
	await _until(func() -> bool: return session.step == ReadingSession.Step.DONE)
	_check(screen.reading_panel.reading() != "", "the reading comes")
	_check(screen.export_markdown().contains("**Cards:** your own"), "the export says the cards were your own")
	_check(not screen.export_markdown().contains("**Deck:**"), "and names no app deck")
	var saved: Dictionary = ReadingHistory.load_record(screen.history_path)
	_check(saved.get("draw") == "own", "the history notes your own cards")
	await _shot("9c_own_done")
	_press(screen.new_button)
	screen.draw_input.select(0)
	screen.draw_input.item_selected.emit(0)
	await _frames(2)


## First run (the smoke test starts from no settings): the notice covers the app until
## it is agreed to, and agreeing is remembered.
func _notice() -> void:
	var notice: NoticeDialog = _app.notice
	_check(notice != null and notice.visible, "the first run shows the notice")
	if notice == null:
		return
	_check(notice.get_index() == _app.get_child_count() - 1, "the notice is above everything")
	await _shot("0_notice")
	_press(notice.agree_button)
	await _frames(2)
	_check(_app.notice == null and not is_instance_valid(notice), "I agree closes the notice")
	_check(AppSettings.load_from(SETTINGS_PATH).notice_accepted == NoticeDialog.VERSION,
			"agreeing is saved")
	_app.show_notice_if_needed()
	_check(_app.notice == null, "an agreed notice is not shown again")


## A question about doing harm: Deal waits while the question is weighed, then the
## reader refuses and no card is dealt.
func _refused() -> void:
	var screen: ReadingScreen = _app.screen
	var session: ReadingSession = _app.session
	var normal_reply: String = _fake.classify_reply
	_fake.classify_reply = "{\"life_area\": \"relationships\", \"question_type\": \"yes_no\", \"harm\": true}"
	_fake.hold_classify = true
	screen.question_input.text = "Should I kill my best friend?"
	_press(screen.shuffle_button)
	await _frames(2)
	_check(screen.deal_button.disabled, "Deal waits while the question is weighed")
	_check(screen.status.text.begins_with("The reader is weighing"),
			"the status says the question is being weighed (got %s)" % screen.status.text)
	_fake.release_classify()
	await _frames(2)
	_check(session.refusal != "" and session.layout.is_empty(), "a question about harm deals no cards")
	_check(screen.deal_button.disabled and not screen.new_button.disabled,
			"after a refusal only New reading is left")
	_check(screen.reading_panel.text_view.get_parsed_text().contains("won't lay out the cards"),
			"the panel says why (got %s)" % screen.reading_panel.text_view.get_parsed_text())
	await _shot("refused")
	_fake.classify_reply = normal_reply
	_press(screen.new_button)
	await _frames(2)
	_check(session.step == ReadingSession.Step.ASK and session.refusal == "", "New reading starts over")


## Settings -> Design... opens the spread designer; cards are added, moved, turned and
## joined with the mouse, the fields filled in, and the saved spread read with.
func _designer() -> void:
	var screen: ReadingScreen = _app.screen
	_press(_app.settings_panel.designer_button)
	await _frames(3)
	var window: SpreadDesignerWindow = _app.designer_window
	_check(window != null and window.visible, "Design... opens the spread designer")
	if window == null:
		return
	var designer: SpreadDesigner = window.designer
	var canvas: SpreadCanvas = designer.canvas
	_check(designer.save_button.disabled, "an empty spread can't be saved")
	_check(designer.card_height_input.shown_text() == "Auto (%s)" % TableView.CARD_HEIGHT,
			"an unset card height reads Auto (got \"%s\")" % designer.card_height_input.shown_text())
	designer.card_height_input.value = 0.3
	await _frames(1)
	_check(designer.card_height_input.shown_text() == "0.3",
			"a set card height shows its number (got \"%s\")" % designer.card_height_input.shown_text())
	var size: Vector2 = canvas.table_size
	for at: Vector2 in [Vector2(0.1, 0.5), Vector2(0.42, 0.5), Vector2(0.78, 0.5)]:
		await _canvas_click(canvas, TableView.slot_centre_for(at, size), true)
	_check(designer.draft.size() == 3, "double-clicks add three cards (got %d)" % designer.draft.size())
	await _frames(1)
	_check(designer.columns_input.shown_text() == "Auto (4.5)",
			"Columns' Auto follows the cards (got \"%s\")" % designer.columns_input.shown_text())
	# Drag the middle card up a little; Ctrl+drag the last one round to 45 degrees.
	var middle: Vector2 = canvas.centre(1)
	await _canvas_drag(canvas, middle, middle + Vector2(0, -40))
	_check(float(designer.draft.position(1)["y"]) < 0.5, "a drag moves the card")
	var last: Vector2 = canvas.centre(2)
	await _canvas_drag(canvas, last + Vector2(0, -40), last + Vector2(28, -28), true)
	_check(designer.draft.rotation_of(2) == 45.0, "Ctrl+drag turns a card by an eighth (got %s)" % designer.draft.rotation_of(2))
	# Line 1-2 from a node of the selected card; line 2-3 from the glowing ring just
	# outside card 2's edge, with nothing selected.
	await _canvas_click(canvas, canvas.centre(0))
	await _canvas_drag(canvas, canvas.nodes(0)[3], canvas.centre(1))
	canvas.select(-1)
	var ring_point: Vector2 = canvas.centre(1) + Vector2(
			canvas.card_height() * canvas.aspect() / 2.0 + 8.0 / canvas._scale(), canvas.card_height() * 0.3)
	_canvas_event(canvas, ring_point, null, false, false)
	await _frames(1)
	_check(canvas._ring_hovered == 1 and canvas.mouse_default_cursor_shape == Control.CURSOR_CROSS,
			"the ring glows and shows a crosshair under the mouse")
	await _shot("9_designer_ring", window)
	await _canvas_drag(canvas, ring_point, canvas.centre(2))
	_check(designer.draft.pairs() == [["p1", "p2"], ["p2", "p3"]], "node and ring drags draw the dignity lines: %s" % [designer.draft.pairs()])
	await _shot("9_designer", window)
	# The narrow table: every card shrinks to the table's card height (a CardView once
	# stayed at its old, larger minimum size).
	designer.table_input.select(1)
	designer.table_input.item_selected.emit(1)
	await _frames(1)
	_check(is_equal_approx(canvas._cards[0].size.y, roundf(canvas.card_height())),
			"cards shrink with the narrow table (%s, want %s)" % [canvas._cards[0].size.y, roundf(canvas.card_height())])
	var layout: PackedStringArray = SpreadLayout.problems(designer.draft.spread(), canvas.aspect())
	_check(layout.is_empty(), "the spread fits the narrow table too: %s" % "; ".join(layout))
	designer.table_input.select(0)
	designer.table_input.item_selected.emit(0)
	designer.id_input.text = "smoke_designed"
	designer.id_input.text_changed.emit("smoke_designed")
	designer.name_input.text = "Smoke designed"
	designer.name_input.text_changed.emit("Smoke designed")
	var names: PackedStringArray = ["root", "stem", "flower"]
	for i: int in 3:
		canvas.select(i)
		designer.position_name_input.text = names[i]
		designer.position_name_input.text_changed.emit(names[i])
		designer.meaning_input.text = "The %s of the matter" % names[i]
		designer.meaning_input.text_changed.emit()
	_check(designer.problems().is_empty(), "the designed spread has no problems: %s" % "; ".join(designer.problems()))
	_press(designer.save_button)
	await _frames(2)
	var saved: String = ProjectSettings.globalize_path(screen.spreads_folder).path_join("smoke_designed.json")
	_check(FileAccess.file_exists(saved), "Save writes smoke_designed.json")
	_check(screen._spread_ids.has("smoke_designed"), "the saved spread is in the spread menu")
	window.close()
	await _frames(2)
	_check(not window.visible, "the designer closes")
	_spread = "smoke_designed"
	await _reading(6)
	_spread = ""
	var spread: Spread = Spread.from_db(_app.db, "smoke_designed")
	_check(spread != null and spread.neighbours("p2").size() == 2, "the middle card has both drawn neighbours")
	var summary: ReadingSummary = _app.session.summary
	if summary != null and summary.positions.size() == 3:
		var withs: PackedStringArray = []
		for relation: Dictionary in summary.positions[1]["dignity"]["relations"]:
			withs.append(relation["with"])
		_check(withs.size() == 0 or (withs.has("p1") or withs.has("p3")),
				"the reading's dignities follow the drawn lines: %s" % [withs])
	DirAccess.remove_absolute(saved)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(screen.spreads_folder))
	screen.refresh_spreads()


## The wheel zooms the reading table about the mouse and the middle button pans it,
## through real input events; a card under the mouse doesn't stop it.
func _table_zoom() -> void:
	var table: TableView = _app.screen.table
	var at: Vector2 = table.get_global_rect().get_center() * root.content_scale_factor
	await _mouse(at)
	await _mouse(at, MOUSE_BUTTON_WHEEL_UP)
	await _mouse(at, MOUSE_BUTTON_WHEEL_UP)
	_check(table.zoom > 1.2, "the wheel zooms the table (zoom %s)" % table.zoom)
	var before: Vector2 = table._content.position
	await _mouse(at, MOUSE_BUTTON_MIDDLE, true)
	await _mouse(at + Vector2(40, 0))
	await _mouse(at + Vector2(40, 0), MOUSE_BUTTON_MIDDLE, false)
	_check(table._content.position.x > before.x, "a middle-drag pans the table")
	await _shot("11_zoomed")
	table.reset_view()


## A mouse event pushed through the window: a move to `at`, or a button there.
func _mouse(at: Vector2, button: MouseButton = MOUSE_BUTTON_NONE, pressed: Variant = null) -> void:
	if button == MOUSE_BUTTON_NONE:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.position = at
		motion.global_position = at
		motion.relative = at - _last_mouse
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or _middle_down:
			motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		_last_mouse = at
		root.push_input(motion)
	else:
		for down: bool in ([true, false] if pressed == null else [pressed]):
			var event: InputEventMouseButton = InputEventMouseButton.new()
			event.button_index = button
			event.pressed = down
			event.position = at
			event.global_position = at
			if button == MOUSE_BUTTON_MIDDLE:
				_middle_down = down
			root.push_input(event)
	await _frames(1)


func _canvas_event(canvas: SpreadCanvas, at: Vector2, pressed: Variant, double: bool = false,
		ctrl: bool = false) -> void:
	var event: InputEvent
	if pressed == null:
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		event = motion
	else:
		var button: InputEventMouseButton = InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.double_click = double
		event = button
	(event as InputEventMouse).position = canvas.to_canvas(at)
	(event as InputEventWithModifiers).ctrl_pressed = ctrl
	canvas._gui_input(event)


func _canvas_click(canvas: SpreadCanvas, at: Vector2, double: bool = false) -> void:
	_canvas_event(canvas, at, true, double)
	_canvas_event(canvas, at, false)
	await _frames(1)


func _canvas_drag(canvas: SpreadCanvas, from: Vector2, to: Vector2, ctrl: bool = false) -> void:
	_canvas_event(canvas, from, true, false, ctrl)
	for step: int in range(1, 6):
		_canvas_event(canvas, from.lerp(to, step / 5.0), null, false, ctrl)
	_canvas_event(canvas, to, false, false, ctrl)
	await _frames(1)


func _clear_folder(folder: String) -> void:
	var path: String = ProjectSettings.globalize_path(folder)
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


## Clicks the deck, then picks `count` cards from the fan out of order, and checks that
## exactly those cards, in that order, lie face down in the positions.
func _pick_cards(count: int) -> void:
	var screen: ReadingScreen = _app.screen
	var session: ReadingSession = _app.session
	var top: CardView = screen.table.pile_top()
	_check(top != null and top.clickable, "the deck can be clicked once shuffled")
	top.pressed.emit(top)
	await _frames(2)
	_check(screen.picking and screen.table.is_fanned(), "clicking the deck fans it for picking")
	await _frames(int(30 * _app.motion) + 2)  # the fan spreads out
	var places: Array[int] = []
	for i: int in count:
		places.append((40 + i * 31) % CardIndex.DECK_SIZE)  # out of order, all different
	var expected: Array[int] = []
	for place: int in places:
		expected.append(session.deck[place])
	for i: int in places.size():
		var fan_card: CardView = screen.table.fan_view(places[i])
		fan_card.pressed.emit(fan_card)
		await _frames(1)
		if i == 0:
			_check(screen.cut_button.disabled and screen.deal_button.disabled, "no cut or deal once picking")
			fan_card.pressed.emit(fan_card)
			_check(session.picked.size() == 1, "a card can't be picked twice")
		if i == 1:
			await _shot("1b_pick_fan")
		if i < places.size() - 1:
			var still: CardView = screen.table.fan_view(places[places.size() - 1])
			var taken: CardView = screen.table.slot_view(i)
			_check(still.get_index() > taken.get_index(), "a picked card goes under the fan")
			_check(still.position.y + still.size.y > screen.table.size.y,
					"the fan peeks up from the bottom edge of the table")
	_check(not screen.picking and not screen.table.is_fanned(), "the fan closes after the last pick")
	var laid: Array[int] = []
	for entry: Dictionary in session.layout:
		laid.append(entry["card"])
	_check(laid == expected, "the picked cards lie in the positions in the order picked")
	# By time, not frames: saving screenshots makes frames uneven.
	await create_timer(TableView.DEAL_TIME * _app.motion + 0.3).timeout
	await _frames(2)
	var settled: bool = true
	for slot: int in count:
		var view: CardView = screen.table.slot_view(slot)
		settled = settled and view.position.distance_to(screen.table._slot_position(slot)) < 1.0 \
				and is_equal_approx(view.rotation_degrees, screen.table._slot_rotation(slot)) and not view.face_up
		if view.position.distance_to(screen.table._slot_position(slot)) >= 1.0:
			print("OFF slot %d at %s, want %s" % [slot, view.position, screen.table._slot_position(slot)])
	_check(settled, "each picked card comes to rest face down at its position")
	_check(session.draw == "picked", "the reading knows its cards were picked")


## A key press and release, as if typed.
func _key(keycode: Key, ctrl: bool = false) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.ctrl_pressed = ctrl
		event.pressed = pressed
		root.push_input(event)
	await _frames(2)


func _press(button: Button, why: String = "") -> void:
	if button.disabled:
		if why == "":
			_failures.append("%s is disabled" % button.text)
		return
	button.pressed.emit()


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)


func _frames(count: int) -> void:
	for i: int in count:
		await process_frame


func _until(condition: Callable) -> void:
	var deadline: int = Time.get_ticks_msec() + int(
			1000 * (LIVE_WAIT_SECONDS if _live else MAX_WAIT_SECONDS))
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return
		await process_frame


func _shot(shot_name: String, window: Viewport = null) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	await _frames(int(30 * _app.motion) + 2)
	await RenderingServer.frame_post_draw
	var path: String = _shots_dir.path_join(shot_name + ".png")
	if not FileAccess.file_exists(path):
		var source: Viewport = window if window != null and not (window as Window).is_embedded() else root
		source.get_texture().get_image().save_png(path)
