class_name DeckImages
extends RefCounted
## Loads a deck's card images from disk at runtime and caches them as textures.
## Nothing here goes through the importer, so deck images never end up in res:// or an export.

var deck: DeckInfo
## Images taller than this are scaled down on load. 0 keeps the original size.
var max_height: int = 0
## The deck's card shape (width / height), measured from its back or card 0, so cards
## are drawn at their own proportions. Kept within ASPECT_RANGE.
var aspect: float = DEFAULT_ASPECT

## Most deck scans are about 0.58 wide to 1 tall; used when nothing can be measured.
const DEFAULT_ASPECT: float = 0.58
const ASPECT_RANGE: Vector2 = Vector2(0.45, 0.75)

var _textures: Dictionary = {}


func _init(deck_info: DeckInfo, height_limit: int = 0) -> void:
	deck = deck_info
	max_height = height_limit
	aspect = measure_aspect(deck)


## The card shape of `deck`: its back's width / height, or card 0's when it has no back.
static func measure_aspect(deck_info: DeckInfo) -> float:
	for path: String in [deck_info.back_path(), deck_info.card_path(0)]:
		if path == "":
			continue
		var size: Vector2i = image_size(path)
		if size.y > 0:
			return clampf(float(size.x) / size.y, ASPECT_RANGE.x, ASPECT_RANGE.y)
	return DEFAULT_ASPECT


## An image file's pixel size, or (0, 0) if it cannot be read.
static func image_size(path: String) -> Vector2i:
	var loaded: Image = Image.load_from_file(path)
	return Vector2i.ZERO if loaded == null or loaded.is_empty() else loaded.get_size()


## The image for canonical card `index`, or null (with a warning) if it cannot be read.
func image(index: int) -> Image:
	return _load_image(deck.card_path(index), "card %d" % index)


func back_image() -> Image:
	return _load_image(deck.back_path(), "back")


## Cached texture for canonical card `index`, or null if it cannot be read.
func texture(index: int) -> Texture2D:
	return _texture(index)


func back_texture() -> Texture2D:
	return _texture(-1)


func clear() -> void:
	_textures.clear()


func _texture(key: int) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	if key < 0 and deck.back_path() == "":
		_textures[key] = null  # no back: CardView draws its own, no warning needed
		return null
	var loaded: Image = back_image() if key < 0 else image(key)
	var result: Texture2D = null if loaded == null else ImageTexture.create_from_image(loaded)
	_textures[key] = result
	return result


func _load_image(path: String, label: String) -> Image:
	if path == "":
		push_warning("%s: no file for %s" % [deck.name, label])
		return null
	var loaded: Image = Image.load_from_file(path)
	if loaded == null or loaded.is_empty():
		push_warning("%s: could not read %s (%s)" % [deck.name, label, path])
		return null
	if max_height > 0 and loaded.get_height() > max_height:
		var width: int = maxi(1, roundi(loaded.get_width() * float(max_height) / loaded.get_height()))
		loaded.resize(width, max_height, Image.INTERPOLATE_LANCZOS)
	# Cards are drawn well below the loaded size (a Celtic Cross card is ~190 px tall).
	# Mipmaps let CardView's LINEAR_WITH_MIPMAPS filter shrink them cleanly instead of
	# plain bilinear sampling, which turns fine linework and lettering jagged.
	if loaded.is_compressed():
		loaded.decompress()
	loaded.generate_mipmaps()
	return loaded
