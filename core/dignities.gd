class_name Dignities
extends RefCounted
## Book T elemental dignities, computed from the spread's adjacency.
##
## Every pairing of a card with a neighbour scores the weight of its relation
## (correspondences.dignity_weights: same, friendly, contrary). The total decides:
## above 0 well-dignified, below 0 ill-dignified, 0 neutral. A card whose
## dignity_element is null (planetary trumps) is neutral and does not count
## as a neighbour for anyone else.

const WELL := "well-dignified"
const ILL := "ill-dignified"
const NEUTRAL := "neutral"


## Returns { position_id: {
##     state, score, element,
##     relations: [{ with, with_card, with_element, relation, weight }],
##     note } }
static func compute(spread: Spread, layout: Array[Dictionary], db: CardDb) -> Dictionary:
	var by_position: Dictionary = {}
	for slot: Dictionary in layout:
		by_position[slot["position"]["id"]] = slot["card"]

	var result: Dictionary = {}
	for slot: Dictionary in layout:
		var position_id: String = slot["position"]["id"]
		var own: Dictionary = db.card(slot["card"])
		var element: Variant = own.get("dignity_element")
		var entry: Dictionary = {
			"state": NEUTRAL, "score": 0, "element": element, "relations": [], "note": "",
		}
		result[position_id] = entry
		if element == null:
			entry["note"] = "no dignity element (planetary trump), not counted"
			continue

		var score: int = 0
		for other_id: String in spread.neighbours(position_id):
			if not by_position.has(other_id):
				continue
			var other: Dictionary = db.card(by_position[other_id])
			var other_element: Variant = other.get("dignity_element")
			if other_element == null:
				continue
			var relation: String = db.relation(element, other_element)
			var weight: int = db.dignity_weight(relation)
			score += weight
			entry["relations"].append({
				"with": other_id, "with_name": Spread.label(spread.position(other_id)),
				"with_card": other["name"],
				"with_element": other_element, "relation": relation, "weight": weight,
			})

		entry["score"] = score
		if entry["relations"].is_empty():
			entry["note"] = "no neighbour with an element"
		elif score > 0:
			entry["state"] = WELL
		elif score < 0:
			entry["state"] = ILL
	return result


## One line explaining a position's dignity, e.g.
## "ill-dignified (-1): contrary to Ace of Cups (water) in future; friendly to ..."
static func describe(entry: Dictionary) -> String:
	var reasons: PackedStringArray = []
	for relation: Dictionary in entry["relations"]:
		var verb: String = "same element as" if relation["relation"] == "same" \
				else "%s to" % relation["relation"]
		reasons.append("%s %s (%s) in %s, %+d" % [
			verb, relation["with_card"], relation["with_element"],
			relation.get("with_name", relation["with"]),
			relation["weight"],
		])
	var text: String = "%s (score %+d)" % [entry["state"], entry["score"]]
	if not reasons.is_empty():
		text += ": " + "; ".join(reasons)
	if entry["note"] != "":
		text += ": " + entry["note"]
	return text
