extends RefCounted
## What code can check about a finished reading, for comparing models (tools/compare.gd).
## It can't judge how good a reading is: only whether it did what the prompt asks.

const RANKS := "Ace|Two|Three|Four|Five|Six|Seven|Eight|Nine|Ten|Page|Knight|Queen|King"
const SUITS := "Wands|Cups|Swords|Pentacles"
## Words of a refusal, or of the harm rule, in a reading of a harmless question.
const REFUSAL := "(?i)never counsel|crisis line|what lies behind this|better way through|" \
		+ "brought you here|cannot answer|can't answer|as an ai\\b"


## {problems: PackedStringArray, words: int, passed: int, checks: int}
static func check(summary: ReadingSummary, reading: String) -> Dictionary:
	var problems: PackedStringArray = []
	var checks: int = 0
	var text: String = reading.strip_edges()

	checks += 1
	var headed: int = 0
	for i: int in summary.positions.size():
		if RegEx.create_from_string("(?m)^\\W*%d\\s*[.:)]" % (i + 1)).search(text) != null:
			headed += 1
	if headed < summary.positions.size():
		problems.append("%d of %d positions headed" % [headed, summary.positions.size()])

	checks += 1
	var missing: PackedStringArray = _not_named(summary.positions, text, "")
	if not missing.is_empty():
		problems.append("not named: %s" % ", ".join(missing))

	checks += 1
	var at: int = text.rfind("Synthesis")
	if at < 0:
		problems.append("no synthesis")

	checks += 1
	var ignored: PackedStringArray = _not_named(summary.positions, text.substr(at) if at >= 0 else "", Dignities.ILL)
	if not ignored.is_empty():
		problems.append("ill-dignified, not in the synthesis: %s" % ", ".join(ignored))

	checks += 1
	var invented: PackedStringArray = invented_cards(summary, text)
	if not invented.is_empty():
		problems.append("cards not in the spread: %s" % ", ".join(invented))

	checks += 1
	var wrong: PackedStringArray = dignity_errors(summary, text)
	if not wrong.is_empty():
		problems.append("wrong dignity: %s" % "; ".join(wrong))

	checks += 1
	if RegEx.create_from_string("(?i)\\breversed\\b").search(text) != null:
		problems.append("speaks of a reversed card")

	checks += 1
	var refusal: RegExMatch = RegEx.create_from_string(REFUSAL).search(text)
	if refusal != null:
		problems.append("a refusal in it (\"%s\")" % refusal.get_string())

	checks += 1
	var words: int = text.replace("\n", " ").split(" ", false).size()
	var asked: PackedInt32Array = word_range(summary.reading_words)
	if words < asked[0] * 0.7 or words > asked[1] * 1.3:
		problems.append("%d words, asked for %s" % [words, summary.reading_words])

	if str(summary.classification.get("question_type", "")) == "yes_no":
		checks += 1
		# In bold anywhere in the synthesis, or plainly near the end: some go on after the answer.
		if RegEx.create_from_string("(?i)\\*\\*[^*\\n]{0,40}\\b(yes|no|not yet)\\b").search(
				text.substr(maxi(at, 0))) == null \
				and RegEx.create_from_string("(?i)\\b(yes|not yet)\\b|\\bno\\b(?=\\s*[.,:;!*—-])|\\bis[ *]+no\\b").search(
				text.right(700)) == null:
			problems.append("no clear yes, no or not yet")
	return {"problems": problems, "words": words, "passed": checks - problems.size(), "checks": checks}


## Minor cards named in `text` that the spread doesn't hold. Trumps are left out: "the Sun"
## and "strength" are also ordinary words in a reading.
static func invented_cards(summary: ReadingSummary, text: String) -> PackedStringArray:
	var held: PackedStringArray = []
	for entry: Dictionary in summary.positions:
		held.append(str(entry["card"]["name"]))
	var found: PackedStringArray = []
	for hit: RegExMatch in RegEx.create_from_string("\\b(%s) of (%s)\\b" % [RANKS, SUITS]).search_all(text):
		var card: String = hit.get_string()
		if not held.has(card) and not found.has(card):
			found.append(card)
	return found


## Sentences that call a card well- or ill-dignified when it is not. In a position's own
## section that is its card, unless another is named; elsewhere the one card named.
## Sentences with several cards, or a "not", are left alone: too easy to misjudge.
static func dignity_errors(summary: ReadingSummary, text: String) -> PackedStringArray:
	var found: PackedStringArray = []
	var heading: RegEx = RegEx.create_from_string("^\\W*(?:Position\\s+)?(\\d+)\\s*[.:)]")
	var split: RegEx = RegEx.create_from_string("[^.!?;:]+")
	var section: int = -1
	for line: String in text.split("\n"):
		var head: RegExMatch = heading.search(line)
		if head != null:
			section = head.get_string(1).to_int() - 1
			line = line.substr(head.get_end())
		elif line.contains("Synthesis") and line.strip_edges().length() < 40:
			section = -1
		for part: RegExMatch in split.search_all(line):
			var entry: Dictionary = _dignity_said(summary, part.get_string(), section)
			if entry.is_empty():
				continue
			var state: String = entry["entry"]["dignity"]["state"]
			var truth: String = {Dignities.WELL: "well", Dignities.ILL: "ill"}.get(state, "neutral")
			if entry["says"] != truth:
				found.append("%s called %s, is %s" % [entry["entry"]["card"]["name"], entry["says"], truth])
	return found


## The card a sentence gives a dignity to, and which: {entry, says}, or {} when unclear.
static func _dignity_said(summary: ReadingSummary, sentence: String, section: int) -> Dictionary:
	var called: Array[RegExMatch] = RegEx.create_from_string("(?i)\\b(well|ill)[- ]dignified").search_all(sentence)
	if called.size() != 1 or RegEx.create_from_string("(?i)\\b(not|neither|nor|unlike|rather than|if|were|every|each|all|both|any|no|other|others|neighbou?rs?|cards|dignities)\\b|n't").search(sentence) != null:
		return {}
	var named: Array[Dictionary] = []
	for entry: Dictionary in summary.positions:
		if RegEx.create_from_string("\\b%s\\b" % str(entry["card"]["name"])).search(sentence) != null:
			named.append(entry)
	if named.size() > 1:
		return {}
	var own: Dictionary = summary.positions[section] if section >= 0 and section < summary.positions.size() else {}
	# "This card is ill-dignified in relation to The Empress": not plain which is meant.
	if not own.is_empty() and not named.is_empty() and named[0] != own:
		return {}
	# Elsewhere than in a section, a sentence that names no card could mean any.
	if named.is_empty() and own.is_empty():
		return {}
	var entry: Dictionary = named[0] if not named.is_empty() else own
	return {"entry": entry, "says": called[0].get_string(1).to_lower()}


## "300 to 500" -> [300, 500].
static func word_range(asked: String) -> PackedInt32Array:
	var numbers: PackedInt32Array = []
	for hit: RegExMatch in RegEx.create_from_string("\\d+").search_all(asked.replace(",", "")):
		numbers.append(hit.get_string().to_int())
	if numbers.is_empty():
		return PackedInt32Array([0, 100000])
	return PackedInt32Array([numbers[0], numbers[numbers.size() - 1]])


## The cards (in the dignity `state`, or any for "") that `text` doesn't name.
static func _not_named(positions: Array, text: String, state: String) -> PackedStringArray:
	var missing: PackedStringArray = []
	var lower: String = text.to_lower()
	for entry: Dictionary in positions:
		if state != "" and entry["dignity"]["state"] != state:
			continue
		var card: String = str(entry["card"]["name"])
		if not lower.contains(card.to_lower().trim_prefix("the ")):
			missing.append(card)
	return missing
