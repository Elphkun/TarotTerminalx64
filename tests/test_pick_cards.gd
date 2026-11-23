extends "res://tests/test_case.gd"
## Picking the cards face down from the fanned deck: each pick is the card at that place
## in the (cut) deck, in pick order; no card twice; the last pick deals.


func _shuffled(spread_id: String = "three_card") -> ReadingSession:
	var session: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	session.start("Q?", spread_id, 7)
	return session


func test_picks_fill_the_positions_in_order() -> void:
	var session: ReadingSession = _shuffled()
	var dealt: Array = []
	session.dealt.connect(func(layout: Array[Dictionary]) -> void: dealt.append(layout.size()))
	var deck: Array[int] = session.deck.duplicate()
	assert_eq(session.pick(40), deck[40])
	assert_eq(session.pick(40), -1, "the same card can't be picked twice")
	assert_eq(session.pick(3), deck[3])
	assert_eq(session.step, ReadingSession.Step.SHUFFLED, "still picking")
	assert_eq(dealt, [], "nothing dealt yet")
	assert_eq(session.pick(71), deck[71])
	assert_eq(session.step, ReadingSession.Step.DEALT, "the last pick deals")
	assert_eq(dealt, [3], "once")
	var cards: Array[int] = []
	for entry: Dictionary in session.layout:
		cards.append(entry["card"])
	assert_eq(cards, [deck[40], deck[3], deck[71]] as Array[int], "in the order picked")
	assert_eq(session.draw, "picked")
	assert_eq(session.pick(5), -1, "no picks once dealt")


func test_no_cut_or_deal_mid_pick() -> void:
	var session: ReadingSession = _shuffled()
	var deck: Array[int] = session.deck.duplicate()
	session.pick(10)
	session.cut(20)
	assert_eq(session.deck, deck, "a cut after the first pick is refused")
	session.deal()
	assert_eq(session.step, ReadingSession.Step.SHUFFLED, "and so is a deal")


func test_a_cut_first_changes_what_the_fan_holds() -> void:
	var session: ReadingSession = _shuffled()
	var before: int = session.deck[0]
	session.cut(20)
	assert_true(session.deck[0] != before)
	assert_eq(session.pick(0), session.deck[0], "the fan is the cut deck")


func test_out_of_range_and_wrong_step() -> void:
	var session: ReadingSession = _shuffled()
	assert_eq(session.pick(-1), -1)
	assert_eq(session.pick(78), -1)
	var fresh: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	assert_eq(fresh.pick(0), -1, "not before shuffling")
	var own: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	own.start("Q?", "three_card", -1, true)
	assert_eq(own.pick(0), -1, "not with your own cards")


func test_dealing_still_takes_the_top() -> void:
	var session: ReadingSession = _shuffled()
	var top: Array[int] = session.deck.slice(0, 3)
	session.deal()
	var cards: Array[int] = []
	for entry: Dictionary in session.layout:
		cards.append(entry["card"])
	assert_eq(cards, top)
	assert_eq(session.draw, "app")


func test_the_record_and_export_say_picked() -> void:
	var session: ReadingSession = _shuffled("single")
	session.pick(12)
	session.question = "Q?"
	session.reading_text = "A reading."
	session.summary = ReadingSummary.build(db(), session.spread, session.layout, "Q?")
	var record: Dictionary = ReadingHistory.record_from(session, db().spread("single"))
	assert_eq(record["draw"], "picked")
	var text: String = ReadingExport.to_markdown(session.summary, "A reading.", {"cards": "picked"})
	assert_true(text.contains("**Cards:** picked face down from the deck"), text)
