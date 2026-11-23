class_name ReadingExport
extends RefCounted
## A finished reading as a plain Markdown file: the question, the deal (one line per
## position), the reading as the model wrote it, then the dignities and patterns.
## UI wording: RWS names, no GD rank labels (GD titles appear only in the panel).


## `details` may hold: date (String), deck (String), model (String), cards (String:
## "own" for the querent's own deck, "picked" for cards chosen face down from the fan).
static func to_markdown(summary: ReadingSummary, reading: String, details: Dictionary = {}) -> String:
	var lines: PackedStringArray = []
	lines.append("# %s" % _one_line(summary.question))
	lines.append("")
	var facts: PackedStringArray = []
	for key: String in ["date", "spread", "deck", "cards", "model"]:
		var value: String = summary.spread_name if key == "spread" else str(details.get(key, ""))
		if key == "cards":
			value = {"own": "your own, laid out by hand", "picked": "picked face down from the deck"}.get(value, "")
		if value != "":
			facts.append("**%s:** %s" % [key.capitalize(), value])
	lines.append("  \n".join(facts))
	lines.append("")

	lines.append("## The deal")
	lines.append("")
	for i: int in summary.positions.size():
		var entry: Dictionary = summary.positions[i]
		lines.append("%d. **%s:** %s (%s)" % [i + 1, Spread.title(entry["name"]),
				entry["card"]["name"], entry["dignity"]["state"]])
	lines.append("")

	lines.append("## The reading")
	lines.append("")
	lines.append(reading.strip_edges())
	lines.append("")

	lines.append("## Dignities")
	lines.append("")
	for entry: Dictionary in summary.positions:
		lines.append("- **%s** (%s): %s" % [entry["card"]["name"], entry["name"],
				Dignities.describe(entry["dignity"])])
	lines.append("")
	lines.append("## Patterns")
	lines.append("")
	for line: String in summary.display_patterns():
		lines.append("- %s" % line)
	return "\n".join(lines) + "\n"


## "2026-11-19 should-i-take-the-job.md": the date, then the question's first words.
static func file_name(question: String, date: String) -> String:
	var words: PackedStringArray = []
	for word: String in question.to_lower().split(" ", false):
		var clean: String = ""
		for character: String in word:
			if (character >= "a" and character <= "z") or (character >= "0" and character <= "9"):
				clean += character
		if clean != "":
			words.append(clean)
		if words.size() == 6:
			break
	var slug: String = "-".join(words)
	return "%s %s.md" % [date, slug if slug != "" else "reading"]


static func save(path: String, text: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


static func _one_line(text: String) -> String:
	return " ".join(text.strip_edges().split("\n", false))
