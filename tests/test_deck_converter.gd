extends "res://tests/test_case.gd"
## tools/deck_converter.gd: decks shrink to JPEGs the app can still read, the back
## included, and deck.json follows the back's new name.

const FOLDER := "user://test_convert_deck"


func _make_deck(card_size: Vector2i) -> String:
	var folder: String = ProjectSettings.globalize_path(FOLDER)
	_remove(folder)
	DirAccess.make_dir_recursive_absolute(folder)
	var image: Image = Image.create(card_size.x, card_size.y, false, Image.FORMAT_RGB8)
	image.fill(Color(0.6, 0.2, 0.3))
	for index: int in CardIndex.DECK_SIZE:
		image.save_png(folder.path_join("%02d.png" % index))
	image.save_png(folder.path_join("back.png"))
	var file: FileAccess = FileAccess.open(folder.path_join("deck.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"name": "Test", "back": "back.png", "distributable": true}))
	file.close()
	return folder


func _remove(folder: String) -> void:
	if not DirAccess.dir_exists_absolute(folder):
		return
	for file: String in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
	DirAccess.remove_absolute(folder)


func test_target_size_keeps_the_shape() -> void:
	assert_eq(DeckConverter.target_size(Vector2i(1080, 1920), 1440), Vector2i(810, 1440))
	assert_eq(DeckConverter.target_size(Vector2i(300, 527), 1440), Vector2i(300, 527),
			"a small card keeps its size")


func test_a_deck_becomes_jpegs_the_app_reads() -> void:
	var folder: String = _make_deck(Vector2i(60, 120))
	var converter: DeckConverter = DeckConverter.new()
	converter.height = 80
	assert_true(converter.convert(folder), "converted: %s" % ", ".join(converter.problems))
	assert_eq(converter.converted, CardIndex.DECK_SIZE + 1, "every card and the back")
	var files: PackedStringArray = DirAccess.get_files_at(folder)
	for file: String in files:
		assert_false(file.ends_with(".png"), "no PNG left: %s" % file)
	var deck: DeckInfo = DeckInfo.load_folder(folder)
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_eq(deck.back_file, "back.jpg", "deck.json points at the new back")
	assert_eq(Image.load_from_file(deck.card_path(28)).get_size(), Vector2i(40, 80))
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("deck.json")))
	assert_eq(data.get("distributable"), true, "other deck.json fields are kept")
	_remove(folder)


func test_a_dry_run_changes_nothing() -> void:
	var folder: String = _make_deck(Vector2i(20, 40))
	var converter: DeckConverter = DeckConverter.new()
	converter.height = 20
	converter.dry_run = true
	assert_true(converter.convert(folder))
	assert_eq(converter.converted, CardIndex.DECK_SIZE + 1)
	assert_true(FileAccess.file_exists(folder.path_join("00.png")))
	assert_false(FileAccess.file_exists(folder.path_join("00.jpg")))
	_remove(folder)
