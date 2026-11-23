class_name AppSettings
extends RefCounted
## App preferences, saved as user://settings.json. LLM settings live separately in
## LlmConfig (user://llm.json). The settings screen comes in Milestone 5.

const DEFAULT_PATH := "user://settings.json"
const FIELDS: PackedStringArray = ["deck_folder", "deck", "export_folder", "ui_scale", "spread",
		"keep_history", "draw_mode", "notice_accepted"]
## The interface sizes Settings offers.
const UI_SCALES: Array[float] = [1.0, 1.25, 1.5, 1.75, 2.0]

## Where the decks live. "" means the default, DeckLibrary.default_folder().
var deck_folder: String = ""
## The selected deck's id (its folder name), or "" for the first one found.
var deck: String = ""
## The spread chosen last, by id, or "" for the first one.
var spread: String = ""
## Save every finished reading to the history (ReadingHistory).
var keep_history: bool = true
## "app": the app shuffles and deals. "own": the querent lays out their own cards and
## names each one.
var draw_mode: String = "app"
## Where the last reading was exported; "" means the Documents folder.
var export_folder: String = ""
## Interface size: 1.0 is the design size (text as at 1280x720); 1.5 for a high-DPI
## screen or bigger text. The window's minimum size grows with it.
var ui_scale: float = 1.0
## The version of the first-run notice the user agreed to (NoticeDialog.VERSION); 0 until
## they agree.
var notice_accepted: int = 0

var _path: String = DEFAULT_PATH


static func load_from(path: String = DEFAULT_PATH) -> AppSettings:
	var settings: AppSettings = AppSettings.new()
	settings._path = path
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			for field: String in FIELDS:
				if data.has(field):
					var value: Variant = data[field]
					if typeof(settings.get(field)) == TYPE_FLOAT:
						settings.set(field, float(value) if value is float or value is int else 1.0)
					elif typeof(settings.get(field)) == TYPE_INT:
						settings.set(field, int(value) if value is float or value is int else 0)
					elif typeof(settings.get(field)) == TYPE_BOOL:
						settings.set(field, value if value is bool else str(value).to_lower() in ["1", "true", "yes"])
					else:
						settings.set(field, str(value))
		else:
			push_warning("Ignoring unreadable %s" % path)
	return settings


func save() -> Error:
	var data: Dictionary = {}
	for field: String in FIELDS:
		data[field] = get(field)
	var file: FileAccess = FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


## The selected deck among `decks`: the saved one if it is there and valid,
## otherwise the first valid deck, otherwise null.
func pick_deck(decks: Array[DeckInfo]) -> DeckInfo:
	for candidate: DeckInfo in decks:
		if candidate.id == deck and candidate.is_valid():
			return candidate
	for candidate: DeckInfo in decks:
		if candidate.is_valid():
			return candidate
	return null
