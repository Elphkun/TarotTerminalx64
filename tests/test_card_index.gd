extends "res://tests/test_case.gd"


func test_claude_md_checks() -> void:
	assert_eq(CardIndex.pip("wands", 7), 28, "7 of Wands")
	assert_eq(CardIndex.court("wands", "page"), 32, "Page of Wands")
	assert_eq(CardIndex.pip("cups", 1), 36, "Ace of Cups")
	assert_eq(CardIndex.pip("swords", 1), 50, "Ace of Swords")
	assert_eq(CardIndex.court("pentacles", "king"), 77, "King of Pentacles")


func test_rws_trump_numbering() -> void:
	assert_eq(db().card(CardIndex.trump(8))["name"], "Strength")
	assert_eq(db().card(CardIndex.trump(11))["name"], "Justice")


func test_every_card_round_trips() -> void:
	for index: int in CardIndex.DECK_SIZE:
		var card: Dictionary = db().card(index)
		var expected: int = -1
		match card["type"]:
			"trump":
				expected = CardIndex.trump(int(card["number"]))
			"pip":
				expected = CardIndex.pip(card["suit"], int(card["rank"]))
			"court":
				expected = CardIndex.court(card["suit"], card["rws_rank"])
		assert_eq(expected, index, card["name"])
		assert_eq(CardIndex.suit_of(index), card.get("suit", ""), "suit of %s" % card["name"])
		assert_eq(int(db().by_id(card["id"])["index"]), index, "by_id %s" % card["id"])
