class_name Deck
extends RefCounted
## The 78 canonical indices, shuffled and cut. Adapted from KitsuTarot's Deck.


static func full() -> Array[int]:
	var cards: Array[int] = []
	cards.resize(CardIndex.DECK_SIZE)
	for index: int in CardIndex.DECK_SIZE:
		cards[index] = index
	return cards


## A new shuffled deck. Uses only `rng`, so a seed reproduces the order exactly.
static func shuffled(rng: RandomNumberGenerator) -> Array[int]:
	var cards: Array[int] = full()
	for i: int in range(cards.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swapped: int = cards[i]
		cards[i] = cards[j]
		cards[j] = swapped
	return cards


## Lifts the top `at` cards and puts them underneath. `at` is clamped to the deck.
static func cut(cards: Array[int], at: int) -> Array[int]:
	var point: int = clampi(at, 0, cards.size())
	var result: Array[int] = cards.slice(point)
	result.append_array(cards.slice(0, point))
	return result
