extends "res://tests/test_case.gd"


func test_loads_without_errors() -> void:
	assert_eq(db().errors.size(), 0, "load errors: %s" % ", ".join(db().errors))
	assert_eq(db().cards.size(), 78)


func test_meanings_have_three_text_fields() -> void:
	for card: Dictionary in db().cards:
		var meanings: Dictionary = card["meanings"]
		assert_eq(meanings.keys().size(), 3, card["name"])
		for key: String in ["waite", "gd", "personal"]:
			assert_true(meanings.get(key) is String, "%s meanings.%s" % [card["name"], key])
		assert_true(card["keywords"] is Array, "%s keywords" % card["name"])


## Waite's and the Golden Dawn's meanings are tradition and ship in cards.json. "personal"
## is the user's own and ships empty: users add theirs in local/meanings.json.
func test_shipped_meanings_are_tradition_only() -> void:
	for card: Dictionary in db().cards:
		var meanings: Dictionary = card["meanings"]
		assert_eq(meanings["personal"], "", "%s ships no personal meaning" % card["name"])
		assert_true(str(meanings["waite"]).strip_edges() != "", "%s has Waite's meaning" % card["name"])
		assert_true(str(meanings["gd"]).strip_edges() != "", "%s has the GD meaning" % card["name"])


func test_local_meanings_are_laid_over() -> void:
	var path: String = "user://test_local_meanings.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"0": {"personal": "Mine.", "gd": "GD."}, "99": {"gd": "x"}}))
	file.close()
	var fresh: CardDb = CardDb.load_from(CardDb.DEFAULT_DIR)
	var shipped_waite: String = fresh.card(0)["meanings"]["waite"]
	assert_eq(fresh.load_local_meanings(path), 1)
	assert_eq(fresh.card(0)["meanings"], {"waite": shipped_waite, "gd": "GD.", "personal": "Mine."},
			"only the listed fields change")
	assert_eq(fresh.errors.size(), 1, "the bad index is reported")
	assert_eq(fresh.load_local_meanings("user://no_such_file.json"), 0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_hulse_court_mapping() -> void:
	var expected: Dictionary = {
		"page": ["princess", "earth"], "knight": ["knight", "fire"],
		"queen": ["queen", "water"], "king": ["prince", "air"],
	}
	for card: Dictionary in db().cards:
		if card["type"] != "court":
			continue
		assert_eq(card["gd_rank"], expected[card["rws_rank"]][0], card["name"])
		assert_eq(card["sub_element"], expected[card["rws_rank"]][1], card["name"])
		assert_true(card["name"].begins_with(str(card["rws_rank"]).capitalize()),
				"%s uses the RWS name" % card["name"])


func test_hulse_court_fields() -> void:
	var queen: Dictionary = db().by_id("wands_queen")
	assert_eq(queen["family_role"], "mother")
	assert_eq(queen["throne"], "wands_3")
	assert_eq(queen["predominant_sign"], "aries")
	assert_eq(queen["decans_ruled"], ["cups_10", "wands_2", "wands_3"])
	var page: Dictionary = db().by_id("pentacles_page")
	assert_eq(page["elemental_throne"], {"ace": "pentacles_ace", "trump": "world"})
	assert_eq(page["throne"], "pentacles_10")


func test_every_trump_has_a_dignity_element() -> void:
	for number: int in 22:
		assert_true(db().card(number)["dignity_element"] != null, db().card(number)["name"])


func test_trump_paths() -> void:
	for number: int in 22:
		var card: Dictionary = db().card(number)
		assert_eq(int(card["path"]), number + 11, card["name"])
	assert_eq(db().card(8)["hebrew_letter"], "teth", "Strength is Teth")
	assert_eq(db().card(11)["hebrew_letter"], "lamed", "Justice is Lamed")


func test_suit_elements() -> void:
	var elements: Dictionary = {
		"wands": "fire", "cups": "water", "swords": "air", "pentacles": "earth",
	}
	for card: Dictionary in db().cards:
		if card.has("suit"):
			assert_eq(card["element"], elements[card["suit"]], card["name"])
