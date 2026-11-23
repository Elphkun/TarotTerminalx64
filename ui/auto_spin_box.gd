class_name AutoSpinBox
extends SpinBox
## A SpinBox whose lowest value means "automatic". At that value it shows `auto_text`
## ("Auto (0.42)") instead of the number, so 0 doesn't read as a size of nothing.
## While it is being typed in, it shows the plain number, so typing works as usual.

## What the box shows at its lowest value.
var auto_text: String = "Auto":
	set(text):
		auto_text = text
		_show_auto()


func _ready() -> void:
	value_changed.connect(func(_value: float) -> void: _show_auto())
	var edit: LineEdit = get_line_edit()
	edit.focus_entered.connect(_start_typing)
	# Deferred: SpinBox reads the typed text on focus loss and then rewrites it.
	edit.focus_exited.connect(_show_auto, CONNECT_DEFERRED)
	edit.text_submitted.connect(func(_text: String) -> void: _show_auto.call_deferred())
	_show_auto.call_deferred()


func is_auto() -> bool:
	return value <= min_value


## The text in the box (auto_text at the lowest value).
func shown_text() -> String:
	return get_line_edit().text


func _show_auto() -> void:
	if not is_inside_tree() or get_line_edit().has_focus():
		return
	# Any other value: SpinBox has already written the number.
	if is_auto():
		get_line_edit().text = auto_text


## Typing starts from the number, not the "Auto" text.
func _start_typing() -> void:
	if is_auto():
		var edit: LineEdit = get_line_edit()
		edit.text = str(min_value)
		edit.select_all.call_deferred()
