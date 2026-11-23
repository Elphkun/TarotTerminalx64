extends "res://tests/test_case.gd"
## Every spread in spreads.json: well-formed data, and a table layout where no two
## cards overlap (except a card declared to lie "over" another) and all stay in view.

## The table's size in the 1280x720 window, and a smaller window.
const TABLE_SIZES: Array[Vector2] = [Vector2(760, 570), Vector2(600, 480)]


func test_spread_data_is_well_formed() -> void:
	for spread_id: String in db().spreads:
		var spread: Spread = Spread.from_db(db(), spread_id)
		var ids: PackedStringArray = []
		for entry: Dictionary in spread.positions:
			var position_id: String = entry.get("id", "")
			assert_true(position_id != "" and not ids.has(position_id), "%s: id %s" % [spread_id, position_id])
			ids.append(position_id)
			assert_true(str(entry.get("meaning", "")) != "", "%s.%s has a meaning" % [spread_id, position_id])
			for axis: String in ["x", "y"]:
				var value: float = float(entry.get(axis, -1))
				assert_true(value >= 0.0 and value <= 1.0, "%s.%s %s in 0..1" % [spread_id, position_id, axis])
			if entry.has("over"):
				assert_true(spread.position(entry["over"]) != {}, "%s.%s lies over a real position" % [spread_id, position_id])
		var seen: PackedStringArray = []
		for pair: PackedStringArray in spread.adjacency:
			assert_eq(pair.size(), 2, "%s: pair %s" % [spread_id, pair])
			assert_true(ids.has(pair[0]) and ids.has(pair[1]) and pair[0] != pair[1],
					"%s: pair %s names two real positions" % [spread_id, pair])
			var key: String = "-".join(PackedStringArray([pair[0], pair[1]]) if pair[0] < pair[1] else PackedStringArray([pair[1], pair[0]]))
			assert_false(seen.has(key), "%s: pair %s listed once" % [spread_id, pair])
			seen.append(key)


## Waite's order and the "lines" neighbours chosen by the author.
func test_celtic_cross() -> void:
	var spread: Spread = Spread.from_db(db(), "celtic_cross")
	var ids: PackedStringArray = []
	for entry: Dictionary in spread.positions:
		ids.append(entry["id"])
	assert_eq(ids, PackedStringArray(["cover", "cross", "crown", "beneath", "behind", "before",
			"self", "house", "hopes_fears", "outcome"]))
	assert_eq(spread.neighbours("cover"), PackedStringArray(["cross", "crown", "beneath", "behind", "before"]))
	assert_eq(spread.neighbours("cross"), PackedStringArray(["cover"]))
	assert_eq(spread.neighbours("crown"), PackedStringArray(["cover"]))
	assert_eq(spread.neighbours("house"), PackedStringArray(["self", "hopes_fears"]))
	assert_eq(spread.neighbours("outcome"), PackedStringArray(["hopes_fears"]))
	assert_eq(Spread.label(spread.positions[8]), "hopes and fears")
	assert_eq(Spread.title(Spread.label(spread.positions[8])), "Hopes and fears")


## Sun outward in orbit order; each card's neighbours are the orbits on either side.
func test_planetary_orbit() -> void:
	var spread: Spread = Spread.from_db(db(), "planetary_orbit")
	var ids: PackedStringArray = []
	for entry: Dictionary in spread.positions:
		ids.append(entry["id"])
	assert_eq(ids, PackedStringArray(["sun", "mercury", "venus", "earth", "mars", "jupiter",
			"saturn", "uranus", "neptune", "pluto"]))
	assert_eq(spread.neighbours("sun"), PackedStringArray(["mercury"]))
	assert_eq(spread.neighbours("earth"), PackedStringArray(["venus", "mars"]))
	assert_eq(spread.neighbours("pluto"), PackedStringArray(["neptune"]))


func test_celtic_cross_reading_names_positions() -> void:
	var spread: Spread = Spread.from_db(db(), "celtic_cross")
	var cards: Array[int] = []
	for i: int in 10:
		cards.append(i)
	var summary: ReadingSummary = ReadingSummary.build(db(), spread, spread.lay_out(cards), "Q")
	var text: String = summary.to_prompt_text()
	assert_true(text.contains("Position 9 (hopes and fears): Your hopes and fears"), text)
	assert_true(text.contains("Position 10 (what will come):"), text)
	assert_false(text.contains("hopes_fears"), "ids stay out of the prompt")
	assert_eq(summary.reading_words, "700 to 1000")
	var system: String = ReadingPipeline.reading_messages(summary)[0]["content"]
	assert_true(system.contains("10 positions; write about 700 to 1000 words"), system)
	# The Fool (air) covers, the Magician (Mercury, air) crosses: same element.
	assert_true(Dignities.describe(summary.positions[0]["dignity"]).contains("in crosses"),
			Dignities.describe(summary.positions[0]["dignity"]))


## At the default card shape and at a 9:16 deck's (1080x1920 scans).
func test_cards_do_not_overlap_and_stay_on_the_table() -> void:
	for spread_id: String in db().spreads:
		var spread: Spread = Spread.from_db(db(), spread_id)
		for aspect: float in [CardView.ASPECT, 0.5625]:
			var problems: PackedStringArray = SpreadLayout.problems(spread, aspect, TABLE_SIZES)
			assert_true(problems.is_empty(), "%s at aspect %s: %s" % [spread_id, aspect, "; ".join(problems)])


## The designer and the layout check use TableView's static geometry: it must be the
## geometry a real table lays cards out with.
func test_the_table_lays_cards_out_by_its_static_geometry() -> void:
	var tall_deck: DeckImages = DeckImages.new(DeckInfo.new())
	tall_deck.aspect = 0.5625
	for spread_id: String in db().spreads:
		var spread: Spread = Spread.from_db(db(), spread_id)
		for table_size: Vector2 in TABLE_SIZES:
			var table: TableView = TableView.new()
			table.db = db()
			table.size = table_size
			table.set_images(tall_deck)
			table.set_spread(spread)
			var height: float = TableView.card_height_for(table_size, 0.5625, spread)
			assert_eq(table._card_height(), height)
			assert_eq(table._pile_position(), TableView.pile_position_for(table_size, height, 0.5625))
			for i: int in spread.size():
				var entry: Dictionary = spread.positions[i]
				var normalized: Vector2 = Vector2(entry["x"], entry["y"])
				var centre: Vector2 = TableView.slot_centre_for(normalized, table_size)
				assert_eq(table._slot_centre(i), centre)
				assert_true(TableView.normalized_for(centre, table_size).is_equal_approx(normalized),
						"%s.%s round trip" % [spread_id, entry["id"]])
			table.free()
