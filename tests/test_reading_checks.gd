extends "res://tests/test_case.gd"
## The checks tools/compare.gd makes on each model's reading.

const Checks := preload("res://tools/reading_checks.gd")


func _summary(question_type: String = "yes_no") -> ReadingSummary:
	# Fire, water, earth: the Two of Wands and the Two of Cups are ill-dignified.
	return ReadingSummary.build(db(), spread3(), three_card(["wands_2", "cups_2", "world"]), "Will it work?",
			{"question_type": question_type, "harm": false})


func _good() -> String:
	var filler: String = "word ".repeat(330)
	return ("**1. Past**\nThe Two of Wands. %s\n**2. Present**\nThe Two of Cups.\n**3. Future**\nThe World.\n"
			+ "**Synthesis**\nThe Two of Wands and the Two of Cups are weak, so: not yet.") % filler


func test_a_good_reading_passes() -> void:
	var result: Dictionary = Checks.check(_summary(), _good())
	assert_eq(result["problems"], PackedStringArray())
	assert_eq(result["passed"], result["checks"])


func test_each_fault_is_found() -> void:
	var faults: Dictionary = {
		"positions headed": _good().replace("**2. Present**", ""),
		"not named: The World": _good().replace("The World", "This card"),
		"no synthesis": _good().replace("**Synthesis**", "**So**"),
		"not in the synthesis: Two of Cups": _good().replace("and the Two of Cups are", "is"),
		"not in the spread: Ten of Swords": _good() + " Like the Ten of Swords, not yet.",
		"wrong dignity: Two of Cups called well, is ill": _good() + " The Two of Cups is well-dignified here.",
		"wrong dignity: The World called ill": _good() + " The World is ill dignified here.",
		"reversed": _good() + " It is reversed.",
		"refusal": "No. These cards will never counsel you to harm anyone.\n" + _good(),
		"words, asked for": _good().replace("word ", ""),
		"no clear yes": _good().replace("not yet", "perhaps, as there are no hard cards"),
	}
	for fault: String in faults:
		var problems: String = "; ".join(Checks.check(_summary(), faults[fault])["problems"])
		assert_true(problems.contains(fault), "%s: got '%s'" % [fault, problems])


func test_an_open_question_needs_no_leaning() -> void:
	var problems: PackedStringArray = Checks.check(_summary("open"), _good().replace("not yet", "perhaps"))["problems"]
	assert_eq(problems, PackedStringArray())


func test_an_answer_before_a_long_ending_counts() -> void:
	var ending: String = "The road is long. ".repeat(50)
	var reading: String = _good().replace("word ".repeat(150), "").replace(
			"so: not yet.", "so.\n**No, not yet.** " + ending)
	assert_eq(Checks.check(_summary(), reading)["problems"], PackedStringArray())
	var unanswered: String = reading.replace("**No, not yet.** ", "")
	assert_true("; ".join(Checks.check(_summary(), unanswered)["problems"]).contains("no clear yes"))


func test_dignities_rightly_told_pass() -> void:
	for sentence: String in ["The Two of Cups is ill-dignified.", "The Two of Cups is not well-dignified.",
			"Unlike the Two of Cups, all is well-dignified.", "The Two of Cups and The World are well-dignified.",
			"The well-dignified air around it. The Two of Cups is weak."]:
		assert_eq(Checks.dignity_errors(_summary(), sentence), PackedStringArray(), sentence)


func test_a_section_says_which_card_is_meant() -> void:
	var reading: String = "**2. Present**\nThis card is %s-dignified.\n**Synthesis**\nIt is well-dignified."
	assert_eq(Checks.dignity_errors(_summary(), reading % "ill"), PackedStringArray())
	assert_eq(Checks.dignity_errors(_summary(), reading % "well"),
			PackedStringArray(["Two of Cups called well, is ill"]))
	# With another card named there, it is not plain which is meant.
	assert_eq(Checks.dignity_errors(_summary(), "**2. Present**\nThis is well-dignified beside The World."), PackedStringArray())
	assert_eq(Checks.dignity_errors(_summary(), "**3. Future**\nThis is ill-dignified beside the Two of Cups."), PackedStringArray())


func test_word_range() -> void:
	assert_eq(Checks.word_range("300 to 500"), PackedInt32Array([300, 500]))
	assert_eq(Checks.word_range("700 to 1,000"), PackedInt32Array([700, 1000]))
