extends "res://tests/test_case.gd"


func test_counts_elements_and_types() -> void:
	var patterns: Dictionary = SpreadPatterns.compute(
			three_card(["wands_7", "wands_page", "sun"]), db())
	assert_eq(patterns["elements"]["fire"], 3, "the Sun counts as fire")
	assert_eq(patterns["elements"]["planetary"], 0)
	assert_eq(patterns["types"], {"trump": 1, "pip": 1, "court": 1})
	assert_eq(patterns["dominant_elements"], ["fire"] as Array[String])
	assert_eq(patterns["missing_elements"], ["water", "air", "earth"] as Array[String])


func test_repeated_numbers() -> void:
	var patterns: Dictionary = SpreadPatterns.compute(
			three_card(["wands_7", "cups_7", "swords_2"]), db())
	assert_eq(patterns["repeated_ranks"].size(), 1)
	assert_eq(patterns["repeated_ranks"][0]["rank"], 7)
	assert_eq(patterns["repeated_ranks"][0]["positions"], ["past", "present"])


func test_court_roles() -> void:
	var patterns: Dictionary = SpreadPatterns.compute(
			three_card(["cups_king", "swords_king", "fool"]), db())
	assert_eq(patterns["courts"].size(), 2)
	assert_eq(patterns["courts"][0]["gd_rank"], "prince")
	assert_eq(patterns["courts"][0]["sub_element"], "air")
	assert_eq(patterns["repeated_courts"][0]["rws_rank"], "king")
	assert_eq(patterns["dominant_elements"], ["air"] as Array[String],
			"King of Swords and the Fool are both air")


func test_no_majority_without_a_repeat() -> void:
	var patterns: Dictionary = SpreadPatterns.compute(
			three_card(["wands_2", "cups_2", "swords_2"]), db())
	assert_eq(patterns["dominant_elements"].size(), 0, "one card per element is no majority")
