class_name SettingsPanel
extends Control
## The settings dialog: the reader's LLM connection and the deck folder. Edits happen
## on the controls and only reach LlmConfig and AppSettings (and their files) on Save.

signal saved()
## "Manage…" next to the example readings.
signal examples_requested()
## "Design…" next to Spreads: open the spread designer.
signal designer_requested()
## Licenses… was pressed: App opens the LicensesDialog.
signal licenses_requested()

const FIRST_LISTED := "First model the server lists"
## LlmConfig.BACKENDS, as the dropdown shows them.
const BACKEND_NAMES: PackedStringArray = ["Automatic", "Ollama (native API)", "OpenAI-compatible"]
## The same credits as README.md's Sources.
const SOURCES := "Sources: Golden Dawn attributions, court cards and invisible paths after " \
		+ "David Allen Hulse, The Key of It All, Book Two: The Western Mysteries (Llewellyn, 2nd ed., 2000)." \
		+ "Elemental dignities after the Golden Dawn's Book T. Celtic Cross after A. E. Waite, " \
		+ "The Pictorial Key to the Tarot (1911). Card meanings: Waite's and the Golden Dawn's, " \
		+ "and your own from local/meanings.json."

var llm_config: LlmConfig
var llm_config_path: String
var settings: AppSettings
## Builds a client for an unsaved config, for Test connection: (LlmConfig) -> LlmClient.
var make_client: Callable
## Only read here, for the count; the Example readings dialog edits them.
var examples_path: String = ReadingExamples.default_path()

var endpoint_input: LineEdit
var model_input: OptionButton
var api_key_input: LineEdit
var temperature_input: HSlider
var temperature_label: Label
var max_tokens_input: SpinBox
var context_input: SpinBox
var timeout_input: SpinBox
var critique_input: CheckBox
var backend_input: OptionButton
var thinking_input: CheckBox
var history_input: CheckBox
var deck_folder_input: LineEdit
var ui_scale_input: OptionButton
var examples_count: Label
var examples_button: Button
var designer_button: Button
var licenses_button: Button
var test_button: Button
var connection_status: Label
var save_button: Button
var cancel_button: Button

var _folder_dialog: FileDialog
var _testing: bool = false
var _scroll: ScrollContainer
var _body: VBoxContainer
## Space kept clear above and below the dialog.
const SCREEN_MARGIN: float = 24.0
var _dialog: PanelContainer


func _init(config: LlmConfig, config_path: String, app_settings: AppSettings,
		client_factory: Callable) -> void:
	llm_config = config
	llm_config_path = config_path
	settings = app_settings
	make_client = client_factory
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	_build()
	resized.connect(fit_height)


## Shows the dialog with the saved values, and asks the server for its models.
func open() -> void:
	endpoint_input.text = llm_config.endpoint
	api_key_input.text = llm_config.api_key
	temperature_input.value = llm_config.temperature
	max_tokens_input.value = llm_config.max_tokens
	context_input.value = llm_config.context_tokens
	timeout_input.value = llm_config.timeout_s
	critique_input.button_pressed = llm_config.critique
	backend_input.select(maxi(0, LlmConfig.BACKENDS.find(llm_config.backend)))
	history_input.button_pressed = settings.keep_history
	thinking_input.button_pressed = llm_config.thinking
	deck_folder_input.text = settings.deck_folder
	var scale_index: int = AppSettings.UI_SCALES.find(settings.ui_scale)
	ui_scale_input.select(scale_index if scale_index >= 0 else 0)
	_fill_models(PackedStringArray(), llm_config.model)
	connection_status.text = ""
	show_examples_count()
	visible = true
	fit_height.call_deferred()
	endpoint_input.grab_focus()
	test_connection()


func show_examples_count() -> void:
	var count: int = ReadingExamples.count(examples_path)
	if count == 0:
		examples_count.text = "None saved"
	else:
		examples_count.text = "%d of %d saved, sent with every reading" % [count, ReadingExamples.LIMIT]


func close() -> void:
	visible = false


## The values on screen, as LlmConfig fields.
func llm_values() -> Dictionary:
	return {
		"endpoint": endpoint_input.text.strip_edges().trim_suffix("/"),
		"model": _selected_model(),
		"api_key": api_key_input.text.strip_edges(),
		"temperature": temperature_input.value,
		"max_tokens": int(max_tokens_input.value),
		"context_tokens": int(context_input.value),
		"timeout_s": timeout_input.value,
		"critique": critique_input.button_pressed,
		"backend": LlmConfig.BACKENDS[maxi(0, backend_input.selected)],
		"thinking": thinking_input.button_pressed,
	}


func save() -> void:
	llm_config.apply(llm_values())
	var llm_error: Error = llm_config.save(llm_config_path)
	settings.deck_folder = deck_folder_input.text.strip_edges()
	settings.ui_scale = AppSettings.UI_SCALES[maxi(0, ui_scale_input.selected)]
	settings.keep_history = history_input.button_pressed
	var settings_error: Error = settings.save()
	if llm_error != OK or settings_error != OK:
		connection_status.text = "Could not save settings (%s)." % error_string(
				llm_error if llm_error != OK else settings_error)
		connection_status.add_theme_color_override("font_color", ReaderTheme.ILL)
		return
	close()
	saved.emit()


## Lists the server's models with the endpoint and key on screen (saved or not).
func test_connection() -> void:
	if _testing or make_client.is_null():
		return
	_testing = true
	test_button.disabled = true
	_set_connection_status("Connecting to %s…" % endpoint_input.text, ReaderTheme.MUTED)
	var candidate: LlmConfig = LlmConfig.new()
	candidate.apply(llm_config.to_dict())
	candidate.apply(llm_values())
	var client: LlmClient = make_client.call(candidate)
	add_child(client)
	@warning_ignore("redundant_await")
	var models: PackedStringArray = await client.list_chat_models()
	var problem: String = client.last_error
	@warning_ignore("redundant_await")
	var backend: String = await client.backend_name() if problem == "" else ""
	var sets_window: bool = client.sets_context_window()
	var model: String = _selected_model()
	if model == "" and not models.is_empty():
		model = models[0]
	var loaded: int = -1
	if problem == "" and model != "":
		@warning_ignore("redundant_await")
		loaded = await client.loaded_context(model)
	client.queue_free()
	_testing = false
	test_button.disabled = false
	if not is_inside_tree():
		return
	if problem != "":
		_set_connection_status("Could not list models: %s" % problem, ReaderTheme.ILL)
		return
	_fill_models(models, _selected_model())
	var text: String = "Connected%s: %d chat model(s)." % [
			" (%s)" % backend if backend != "" else "", models.size()]
	var color: Color = ReaderTheme.WELL
	var wanted: int = int(context_input.value)
	if sets_window:
		text += " The app sets the context window: %d tokens." % wanted
	elif loaded > 0:
		text += " %s is loaded with a %d-token context window." % [model, loaded]
		if loaded < wanted:
			text += (" That is smaller than your setting of %d: set OLLAMA_CONTEXT_LENGTH=%d on "
					+ "the server and restart Ollama, or lower Context window here.") % [wanted, wanted]
			color = ReaderTheme.BRASS
	_set_connection_status(text, color)


func _set_connection_status(text: String, color: Color) -> void:
	connection_status.text = text
	connection_status.add_theme_color_override("font_color", color)
	fit_height.call_deferred()


func _fill_models(models: PackedStringArray, keep: String) -> void:
	model_input.clear()
	model_input.add_item(FIRST_LISTED)
	model_input.set_item_metadata(0, "")
	var names: PackedStringArray = models.duplicate()
	if keep != "" and not names.has(keep):
		names.insert(0, keep)
	for model_name: String in names:
		model_input.add_item(model_name)
		model_input.set_item_metadata(model_input.item_count - 1, model_name)
		if model_name == keep:
			model_input.select(model_input.item_count - 1)
	if keep == "":
		model_input.select(0)


func _selected_model() -> String:
	if model_input.selected < 0:
		return ""
	return str(model_input.get_item_metadata(model_input.selected))


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
	dialog.custom_minimum_size = Vector2(620, 0)
	centre.add_child(dialog)
	_dialog = dialog
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	dialog.add_child(column)

	var title: Label = Label.new()
	title.text = "Settings"
	title.theme_type_variation = ReaderTheme.TITLE
	column.add_child(title)
	# The settings scroll between the title and the buttons when the window is short.
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_body)

	_body.add_child(_heading("The reader"))
	var grid: GridContainer = _grid(_body)
	endpoint_input = LineEdit.new()
	endpoint_input.placeholder_text = "http://localhost:11434/v1"
	var endpoint_row: HBoxContainer = HBoxContainer.new()
	endpoint_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	endpoint_row.add_child(endpoint_input)
	test_button = Button.new()
	test_button.text = "Test"
	test_button.tooltip_text = "Connect and list the server's models"
	test_button.pressed.connect(test_connection)
	endpoint_row.add_child(test_button)
	_row(grid, "Server", endpoint_row,
			"Any OpenAI-compatible API, up to and including /v1 (Ollama, LM Studio, llama.cpp).")
	backend_input = OptionButton.new()
	for backend_name: String in BACKEND_NAMES:
		backend_input.add_item(backend_name)
	_row(grid, "API", backend_input,
			"Automatic uses Ollama's own API when the server is Ollama, so the app can set the "
			+ "context window, and the OpenAI-style API otherwise.")
	model_input = OptionButton.new()
	model_input.fit_to_longest_item = false
	_row(grid, "Model", model_input)
	api_key_input = LineEdit.new()
	api_key_input.secret = true
	api_key_input.placeholder_text = "Not needed for a local server"
	_row(grid, "API key", api_key_input)
	var temperature_row: HBoxContainer = HBoxContainer.new()
	temperature_input = HSlider.new()
	temperature_input.min_value = 0.0
	temperature_input.max_value = 1.5
	temperature_input.step = 0.05
	temperature_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	temperature_input.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	temperature_row.add_child(temperature_input)
	temperature_label = Label.new()
	temperature_label.custom_minimum_size.x = 44
	temperature_row.add_child(temperature_label)
	temperature_input.value_changed.connect(func(value: float) -> void:
		temperature_label.text = "%.2f" % value)
	_row(grid, "Temperature", temperature_row, "Lower is steadier, higher is freer.")
	max_tokens_input = _spin(256, 32768, 256)
	_row(grid, "Max tokens", max_tokens_input,
			"The longest reply allowed. Thinking models spend part of this on reasoning before they write.")
	context_input = _spin(2048, 131072, 1024)
	_row(grid, "Context window", context_input,
			"Prompt, examples, thinking and reply must all fit in this. With Ollama's own API "
			+ "the app asks for it (changing it reloads the model once). Over the OpenAI-style "
			+ "API it can't: set OLLAMA_CONTEXT_LENGTH on the server instead. Test shows what is used.")
	timeout_input = _spin(30, 1800, 30)
	timeout_input.suffix = "s"
	_row(grid, "Timeout", timeout_input, "Give up when the server is silent this long.")
	critique_input = CheckBox.new()
	critique_input.text = "Check each reading and revise it if needed"
	_row(grid, "Critique", critique_input,
			"A second pass that checks the question was answered and no ill-dignified card was skipped.")
	thinking_input = CheckBox.new()
	thinking_input.text = "Let the model think before it writes"
	_row(grid, "Thinking", thinking_input,
			"Slower to start, often more careful. Only for models that can think.")
	var examples_row: HBoxContainer = HBoxContainer.new()
	examples_count = Label.new()
	examples_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	examples_row.add_child(examples_count)
	examples_button = Button.new()
	examples_button.text = "Manage…"
	examples_button.pressed.connect(func() -> void: examples_requested.emit())
	examples_row.add_child(examples_button)
	_row(grid, "Examples", examples_row,
			"Your edited readings, sent to the model as style examples. Saved as soon as you save them there.")
	connection_status = Label.new()
	connection_status.theme_type_variation = ReaderTheme.MUTED_LABEL
	connection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(connection_status)

	_body.add_child(_heading("Decks and display"))
	var deck_grid: GridContainer = _grid(_body)
	ui_scale_input = OptionButton.new()
	for size_option: float in AppSettings.UI_SCALES:
		ui_scale_input.add_item("%d%%" % roundi(size_option * 100))
	_row(deck_grid, "Interface size", ui_scale_input,
			"Text and controls at this size. A bigger window gives the table more room; "
			+ "the window cannot be made smaller than 1280×720 at this size.")
	var folder_row: HBoxContainer = HBoxContainer.new()
	deck_folder_input = LineEdit.new()
	deck_folder_input.placeholder_text = DeckLibrary.default_folder()
	deck_folder_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folder_row.add_child(deck_folder_input)
	var browse: Button = Button.new()
	browse.text = "Browse…"
	browse.pressed.connect(_browse_folder)
	folder_row.add_child(browse)
	var default_button: Button = Button.new()
	default_button.text = "Default"
	default_button.tooltip_text = "Use the project's decks/ folder"
	default_button.pressed.connect(func() -> void: deck_folder_input.text = "")
	folder_row.add_child(default_button)
	_row(deck_grid, "Deck folder", folder_row,
			"Each deck is a subfolder of card images with an optional deck.json.")
	history_input = CheckBox.new()
	history_input.text = "Keep every finished reading"
	_row(deck_grid, "History", history_input,
			"Saved in your user folder; History… opens, exports or deletes them.")
	var spreads_row: HBoxContainer = HBoxContainer.new()
	var spreads_note: Label = Label.new()
	spreads_note.text = "Lay out your own spreads"
	spreads_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spreads_row.add_child(spreads_note)
	designer_button = Button.new()
	designer_button.text = "Design…"
	designer_button.pressed.connect(func() -> void: designer_requested.emit())
	spreads_row.add_child(designer_button)
	_row(deck_grid, "Spreads", spreads_row,
			"Opens the spread designer in its own window. Spreads it saves join the spread menu.")

	var sources: Label = Label.new()
	sources.text = SOURCES
	sources.theme_type_variation = ReaderTheme.MUTED_LABEL
	sources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sources.add_theme_font_size_override("font_size", 13)
	_body.add_child(sources)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	licenses_button = Button.new()
	licenses_button.text = "Licenses…"
	licenses_button.tooltip_text = "TarotTerminal's license, and the Godot Engine's"
	licenses_button.pressed.connect(func() -> void: licenses_requested.emit())
	buttons.add_child(licenses_button)
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(close)
	buttons.add_child(cancel_button)
	save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(save)
	buttons.add_child(save_button)

	_folder_dialog = FileDialog.new()
	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.use_native_dialog = true
	_folder_dialog.title = "Choose the deck folder"
	_folder_dialog.dir_selected.connect(func(dir: String) -> void: deck_folder_input.text = dir)
	add_child(_folder_dialog)


## The scroll area as tall as the settings, or as the window allows.
func fit_height() -> void:
	if _scroll == null:
		return
	var wanted: float = _body.get_combined_minimum_size().y
	# The title, buttons and margins: the dialog's height without the scroll area.
	var frame: float = _dialog.get_combined_minimum_size().y - _scroll.custom_minimum_size.y
	_scroll.custom_minimum_size.y = maxf(120.0, minf(wanted, size.y - frame - 2.0 * SCREEN_MARGIN))


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _browse_folder() -> void:
	var current: String = deck_folder_input.text.strip_edges()
	_folder_dialog.current_dir = current if current != "" else DeckLibrary.default_folder()
	_folder_dialog.popup_centered_ratio(0.6)


func _heading(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.theme_type_variation = ReaderTheme.HEADING
	return label


func _grid(parent: Control) -> GridContainer:
	var grid: GridContainer = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	return grid


func _row(grid: GridContainer, label_text: String, control: Control, hint: String = "") -> void:
	var label: Label = Label.new()
	label.text = label_text
	label.theme_type_variation = ReaderTheme.MUTED_LABEL
	label.tooltip_text = hint
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.tooltip_text = hint
	grid.add_child(control)


func _spin(low: float, high: float, step: float) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.rounded = true
	return spin
