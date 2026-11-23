class_name WindowPlace
extends RefCounted
## Where the desktop window was when the app last closed (user://window.json), so it
## opens there again. The saved place is checked against the screens as they are now,
## and moved back onto a screen (and shrunk to fit) if a screen has gone or shrunk.

const DEFAULT_PATH := "user://window.json"
## Room for the title bar above the window's top edge, which its position leaves out.
const TITLE_BAR_ROOM: int = 40

## The window's position and size, without its frame (Window.position and size).
var rect: Rect2i = Rect2i()
var maximized: bool = false


func has_place() -> bool:
	return rect.size.x > 0 and rect.size.y > 0


static func load_from(path: String = DEFAULT_PATH) -> WindowPlace:
	var place: WindowPlace = WindowPlace.new()
	if not FileAccess.file_exists(path):
		return place
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return place
	var numbers: Array[int] = []
	for key: String in ["x", "y", "width", "height"]:
		var value: Variant = data.get(key)
		if not (value is float or value is int):
			return place
		numbers.append(int(value))
	place.rect = Rect2i(numbers[0], numbers[1], numbers[2], numbers[3])
	place.maximized = data.get("maximized", false) == true
	return place


func save(path: String = DEFAULT_PATH) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"x": rect.position.x, "y": rect.position.y,
			"width": rect.size.x, "height": rect.size.y, "maximized": maximized}, "\t"))
	return OK


## `wanted` moved onto the screen area it overlaps most (or the first area, if it
## overlaps none), shrunk to fit, with room for the title bar above it.
static func fit(wanted: Rect2i, areas: Array[Rect2i]) -> Rect2i:
	if areas.is_empty():
		return wanted
	var best: Rect2i = areas[0]
	var best_overlap: int = -1
	for area: Rect2i in areas:
		var overlap: Rect2i = area.intersection(wanted)
		if overlap.get_area() > best_overlap:
			best_overlap = overlap.get_area()
			best = area
	var room: Rect2i = Rect2i(best.position + Vector2i(0, TITLE_BAR_ROOM),
			best.size - Vector2i(0, TITLE_BAR_ROOM))
	var size: Vector2i = wanted.size.min(room.size)
	var position: Vector2i = wanted.position.clamp(room.position, room.end - size)
	return Rect2i(position, size)


## Every screen's usable area (without the taskbar).
static func screen_areas() -> Array[Rect2i]:
	var areas: Array[Rect2i] = []
	for screen: int in DisplayServer.get_screen_count():
		areas.append(DisplayServer.screen_get_usable_rect(screen))
	return areas
