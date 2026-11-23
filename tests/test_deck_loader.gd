extends "res://tests/test_case.gd"
## Builds small throwaway decks under user://test_decks and loads them.

const ROOT := "user://test_decks"


func _make_deck(folder_name: String, deck_json: Variant = null, skip: Array = [],
		padded: bool = false, image_size: Vector2i = Vector2i(4, 6), with_back: bool = true) -> String:
	var path: String = ProjectSettings.globalize_path(ROOT).path_join(folder_name)
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
	DirAccess.make_dir_recursive_absolute(path)
	var image: Image = Image.create(image_size.x, image_size.y, false, Image.FORMAT_RGB8)
	for index: int in CardIndex.DECK_SIZE:
		if skip.has(index):
			continue
		image.fill(Color8(index, 0, 0))
		image.save_png(path.path_join(("%02d.png" if padded else "%d.png") % index))
	if with_back:
		image.fill(Color.WHITE)
		image.save_png(path.path_join("back.png"))
	if deck_json != null:
		var file: FileAccess = FileAccess.open(path.path_join("deck.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(deck_json))
		file.close()
	return path


func test_canonical_deck_without_deck_json() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("plain"))
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_eq(deck.name, "plain")
	assert_false(deck.distributable)
	for index: int in CardIndex.DECK_SIZE:
		assert_eq(deck.file_index(index), index)
	assert_true(deck.card_path(77).ends_with("77.png"))
	assert_true(deck.back_path().ends_with("back.png"))


func test_zero_padded_file_names() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("padded", null, [], true))
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_true(deck.card_path(7).ends_with("07.png"))


func test_suit_order() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("swords_second",
			{"suit_order": ["wands", "swords", "cups", "pentacles"]}))
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_eq(deck.file_index(CardIndex.pip("cups", 1)), 50, "Ace of Cups is file 50")
	assert_eq(deck.file_index(CardIndex.pip("swords", 1)), 36, "Ace of Swords is file 36")
	assert_eq(deck.file_index(CardIndex.court("pentacles", "king")), 77)


func test_court_order() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("kings_first",
			{"court_order": ["king", "queen", "knight", "page"]}))
	assert_eq(deck.file_index(CardIndex.court("wands", "king")), 32)
	assert_eq(deck.file_index(CardIndex.court("wands", "page")), 35)
	assert_eq(deck.file_index(CardIndex.court("cups", "queen")), 36 + 11)


func test_index_overrides_for_marseille_numbering() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("marseille",
			{"name": "Marseille", "index_overrides": {"8": 11, "11": 8}, "distributable": true}))
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_eq(deck.name, "Marseille")
	assert_true(deck.distributable)
	assert_eq(deck.file_index(8), 11, "Strength")
	assert_eq(deck.file_index(11), 8, "Justice")
	assert_eq(deck.file_index(9), 9)


func test_problems_are_reported() -> void:
	var missing: DeckInfo = DeckInfo.load_folder(_make_deck("missing", null, [5, 40]))
	assert_false(missing.is_valid())
	assert_true(missing.errors[0].contains("5, 40"), str(missing.errors))
	var bad_order: DeckInfo = DeckInfo.load_folder(_make_deck("bad_order",
			{"court_order": ["page", "page", "queen", "king"]}))
	assert_false(bad_order.is_valid(), "court_order must be a permutation")
	var clash: DeckInfo = DeckInfo.load_folder(_make_deck("clash", {"index_overrides": {"8": 11}}))
	assert_false(clash.is_valid(), "two cards on file 11")


func test_images_load_with_the_mapping() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("swords_second",
			{"suit_order": ["wands", "swords", "cups", "pentacles"]}))
	var images: DeckImages = DeckImages.new(deck)
	var ace_of_cups: Image = images.image(CardIndex.pip("cups", 1))
	assert_eq(ace_of_cups.get_pixel(0, 0).r8, 50, "pixel colour encodes the file index")
	assert_eq(images.back_image().get_pixel(0, 0), Color.WHITE)
	var scaled: DeckImages = DeckImages.new(deck, 3)
	assert_eq(scaled.image(0).get_height(), 3)
	assert_eq(scaled.image(0).get_width(), 2)


## A 9:16 deck (like 1080x1920 scans) is drawn at its own shape, not the default 0.58.
func test_deck_shape_is_measured() -> void:
	var tall: DeckInfo = DeckInfo.load_folder(_make_deck("tall", null, [], false, Vector2i(54, 96)))
	assert_true(is_equal_approx(DeckImages.new(tall).aspect, 0.5625), "54x96 is 0.5625")
	var odd: DeckInfo = DeckInfo.load_folder(_make_deck("odd", null, [], false, Vector2i(30, 10)))
	assert_eq(DeckImages.new(odd).aspect, DeckImages.ASPECT_RANGE.y, "a strange shape is clamped")


## Cards are drawn far below their loaded size, so textures carry mipmaps.
func test_textures_have_mipmaps() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("mips", null, [], false, Vector2i(54, 96)))
	var images: DeckImages = DeckImages.new(deck, 48)
	var loaded: Image = images.image(3)
	assert_eq(loaded.get_height(), 48, "scaled down to the limit")
	assert_true(loaded.has_mipmaps(), "mipmaps generated")
	assert_true(images.texture(3).get_image().has_mipmaps(), "and kept in the texture")


## A deck without a back still works; the app's own back is drawn instead.
func test_deck_without_a_back_is_usable() -> void:
	var deck: DeckInfo = DeckInfo.load_folder(_make_deck("no_back", null, [], false,
			Vector2i(54, 96), false))
	assert_true(deck.is_valid(), ", ".join(deck.errors))
	assert_eq(deck.back_path(), "")
	assert_true(" ".join(deck.warnings).contains("no back image"), str(deck.warnings))
	assert_eq(DeckImages.new(deck).back_texture(), null, "CardView falls back to its placeholder")
	assert_true(is_equal_approx(DeckImages.new(deck).aspect, 0.5625), "shape measured from card 0")
	var named: DeckInfo = DeckInfo.load_folder(_make_deck("named_back", {"back": "nope.png"}))
	assert_true(named.is_valid() and named.back_path() == "", "a missing named back is a warning")


func test_default_folder_is_the_project_decks_folder() -> void:
	var settings: AppSettings = AppSettings.new()
	assert_eq(DeckLibrary.folder(settings), ProjectSettings.globalize_path("res://decks"))
	settings.deck_folder = "D:/Tarot"
	assert_eq(DeckLibrary.folders(settings), PackedStringArray(["D:/Tarot"]))


func test_library_scan_and_pick() -> void:
	_make_deck("plain")
	_make_deck("missing", null, [5])
	var decks: Array[DeckInfo] = DeckLibrary.scan([ROOT, "user://no_such_folder"])
	var ids: PackedStringArray = []
	for deck: DeckInfo in decks:
		ids.append(deck.id)
	assert_true(ids.has("plain") and ids.has("missing"), str(ids))
	var settings: AppSettings = AppSettings.new()
	settings.deck = "missing"
	assert_true(settings.pick_deck(decks).is_valid(), "a broken saved deck falls back to a valid one")
	settings.deck = "plain"
	assert_eq(settings.pick_deck(decks).id, "plain")
