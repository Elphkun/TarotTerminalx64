class_name App
extends Control
## The app's root: theme, background, data, settings and the LLM client, then the
## reading screen. Tests set the fields below before adding it to the tree.

## Scales every animation; the UI smoke test sets 0.
var motion: float = 1.0
## Tests pass a fake; otherwise an OpenAiClient for LlmConfig's endpoint.
var client: LlmClient = null
var settings_path: String = AppSettings.DEFAULT_PATH
var llm_config_path: String = LlmConfig.DEFAULT_PATH
## Where "Save as example" writes; the smoke test points it at user://.
var examples_path: String = ReadingExamples.default_path()
## Builds the client Settings uses for Test connection: (LlmConfig) -> LlmClient.
var make_test_client: Callable = func(config: LlmConfig) -> LlmClient:
	return OpenAiClient.new(config)

var db: CardDb
var settings: AppSettings
var llm_config: LlmConfig
var session: ReadingSession
var screen: ReadingScreen
var settings_panel: SettingsPanel
var examples_dialog: ExamplesDialog
var history_dialog: HistoryDialog
var licenses_dialog: LicensesDialog
## The first-run notice, while it waits for an answer (null once agreed).
var notice: NoticeDialog
## The spread designer's window, made the first time it is opened.
var designer_window: SpreadDesignerWindow
## Where finished readings are kept; tests point it elsewhere.
var history_folder: String = ReadingHistory.DEFAULT_FOLDER
## Where the window's place is kept between runs.
var window_place_path: String = WindowPlace.DEFAULT_PATH
## The place loaded at start; kept so closing while maximized remembers the size to
## return to.
var _window_place: WindowPlace = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ReaderTheme.build()
	add_child(ReaderTheme.background())
	db = CardDb.load_default()
	if not db.errors.is_empty():
		push_error("Data problems: %s" % ", ".join(db.errors))
	settings = AppSettings.load_from(settings_path)
	llm_config = LlmConfig.load_from(llm_config_path)
	if client == null:
		client = OpenAiClient.new(llm_config)
	add_child(client)
	session = ReadingSession.new(db, client, llm_config)
	screen = ReadingScreen.new(session, settings, motion)
	screen.history_folder = history_folder
	add_child(screen)
	settings_panel = SettingsPanel.new(llm_config, llm_config_path, settings, make_test_client)
	add_child(settings_panel)
	screen.settings_requested.connect(settings_panel.open)
	settings_panel.examples_path = examples_path
	settings_panel.saved.connect(_on_settings_saved)
	get_window().size_changed.connect(apply_ui_scale)
	restore_window_place()
	apply_ui_scale(true)
	apply_window_icon()
	# Added last so it sits above Settings, which can open it.
	examples_dialog = ExamplesDialog.new()
	examples_dialog.examples_path = examples_path
	add_child(examples_dialog)
	screen.example_requested.connect(examples_dialog.open)
	settings_panel.examples_requested.connect(func() -> void: examples_dialog.open())
	settings_panel.designer_requested.connect(open_designer)
	examples_dialog.saved.connect(_on_examples_saved)
	history_dialog = HistoryDialog.new()
	history_dialog.history_folder = history_folder
	add_child(history_dialog)
	screen.history_requested.connect(history_dialog.open)
	history_dialog.open_requested.connect(func(path: String) -> void: screen.open_record(path))
	history_dialog.export_requested.connect(func(path: String) -> void:
		if screen.open_record(path) == "":
			screen.export_reading())
	history_dialog.reread_requested.connect(func(path: String) -> void:
		if screen.open_record(path) == "":
			screen.reread())
	licenses_dialog = LicensesDialog.new()
	add_child(licenses_dialog)
	settings_panel.licenses_requested.connect(licenses_dialog.open)
	show_notice_if_needed()


## The first-run notice, on top of everything, until it is agreed to (once per
## NoticeDialog.VERSION). Quit closes the app.
func show_notice_if_needed() -> void:
	if settings.notice_accepted >= NoticeDialog.VERSION:
		return
	notice = NoticeDialog.new()
	notice.accepted.connect(func() -> void:
		settings.notice_accepted = NoticeDialog.VERSION
		settings.save()
		notice = null
		screen.question_input.grab_focus())
	notice.declined.connect(func() -> void: get_tree().quit())
	add_child(notice)


## Opens the spread designer, in a desktop window of its own where there are such.
func open_designer() -> void:
	if designer_window == null:
		designer_window = SpreadDesignerWindow.new(db)
		designer_window.designer.saved.connect(func(_id: String) -> void: screen.refresh_spreads())
		designer_window.native = _is_desktop_window()
		add_child(designer_window)
	designer_window.designer.spreads_folder = screen.spreads_folder
	designer_window.designer.set_images(screen.table.images)
	designer_window.open()


func _on_examples_saved(count: int) -> void:
	settings_panel.show_examples_count()
	if not settings_panel.visible:
		screen.reading_panel.set_status("Examples saved: %d of %d, sent with every reading." % [
				count, ReadingExamples.LIMIT], ReaderTheme.WELL)


## The layout is designed for this size; the window may be larger (more room, same
## text size) but the app scales down rather than squeeze below it.
const DESIGN_SIZE: Vector2 = Vector2(1280, 720)
const TITLE_BAR_ROOM: float = 40.0

var _embedded_note_shown: bool = false


## The content scale for a window: the chosen interface size, reduced only when the
## window is too small to hold the design size at that scale.
static func scale_for(window_size: Vector2, ui_scale: float) -> float:
	return maxf(0.25, minf(ui_scale, minf(window_size.x / DESIGN_SIZE.x, window_size.y / DESIGN_SIZE.y)))


## Sets the content scale for the current window size. With `fit_window` (at start and
## after Settings is saved), a desktop window smaller than the design size at this
## interface size first grows to it, within the screen, so 150% really shows at 150%.
func apply_ui_scale(fit_window: bool = false) -> void:
	var window: Window = get_window()
	if window == null:
		return
	# Inside the editor's Game tab the editor decides the size; the game can't resize.
	var embedded: bool = Engine.is_embedded_in_editor()
	if embedded and fit_window and not _embedded_note_shown:
		_embedded_note_shown = true
		print("TarotTerminal is running inside the editor's Game tab, which fixes the window "
				+ "size. To see window resizing and Interface size, turn off \"Embed Game on Next "
				+ "Play\" in the Game tab's menu (or set its size to Stretch), or run outside the editor.")
	if not embedded and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var area: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
		# Leave room for the title bar, which the window's size does not include.
		var room: Vector2 = Vector2(area.size) - Vector2(0, TITLE_BAR_ROOM)
		var wanted: Vector2 = DESIGN_SIZE * settings.ui_scale
		var minimum: Vector2i = Vector2i(Vector2(minf(wanted.x, room.x), minf(wanted.y, room.y)))
		window.min_size = minimum
		if fit_window and (window.size.x < minimum.x or window.size.y < minimum.y) \
				and window.mode == Window.MODE_WINDOWED:
			window.size = Vector2i(maxi(window.size.x, minimum.x), maxi(window.size.y, minimum.y))
			if _window_place != null and _window_place.has_place():
				# Grown in place, then nudged back onto the screen if it now runs off it.
				window.position = WindowPlace.fit(Rect2i(window.position, window.size),
						WindowPlace.screen_areas()).position
			else:
				window.position = area.position + Vector2i(Vector2(area.size - window.size) / 2.0)
	window.content_scale_factor = scale_for(Vector2(window.size), settings.ui_scale)


## A real desktop window, which the app may move and size (not the editor's Game tab,
## a browser or a headless run).
func _is_desktop_window() -> bool:
	return not Engine.is_embedded_in_editor() and not OS.has_feature("web") \
			and DisplayServer.get_name() != "headless"


## Puts the window where it was when the app last closed, kept on today's screens.
func restore_window_place() -> void:
	if not _is_desktop_window():
		return
	_window_place = WindowPlace.load_from(window_place_path)
	if not _window_place.has_place():
		return
	var window: Window = get_window()
	var rect: Rect2i = WindowPlace.fit(_window_place.rect, WindowPlace.screen_areas())
	window.size = rect.size
	window.position = rect.position
	if _window_place.maximized:
		window.mode = Window.MODE_MAXIMIZED


## Remembers the window's place for next time. A minimized window keeps the last place;
## a maximized one keeps the size it un-maximizes to.
func save_window_place() -> void:
	if not _is_desktop_window():
		return
	var window: Window = get_window()
	if window.mode == Window.MODE_MINIMIZED:
		return
	var place: WindowPlace = WindowPlace.new()
	place.maximized = window.mode == Window.MODE_MAXIMIZED
	if window.mode == Window.MODE_WINDOWED:
		place.rect = Rect2i(window.position, window.size)
	elif _window_place != null and _window_place.has_place():
		place.rect = _window_place.rect
	else:
		place.rect = Rect2i(window.position, window.size)
	if place.save(window_place_path) != OK:
		push_warning("Could not save the window's place to %s" % window_place_path)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_window_place()


## Windows' large icon at 100% display scaling (SM_CXICON); it grows with the DPI.
const WINDOW_ICON_SIZE: int = 32
## The project icon's file, when its uid:// setting can't be resolved.
const ICON_FILE := "res://TarotTerminal.png"


## The project icon shrunk with Lanczos to `pixels` px. Godot otherwise hands Windows the
## full-size icon roughly shrunk, and Windows shrinks it again for the taskbar, so it
## comes out pixellated. Null if the icon can't be read.
static func icon_image(source: Image, pixels: int) -> Image:
	if source == null or source.is_empty():
		return null
	var image: Image = source.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	image.resize(pixels, pixels, Image.INTERPOLATE_LANCZOS)
	return image


## Sets a cleanly shrunk window icon (title bar and taskbar) on Windows.
func apply_window_icon() -> void:
	if OS.get_name() != "Windows" or Engine.is_embedded_in_editor() \
			or DisplayServer.get_name() == "headless":
		return
	var icon_path: String = ProjectSettings.get_setting("application/config/icon", "")
	# The setting is a uid://, which a stale .godot/uid_cache.bin can fail to resolve
	# (seen once in development): fall back to the icon's file rather than log an error.
	if icon_path.begins_with("uid://") and not ResourceUID.has_id(ResourceUID.text_to_id(icon_path)):
		icon_path = ICON_FILE
	if icon_path == "" or not ResourceLoader.exists(icon_path):
		return
	var texture: Texture2D = load(icon_path) as Texture2D
	if texture == null:
		return
	var dpi: int = DisplayServer.screen_get_dpi(get_window().current_screen)
	var pixels: int = roundi(WINDOW_ICON_SIZE * maxf(1.0, dpi / 96.0))
	var image: Image = icon_image(texture.get_image(), pixels)
	if image != null:
		DisplayServer.set_icon(image)


func _on_settings_saved() -> void:
	apply_ui_scale(true)
	client.settings_changed()
	screen.settings_changed()
