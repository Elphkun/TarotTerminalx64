class_name SpreadDraft
extends RefCounted
## A spread being designed (ui/spread_designer.gd): its definition in the spreads.json
## format, the edits the designer makes to it, and saving it as an added spread.
## No UI here, so every edit can be tested.

## Field order in the saved file, so it reads like data/spreads.json.
const SPREAD_KEYS: PackedStringArray = ["name", "source", "reading_words", "card_height",
		"columns", "compact_labels", "positions", "dignity_adjacency"]
const POSITION_KEYS: PackedStringArray = ["id", "name", "meaning", "x", "y", "rotation", "over"]
## x/y are kept to this precision: a thousandth of the table is under a pixel.
const STEP: float = 0.001

## The spread's id: its key in the file and in the spread menu.
var id: String = "my_spread"
var data: Dictionary = {"name": "My spread", "positions": [], "dignity_adjacency": []}
## The added-spreads file this spread came from (a file name in the spreads folder),
## or "" for a new spread or a copy of a built-in one.
var file: String = ""
## The id it had in that file, so a rename replaces it there.
var saved_id: String = ""


## A copy of a spread to edit. A built-in spread becomes a new spread ("... (copy)"),
## since built-in spreads are never written to.
static func from_spread(spread_id: String, definition: Dictionary, builtin: bool,
		from_file: String = "") -> SpreadDraft:
	var draft: SpreadDraft = SpreadDraft.new()
	draft.data = definition.duplicate(true)
	if not draft.data.get("positions") is Array:
		draft.data["positions"] = []
	if not draft.data.get("dignity_adjacency") is Array:
		draft.data["dignity_adjacency"] = []
	if builtin:
		draft.id = spread_id + "_copy"
		draft.data["name"] = "%s (copy)" % draft.data.get("name", spread_id)
	else:
		draft.id = spread_id
		draft.file = from_file
		draft.saved_id = spread_id
	return draft


func positions() -> Array:
	return data["positions"]


func pairs() -> Array:
	return data["dignity_adjacency"]


func size() -> int:
	return positions().size()


func position(i: int) -> Dictionary:
	return positions()[i]


func index_of(position_id: String) -> int:
	for i: int in size():
		if position(i).get("id") == position_id:
			return i
	return -1


func is_full() -> bool:
	return size() >= SpreadLibrary.MAX_POSITIONS


## Adds a position at normalized (x, y), with the next free id (p1, p2...). Returns its
## index, or -1 when the spread already has SpreadLibrary.MAX_POSITIONS.
func add_position(at: Vector2) -> int:
	if is_full():
		return -1
	var number: int = size() + 1
	while index_of("p%d" % number) >= 0:
		number += 1
	positions().append({"id": "p%d" % number, "meaning": "", "x": 0.5, "y": 0.5, "rotation": 0})
	move_position(size() - 1, at)
	return size() - 1


## Removes a position, its dignity lines, and any "over" that pointed at it.
func remove_position(i: int) -> void:
	var gone: String = str(position(i).get("id"))
	positions().remove_at(i)
	for k: int in range(pairs().size() - 1, -1, -1):
		if gone in pairs()[k]:
			pairs().remove_at(k)
	for entry: Dictionary in positions():
		if entry.get("over") == gone:
			entry.erase("over")


func move_position(i: int, at: Vector2) -> void:
	var low: float = -SpreadLibrary.REACH
	var high: float = 1.0 + SpreadLibrary.REACH
	position(i)["x"] = snappedf(clampf(at.x, low, high), STEP)
	position(i)["y"] = snappedf(clampf(at.y, low, high), STEP)


func rotation_of(i: int) -> float:
	return float(position(i).get("rotation", 0.0))


## Sets the rotation in degrees, kept within 0..360 (a whole number when it is one).
func set_rotation(i: int, degrees: float) -> void:
	var value: float = fposmod(degrees, 360.0)
	if is_equal_approx(value, roundf(value)):
		position(i)["rotation"] = int(roundf(value)) % 360
	else:
		position(i)["rotation"] = value


## `degrees` snapped to the nearest eighth of a turn.
static func snap_eighth(degrees: float) -> float:
	return snappedf(degrees, 45.0)


## Adds a dignity line between two positions. False if it is the same position or the
## line is already there (either way round).
func connect_positions(a: int, b: int) -> bool:
	if a == b or a < 0 or b < 0 or a >= size() or b >= size():
		return false
	var pair: Array = [position(a)["id"], position(b)["id"]]
	if pair_index(pair[0], pair[1]) >= 0:
		return false
	pairs().append(pair)
	return true


## The index of the line between two position ids (either way round), or -1.
func pair_index(a: String, b: String) -> int:
	for k: int in pairs().size():
		var pair: Array = pairs()[k]
		if pair.size() == 2 and ((pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a)):
			return k
	return -1


func disconnect_pair(k: int) -> void:
	pairs().remove_at(k)


## Gives a position a new id, carrying its lines and any "over" along. Returns what is
## wrong with the new id, or "" when done.
func rename_position(i: int, new_id: String) -> String:
	var old_id: String = str(position(i).get("id"))
	if new_id == old_id:
		return ""
	if new_id.strip_edges() == "":
		return "a position needs an id"
	if index_of(new_id) >= 0:
		return "the id \"%s\" is already used" % new_id
	position(i)["id"] = new_id
	for pair: Array in pairs():
		for side: int in pair.size():
			if pair[side] == old_id:
				pair[side] = new_id
	for entry: Dictionary in positions():
		if entry.get("over") == old_id:
			entry["over"] = new_id
	return ""


## Sets a position's text field (name, meaning, over). An empty optional field is removed.
func set_position_field(i: int, key: String, value: String) -> void:
	if value == "" and key != "meaning":
		position(i).erase(key)
	else:
		position(i)[key] = value


## Moves a position up (-1) or down (+1) in the reading order. Returns its new index.
func move_in_order(i: int, delta: int) -> int:
	var to: int = clampi(i + delta, 0, size() - 1)
	if to != i:
		var entry: Dictionary = position(i)
		positions().remove_at(i)
		positions().insert(to, entry)
	return to


## Sets a spread field. Text fields left empty, and numbers of 0, are removed (the app's
## defaults apply).
func set_spread_field(key: String, value: Variant) -> void:
	if (value is String and value == "" and key != "name") \
			or ((value is float or value is int) and value <= 0) \
			or (key == "compact_labels" and value == false):
		data.erase(key)
	else:
		data[key] = value


## The definition as saved: known fields in a fixed order, then any others it had.
func to_data() -> Dictionary:
	var out: Dictionary = {}
	for key: String in SPREAD_KEYS:
		if data.has(key):
			out[key] = data[key]
	for key: Variant in data:
		if not out.has(key):
			out[key] = data[key]
	var ordered: Array = []
	for entry: Dictionary in positions():
		var clean: Dictionary = {}
		for key: String in POSITION_KEYS:
			if entry.has(key):
				clean[key] = entry[key]
		for key: Variant in entry:
			if not clean.has(key):
				clean[key] = entry[key]
		ordered.append(clean)
	out["positions"] = ordered
	return out.duplicate(true)


func spread() -> Spread:
	return Spread.from_data(id, to_data())


## What is wrong with the spread's id: built-in ids and ids used by other added spreads
## (`taken`: id -> file) can't be reused, and the id names the file.
func id_problems(builtin_ids: PackedStringArray, taken: Dictionary) -> PackedStringArray:
	var problems: PackedStringArray = []
	if not id.is_valid_filename() or id.strip_edges() == "" or id.contains(" "):
		problems.append("the spread id must be one word of letters, digits, _ or - (it names the file)")
	elif builtin_ids.has(id):
		problems.append("the id \"%s\" belongs to a built-in spread; give it another" % id)
	elif taken.has(id) and not (taken[id] == file and id == saved_id):
		problems.append("the id \"%s\" is already used in %s" % [id, taken[id]])
	return problems


## Saves into `folder`: back into the file it came from (other spreads in it are kept,
## the old id replaced), or as <id>.json. Returns "" or what went wrong.
func save(folder: String) -> String:
	var path: String = ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
	var file_name: String = file if file != "" else id + ".json"
	var target: String = path.path_join(file_name)
	var contents: Dictionary = {}
	if FileAccess.file_exists(target):
		var existing: Variant = JSON.parse_string(FileAccess.get_file_as_string(target))
		if existing is Dictionary:
			contents = existing
		else:
			return "%s is not a spreads file; not overwritten" % file_name
	# Keep the spread's place in the file when it is renamed.
	var rebuilt: Dictionary = {}
	var placed: bool = false
	for key: Variant in contents:
		if key == saved_id or key == id:
			if not placed:
				rebuilt[id] = to_data()
				placed = true
		else:
			rebuilt[key] = contents[key]
	if not placed:
		rebuilt[id] = to_data()
	var handle: FileAccess = FileAccess.open(target, FileAccess.WRITE)
	if handle == null:
		return "cannot write %s: %s" % [target, error_string(FileAccess.get_open_error())]
	handle.store_string(JSON.stringify(rebuilt, "\t", false) + "\n")
	handle.close()
	file = file_name
	saved_id = id
	return ""
