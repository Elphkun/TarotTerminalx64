class_name SpreadDesignerWindow
extends Window
## The spread designer in a window of its own: a separate desktop window where the
## platform has them (App sets `native`), otherwise a window inside the app's (the web,
## the editor's Game tab, headless tests).

const START_SIZE: Vector2i = Vector2i(1280, 800)
const SMALLEST: Vector2i = Vector2i(960, 600)

var designer: SpreadDesigner
## Open as a desktop window of its own.
var native: bool = false


func _init(card_db: CardDb) -> void:
	title = "Spread designer"
	theme = ReaderTheme.build()
	wrap_controls = false
	transient = false
	exclusive = false
	visible = false
	# Its own dialogs (discard changes, lay over) open inside it, not in the app's window.
	gui_embed_subwindows = true
	designer = SpreadDesigner.new(card_db)
	add_child(designer)
	close_requested.connect(close)


## Shows the window, sized to fit the screen (or the app's window, when embedded).
func open() -> void:
	var room: Vector2i = START_SIZE
	if native:
		var screen: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		room = screen.size - Vector2i(40, 80)
	else:
		room = Vector2i(get_parent().get_viewport().get_visible_rect().size) - Vector2i(40, 60)
	min_size = SMALLEST.min(room)
	# The app's other windows are drawn inside it; only this one is let out.
	force_native = native
	popup_centered(START_SIZE.min(room))
	grab_focus()


## Hides the window, asking first if the spread has unsaved changes.
func close() -> void:
	designer._unless_unsaved(func() -> void:
		designer.dirty = false
		hide())
