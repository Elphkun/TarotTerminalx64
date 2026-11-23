class_name Spread
extends RefCounted
## A spread definition from spreads.json, and dealing cards into it.
##
## A layout is an Array of { "position": <position dict>, "card": <card index> },
## in the order the positions are listed.

const DEFAULT_READING_WORDS := "300 to 500"

var id: String
var name: String
var positions: Array[Dictionary] = []
## Pairs of position ids that count as neighbours for dignities.
var adjacency: Array[PackedStringArray] = []
## How long the reading should be, for the prompt ("700 to 1000").
var reading_words: String = DEFAULT_READING_WORDS
## Card height as a share of the table's height; 0 lets the table choose.
var card_height: float = 0.0
## How many card widths the table must fit across; 0 lets the table choose.
var columns: float = 0.0
## Many cards close together: numbers and dignity marks go on the cards themselves
## instead of name labels underneath.
var compact_labels: bool = false


static func from_db(db: CardDb, spread_id: String) -> Spread:
	return from_data(spread_id, db.spread(spread_id))


## A spread from its definition (as in spreads.json, or as stored with a saved reading).
static func from_data(spread_id: String, data: Dictionary) -> Spread:
	if data.is_empty():
		return null
	var spread: Spread = Spread.new()
	spread.id = spread_id
	spread.name = data.get("name", spread_id)
	spread.positions.assign(data.get("positions", []))
	for pair: Array in data.get("dignity_adjacency", []):
		spread.adjacency.append(PackedStringArray(pair))
	spread.reading_words = str(data.get("reading_words", DEFAULT_READING_WORDS))
	spread.card_height = float(data.get("card_height", 0.0))
	spread.columns = float(data.get("columns", 0.0))
	spread.compact_labels = bool(data.get("compact_labels", false))
	return spread


## A position's name for the prompt and the UI: its `name`, or its id. Lower case, as it
## sits mid-sentence ("The Tower in hopes and fears"); see title().
static func label(entry: Dictionary) -> String:
	return str(entry.get("name", str(entry.get("id", "")).replace("_", " ")))


## The name with its first letter capitalised, for headings ("Hopes and fears").
static func title(text: String) -> String:
	return text.left(1).to_upper() + text.substr(1)


func size() -> int:
	return positions.size()


## The position with this id, or {}.
func position(position_id: String) -> Dictionary:
	for entry: Dictionary in positions:
		if entry.get("id") == position_id:
			return entry
	return {}


## Deals from the top of `deck` (index 0) into each position in order.
func deal(deck: Array[int]) -> Array[Dictionary]:
	assert(deck.size() >= size(), "not enough cards to deal")
	return lay_out(deck.slice(0, size()))


## Places the given cards in the positions in order. Used for forced draws in tests.
func lay_out(cards: Array[int]) -> Array[Dictionary]:
	assert(cards.size() == size(), "need exactly %d cards" % size())
	var layout: Array[Dictionary] = []
	for i: int in size():
		layout.append({"position": positions[i], "card": cards[i]})
	return layout


## Position ids adjacent to `position_id`, in the order they appear in the spread.
func neighbours(position_id: String) -> PackedStringArray:
	var found: PackedStringArray = []
	for entry: Dictionary in positions:
		var other: String = entry["id"]
		for pair: PackedStringArray in adjacency:
			if (pair[0] == position_id and pair[1] == other) \
					or (pair[1] == position_id and pair[0] == other):
				found.append(other)
				break
	return found
