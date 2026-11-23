extends Control
## Developer view of a deck: every card in canonical order with its name and file,
## to check a deck's suit_order, court_order and index_overrides by eye.
##
## Usage: godot --path . res://tools/deck_viewer.tscn [-- --deck=<folder name> --shot=out.png]
## With --shot it saves a screenshot after loading and quits.

const THUMB_SIZE := Vector2(72, 124)
const COLUMNS: int = 14

var _db: CardDb
var _picker: DeckPicker
var _grid: GridContainer
var _status: Label
var _options: Dictionary = {}


func _ready() -> void:
	_db = CardDb.load_default()
	_options = _parse_options()
	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	add_child(root)

	var bar: HBoxContainer = HBoxContainer.new()
	root.add_child(bar)
	_picker = DeckPicker.new()
	if _options.has("deck"):
		_picker.settings = AppSettings.load_from()
		_picker.settings.deck = _options["deck"]
	_picker.custom_minimum_size.x = 280
	bar.add_child(_picker)
	_status = Label.new()
	bar.add_child(_status)

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 6)
	_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_grid)

	_picker.deck_changed.connect(_show_deck)
	if _picker.is_node_ready():
		_show_deck(_picker.selected_deck())


func _show_deck(deck: DeckInfo) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()
	if deck == null:
		_status.text = "No usable deck. Check the folder with tools/deck_check.gd."
		return
	var images: DeckImages = DeckImages.new(deck, int(THUMB_SIZE.y * 2))
	_status.text = "%s: suits %s, courts %s, %d override(s)%s" % [
		deck.name, "/".join(deck.suit_order), "/".join(deck.court_order),
		deck.index_overrides.size(), "" if deck.distributable else ", not distributable"]
	for index: int in CardIndex.DECK_SIZE:
		var moved: bool = deck.file_index(index) != index
		_grid.add_child(_cell(images.texture(index), "%d %s" % [index, _short_name(index)],
				"file %d" % deck.file_index(index), moved))
		# Start each suit on a new row: 22 trumps fill one row of 14 and part of the next.
		if index == CardIndex.TRUMP_COUNT - 1:
			for pad: int in COLUMNS - CardIndex.TRUMP_COUNT % COLUMNS:
				_grid.add_child(Control.new())
	_grid.add_child(_cell(images.back_texture(), "back", deck.back_file, false))
	if _options.has("shot"):
		_save_shot.call_deferred(str(_options["shot"]))


func _cell(texture: Texture2D, title: String, file: String, moved: bool) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var picture: TextureRect = TextureRect.new()
	picture.texture = texture
	picture.custom_minimum_size = THUMB_SIZE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(picture)
	for text: String in [title, file]:
		var label: Label = Label.new()
		label.text = text
		label.custom_minimum_size.x = THUMB_SIZE.x
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 10)
		if moved:
			label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.3))
		box.add_child(label)
	return box


func _short_name(index: int) -> String:
	return str(_db.card(index)["name"]).trim_prefix("The ").replace(" of ", " ")


func _save_shot(path: String) -> void:
	for i: int in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error: Error = get_viewport().get_texture().get_image().save_png(path)
	print("Saved %s (%s)" % [path, error_string(error)])
	get_tree().quit()


func _parse_options() -> Dictionary:
	var options: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		var body: String = argument.trim_prefix("--")
		var split: int = body.find("=")
		if split > 0:
			options[body.left(split)] = body.substr(split + 1)
	return options
