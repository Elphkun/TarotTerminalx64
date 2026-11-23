class_name DeckConverter
extends RefCounted
## Shrinks a deck's images to a height the app can use and saves them as JPEG, replacing
## the originals (keep your own backup). The app never loads cards taller than
## ReadingScreen's 1440 px cap, so anything above that is wasted space.
##
## Run it with tools/convert_decks.gd.

const DEFAULT_HEIGHT: int = 1440
## save_jpg's quality, 0 to 1.
const DEFAULT_QUALITY: float = 0.9

var height: int = DEFAULT_HEIGHT
var quality: float = DEFAULT_QUALITY
## Report what would change without writing anything.
var dry_run: bool = false

## Totals for the last convert(): bytes before and after, files changed, problems.
var bytes_before: int = 0
var bytes_after: int = 0
var converted: int = 0
var problems: PackedStringArray = []


## The size an image of `size` is shrunk to: `max_height` tall, same shape. An image
## no taller than that keeps its size.
static func target_size(size: Vector2i, max_height: int) -> Vector2i:
	if size.y <= max_height:
		return size
	return Vector2i(maxi(1, roundi(size.x * float(max_height) / size.y)), max_height)


## Converts every card image and the back of the deck in `folder`. Returns false if the
## deck could not be read or any image failed (the others are still converted).
func convert(folder: String) -> bool:
	bytes_before = 0
	bytes_after = 0
	converted = 0
	problems = []
	var deck: DeckInfo = DeckInfo.load_folder(folder)
	if not deck.is_valid():
		problems.append_array(deck.errors)
		return false
	var files: PackedStringArray = []
	for file: String in deck._files.values():
		files.append(deck.folder.path_join(file))
	var old_back: String = deck.back_file
	var new_back: String = old_back
	for path: String in files:
		_convert_file(path)
	if old_back != "":
		var result: String = _convert_file(deck.back_path())
		if result != "":
			new_back = result.get_file()
	if new_back != old_back and deck.has_deck_file and not dry_run:
		_set_back(deck.folder.path_join(DeckInfo.DECK_FILE), new_back)
	return problems.is_empty()


## Converts one image. Returns the JPEG's path (the same path if nothing needed doing),
## or "" on failure.
func _convert_file(path: String) -> String:
	var before: int = _file_size(path)
	bytes_before += before
	var jpeg_path: String = path.get_basename() + ".jpg"
	var image: Image = Image.load_from_file(path)
	if image == null or image.is_empty():
		problems.append("cannot read %s" % path)
		bytes_after += before
		return ""
	var size: Vector2i = target_size(image.get_size(), height)
	var is_jpeg: bool = path.get_extension().to_lower() in ["jpg", "jpeg"]
	if is_jpeg and size == image.get_size():
		bytes_after += before
		return path
	if image.detect_alpha() != Image.ALPHA_NONE:
		problems.append("%s has transparency, which JPEG can't keep; left as it is" % path)
		bytes_after += before
		return ""
	if dry_run:
		converted += 1
		bytes_after += before
		return jpeg_path
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGB8)
	if size != image.get_size():
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	# Written beside the original first, and checked, so a failure never loses a card.
	var temp_path: String = path.get_basename() + ".converting.jpg"
	if image.save_jpg(temp_path, quality) != OK:
		problems.append("cannot write %s" % temp_path)
		bytes_after += before
		return ""
	var check: Image = Image.load_from_file(temp_path)
	if check == null or check.get_size() != size:
		DirAccess.remove_absolute(temp_path)
		problems.append("the converted %s did not read back; original kept" % path)
		bytes_after += before
		return ""
	DirAccess.remove_absolute(path)
	if jpeg_path != path and FileAccess.file_exists(jpeg_path):
		DirAccess.remove_absolute(jpeg_path)
	DirAccess.rename_absolute(temp_path, jpeg_path)
	converted += 1
	bytes_after += _file_size(jpeg_path)
	return jpeg_path


## Points deck.json's "back" at the new file, leaving every other field as it was.
func _set_back(json_path: String, back_file: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not data is Dictionary or not (data as Dictionary).has("back"):
		return
	data["back"] = back_file
	var file: FileAccess = FileAccess.open(json_path, FileAccess.WRITE)
	if file == null:
		problems.append("cannot update %s; set \"back\" to %s" % [json_path, back_file])
		return
	file.store_string(JSON.stringify(data, "\t", false) + "\n")


static func _file_size(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	return 0 if file == null else file.get_length()
