class_name CardDb
extends RefCounted
## Card, correspondence and spread data loaded from data/*.json.
## Read-only after load. Use `CardDb.load_default()` or `load_from(dir)`.

const DEFAULT_DIR := "res://data"
const LOCAL_MEANINGS := "res://local/meanings.json"
const MEANING_FIELDS: PackedStringArray = ["waite", "gd", "personal"]

var cards: Array[Dictionary] = []
var correspondences: Dictionary = {}
var spreads: Dictionary = {}
## The ids of the spreads in data/spreads.json, in order; any others were added.
var builtin_spread_ids: PackedStringArray = []
## Problems found while loading. Empty means the data loaded cleanly.
var errors: Array[String] = []
## How many cards took meanings from the author's local file.
var meanings_loaded: int = 0

var _by_id: Dictionary = {}
var _relations: Dictionary = {}


## The shipped data plus the author's local meanings, if there are any.
static func load_default() -> CardDb:
	var db: CardDb = load_from(DEFAULT_DIR)
	db.load_local_meanings(local_meanings_path())
	return db


## The user's own card meanings live outside the shipped data: local/meanings.json in
## the project, or next to the executable in an exported build. Git-ignored and never
## exported (docs/card_meanings.md).
static func local_meanings_path() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path(LOCAL_MEANINGS)
	return OS.get_executable_path().get_base_dir().path_join("local/meanings.json")


## Overlays meanings from `path` ({index: {waite, gd, personal}}) if the file exists.
## Returns how many cards it changed.
func load_local_meanings(path: String) -> int:
	if not FileAccess.file_exists(path):
		return 0
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		errors.append("%s: not a JSON object" % path)
		return 0
	return apply_meanings(data)


## Overlays meanings ({index: {waite, gd, personal}}): only the listed fields change.
func apply_meanings(data: Dictionary) -> int:
	var changed: int = 0
	for key: Variant in data:
		var index: int = int(str(key)) if str(key).is_valid_int() else -1
		if not CardIndex.is_valid(index) or not data[key] is Dictionary:
			errors.append("local meanings: bad entry '%s'" % key)
			continue
		var meanings: Dictionary = cards[index].get("meanings", {})
		for field: String in MEANING_FIELDS:
			if data[key].has(field):
				meanings[field] = str(data[key][field])
		cards[index]["meanings"] = meanings
		changed += 1
	meanings_loaded += changed
	return changed


static func load_from(dir: String) -> CardDb:
	var db: CardDb = CardDb.new()
	db._load(dir)
	return db


func card(index: int) -> Dictionary:
	assert(CardIndex.is_valid(index), "card index out of range: %d" % index)
	return cards[index]


func by_id(id: String) -> Dictionary:
	return _by_id.get(id, {})


func spread(id: String) -> Dictionary:
	return spreads.get(id, {})


## Replaces the added spreads with the usable ones of `entries` (from SpreadLibrary.scan),
## after the built-in ones. Returns how many were added.
func set_added_spreads(entries: Array[Dictionary]) -> int:
	var kept: Dictionary = {}
	for spread_id: String in builtin_spread_ids:
		kept[spread_id] = spreads[spread_id]
	var added: int = 0
	for entry: Dictionary in entries:
		if (entry["errors"] as PackedStringArray).is_empty() and not kept.has(entry["id"]):
			kept[entry["id"]] = entry["data"]
			added += 1
	spreads = kept
	return added


## "same", "friendly", "contrary", or "" when either element is missing
## or the pair is not in the dignities table.
func relation(a: Variant, b: Variant) -> String:
	if a == null or b == null:
		return ""
	if a == b:
		return "same"
	return _relations.get(_pair_key(str(a), str(b)), "")


## The score a relation adds, from correspondences.dignity_weights.
func dignity_weight(relation_name: String) -> int:
	var weights: Dictionary = correspondences.get("dignity_weights", {})
	return int(weights.get(relation_name, 0))


func sephira(id: String) -> Dictionary:
	for entry: Dictionary in correspondences.get("sephiroth", []):
		if entry["id"] == id:
			return entry
	return {}


func hebrew_letter(id: String) -> Dictionary:
	for entry: Dictionary in correspondences.get("hebrew_letters", []):
		if entry["id"] == id:
			return entry
	return {}


func _load(dir: String) -> void:
	var card_data: Variant = _read_json(dir.path_join("cards.json"))
	correspondences = _as_dict(_read_json(dir.path_join("correspondences.json")))
	spreads = _as_dict(_read_json(dir.path_join("spreads.json")))
	builtin_spread_ids = PackedStringArray(spreads.keys())

	cards.resize(CardIndex.DECK_SIZE)
	if card_data is Dictionary:
		for key: String in card_data:
			var entry: Dictionary = card_data[key]
			var index: int = int(entry.get("index", -1))
			if not key.is_valid_int() or int(key) != index or not CardIndex.is_valid(index):
				errors.append("cards.json: key '%s' does not match index %d" % [key, index])
				continue
			cards[index] = entry
			_by_id[entry.get("id", "")] = entry
	for index: int in CardIndex.DECK_SIZE:
		if cards[index].is_empty():
			errors.append("cards.json: no entry for index %d" % index)

	var table: Dictionary = correspondences.get("dignities", {})
	for kind: String in ["friendly", "contrary"]:
		for pair: Array in table.get(kind, []):
			_relations[_pair_key(pair[0], pair[1])] = kind


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("missing %s" % path)
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		errors.append("%s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _as_dict(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]
