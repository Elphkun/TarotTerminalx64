class_name DeckInfo
extends RefCounted
## One deck folder on disk: its deck.json and which image file shows each card.
##
## A deck folder holds the 78 card images, a back image and an optional deck.json:
##   {
##     "name": "Rider-Waite-Smith",
##     "back": "back.jpg",
##     "suit_order": ["wands", "cups", "swords", "pentacles"],  (files 22-35, 36-49, ...)
##     "court_order": ["page", "knight", "queen", "king"],       (suit offsets +10..+13)
##     "index_overrides": {"8": 11, "11": 8},                     (canonical -> file index)
##     "distributable": false
##   }
## Every field is optional; the defaults are the canonical layout. Card files are found
## by number, so "7.jpg", "07.jpg" and "007.png" all count as file 7.
##
## Decks are never imported under res://: images load with Image.load_from_file().

const IMAGE_EXTENSIONS: PackedStringArray = ["jpg", "jpeg", "png", "webp"]
const DECK_FILE := "deck.json"

## Folder name, used as the deck's id in settings.
var id: String = ""
## Absolute path of the folder.
var folder: String = ""
var name: String = ""
var back_file: String = ""
var suit_order: PackedStringArray = CardIndex.SUITS
var court_order: PackedStringArray = CardIndex.COURT_RANKS
## canonical index -> file index
var index_overrides: Dictionary = {}
var distributable: bool = false
var has_deck_file: bool = false

## Problems that make the deck unusable (missing cards, a bad deck.json).
var errors: Array[String] = []
## Things worth knowing that do not stop the deck working.
var warnings: Array[String] = []

## file index -> file name, as found in the folder
var _files: Dictionary = {}


static func load_folder(path: String) -> DeckInfo:
	var deck: DeckInfo = DeckInfo.new()
	deck._load(path)
	return deck


func is_valid() -> bool:
	return errors.is_empty()


## The file index that shows canonical card `index` in this deck.
func file_index(index: int) -> int:
	if index_overrides.has(index):
		return index_overrides[index]
	if CardIndex.is_trump(index):
		return index
	var offset: int = CardIndex.offset_in_suit(index)
	if offset >= CardIndex.FIRST_COURT_OFFSET:
		var rank: String = CardIndex.COURT_RANKS[offset - CardIndex.FIRST_COURT_OFFSET]
		offset = CardIndex.FIRST_COURT_OFFSET + court_order.find(rank)
	var suit_position: int = suit_order.find(CardIndex.suit_of(index))
	return CardIndex.TRUMP_COUNT + suit_position * CardIndex.CARDS_PER_SUIT + offset


## Absolute path of the image for canonical card `index`, or "" if the file is missing.
func card_path(index: int) -> String:
	var file: Variant = _files.get(file_index(index))
	return "" if file == null else folder.path_join(file)


func back_path() -> String:
	return "" if back_file == "" else folder.path_join(back_file)


func _load(path: String) -> void:
	folder = ProjectSettings.globalize_path(path).simplify_path()
	id = folder.get_file()
	name = id
	var json_path: String = folder.path_join(DECK_FILE)
	if FileAccess.file_exists(json_path):
		has_deck_file = true
		var json: JSON = JSON.new()
		if json.parse(FileAccess.get_file_as_string(json_path)) != OK:
			errors.append("%s line %d: %s" % [
				DECK_FILE, json.get_error_line(), json.get_error_message()])
		elif not json.data is Dictionary:
			errors.append("%s is not a JSON object" % DECK_FILE)
		else:
			_apply(json.data)
	else:
		warnings.append("no %s, using the canonical layout" % DECK_FILE)

	_scan_files()
	_check_mapping()


func _apply(data: Dictionary) -> void:
	name = str(data.get("name", name))
	distributable = data.get("distributable", false) == true
	back_file = str(data.get("back", ""))
	if data.has("suit_order"):
		suit_order = _permutation(data["suit_order"], CardIndex.SUITS, "suit_order")
	if data.has("court_order"):
		court_order = _permutation(data["court_order"], CardIndex.COURT_RANKS, "court_order")
	var overrides: Variant = data.get("index_overrides", {})
	if not overrides is Dictionary:
		errors.append("index_overrides must be an object")
		return
	for key: Variant in overrides:
		var from: String = str(key)
		var to: Variant = overrides[key]
		if not from.is_valid_int() or not CardIndex.is_valid(from.to_int()) \
				or not (to is float or to is int) or not CardIndex.is_valid(int(to)):
			errors.append("index_overrides: %s -> %s is not two card indices 0-77" % [from, to])
			continue
		index_overrides[from.to_int()] = int(to)


func _permutation(value: Variant, expected: PackedStringArray, field: String) -> PackedStringArray:
	var list: PackedStringArray = PackedStringArray(value) if value is Array else PackedStringArray()
	var sorted_list: PackedStringArray = list.duplicate()
	sorted_list.sort()
	var sorted_expected: PackedStringArray = expected.duplicate()
	sorted_expected.sort()
	if sorted_list != sorted_expected:
		errors.append("%s must list each of %s once" % [field, ", ".join(expected)])
		return expected
	return list


func _scan_files() -> void:
	var dir: DirAccess = DirAccess.open(folder)
	if dir == null:
		errors.append("cannot open folder %s" % folder)
		return
	var backs: PackedStringArray = []
	for file: String in dir.get_files():
		if not IMAGE_EXTENSIONS.has(file.get_extension().to_lower()):
			continue
		var stem: String = file.get_basename()
		if stem.to_lower() == "back":
			backs.append(file)
		elif stem.is_valid_int() and CardIndex.is_valid(stem.to_int()):
			var number: int = stem.to_int()
			if _files.has(number):
				warnings.append("files %s and %s are both card %d; using %s" % [
					_files[number], file, number, _files[number]])
			else:
				_files[number] = file
		else:
			warnings.append("ignoring %s" % file)

	# A deck without a back still works: CardView draws the app's own back instead.
	if back_file == "":
		if backs.is_empty():
			warnings.append("no back image (back.jpg or back.png); the app's own back is used")
		else:
			back_file = backs[0]
	elif not FileAccess.file_exists(folder.path_join(back_file)):
		warnings.append("back image %s not found; the app's own back is used" % back_file)
		back_file = ""


func _check_mapping() -> void:
	var used: Dictionary = {}
	var missing: PackedStringArray = []
	for index: int in CardIndex.DECK_SIZE:
		var file: int = file_index(index)
		if used.has(file):
			errors.append("cards %d and %d both map to file %d" % [used[file], index, file])
		used[file] = index
		if not _files.has(file):
			missing.append(str(file))
	if not missing.is_empty():
		errors.append("missing card files: %s" % ", ".join(missing))
