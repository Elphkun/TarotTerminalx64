extends SceneTree
## Lists the decks the app can see, checks each one and loads every image.
##
## Usage: godot --headless --script tools/deck_check.gd [-- --folder=PATH]
##
## Quits with 0 when every deck found is usable, 1 if any has errors, 2 if none was found.


func _initialize() -> void:
	var settings: AppSettings = AppSettings.load_from()
	var folders: PackedStringArray = DeckLibrary.folders(settings)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--folder="):
			folders = [argument.trim_prefix("--folder=")]
	print("Deck folders: %s" % ", ".join(Array(folders).map(
			func(folder: String) -> String: return ProjectSettings.globalize_path(folder))))

	var decks: Array[DeckInfo] = DeckLibrary.scan(folders)
	if decks.is_empty():
		print("No decks found.")
		quit(2)
		return
	var db: CardDb = CardDb.load_default()
	var broken: int = 0
	for deck: DeckInfo in decks:
		print("")
		print("%s  [%s]%s" % [deck.name, deck.folder,
				"" if deck.distributable else "  (not distributable)"])
		for warning: String in deck.warnings:
			print("  warning: %s" % warning)
		for error: String in deck.errors:
			print("  ERROR: %s" % error)
		if not deck.is_valid():
			broken += 1
			continue
		_report_layout(deck, db)
		_load_all(deck)
	print("")
	print("%d deck(s), %d with errors." % [decks.size(), broken])
	quit(1 if broken > 0 else 0)


## Prints where this deck differs from the canonical file layout.
func _report_layout(deck: DeckInfo, db: CardDb) -> void:
	print("  suits in files: %s; courts: %s; %d override(s)" % [
		", ".join(deck.suit_order), ", ".join(deck.court_order), deck.index_overrides.size()])
	var moved: PackedStringArray = []
	for index: int in CardIndex.DECK_SIZE:
		if deck.file_index(index) != index:
			moved.append("%s -> file %d" % [db.card(index)["name"], deck.file_index(index)])
	if moved.is_empty():
		print("  every card is at its canonical index")
	else:
		print("  %d card(s) not at their canonical index, e.g. %s" % [
			moved.size(), "; ".join(moved.slice(0, 4))])


func _load_all(deck: DeckInfo) -> void:
	var images: DeckImages = DeckImages.new(deck)
	var sizes: Dictionary = {}
	var failed: PackedStringArray = []
	for index: int in CardIndex.DECK_SIZE:
		var loaded: Image = images.image(index)
		if loaded == null:
			failed.append(str(index))
		else:
			sizes["%dx%d" % [loaded.get_width(), loaded.get_height()]] = true
	var expected: int = CardIndex.DECK_SIZE
	if deck.back_path() != "":
		expected += 1
		var back: Image = images.back_image()
		if back == null:
			failed.append("back")
		else:
			sizes["%dx%d" % [back.get_width(), back.get_height()]] = true
	print("  loaded %d of %d images; sizes: %s; drawn at aspect %.4f (width / height)" % [
		expected - failed.size(), expected, ", ".join(PackedStringArray(sizes.keys())), images.aspect])
	if sizes.size() > 1:
		print("  warning: the images are not all the same size; cards are drawn at the back's "
				+ "shape (or card 0's), so the others are stretched to it")
	if not failed.is_empty():
		print("  ERROR: could not read %s" % ", ".join(failed))
