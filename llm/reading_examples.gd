class_name ReadingExamples
extends RefCounted
## The few-shot example readings sent with every reading (prompts/read_examples.txt):
## up to LIMIT entries, separated by a line holding only "---". The Example readings
## dialog edits them. In an exported build res:// is read-only, so they go to user://.

const PROJECT_PATH := "res://prompts/read_examples.txt"
const EXPORTED_PATH := "user://read_examples.txt"
const PLACEHOLDER := "[PLACEHOLDER]"
const SEPARATOR := "---"
## Each example costs prompt tokens on every reading; three is plenty for style.
const LIMIT: int = 3


## Where examples are read from and saved to.
static func default_path() -> String:
	return PROJECT_PATH if OS.has_feature("editor") else EXPORTED_PATH


## The examples text for the prompt, or "" when there are none.
static func load_text(path: String = default_path()) -> String:
	return ("\n\n%s\n\n" % SEPARATOR).join(entries(path))


## The saved examples, one string each. A missing, empty or placeholder file has none.
static func entries(path: String = default_path()) -> PackedStringArray:
	# An exported build has no user copy until the first save: start from the bundled file.
	if path == EXPORTED_PATH and not FileAccess.file_exists(path):
		path = PROJECT_PATH
	if not FileAccess.file_exists(path):
		return PackedStringArray()
	var text: String = FileAccess.get_file_as_string(path).replace("\r\n", "\n").strip_edges()
	if text.begins_with(PLACEHOLDER):
		return PackedStringArray()
	var found: PackedStringArray = []
	var current: PackedStringArray = []
	for line: String in (text + "\n" + SEPARATOR).split("\n"):
		if line.strip_edges() == SEPARATOR:
			var entry: String = "\n".join(current).strip_edges()
			if entry != "":
				found.append(entry)
			current.clear()
		else:
			current.append(line)
	return found


static func count(path: String = default_path()) -> int:
	return entries(path).size()


## Writes the examples, dropping empty ones. Refuses more than LIMIT.
static func save_entries(list: PackedStringArray, path: String = default_path()) -> Error:
	var kept: PackedStringArray = []
	for entry: String in list:
		if entry.strip_edges() != "":
			kept.append(entry.strip_edges())
	if kept.size() > LIMIT:
		return ERR_INVALID_PARAMETER
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(("\n\n%s\n\n" % SEPARATOR).join(kept) + ("\n" if not kept.is_empty() else ""))
	file.close()
	return OK


## A short name for an entry: its question, or its first line.
static func title(entry: String) -> String:
	var first: String = entry.strip_edges().get_slice("\n", 0).strip_edges()
	first = first.trim_prefix("Question:").strip_edges()
	return first if first != "" else "(empty)"


## A finished reading as an example for the author to edit: the question, one line per
## card with its dignity, then the reading.
static func draft(summary: ReadingSummary, reading: String) -> String:
	var cards: PackedStringArray = []
	for entry: Dictionary in summary.positions:
		cards.append("%s %s (%s)" % [
				str(entry["name"]), str(entry["card"]["name"]), str(entry["dignity"]["state"])])
	return "Question: %s\nCards: %s\n\n%s" % [
			summary.question.strip_edges(), ", ".join(cards), reading.strip_edges()]
