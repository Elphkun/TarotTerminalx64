extends "res://tests/test_case.gd"
## Saved readings: written, listed newest first, reopened with the same summary, and
## deleted. A reading from a spread that is no longer in the menu still reopens.

const FOLDER := "user://test_history"


func _clear() -> void:
	var path: String = ProjectSettings.globalize_path(FOLDER)
	if DirAccess.dir_exists_absolute(path):
		for file: String in DirAccess.get_files_at(path):
			DirAccess.remove_absolute(path.path_join(file))
		DirAccess.remove_absolute(path)


## A finished reading, without dealing or a model: the fields a real one ends with.
func _finished(spread: Spread, cards: Array[int], question: String, date: String) -> ReadingSession:
	var session: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	session.spread = spread
	session.question = question
	session.layout = spread.lay_out(cards)
	session.summary = ReadingSummary.build(db(), spread, session.layout, question)
	session.reading_text = "**1. Past**\nThe Fool.\n\n**Synthesis**\nAll is well."
	session.reading_model = "gemma"
	session.reading_deck = "Baroque"
	session.finished_at = date
	return session


func test_save_list_reopen_delete() -> void:
	_clear()
	var spread: Spread = Spread.from_db(db(), "three_card")
	var first: ReadingSession = _finished(spread, [0, 28, 50] as Array[int], "Should I move?", "2026-11-19 10:00:00")
	var second: ReadingSession = _finished(spread, [1, 2, 3] as Array[int], "What next?", "2026-11-20 09:30:00")
	var first_path: String = ReadingHistory.save(ReadingHistory.record_from(first, db().spread("three_card")), FOLDER)
	var second_path: String = ReadingHistory.save(ReadingHistory.record_from(second, db().spread("three_card")), FOLDER)
	assert_true(first_path.ends_with("2026-11-19 100000 should-i-move.json"), first_path)
	var listed: Array[Dictionary] = ReadingHistory.list(FOLDER)
	assert_eq(listed.size(), 2)
	assert_eq(listed[0]["question"], "What next?", "newest first")
	assert_eq(listed[0]["spread_name"], "Past, Present, Future")
	assert_true(listed[1]["preview"].begins_with("1. Past The Fool."), listed[1]["preview"])

	var reopened: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	assert_eq(reopened.restore(ReadingHistory.load_record(first_path)), "")
	assert_eq(reopened.step, ReadingSession.Step.DONE)
	assert_eq(reopened.question, "Should I move?")
	assert_eq(reopened.reading_deck, "Baroque")
	assert_eq(reopened.reading_text, first.reading_text)
	assert_true(reopened.all_turned(), "every card face up")
	assert_eq(reopened.summary.to_prompt_text(), first.summary.to_prompt_text(),
			"the dignities and patterns are worked out again, the same")

	# A retry rewrites the same file.
	first.reading_text = "A second take."
	assert_eq(ReadingHistory.save(ReadingHistory.record_from(first, db().spread("three_card")), FOLDER, first_path), first_path)
	assert_eq(ReadingHistory.list(FOLDER).size(), 2)
	assert_eq(ReadingHistory.load_record(first_path)["reading"], "A second take.")

	assert_eq(ReadingHistory.delete(second_path), OK)
	assert_eq(ReadingHistory.list(FOLDER).size(), 1)
	_clear()


func test_same_question_twice_gets_two_files() -> void:
	_clear()
	var spread: Spread = Spread.from_db(db(), "single")
	var session: ReadingSession = _finished(spread, [5] as Array[int], "Today?", "2026-11-20 08:00:00")
	var a: String = ReadingHistory.save(ReadingHistory.record_from(session, db().spread("single")), FOLDER)
	var b: String = ReadingHistory.save(ReadingHistory.record_from(session, db().spread("single")), FOLDER)
	assert_true(a != b and b.ends_with("(2).json"), b)
	_clear()


func test_a_spread_no_longer_in_the_menu_still_reopens() -> void:
	_clear()
	var data: Dictionary = {"name": "Gone", "positions": [
		{"id": "a", "meaning": "One", "x": 0.3, "y": 0.5}, {"id": "b", "meaning": "Two", "x": 0.7, "y": 0.5}],
		"dignity_adjacency": [["a", "b"]]}
	var spread: Spread = Spread.from_data("gone", data)
	var session: ReadingSession = _finished(spread, [22, 36] as Array[int], "Q", "2026-11-20 12:00:00")
	var path: String = ReadingHistory.save(ReadingHistory.record_from(session, data), FOLDER)
	assert_false(db().spreads.has("gone"))
	var reopened: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	assert_eq(reopened.restore(ReadingHistory.load_record(path)), "")
	assert_eq(reopened.spread.name, "Gone")
	# Ace of Wands (fire) beside Ace of Cups (water): contrary.
	assert_true(Dignities.describe(reopened.summary.positions[0]["dignity"]).contains("contrary"),
			Dignities.describe(reopened.summary.positions[0]["dignity"]))
	_clear()


func test_bad_records_are_refused() -> void:
	var session: ReadingSession = ReadingSession.new(db(), LlmClient.new(), LlmConfig.new())
	var spread_entry: Dictionary = {"id": "three_card", "data": db().spread("three_card")}
	assert_true(session.restore({}) != "", "no spread")
	assert_true(session.restore({"spread": spread_entry, "layout": [{"card": 1}]}).contains("1 cards for 3"))
	assert_true(session.restore({"spread": spread_entry,
			"layout": [{"card": 1}, {"card": 2}, {"card": 99}]}).contains("not in the deck"))
	assert_eq(session.step, ReadingSession.Step.ASK, "a refused record changes nothing")
	assert_eq(ReadingHistory.load_record("user://no_such_reading.json"), {})
