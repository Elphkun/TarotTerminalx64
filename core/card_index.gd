class_name CardIndex
extends RefCounted
## The canonical index scheme (also the image file names 0.jpg to 77.jpg).
##
##   0-21   trumps, by RWS number (Strength 8, Justice 11)
##   22-35  wands, 36-49 cups, 50-63 swords, 64-77 pentacles
##
## Within a suit: Ace +0, 2-10 +(rank - 1), Page +10, Knight +11, Queen +12, King +13.
## Only the numbering lives here. Every correspondence is in data/.

const DECK_SIZE: int = 78
const TRUMP_COUNT: int = 22
const CARDS_PER_SUIT: int = 14
const SUITS: PackedStringArray = ["wands", "cups", "swords", "pentacles"]
const COURT_RANKS: PackedStringArray = ["page", "knight", "queen", "king"]
const FIRST_COURT_OFFSET: int = 10


static func is_valid(index: int) -> bool:
	return index >= 0 and index < DECK_SIZE


static func is_trump(index: int) -> bool:
	return index >= 0 and index < TRUMP_COUNT


static func suit_base(suit: String) -> int:
	var position: int = SUITS.find(suit)
	assert(position >= 0, "unknown suit '%s'" % suit)
	return TRUMP_COUNT + position * CARDS_PER_SUIT


static func pip(suit: String, rank: int) -> int:
	assert(rank >= 1 and rank <= 10, "pip rank must be 1-10")
	return suit_base(suit) + rank - 1


static func court(suit: String, rws_rank: String) -> int:
	var position: int = COURT_RANKS.find(rws_rank)
	assert(position >= 0, "unknown court rank '%s'" % rws_rank)
	return suit_base(suit) + FIRST_COURT_OFFSET + position


static func trump(number: int) -> int:
	assert(number >= 0 and number < TRUMP_COUNT, "trump number must be 0-21")
	return number


## The suit of a minor card, or "" for a trump.
static func suit_of(index: int) -> String:
	if is_trump(index):
		return ""
	@warning_ignore("integer_division")
	return SUITS[(index - TRUMP_COUNT) / CARDS_PER_SUIT]


## 0-13 within the suit, or -1 for a trump.
static func offset_in_suit(index: int) -> int:
	if is_trump(index):
		return -1
	return (index - TRUMP_COUNT) % CARDS_PER_SUIT
