extends SceneTree
## Checks data/*.json and writes the verification table for checking against Hulse.
##
## Usage: godot --headless --script tools/verify_data.gd
##
## Quits with 0 when every structural check passes, 1 otherwise. Either way the
## table is printed and written to docs/verification.md.

const OUTPUT_PATH := "res://docs/verification.md"

const REQUIRED_COMMON: PackedStringArray = [
	"id", "index", "type", "name", "gd_title", "dignity_element", "meanings", "keywords",
]
const REQUIRED_BY_TYPE: Dictionary = {
	"trump": ["number", "path", "hebrew_letter", "attribution", "connects"],
	"pip": ["suit", "rank", "sephira", "element", "decan"],
	"court": ["suit", "rws_rank", "gd_rank", "element", "sub_element", "zodiac_span"],
}

var _problems: Array[String] = []
var _db: CardDb


func _init() -> void:
	_db = CardDb.load_from(CardDb.DEFAULT_DIR)
	_problems.append_array(_db.errors)
	if _db.errors.is_empty():
		_check()

	var report: String = _report()
	print(report)
	var file: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		print("Could not write %s" % OUTPUT_PATH)
	else:
		file.store_string(report)
		file.close()
		print("Wrote %s" % ProjectSettings.globalize_path(OUTPUT_PATH))

	if _problems.is_empty():
		print("All checks passed.")
	else:
		for problem: String in _problems:
			print("PROBLEM  %s" % problem)
		print("%d problem(s)." % _problems.size())
	quit(0 if _problems.is_empty() else 1)


func _check() -> void:
	var corr: Dictionary = _db.correspondences
	var elements: Dictionary = corr.get("elements", {})
	var signs: Dictionary = {}
	for sign_entry: Dictionary in corr.get("signs", []):
		signs[sign_entry["id"]] = sign_entry
	var planets: Array = corr.get("planets", [])

	var ids: Dictionary = {}
	var paths: Dictionary = {}
	var letters: Dictionary = {}
	var decans: Dictionary = {}
	var hulse_paths: Dictionary = {}

	for card: Dictionary in _db.cards:
		var label: String = "%d %s" % [int(card.get("index", -1)), card.get("name", "?")]
		for field: String in REQUIRED_COMMON:
			_require(card.has(field), "%s: missing '%s'" % [label, field])
		var type: String = card.get("type", "")
		_require(REQUIRED_BY_TYPE.has(type), "%s: unknown type '%s'" % [label, type])
		for field: String in REQUIRED_BY_TYPE.get(type, []):
			_require(card.has(field), "%s: missing '%s'" % [label, field])
		if not REQUIRED_BY_TYPE.has(type):
			continue

		var id: String = card.get("id", "")
		_require(not ids.has(id), "%s: duplicate id '%s'" % [label, id])
		ids[id] = true

		var de: Variant = card.get("dignity_element")
		_require(de == null or (elements.has(de) and elements[de].get("suit") != null),
				"%s: dignity_element '%s' is not a suit element" % [label, de])
		var meanings: Dictionary = card.get("meanings", {})
		for key: String in ["waite", "gd", "personal"]:
			_require(meanings.has(key), "%s: meanings.%s missing" % [label, key])

		var index: int = int(card["index"])
		match type:
			"trump":
				_require(CardIndex.is_trump(index), "%s: trump outside 0-21" % label)
				_require(int(card["number"]) == index, "%s: number != index" % label)
				var path: int = int(card["path"])
				_require(not paths.has(path), "%s: path %d used twice" % [label, path])
				paths[path] = true
				var letter_id: String = card["hebrew_letter"]
				_require(not letters.has(letter_id), "%s: letter %s used twice" % [label, letter_id])
				letters[letter_id] = true
				var letter: Dictionary = _db.hebrew_letter(letter_id)
				_require(not letter.is_empty(), "%s: unknown letter %s" % [label, letter_id])
				_require(int(letter.get("path", -1)) == path,
						"%s: letter %s is on path %s in correspondences, card says %d" % [
							label, letter_id, letter.get("path"), path])
				var attribution: Dictionary = card["attribution"]
				match attribution.get("kind"):
					"element":
						_require(elements.has(attribution["value"]), "%s: unknown element" % label)
						_require(de == attribution["value"],
								"%s: elemental trump with dignity_element %s" % [label, de])
					"sign":
						_require(signs.has(attribution["value"]), "%s: unknown sign" % label)
						_require(de == signs.get(attribution["value"], {}).get("element"),
								"%s: dignity_element differs from the sign's element" % label)
					"planet":
						_require(planets.has(attribution["value"]), "%s: unknown planet" % label)
						var planet_element: Variant = corr.get("planet_elements", {}).get(
								attribution["value"])
						_require(de == null or de == planet_element,
								"%s: dignity_element %s differs from planet_elements (%s)" % [
									label, de, planet_element])
					_:
						_problems.append("%s: bad attribution kind" % label)
				for sephira: String in card["connects"]:
					_require(not _db.sephira(sephira).is_empty(),
							"%s: unknown sephira %s" % [label, sephira])
			"pip":
				var rank: int = int(card["rank"])
				_require(CardIndex.pip(card["suit"], rank) == index,
						"%s: index does not match suit/rank" % label)
				_require(_db.sephira(card["sephira"]).get("number", -1) == float(rank),
						"%s: sephira %s is not number %d" % [label, card["sephira"], rank])
				_check_suit_element(card, label, elements)
				var decan: Variant = card["decan"]
				if rank == 1:
					_require(decan == null, "%s: Ace has a decan" % label)
				else:
					_require(decan != null, "%s: no decan" % label)
					if decan != null:
						_require(signs.has(decan["sign"]), "%s: unknown decan sign" % label)
						_require(planets.has(decan["planet"]), "%s: unknown decan planet" % label)
						_require(signs.get(decan["sign"], {}).get("element") == card["element"],
								"%s: decan sign not of the suit's element" % label)
						var key: String = "%s %s" % [decan["sign"], decan["degrees"]]
						_require(not decans.has(key), "%s: decan %s used twice" % [label, key])
						decans[key] = true
			"court":
				_require(CardIndex.court(card["suit"], card["rws_rank"]) == index,
						"%s: index does not match suit/rank" % label)
				_check_suit_element(card, label, elements)
				var rank_info: Dictionary = corr.get("court_ranks", {}).get(card["rws_rank"], {})
				_require(rank_info.get("gd_rank") == card["gd_rank"],
						"%s: gd_rank does not follow court_ranks" % label)
				_require(rank_info.get("element") == card["sub_element"],
						"%s: sub_element does not follow court_ranks" % label)
				_require((card["zodiac_span"] == null) == (card["gd_rank"] == "princess"),
						"%s: only Princesses (Pages) lack a zodiac span" % label)
				_check_court_hulse(card, label, rank_info, hulse_paths)

	_require(paths.size() == 22, "expected 22 trump paths, found %d" % paths.size())
	_require(decans.size() == 36, "expected 36 distinct decans, found %d" % decans.size())
	_require(hulse_paths.size() == 16, "expected 16 distinct court paths, found %d" % hulse_paths.size())
	for planet: String in planets:
		_require(elements.has(corr.get("planet_elements", {}).get(planet, "")),
				"planet_elements has no element for %s" % planet)
	for check: Array in [[28, "Seven of Wands"], [32, "Page of Wands"], [36, "Ace of Cups"], [50, "Ace of Swords"],
			[77, "King of Pentacles"], [8, "Strength"], [11, "Justice"]]:
		_require(_db.card(check[0])["name"] == check[1],
				"index %d should be %s" % [check[0], check[1]])
	var weights: Dictionary = corr.get("dignity_weights", {})
	for key: String in ["same", "friendly", "contrary"]:
		_require(weights.has(key), "dignity_weights.%s missing" % key)


## The court fields taken from Hulse: family role, throne, decans ruled, invisible path.
func _check_court_hulse(
		card: Dictionary, label: String, rank_info: Dictionary, hulse_paths: Dictionary
) -> void:
	for field: String in ["family_role", "throne", "hulse_path", "predominant_sign", "decans_ruled",
			"gd_title_elemental"]:
		_require(card.has(field), "%s: missing '%s'" % [label, field])
	_require(card.get("family_role") == rank_info.get("family_role"),
			"%s: family_role does not follow court_ranks" % label)
	_require(card.get("throne") == "%s_%d" % [card["suit"], int(rank_info.get("throne_rank", 0))],
			"%s: throne is not the suit's %s card" % [label, rank_info.get("throne_rank")])

	var path: Dictionary = card.get("hulse_path", {})
	var number: int = int(path.get("number", 0))
	_require(number >= 33 and number <= 48, "%s: court path %d outside 33-48" % [label, number])
	_require(not hulse_paths.has(number), "%s: court path %d used twice" % [label, number])
	hulse_paths[number] = true
	if path.get("connects") != null:
		for sephira: String in path["connects"]:
			_require(not _db.sephira(sephira).is_empty(), "%s: unknown sephira %s" % [label, sephira])

	var span: Variant = card["zodiac_span"]
	if span == null:
		var throne: Dictionary = card.get("elemental_throne", {})
		_require(_db.by_id(throne.get("ace", "")).get("rank") == 1.0
				and _db.by_id(throne.get("ace", "")).get("suit") == card["suit"],
				"%s: elemental_throne.ace is not this suit's Ace" % label)
		var trump: Dictionary = _db.by_id(throne.get("trump", ""))
		_require(trump.get("dignity_element") == card["element"],
				"%s: elemental_throne.trump %s is not of %s" % [label, throne.get("trump"), card["element"]])
		_require(_db.by_id(card.get("archetype_trump", "")).get("type") == "trump",
				"%s: archetype_trump is not a trump" % label)
		return
	# A court rules the last decan of its first sign and the first two of the next.
	var first: String = str(span["from"]).get_slice(" ", 1)
	var second: String = str(span["to"]).get_slice(" ", 1)
	_require(card.get("predominant_sign") == second,
			"%s: predominant_sign should be %s" % [label, second])
	var expected: Array = [[first, "20-30"], [second, "0-10"], [second, "10-20"]]
	var ruled: Array = card.get("decans_ruled", [])
	_require(ruled.size() == 3, "%s: decans_ruled needs 3 cards" % label)
	for i: int in mini(ruled.size(), 3):
		var decan: Variant = _db.by_id(ruled[i]).get("decan")
		_require(decan is Dictionary and decan["sign"] == expected[i][0]
				and decan["degrees"] == expected[i][1],
				"%s: decans_ruled[%d] %s is not %s %s" % [label, i, ruled[i], expected[i][0], expected[i][1]])


func _check_suit_element(card: Dictionary, label: String, elements: Dictionary) -> void:
	_require(elements.get(card["element"], {}).get("suit") == card["suit"],
			"%s: element %s is not the element of %s" % [label, card["element"], card["suit"]])


func _require(condition: bool, problem: String) -> void:
	if not condition:
		_problems.append(problem)


func _report() -> String:
	var lines: PackedStringArray = []
	lines.append("# Data verification table")
	lines.append("")
	lines.append("Generated by `tools/verify_data.gd` from `data/`. Check each row against Hulse.")
	lines.append("Regenerate after editing the data: `godot --headless --script tools/verify_data.gd`.")
	lines.append("")
	lines.append("## Trumps")
	lines.append("")
	lines.append("| # | Card | Path | Letter | Attribution | Connects | GD title | Dignity element |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for card: Dictionary in _db.cards:
		if card.get("type") != "trump":
			continue
		var letter: Dictionary = _db.hebrew_letter(card["hebrew_letter"])
		var attribution: String = "%s: %s" % [card["attribution"]["kind"], card["attribution"]["value"]]
		if card.has("secondary_attribution"):
			attribution += " (also %s)" % card["secondary_attribution"]["value"]
		lines.append("| %d | %s | %d | %s %s (%d) | %s | %s–%s | %s | %s |" % [
			int(card["index"]), card["name"], int(card["path"]), letter.get("glyph", ""),
			card["hebrew_letter"], int(letter.get("value", 0)), attribution,
			card["connects"][0], card["connects"][1], card["gd_title"], _el(card),
		])
	for suit: String in CardIndex.SUITS:
		lines.append("")
		lines.append("## %s" % suit.capitalize())
		lines.append("")
		lines.append("| # | Card | Sephira / GD rank | Decan / zodiac span | GD title | Dignity element |")
		lines.append("|---|---|---|---|---|---|")
		for card: Dictionary in _db.cards:
			if card.get("suit") != suit:
				continue
			var where: String
			var when: String
			if card["type"] == "pip":
				where = "%d %s" % [int(card["rank"]), card["sephira"]]
				var decan: Variant = card["decan"]
				when = "—" if decan == null else "%s in %s %s°" % [
					decan["planet"], decan["sign"], decan["degrees"]]
			else:
				where = "%s (%s of %s)" % [card["gd_rank"], card["sub_element"], card["element"]]
				var span: Variant = card["zodiac_span"]
				when = "—" if span == null else "%s → %s" % [span["from"], span["to"]]
			lines.append("| %d | %s | %s | %s | %s | %s |" % [
				int(card["index"]), card["name"], where, when, card["gd_title"], _el(card),
			])

	lines.append("")
	lines.append("## Courts (Hulse)")
	lines.append("")
	lines.append("| # | Card | Role | Elemental title | Throne | Rules / elemental throne | Mainly | Path |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for card: Dictionary in _db.cards:
		if card.get("type") != "court":
			continue
		var rules: String
		if card.get("decans_ruled") != null:
			rules = ", ".join(PackedStringArray(card["decans_ruled"].map(_name_of)))
		else:
			var throne: Dictionary = card.get("elemental_throne", {})
			rules = "%s + %s (archetype %s)" % [
				_name_of(throne.get("ace", "")), _name_of(throne.get("trump", "")),
				_name_of(card.get("archetype_trump", ""))]
		var path: Dictionary = card.get("hulse_path", {})
		var connects: Variant = path.get("connects")
		lines.append("| %d | %s | %s | %s | %s | %s | %s | %d %s |" % [
			int(card["index"]), card["name"], card.get("family_role", ""),
			card.get("gd_title_elemental") if card.get("gd_title_elemental") != null else "**null**",
			_name_of(card.get("throne", "")), rules,
			card.get("predominant_sign") if card.get("predominant_sign") != null else "—",
			int(path.get("number", 0)),
			"(**connects null**)" if connects == null else "%s–%s" % [connects[0], connects[1]],
		])

	lines.append("")
	lines.append("## Planet elements (for dignities)")
	lines.append("")
	var planet_elements: Dictionary = _db.correspondences.get("planet_elements", {})
	lines.append(", ".join(PackedStringArray(planet_elements.keys().map(
			func(planet: String) -> String: return "%s %s" % [planet, planet_elements[planet]]))))

	lines.append("")
	lines.append("## Sephiroth")
	lines.append("")
	lines.append("| # | Sephira | Title | Planet |")
	lines.append("|---|---|---|---|")
	for sephira: Dictionary in _db.correspondences.get("sephiroth", []):
		lines.append("| %d | %s | %s | %s |" % [
			int(sephira["number"]), sephira["id"], sephira["title"], sephira["planet"]])

	lines.append("")
	lines.append("## Notes (checked against Hulse and confirmed by the author, 2026-11-19)")
	lines.append("")
	for flag: String in _flags():
		lines.append("- " + flag)
	lines.append("")
	if not _problems.is_empty():
		lines.append("## Structural problems")
		lines.append("")
		for problem: String in _problems:
			lines.append("- " + problem)
		lines.append("")
	return "\n".join(lines)


func _flags() -> PackedStringArray:
	return [
		"**Judgement / Shin** is attributed to Fire, with Spirit kept as `secondary_attribution`. "
				+ "`dignity_element` is `fire`.",
		"**Planetary trumps** take their dignity element from `planet_elements` (by planetary "
				+ "nature): Sun and Mars fire, Moon and Venus water, Mercury and Jupiter air, Saturn "
				+ "earth. The World as Earth agrees with Hulse, who gives it as the elemental throne "
				+ "of the Page of Pentacles. The others are your choice, not from Hulse.",
		"**Page of Pentacles** is on Hulse's 48th path, the last invisible path, which joins no "
				+ "two sephiroth, so `connects` is null by design.",
		"**Court spans and decans** were checked against Hulse (pp. 309-317) for all 12 courts "
				+ "with a span: every span, decan card and predominant sign matched. Titles, family "
				+ "roles, thrones and invisible paths 33-48 are taken from the same pages.",
		"**Hulse's Knight of Swords** reads \"the elemental counterchange of Fire of Water\": "
				+ "a misprint or OCR error for Fire of Air. The data keeps Fire of Air.",
		"**Pip titles where Hulse's wording differs**: he calls the Six of Swords \"Science\" "
				+ "(Crowley's title) and the Three of Pentacles \"Material Work\". The data keeps the "
				+ "Book T titles \"Lord of Earned Success\" and \"Lord of Material Works\".",
		"**Court `dignity_element`** is the suit element (e.g. Knight of Cups → water), not the "
				+ "sub-element. Change any card if you read it differently.",
		"**Sephirothic planets of Kether, Chokmah and Malkuth** are stored as `primum_mobile`, "
				+ "`zodiac` and `elements`. Sources word these differently.",
		"**GD titles** for trumps, pips and courts were written out from the Book T titles in "
				+ "common use; check the spelling and punctuation (e.g. \"Illusionary Success\", "
				+ "\"Sun of the Morning\" for the Emperor, \"Spirit of Aether\" for the Fool).",
		"**Hebrew letter spellings** (`cheth`, `tzaddi`, `qoph`, `heh`, `vav`) and the "
				+ "one-word letter meanings in `correspondences.json` are a common transliteration; "
				+ "change them to match Hulse if you prefer his.",
		"**Decans** follow the Chaldean order starting with Mars at 0° Aries (2 of Wands). The "
				+ "36 decans are checked as unique, and each sign is checked to belong to the suit's "
				+ "element. The planet assigned to each decan still needs to be checked by eye.",
		"**Pip `decan.degrees`** and trump `secondary_attribution` are small additions beyond "
				+ "the schema in CLAUDE.md.",
	]


func _name_of(id: Variant) -> String:
	var card: Dictionary = _db.by_id(str(id))
	return card.get("name", "?%s" % id)


func _el(card: Dictionary) -> String:
	var element: Variant = card.get("dignity_element")
	return "**null**" if element == null else str(element)
