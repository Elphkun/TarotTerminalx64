extends "res://tests/test_case.gd"


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func test_same_seed_same_order() -> void:
	assert_eq(Deck.shuffled(_rng(7)), Deck.shuffled(_rng(7)))
	assert_false(Deck.shuffled(_rng(7)) == Deck.shuffled(_rng(8)), "different seeds differ")


func test_shuffle_is_a_permutation() -> void:
	var cards: Array[int] = Deck.shuffled(_rng(3))
	cards.sort()
	assert_eq(cards, Deck.full())


func test_cut() -> void:
	var cards: Array[int] = [0, 1, 2, 3, 4]
	assert_eq(Deck.cut(cards, 2), [2, 3, 4, 0, 1] as Array[int])
	assert_eq(Deck.cut(cards, 0), cards)
	assert_eq(Deck.cut(cards, 99), cards, "clamped")


func test_deal_follows_positions() -> void:
	var layout: Array[Dictionary] = spread3().deal([5, 6, 7, 8] as Array[int])
	assert_eq(layout.size(), 3)
	assert_eq(layout[0]["position"]["id"], "past")
	assert_eq(layout[2]["card"], 7)
	assert_eq(spread3().neighbours("present"), PackedStringArray(["past", "future"]))
	assert_eq(spread3().neighbours("past"), PackedStringArray(["present"]))
