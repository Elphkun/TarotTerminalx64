class_name ReadingHistory
extends RefCounted
## Finished readings, one JSON file each in user://history/, so they can be reopened,
## exported again or deleted later. A record keeps the spread's whole definition, so a
## reading from an added spread whose file has gone still reopens. Correspondences,
## dignities and patterns are not stored: they are worked out again from the cards when
## a reading is reopened, as for a new one.
##
## Record: {version, date, question, classification, spread: {id, data}, layout:
## [{position, card}], draw ("app" or "own"), deck, model, reading, critique}

const DEFAULT_FOLDER := "user://history"
const VERSION: int = 1
## How many characters of the reading a list entry previews.
const PREVIEW_LENGTH: int = 240


## The record for a finished reading. `extra` adds or overrides fields (deck, draw).
static func record_from(session: ReadingSession, spread_data: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var layout: Array = []
	for entry: Dictionary in session.layout:
		layout.append({"position": str(entry["position"].get("id", "")), "card": int(entry["card"])})
	var record: Dictionary = {
		"version": VERSION,
		"date": session.finished_at,
		"question": session.question,
		"classification": session.classification,
		"spread": {"id": session.spread.id, "data": spread_data},
		"layout": layout,
		"draw": session.draw,
		"deck": session.reading_deck,
		"model": session.reading_model,
		"reading": session.reading_text,
		"critique": session.critique_verdict,
	}
	record.merge(extra, true)
	return record


## Writes `record` to `path`, or to a new file in `folder` named after its date and
## question. Returns the path written, or "" on failure.
static func save(record: Dictionary, folder: String = DEFAULT_FOLDER, path: String = "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var stem: String = ReadingExport.file_name(str(record.get("question", "")),
				str(record.get("date", "")).replace(":", "")).get_basename()
		path = folder.path_join(stem + ".json")
		var n: int = 2
		while FileAccess.file_exists(path):
			path = folder.path_join("%s (%d).json" % [stem, n])
			n += 1
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(record, "\t"))
	file.close()
	return path


## Every saved reading, newest first: {path, date, spread_name, question, preview}.
static func list(folder: String = DEFAULT_FOLDER) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var absolute: String = ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(absolute):
		return found
	for file: String in DirAccess.get_files_at(absolute):
		if file.get_extension().to_lower() != "json":
			continue
		var path: String = folder.path_join(file)
		var record: Dictionary = load_record(path)
		if record.is_empty():
			continue
		var spread: Dictionary = record.get("spread", {})
		var spread_data: Dictionary = spread.get("data", {}) if spread.get("data") is Dictionary else {}
		found.append({
			"path": path,
			"date": str(record.get("date", "")),
			"spread_name": str(spread_data.get("name", spread.get("id", ""))),
			"question": str(record.get("question", "")),
			"preview": _preview(str(record.get("reading", ""))),
		})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["date"] > b["date"] if a["date"] != b["date"] else a["path"] > b["path"])
	return found


## The record in `path`, or {} if it is missing or not a reading.
static func load_record(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		return {}
	var record: Dictionary = json.data
	if not record.get("layout") is Array or not record.get("spread") is Dictionary:
		return {}
	return record


static func delete(path: String) -> Error:
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## The reading's first words, as plain text on one line.
static func _preview(reading: String) -> String:
	var plain: String = reading.replace("**", "").replace("#", "").replace("\r", "")
	plain = " ".join(plain.split("\n", false)).strip_edges()
	return plain if plain.length() <= PREVIEW_LENGTH else plain.left(PREVIEW_LENGTH).strip_edges() + "…"
