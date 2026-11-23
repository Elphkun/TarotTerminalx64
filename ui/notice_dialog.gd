class_name NoticeDialog
extends Control
## The notice shown on first run, after the splash: the reader must agree before using
## the app, or quit. App shows it while AppSettings.notice_accepted is below VERSION, so
## raising VERSION asks again after the wording changes.

signal accepted()
signal declined()

## Raise when the notice's wording changes enough to ask again.
const VERSION: int = 1
const TEXT: String = """TarotTerminal is for entertainment and reflection only. The cards offer a different way of looking at a question, and the readings are written by an AI model, which can be wrong.

Nothing here is professional advice: not medical, legal, financial or psychological. Make major life decisions with care, and with qualified help where it is needed.

By using this software, you agree that Sasazaki Software, Reiji Kitsuoka and all related entities are not responsible for your decisions or their outcomes.

If you are in crisis, or thinking of harming yourself or someone else, please contact your local emergency services or a crisis line."""

var body: Label
var agree_button: Button
var quit_button: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Nothing underneath can be clicked until the notice is answered.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _ready() -> void:
	agree_button.grab_focus.call_deferred()


func agree() -> void:
	visible = false
	accepted.emit()
	queue_free()


func decline() -> void:
	declined.emit()


func _build() -> void:
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var dialog: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = ReaderTheme.panel()
	style.bg_color = ReaderTheme.BACKGROUND.lightened(0.04)
	style.border_color = Color(ReaderTheme.BRASS, 0.5)
	style.set_content_margin_all(28)
	dialog.add_theme_stylebox_override("panel", style)
	dialog.custom_minimum_size = Vector2(640, 0)
	centre.add_child(dialog)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	dialog.add_child(column)

	var title: Label = Label.new()
	title.text = "Notice"
	title.theme_type_variation = ReaderTheme.TITLE
	column.add_child(title)
	body = Label.new()
	body.text = TEXT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(640, 0)
	column.add_child(body)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	quit_button = Button.new()
	quit_button.text = "Quit"
	quit_button.pressed.connect(decline)
	buttons.add_child(quit_button)
	agree_button = Button.new()
	agree_button.text = "I agree"
	agree_button.pressed.connect(agree)
	buttons.add_child(agree_button)
