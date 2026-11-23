class_name SpreadPatterns
extends RefCounted
## Whole-spread patterns: element balance, card types, repeated numbers, court roles.


## Returns {
##   elements: { fire, water, air, earth, planetary },   counted by dignity_element
##   dominant_elements: [..], missing_elements: [..],
##   types: { trump, pip, court },
##   suits: { wands, ... },
##   repeated_ranks: [{ rank, count, positions }],        pip ranks seen 2+ times
##   repeated_courts: [{ rws_rank, count, positions }],
##   courts: [{ position, name, rws_rank, gd_rank, element, sub_element }],
## }
static func compute(layout: Array[Dictionary], db: CardDb) -> Dictionary:
	var elements: Dictionary = {}
	for element: String in db.correspondences.get("elements", {}):
		if db.correspondences["elements"][element].get("suit") != null:
			elements[element] = 0
	elements["planetary"] = 0
	var types: Dictionary = {"trump": 0, "pip": 0, "court": 0}
	var suits: Dictionary = {}
	for suit: String in CardIndex.SUITS:
		suits[suit] = 0
	var ranks: Dictionary = {}
	var court_ranks: Dictionary = {}
	var courts: Array[Dictionary] = []

	for slot: Dictionary in layout:
		var position_id: String = Spread.label(slot["position"])
		var card: Dictionary = db.card(slot["card"])
		var element: Variant = card.get("dignity_element")
		var element_key: String = "planetary" if element == null else str(element)
		elements[element_key] = elements.get(element_key, 0) + 1
		types[card["type"]] += 1
		if card.has("suit"):
			suits[card["suit"]] += 1
		match card["type"]:
			"pip":
				_add(ranks, int(card["rank"]), position_id)
			"court":
				_add(court_ranks, card["rws_rank"], position_id)
				courts.append({
					"position": position_id, "name": card["name"],
					"rws_rank": card["rws_rank"], "gd_rank": card["gd_rank"],
					"element": card["element"], "sub_element": card["sub_element"],
				})

	var dominant: Array[String] = []
	var missing: Array[String] = []
	var best: int = 1
	for element: String in elements:
		if element == "planetary":
			continue
		var count: int = elements[element]
		if count == 0:
			missing.append(element)
		elif count > best:
			best = count
			dominant = [element]
		elif count == best and best > 1:
			dominant.append(element)

	return {
		"elements": elements,
		"dominant_elements": dominant,
		"missing_elements": missing,
		"types": types,
		"suits": suits,
		"repeated_ranks": _repeated(ranks, "rank"),
		"repeated_courts": _repeated(court_ranks, "rws_rank"),
		"courts": courts,
	}


static func _add(groups: Dictionary, key: Variant, position_id: String) -> void:
	if not groups.has(key):
		groups[key] = []
	groups[key].append(position_id)


static func _repeated(groups: Dictionary, key_name: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for key: Variant in groups:
		var positions: Array = groups[key]
		if positions.size() >= 2:
			found.append({key_name: key, "count": positions.size(), "positions": positions})
	return found
