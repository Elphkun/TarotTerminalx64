class_name ReadingPanel
extends PanelContainer
## The reading as it streams in, plus its status: waiting, errors with Retry, and the
## critique's note.

signal retry_pressed()

## After this long, the weighing line says why it may be slow.
const SLOW_WEIGHING_S: int = 3

var text_view: RichTextLabel
var status: Label
var retry_button: Button
## Under the text: a warning that the prompt may not fit, then the tokens used.
var meter: Label
## Under the text: the question could not be weighed. Stays until the next question.
var note: Label

var _markdown: String = ""
## "weighing" while the question is sorted. While waiting for the first visible words:
## "waiting", or "thinking" once the model streams hidden reasoning. "" otherwise.
var _phase: String = ""
var _thinking_chars: int = 0
var _started_ms: int = 0
var _ticker: Timer


func _init() -> void:
	_ticker = Timer.new()
	_ticker.wait_time = 1.0
	_ticker.timeout.connect(_update_wait_status)
	add_child(_ticker)
	var box: VBoxContainer = VBoxContainer.new()
	add_child(box)
	var header: HBoxContainer = HBoxContainer.new()
	box.add_child(header)
	var title: Label = Label.new()
	title.text = "Reading"
	title.theme_type_variation = ReaderTheme.HEADING
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	retry_button = Button.new()
	retry_button.text = "Retry"
	retry_button.visible = false
	retry_button.pressed.connect(func() -> void: retry_pressed.emit())
	header.add_child(retry_button)

	status = Label.new()
	status.theme_type_variation = ReaderTheme.MUTED_LABEL
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)

	text_view = RichTextLabel.new()
	text_view.bbcode_enabled = true
	text_view.scroll_following = true
	text_view.selection_enabled = true
	text_view.context_menu_enabled = true
	text_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(text_view)

	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", ReaderTheme.BRASS)
	box.add_child(note)

	meter = Label.new()
	meter.theme_type_variation = ReaderTheme.MUTED_LABEL
	meter.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(meter)
	clear()


func clear() -> void:
	_stop_waiting()
	_markdown = ""
	text_view.text = ""
	retry_button.visible = false
	set_meter("")
	set_note("")
	set_status("Ask a question, then shuffle.")


## The note under the reading; "" hides it.
func set_note(text: String) -> void:
	note.text = text
	note.visible = text != ""


## The line under the reading; "" hides it.
func set_meter(text: String, color: Color = ReaderTheme.MUTED) -> void:
	meter.text = text
	meter.visible = text != ""
	meter.add_theme_color_override("font_color", color)


func set_status(text: String, color: Color = ReaderTheme.MUTED) -> void:
	status.text = text
	status.visible = text != ""
	status.add_theme_color_override("font_color", color)


func begin() -> void:
	_start_waiting("waiting")


## The question is being weighed, which also loads the model: the same line and timer.
func begin_weighing() -> void:
	set_note("")
	_start_waiting("weighing")


## The question has been weighed and no reading follows yet.
func end_weighing() -> void:
	if _phase == "weighing":
		_stop_waiting()
		text_view.text = ""


func _start_waiting(phase_name: String) -> void:
	_markdown = ""
	text_view.text = ""
	retry_button.visible = false
	set_meter("")
	_phase = phase_name
	_thinking_chars = 0
	_started_ms = Time.get_ticks_msec()
	set_status("")
	if is_inside_tree():
		_ticker.start()
	_update_wait_status()


## Hidden reasoning from a thinking model: counted, not shown.
func add_thinking(piece: String) -> void:
	if _phase == "" or _phase == "weighing":
		return
	var started_thinking: bool = _phase == "waiting"
	_phase = "thinking"
	_thinking_chars += piece.length()
	if started_thinking:
		_update_wait_status()


func append(piece: String) -> void:
	if _phase != "":
		_stop_waiting()
		set_status("The reader is writing…")
	_markdown += piece
	text_view.text = MarkdownBbcode.convert(_markdown)


func set_reading(markdown: String) -> void:
	_markdown = markdown
	text_view.text = MarkdownBbcode.convert(_markdown)


func finish() -> void:
	_stop_waiting()
	set_status("")


## The current waiting phase, for tests: "weighing", "waiting", "thinking" or "".
func phase() -> String:
	return _phase


## Until the first words, the empty reading says what the reader is doing, with a timer.
func _update_wait_status() -> void:
	var seconds: int = floori((Time.get_ticks_msec() - _started_ms) / 1000.0)
	var line: String = ""
	var color: Color = ReaderTheme.MUTED
	match _phase:
		"weighing":
			line = "The reader is weighing your question… %d s" % seconds
			color = ReaderTheme.BRASS
			if seconds >= SLOW_WEIGHING_S:
				line += "\nA model that isn't loaded yet takes a while to warm up."
		"waiting":
			line = "The reader is studying the spread… %d s" % seconds
		"thinking":
			line = "The reader is thinking it over… %d s (%d characters of private notes)" % [
				seconds, _thinking_chars]
		_:
			return
	text_view.text = "[color=#%s][i]%s[/i][/color]" % [color.to_html(false), line]


## What the reader is doing before the first words ("" once writing), for tests.
func waiting_text() -> String:
	return text_view.get_parsed_text() if _phase != "" else ""


func _stop_waiting() -> void:
	_phase = ""
	_ticker.stop()


## The reader refused the question (ReadingSession.refused): no reading, no Retry.
func show_refusal(message: String) -> void:
	_stop_waiting()
	_markdown = ""
	text_view.text = "[i]%s[/i]" % message
	retry_button.visible = false
	set_status("")


func show_error(message: String) -> void:
	_stop_waiting()
	if _markdown == "":
		text_view.text = ""
	set_status("The reader could not answer: %s" % message, ReaderTheme.ILL)
	retry_button.visible = true


## Plain text of the reading so far (for tests).
func reading() -> String:
	return _markdown
