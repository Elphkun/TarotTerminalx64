class_name ReadingSummary
extends RefCounted
## Everything the code knows about a reading, gathered for the LLM.
## The LLM receives these as facts; it never works out correspondences itself.

var question: String = ""
## From the classify call: life_area, timeframe, question_type.
var classification: Dictionary = {}
var spread_name: String = ""
## How long the reading should be ("700 to 1000"), from the spread.
var reading_words: String = Spread.DEFAULT_READING_WORDS
## [{ position (id), name (Spread.label), meaning, card (full data entry), dignity }]
var positions: Array[Dictionary] = []
var patterns: Dictionary = {}

var _db: CardDb


static func build(
		db: CardDb, spread: Spread, layout: Array[Dictionary],
		question_text: String, classified: Dictionary = {}
) -> ReadingSummary:
	var summary: ReadingSummary = ReadingSummary.new()
	summary._db = db
	summary.question = question_text
	summary.classification = classified
	summary.spread_name = spread.name
	summary.reading_words = spread.reading_words
	var dignities: Dictionary = Dignities.compute(spread, layout, db)
	for slot: Dictionary in layout:
		var position_id: String = slot["position"]["id"]
		summary.positions.append({
			"position": position_id,
			"name": Spread.label(slot["position"]),
			"meaning": slot["position"].get("meaning", ""),
			"card": db.card(slot["card"]),
			"dignity": dignities[position_id],
		})
	summary.patterns = SpreadPatterns.compute(layout, db)
	return summary


func to_dict() -> Dictionary:
	return {
		"question": question,
		"classification": classification,
		"spread": spread_name,
		"positions": positions,
		"patterns": patterns,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "  ", false)


## The compact text the reading prompt receives. GD rank names appear here
## (alongside the RWS name), never in the UI.
func to_prompt_text() -> String:
	var lines: PackedStringArray = []
	lines.append("Spread: %s" % spread_name)
	lines.append("")
	for i: int in positions.size():
		var entry: Dictionary = positions[i]
		var card: Dictionary = entry["card"]
		lines.append("Position %d (%s): %s" % [i + 1, entry["name"], entry["meaning"]])
		lines.append("  Card: %s" % card["name"])
		for line: String in _card_facts(card):
			lines.append("  " + line)
		lines.append("  Dignity: %s" % Dignities.describe(entry["dignity"]))
		var meanings: PackedStringArray = _meanings(card)
		if not meanings.is_empty():
			lines.append("  Author's notes: %s" % " | ".join(meanings))
		lines.append("")
	lines.append("Patterns:")
	for line: String in _pattern_lines():
		lines.append("  " + line)
	return "\n".join(lines)


func _card_facts(card: Dictionary) -> PackedStringArray:
	var facts: PackedStringArray = []
	match card["type"]:
		"trump":
			var letter: Dictionary = _db.hebrew_letter(card["hebrew_letter"])
			var attribution: Dictionary = card["attribution"]
			var line: String = "Trump %d, path %d, Hebrew letter %s (%s), %s %s" % [
				int(card["number"]), int(card["path"]), str(card["hebrew_letter"]).capitalize(),
				letter.get("meaning", ""), attribution["kind"], str(attribution["value"]).capitalize(),
			]
			if card.has("secondary_attribution"):
				line += " (also %s)" % str(card["secondary_attribution"]["value"]).capitalize()
			facts.append(line)
			facts.append("Path joins %s and %s" % [
				_sephira_label(card["connects"][0]), _sephira_label(card["connects"][1]),
			])
		"pip":
			var decan: Variant = card.get("decan")
			if decan == null:
				facts.append("Ace: the root of %s in %s" % [
					card["element"], _sephira_label(card["sephira"]),
				])
			else:
				facts.append("%s in %s; decan: %s in %s (%s degrees)" % [
					card["element"].capitalize(), _sephira_label(card["sephira"]),
					str(decan["planet"]).capitalize(), str(decan["sign"]).capitalize(), decan["degrees"],
				])
		"court":
			facts.append("GD %s: %s of %s" % [
				str(card["gd_rank"]).capitalize(), str(card["sub_element"]).capitalize(),
				card["element"],
			])
			if card.get("family_role") != null:
				facts.append("Family role: %s; throne: %s" % [
					str(card["family_role"]).capitalize(), _card_name(card.get("throne")),
				])
			var span: Variant = card.get("zodiac_span")
			if span != null:
				var ruled: Array = card.get("decans_ruled", [])
				facts.append("Rules from %s to %s, mainly %s (%s)" % [
					span["from"], span["to"], str(card.get("predominant_sign", "")).capitalize(),
					", ".join(PackedStringArray(ruled.map(_card_name))),
				])
			elif card.get("elemental_throne") is Dictionary:
				facts.append("No zodiac span: the element itself; elemental throne %s and %s" % [
					_card_name(card["elemental_throne"]["ace"]),
					_card_name(card["elemental_throne"]["trump"]),
				])
	facts.append("GD title: %s" % card["gd_title"])
	var element: Variant = card.get("dignity_element")
	facts.append("Element for dignities: %s" % ("none" if element == null else element))
	return facts


## Facts for the UI's correspondences panel. Same facts as the prompt, but no GD rank
## labels ("Earth of Fire", not "GD Princess"); GD titles are shown (author's decision).
func display_facts(card: Dictionary) -> PackedStringArray:
	var facts: PackedStringArray = []
	match card["type"]:
		"trump":
			var letter: Dictionary = _db.hebrew_letter(card["hebrew_letter"])
			var attribution: Dictionary = card["attribution"]
			var line: String = "%s %s" % [
				str(attribution["kind"]).capitalize(), str(attribution["value"]).capitalize()]
			if card.has("secondary_attribution"):
				line += " (also %s)" % str(card["secondary_attribution"]["value"]).capitalize()
			facts.append(line)
			facts.append("Path %d, %s %s (%s), joining %s and %s" % [
				int(card["path"]), letter.get("glyph", ""), str(card["hebrew_letter"]).capitalize(),
				letter.get("meaning", ""), _sephira_short(card["connects"][0]),
				_sephira_short(card["connects"][1])])
		"pip":
			var decan: Variant = card.get("decan")
			if decan == null:
				facts.append("Root of %s, in %s" % [card["element"], _sephira_short(card["sephira"])])
			else:
				facts.append("%s in %s" % [str(card["element"]).capitalize(), _sephira_short(card["sephira"])])
				facts.append("Decan: %s in %s, %s°" % [str(decan["planet"]).capitalize(),
						str(decan["sign"]).capitalize(), decan["degrees"]])
		"court":
			facts.append("%s of %s, the %s" % [str(card["sub_element"]).capitalize(),
					str(card["element"]).capitalize(), card.get("family_role", "")])
			var span: Variant = card.get("zodiac_span")
			if span != null:
				var ruled: Array = card.get("decans_ruled", [])
				facts.append("Rules %s to %s, mainly %s (%s)" % [span["from"], span["to"],
						str(card.get("predominant_sign", "")).capitalize(),
						", ".join(PackedStringArray(ruled.map(_card_name)))])
			elif card.get("elemental_throne") is Dictionary:
				facts.append("The element itself: %s and %s" % [
					_card_name(card["elemental_throne"]["ace"]),
					_card_name(card["elemental_throne"]["trump"])])
			if card.has("throne"):
				facts.append("Throne: %s" % _card_name(card["throne"]))
	facts.append("“%s”" % card["gd_title"])
	var element: Variant = card.get("dignity_element")
	facts.append("Element for dignities: %s" % ("none" if element == null else element))
	return facts


## The spread's patterns for the UI, without GD rank names.
func display_patterns() -> PackedStringArray:
	var lines: PackedStringArray = []
	var counts: PackedStringArray = []
	for element: String in patterns["elements"]:
		if element != "planetary" or patterns["elements"][element] > 0:
			counts.append("%s %d" % [element, patterns["elements"][element]])
	lines.append("Elements: %s" % ", ".join(counts))
	if not patterns["dominant_elements"].is_empty():
		lines.append("Dominant: %s" % ", ".join(PackedStringArray(patterns["dominant_elements"])))
	if not patterns["missing_elements"].is_empty():
		lines.append("Missing: %s" % ", ".join(PackedStringArray(patterns["missing_elements"])))
	var types: Dictionary = patterns["types"]
	lines.append("%d trumps, %d pips, %d courts" % [types["trump"], types["pip"], types["court"]])
	for repeat: Dictionary in patterns["repeated_ranks"]:
		lines.append("Number %d appears %d times" % [repeat["rank"], repeat["count"]])
	for repeat: Dictionary in patterns["repeated_courts"]:
		lines.append("%d %ss" % [repeat["count"], str(repeat["rws_rank"]).capitalize()])
	return lines


func _sephira_short(id: String) -> String:
	var sephira: Dictionary = _db.sephira(id)
	return "%s (%s)" % [id.capitalize(), sephira.get("title", "")]


func _card_name(id: Variant) -> String:
	return str(_db.by_id(str(id)).get("name", id))


func _sephira_label(id: String) -> String:
	var sephira: Dictionary = _db.sephira(id)
	return "%s (%d, %s)" % [id.capitalize(), int(sephira.get("number", 0)), sephira.get("title", "")]


func _meanings(card: Dictionary) -> PackedStringArray:
	var found: PackedStringArray = []
	var meanings: Dictionary = card.get("meanings", {})
	for key: String in ["personal", "gd", "waite"]:
		var text: String = str(meanings.get(key, "")).strip_edges()
		if text != "":
			found.append("%s: %s" % [key, text])
	var keywords: Array = card.get("keywords", [])
	if not keywords.is_empty():
		found.append("keywords: %s" % ", ".join(PackedStringArray(keywords)))
	return found


func _pattern_lines() -> PackedStringArray:
	var lines: PackedStringArray = []
	var counts: PackedStringArray = []
	for element: String in patterns["elements"]:
		counts.append("%s %d" % [element, patterns["elements"][element]])
	lines.append("Elements: %s" % ", ".join(counts))
	if not patterns["dominant_elements"].is_empty():
		lines.append("Dominant: %s" % ", ".join(PackedStringArray(patterns["dominant_elements"])))
	if not patterns["missing_elements"].is_empty():
		lines.append("Missing: %s" % ", ".join(PackedStringArray(patterns["missing_elements"])))
	var types: Dictionary = patterns["types"]
	lines.append("Card types: %d trumps, %d pips, %d courts" % [
		types["trump"], types["pip"], types["court"],
	])
	for repeat: Dictionary in patterns["repeated_ranks"]:
		lines.append("Repeated number: %d x rank %d (%s)" % [
			repeat["count"], repeat["rank"], ", ".join(PackedStringArray(repeat["positions"])),
		])
	for repeat: Dictionary in patterns["repeated_courts"]:
		lines.append("Repeated court rank: %d x %s (%s)" % [
			repeat["count"], repeat["rws_rank"], ", ".join(PackedStringArray(repeat["positions"])),
		])
	for court: Dictionary in patterns["courts"]:
		lines.append("Court in %s: %s (GD %s, %s of %s)" % [
			court["position"], court["name"], court["gd_rank"], court["sub_element"],
			court["element"],
		])
	var ill: PackedStringArray = []
	for entry: Dictionary in positions:
		if entry["dignity"]["state"] == Dignities.ILL:
			ill.append("%s in %s" % [entry["card"]["name"], entry["name"]])
	lines.append("Ill-dignified cards: %s" % ("none" if ill.is_empty() else ", ".join(ill)))
	return lines
