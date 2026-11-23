extends "res://tests/test_case.gd"


func _compute(ids: Array) -> Dictionary:
	return Dignities.compute(spread3(), three_card(ids), db())


func test_relations_come_from_table() -> void:
	assert_eq(db().relation("fire", "water"), "contrary")
	assert_eq(db().relation("earth", "air"), "contrary")
	assert_eq(db().relation("air", "fire"), "friendly")
	assert_eq(db().relation("water", "earth"), "friendly")
	assert_eq(db().relation("fire", "fire"), "same")
	assert_eq(db().relation(null, "fire"), "")


func test_contrary_on_both_sides_is_ill() -> void:
	var result: Dictionary = _compute(["wands_2", "cups_2", "wands_3"])
	assert_eq(result["present"]["state"], Dignities.ILL)
	assert_eq(result["present"]["score"], -4)
	assert_eq(result["past"]["state"], Dignities.ILL)
	assert_eq(result["present"]["relations"].size(), 2)


func test_same_and_friendly_is_well() -> void:
	var result: Dictionary = _compute(["wands_2", "wands_3", "swords_2"])
	assert_eq(result["present"]["state"], Dignities.WELL)
	assert_eq(result["present"]["score"], 3)
	assert_eq(result["future"]["score"], 1, "air beside fire is friendly")


func test_mixed_neighbours_follow_the_weights() -> void:
	var result: Dictionary = _compute(["wands_2", "swords_2", "pentacles_2"])
	assert_eq(result["present"]["score"], -1, "friendly +1, contrary -2")
	assert_eq(result["present"]["state"], Dignities.ILL)


func test_planetary_trumps_use_planet_elements() -> void:
	var result: Dictionary = _compute(["wands_2", "tower", "cups_2"])
	assert_eq(result["present"]["element"], "fire", "Mars is fire")
	assert_eq(result["present"]["score"], 0, "same +2, contrary -2")
	assert_eq(_compute(["cups_2", "world", "wands_2"])["present"]["element"], "earth")


func test_card_without_element_is_neutral_and_skipped() -> void:
	db().by_id("magician")["dignity_element"] = null
	var result: Dictionary = _compute(["wands_2", "magician", "cups_2"])
	assert_eq(result["present"]["state"], Dignities.NEUTRAL)
	assert_eq(result["present"]["relations"].size(), 0)
	assert_eq(result["past"]["state"], Dignities.NEUTRAL, "its only neighbour is skipped")
	assert_eq(result["future"]["relations"].size(), 0)


func test_weights_are_read_from_data() -> void:
	db().correspondences["dignity_weights"] = {"same": 2, "friendly": 3, "contrary": -2}
	var result: Dictionary = _compute(["wands_2", "swords_2", "pentacles_2"])
	assert_eq(result["present"]["score"], 1)
	assert_eq(result["present"]["state"], Dignities.WELL)


func test_describe_names_the_reason() -> void:
	var result: Dictionary = _compute(["wands_2", "cups_2", "wands_3"])
	var text: String = Dignities.describe(result["present"])
	assert_true(text.contains("contrary to Two of Wands"), text)
	assert_true(text.begins_with("ill-dignified"), text)
