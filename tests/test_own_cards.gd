extends "res://tests/test_case.gd"
## Own cards: the querent lays out their own deck and names each card. Placing refuses a
## card already laid, a card can be changed until the last one is in, and the last one
## starts the reading. The picker finds cards by name, code or number.


func _session() -> ReadingSession:
	return ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())


func test_positions_wait_for_the_cards() -> void:
	var session: ReadingSession = _session()
	var dealt: Array = []
	session.dealt.connect(func(layout: Array[Dictionary]) -> void: dealt.append(layout.size()))
	assert_eq(session.start("Q?", "three_card", -1, true), "")
	assert_true(session.own_cards)
	assert_eq(session.step, ReadingSession.Step.DEALT, "no shuffle: straight to the positions")
	assert_eq(dealt, [3])
	for entry: Dictionary in session.layout:
		assert_eq(entry["card"], -1, "every position starts empty")
	session.turn(0)
	assert_false(session.turned[0], "turning does nothing with own cards")


func test_placing_cards() -> void:
	var session: ReadingSession = _session()
	session.start("Q?", "three_card", -1, true)
	var placed: Array = []
	session.card_placed.connect(func(slot: int, card: int) -> void: placed.append([slot, card]))
	assert_eq(session.place(0, 28), "")
	assert_eq(session.layout[0]["card"], 28)
	assert_true(session.place(1, 28).contains("already in position 1"), "a card can only be laid once")
	assert_eq(session.layout[1]["card"], -1)
	assert_eq(session.place(0, 16), "", "a laid card can be changed")
	assert_eq(session.place(1, 28), "", "and the old one is free again")
	assert_true(session.place(2, 99) != "", "not a card")
	assert_eq(placed, [[0, 28], [0, 16], [1, 28]])
	assert_eq(session.step, ReadingSession.Step.DEALT, "still waiting for the last card")
	assert_eq(session.place(2, 50), "")
	assert_true(session.step != ReadingSession.Step.DEALT, "the last card starts the reading")
	assert_true(session.place(2, 51) != "", "no changes once the reading has begun")
	var summary: ReadingSummary = ReadingSummary.build(db(), session.spread, session.layout, "Q?")
	assert_eq(summary.positions[0]["card"]["name"], "The Tower")
	assert_eq(summary.positions[1]["card"]["name"], "Seven of Wands")


func test_app_draws_still_deal() -> void:
	var session: ReadingSession = _session()
	session.start("Q?", "three_card", 1)
	assert_false(session.own_cards)
	assert_eq(session.step, ReadingSession.Step.SHUFFLED)
	assert_true(session.place(0, 1) != "", "placing is only for own cards")


func test_picker_finds_cards() -> void:
	var picker: CardPickerDialog = CardPickerDialog.new(db())
	picker.open(0, "Past", [] as Array[int])
	var expect: Dictionary = {
		"7w": [28], "seven wands": [28], "Seven of Wands": [28], "aw": [22], "1c": [36],
		"kp": [77], "pw": [32], "nc": [47], "tower": [16], "16": [16], "0": [0],
	}
	for filter: String in expect:
		picker.set_filter(filter)
		assert_eq(picker.shown(), expect[filter] as Array[int], "\"%s\"" % filter)
	picker.set_filter("king")
	assert_eq(picker.shown(), [35, 49, 63, 77] as Array[int])
	picker.set_filter("")
	assert_eq(picker.shown().size(), 78)
	picker.free()


func test_picker_skips_laid_cards() -> void:
	var picker: CardPickerDialog = CardPickerDialog.new(db())
	var chosen: Array = []
	picker.card_chosen.connect(func(slot: int, card: int) -> void: chosen.append([slot, card]))
	picker.open(2, "Future", [28] as Array[int])
	picker.set_filter("7w")
	assert_true(picker.list.is_item_disabled(0), "a laid card is greyed out")
	picker.choose()
	assert_eq(chosen, [], "and can't be chosen")
	picker.set_filter("seven")
	picker.choose()
	assert_eq(chosen, [[2, 42]], "Enter picks the first free match: Seven of Cups")
	picker.free()
